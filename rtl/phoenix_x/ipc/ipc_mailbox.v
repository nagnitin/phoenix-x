// =============================================================================
// Module      : ipc_mailbox
// Project     : Phoenix-X Heterogeneous SoC
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Inter-Processor Communication (IPC) Mailbox with Hardware Semaphore.
//               Provides two 32-bit message registers (one per direction) and
//               a hardware test-and-set semaphore for mutual exclusion.
//
// WHY IPC MAILBOX?
//   In a dual-core system, cores need to exchange data and synchronize.
//   Software solutions (spin-lock on shared memory) require both cores to poll
//   a memory location continuously, wasting bus bandwidth and power.
//   A hardware mailbox provides:
//   1. Zero-polling IRQ: the receiving core is interrupted when a message arrives
//   2. Atomic semaphore: prevents race conditions in critical section entry
//   3. No shared memory pollution: messages are in dedicated registers, not DRAM
//
// REGISTER MAP (base: 0x0020_0000):
//   Offset 0x00: MBOX_0TO1  — CPU0 writes a message for CPU1 (R/W for CPU0, RO for CPU1)
//   Offset 0x04: MBOX_1TO0  — CPU1 writes a message for CPU0 (R/W for CPU1, RO for CPU0)
//   Offset 0x08: STATUS     — [0] MSG_0TO1_PENDING, [1] MSG_1TO0_PENDING (auto-clear on read by target)
//   Offset 0x0C: SEMAPHORE  — Hardware test-and-set (see below)
//   Offset 0x10: IRQ_CTRL   — [0] IRQ0_EN (enable IRQ to CPU0 on new message), [1] IRQ1_EN
//
// HARDWARE SEMAPHORE:
//   Reading SEMAPHORE returns the current value (0=free, 1=taken) and
//   ATOMICALLY sets it to 1 in the SAME AXI read transaction.
//   A core reads SEMAPHORE: if it gets 0, it has acquired the lock.
//   If it gets 1, another core holds the lock — retry later.
//   To release: write 0 to SEMAPHORE.
//   This is equivalent to the LDREX/STREX pair in ARMv7 or the XCHG instruction in x86.
//
// MESSAGE FLOW EXAMPLE:
//   CPU0: write to MBOX_0TO1         → STATUS[0] set to 1
//   CPU1: IRQ fires (if IRQ1_EN=1)   → CPU1 reads MBOX_0TO1
//   CPU1: reads MBOX_0TO1            → STATUS[0] auto-clears to 0
//   CPU1: replies by writing MBOX_1TO0
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module ipc_mailbox (
    input  wire        clk,
    input  wire        rst_n,

    // =========================================================================
    // AXI-4 Lite Slave Port (accessed by both CPU0 and CPU1)
    // Both CPUs share the same AXI slave port (arbitrated by the crossbar).
    // =========================================================================
    // Write Address Channel
    input  wire [31:0] s_aw_addr,
    input  wire        s_aw_valid,
    output reg         s_aw_ready,
    // Write Data Channel
    input  wire [31:0] s_w_data,
    input  wire [ 3:0] s_w_strb,
    input  wire        s_w_valid,
    output reg         s_w_ready,
    // Write Response Channel
    output reg  [ 1:0] s_b_resp,
    output reg         s_b_valid,
    input  wire        s_b_ready,
    // Read Address Channel
    input  wire [31:0] s_ar_addr,
    input  wire        s_ar_valid,
    output reg         s_ar_ready,
    // Read Data Channel
    output reg  [31:0] s_r_data,
    output reg  [ 1:0] s_r_resp,
    output reg         s_r_valid,
    input  wire        s_r_ready,

    // Which master is accessing? (from crossbar grant_id)
    // Used to route messages and identify semaphore owner
    input  wire [ 1:0] accessing_master,  // 0=CPU0, 1=CPU1, 2=DMA (DMA cannot use IPC)

    // =========================================================================
    // Interrupt Outputs
    // =========================================================================
    output reg         irq_cpu0,   // To Shared PIC → CPU0: new message from CPU1
    output reg         irq_cpu1    // To Shared PIC → CPU1: new message from CPU0
);

    // =========================================================================
    // IPC Registers
    // =========================================================================
    reg [31:0] mbox_0to1;      // Message from CPU0 to CPU1
    reg [31:0] mbox_1to0;      // Message from CPU1 to CPU0
    reg        msg_0to1_pend;  // 1 = CPU0 has posted a message for CPU1
    reg        msg_1to0_pend;  // 1 = CPU1 has posted a message for CPU0
    reg        semaphore;      // Hardware mutex: 0=free, 1=locked
    reg        irq0_en;        // IRQ to CPU0 enabled
    reg        irq1_en;        // IRQ to CPU1 enabled

    // =========================================================================
    // AXI FSM
    // =========================================================================
    localparam IPC_IDLE   = 2'd0;
    localparam IPC_WDATA  = 2'd1;
    localparam IPC_WRESP  = 2'd2;
    localparam IPC_RDATA  = 2'd3;

    reg [1:0]  ipc_state;
    reg [31:0] aw_addr_r;
    reg [31:0] ar_addr_r;
    reg [ 1:0] aw_master_r;   // Master that initiated the write
    reg [ 1:0] ar_master_r;   // Master that initiated the read

    // Register offset from the base address (0x0020_0000)
    wire [3:0] aw_reg = aw_addr_r[5:2];  // Offset / 4
    wire [3:0] ar_reg = ar_addr_r[5:2];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ipc_state     <= IPC_IDLE;
            s_aw_ready    <= 1'b0;
            s_w_ready     <= 1'b0;
            s_b_valid     <= 1'b0;
            s_b_resp      <= `AXI_RESP_OKAY;
            s_ar_ready    <= 1'b0;
            s_r_valid     <= 1'b0;
            s_r_data      <= 32'b0;
            s_r_resp      <= `AXI_RESP_OKAY;
            mbox_0to1     <= 32'b0;
            mbox_1to0     <= 32'b0;
            msg_0to1_pend <= 1'b0;
            msg_1to0_pend <= 1'b0;
            semaphore     <= 1'b0;
            irq0_en       <= 1'b1;   // Default: IRQs enabled
            irq1_en       <= 1'b1;
            irq_cpu0      <= 1'b0;
            irq_cpu1      <= 1'b0;
            aw_master_r   <= 2'b0;
            ar_master_r   <= 2'b0;
        end else begin
            // Default: de-assert handshakes and IRQs each cycle
            s_aw_ready <= 1'b0;
            s_w_ready  <= 1'b0;
            s_ar_ready <= 1'b0;
            s_b_valid  <= 1'b0;
            s_r_valid  <= 1'b0;
            irq_cpu0   <= 1'b0;
            irq_cpu1   <= 1'b0;

            case (ipc_state)

                IPC_IDLE: begin
                    if (s_aw_valid) begin
                        s_aw_ready  <= 1'b1;
                        aw_addr_r   <= s_aw_addr;
                        aw_master_r <= accessing_master;
                        ipc_state   <= IPC_WDATA;
                    end else if (s_ar_valid) begin
                        s_ar_ready  <= 1'b1;
                        ar_addr_r   <= s_ar_addr;
                        ar_master_r <= accessing_master;
                        ipc_state   <= IPC_RDATA;
                    end
                end

                IPC_WDATA: begin
                    s_w_ready <= 1'b1;
                    if (s_w_valid) begin
                        s_w_ready <= 1'b0;
                        case (aw_reg)
                            4'd0: begin
                                // CPU0 writing to MBOX_0TO1
                                if (aw_master_r == `MASTER_CPU0) begin
                                    mbox_0to1     <= s_w_data;
                                    msg_0to1_pend <= 1'b1;
                                    // Fire IRQ to CPU1 if enabled
                                    if (irq1_en) irq_cpu1 <= 1'b1;
                                end
                                // CPU1 cannot write to 0TO1 mailbox
                            end
                            4'd1: begin
                                // CPU1 writing to MBOX_1TO0
                                if (aw_master_r == `MASTER_CPU1) begin
                                    mbox_1to0     <= s_w_data;
                                    msg_1to0_pend <= 1'b1;
                                    // Fire IRQ to CPU0 if enabled
                                    if (irq0_en) irq_cpu0 <= 1'b1;
                                end
                            end
                            4'd2: ; // STATUS is read-only
                            4'd3: begin
                                // SEMAPHORE: write 0 to release
                                if (s_w_data == 32'b0)
                                    semaphore <= 1'b0;
                            end
                            4'd4: begin
                                // IRQ_CTRL
                                irq0_en <= s_w_data[0];
                                irq1_en <= s_w_data[1];
                            end
                            default: ;
                        endcase
                        s_b_resp  <= `AXI_RESP_OKAY;
                        ipc_state <= IPC_WRESP;
                    end
                end

                IPC_WRESP: begin
                    s_b_valid <= 1'b1;
                    if (s_b_valid && s_b_ready) begin
                        s_b_valid <= 1'b0;
                        ipc_state <= IPC_IDLE;
                    end
                end

                IPC_RDATA: begin
                    case (ar_reg)
                        4'd0: begin
                            // Reading MBOX_0TO1:
                            // CPU1 reading this clears the pending flag (auto-ACK)
                            s_r_data <= mbox_0to1;
                            if (ar_master_r == `MASTER_CPU1)
                                msg_0to1_pend <= 1'b0;
                        end
                        4'd1: begin
                            // Reading MBOX_1TO0:
                            // CPU0 reading this clears the pending flag
                            s_r_data <= mbox_1to0;
                            if (ar_master_r == `MASTER_CPU0)
                                msg_1to0_pend <= 1'b0;
                        end
                        4'd2: begin
                            s_r_data <= {30'b0, msg_1to0_pend, msg_0to1_pend};
                        end
                        4'd3: begin
                            // HARDWARE TEST-AND-SET:
                            // Return current semaphore value AND atomically set to 1
                            s_r_data  <= {31'b0, semaphore};
                            semaphore <= 1'b1;  // Atomic set
                        end
                        4'd4: begin
                            s_r_data <= {30'b0, irq1_en, irq0_en};
                        end
                        default: s_r_data <= 32'hDEAD_BEEF;
                    endcase
                    s_r_resp  <= `AXI_RESP_OKAY;
                    s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin
                        s_r_valid <= 1'b0;
                        ipc_state <= IPC_IDLE;
                    end
                end

                default: ipc_state <= IPC_IDLE;
            endcase
        end
    end

endmodule
