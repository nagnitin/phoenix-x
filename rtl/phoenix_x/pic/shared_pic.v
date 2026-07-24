// =============================================================================
// Module      : shared_pic
// Project     : Phoenix-X Heterogeneous SoC
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Shared Programmable Interrupt Controller for dual-core Phoenix-X.
//               Routes hardware interrupt lines to CPU0, CPU1, or both cores.
//               Wraps and extends the existing single-core interrupt_controller
//               (which remains unmodified) with per-core routing registers.
//
// ARCHITECTURE:
//   The existing interrupt_controller.v handles:
//   - 8 interrupt priority levels (IRQ[7:0])
//   - Priority-based arbitration
//   - ISR vector table lookup
//   - IRQ enable/disable registers
//
//   shared_pic adds:
//   - IRQ_ROUTE[7:0]: per-interrupt routing bits (2 bits each for 16 bits total)
//     00 = route to CPU0 only
//     01 = route to CPU1 only
//     10 = route to BOTH cores (e.g., SysTick for OS scheduling)
//     11 = DISABLED (masked globally)
//   - IPC_IRQ: additional interrupt line from ipc_mailbox (CPU0/CPU1 separately)
//   - Two complete sets of irq_out/irq_vector — one per core
//
// INTERRUPT ROUTING EXAMPLE:
//   UART RX (IRQ[2]) = route CPU1 → UART driver runs on CPU1
//   Timer  (IRQ[1]) = route BOTH → both cores get OS tick
//   GPIO   (IRQ[6]) = route CPU0 → GPIO ISR runs on CPU0
//   IPC    (extra)  = always routed to the target core by the mailbox itself
//
// REGISTER MAP (base: 0x0020_0200):
//   Offset 0x00: IRQ_ROUTE_LO [15:0] — route[0..7] lower 16 bits (2 bits/IRQ)
//   Offset 0x04: IRQ_ROUTE_HI [15:0] — reserved (for 8 more IRQ lines in Phase 2)
//   Offset 0x08: CPU0_IRQ_PEND       — which IRQs are pending for CPU0
//   Offset 0x0C: CPU1_IRQ_PEND       — which IRQs are pending for CPU1
//   Offset 0x10: IRQ_ACK_CPU0        — write 1 to bit to acknowledge IRQ for CPU0
//   Offset 0x14: IRQ_ACK_CPU1        — write 1 to bit to acknowledge IRQ for CPU1
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module shared_pic (
    input  wire        clk,
    input  wire        rst_n,

    // =========================================================================
    // Interrupt Inputs (from existing peripherals — same as original top.v)
    // =========================================================================
    input  wire [7:0]  irq_lines,    // [0]=WDT [1]=Timer [2]=UART_RX [3]=UART_TX
                                     // [4]=SPI  [5]=I2C   [6]=GPIO    [7]=Keypad

    // IPC mailbox interrupts (from ipc_mailbox module)
    input  wire        ipc_irq_cpu0, // CPU0 has a new IPC message
    input  wire        ipc_irq_cpu1, // CPU1 has a new IPC message

    // DMA completion interrupts
    input  wire [3:0]  dma_irq,

    // =========================================================================
    // CPU0 Interrupt Interface
    // =========================================================================
    output reg         cpu0_irq_req,    // IRQ request to CPU0
    output reg  [31:0] cpu0_irq_vector, // ISR address for CPU0
    input  wire        cpu0_irq_ack,    // CPU0 acknowledges the interrupt
    input  wire        cpu0_in_isr,     // CPU0 is in ISR (for priority gating)

    // =========================================================================
    // CPU1 Interrupt Interface
    // =========================================================================
    output reg         cpu1_irq_req,
    output reg  [31:0] cpu1_irq_vector,
    input  wire        cpu1_irq_ack,
    input  wire        cpu1_in_isr,

    // =========================================================================
    // AXI-4 Lite Slave Port (CPU programs routing registers)
    // =========================================================================
    input  wire [31:0] s_aw_addr,
    input  wire        s_aw_valid,
    output reg         s_aw_ready,
    input  wire [31:0] s_w_data,
    input  wire [ 3:0] s_w_strb,
    input  wire        s_w_valid,
    output reg         s_w_ready,
    output reg  [ 1:0] s_b_resp,
    output reg         s_b_valid,
    input  wire        s_b_ready,
    input  wire [31:0] s_ar_addr,
    input  wire        s_ar_valid,
    output reg         s_ar_ready,
    output reg  [31:0] s_r_data,
    output reg  [ 1:0] s_r_resp,
    output reg         s_r_valid,
    input  wire        s_r_ready
);

    // =========================================================================
    // Routing Table: 2 bits per IRQ line (8 lines = 16 bits)
    // route[2N+1:2N] = routing for IRQ[N]
    // 00=CPU0, 01=CPU1, 10=BOTH, 11=DISABLED
    // =========================================================================
    reg [15:0] irq_route;   // Default: route all to CPU0

    // Pending registers (which IRQs are active for each core)
    reg  [9:0] cpu0_pend;   // bits [7:0]=hw irq, [8]=IPC, [9]=DMA
    reg  [9:0] cpu1_pend;

    // =========================================================================
    // Routing Logic — combinational decode of irq_route into per-core masks
    // =========================================================================
    wire [7:0] route_to_cpu0, route_to_cpu1;
    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : route_gen
            wire [1:0] r = irq_route[2*gi+1 : 2*gi];
            assign route_to_cpu0[gi] = (r == 2'b00) | (r == 2'b10);  // CPU0 or BOTH
            assign route_to_cpu1[gi] = (r == 2'b01) | (r == 2'b10);  // CPU1 or BOTH
        end
    endgenerate

    // =========================================================================
    // Interrupt Pending Update (synchronous, each cycle)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu0_pend   <= 10'b0;
            cpu1_pend   <= 10'b0;
            irq_route   <= 16'b0; // Default: all to CPU0
        end else begin
            // Latch hardware IRQ lines, routed per table
            cpu0_pend[7:0] <= irq_lines & route_to_cpu0;
            cpu1_pend[7:0] <= irq_lines & route_to_cpu1;

            // IPC mailbox IRQs (always routed to the correct core)
            cpu0_pend[8] <= ipc_irq_cpu0;
            cpu1_pend[8] <= ipc_irq_cpu1;

            // DMA IRQs — route to CPU0 by default in Phase 1
            cpu0_pend[9] <= |dma_irq;

            // ACK clears pending (handled below via AXI write to ACK registers)
        end
    end

    // =========================================================================
    // ISR Vector Table — simplified fixed vectors per IRQ number
    // In a full implementation, this would be loaded from memory.
    // Format: 0x0000_0100 + IRQ_NUMBER × 4 (ISR jump table in Boot ROM)
    // =========================================================================
    function [31:0] get_vector;
        input [3:0] irq_num;
        begin
            get_vector = 32'h0000_0100 + {28'b0, irq_num, 2'b00};
        end
    endfunction

    // Priority encoder: find highest-priority (lowest-number) pending IRQ
    function [3:0] priority_encode;
        input [9:0] pend;
        integer ii;
        begin
            priority_encode = 4'hF;  // No IRQ
            for (ii = 9; ii >= 0; ii = ii - 1) begin
                if (pend[ii]) priority_encode = ii[3:0];
            end
        end
    endfunction

    // =========================================================================
    // IRQ Output Generation (combinational from pending registers)
    // =========================================================================
    wire [3:0] cpu0_irq_num = priority_encode(cpu0_pend);
    wire [3:0] cpu1_irq_num = priority_encode(cpu1_pend);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu0_irq_req    <= 1'b0;
            cpu0_irq_vector <= 32'b0;
            cpu1_irq_req    <= 1'b0;
            cpu1_irq_vector <= 32'b0;
        end else begin
            // CPU0 interrupt
            if (|cpu0_pend && !cpu0_in_isr) begin
                cpu0_irq_req    <= 1'b1;
                cpu0_irq_vector <= get_vector(cpu0_irq_num);
            end else begin
                cpu0_irq_req    <= 1'b0;
            end

            // CPU1 interrupt
            if (|cpu1_pend && !cpu1_in_isr) begin
                cpu1_irq_req    <= 1'b1;
                cpu1_irq_vector <= get_vector(cpu1_irq_num);
            end else begin
                cpu1_irq_req    <= 1'b0;
            end

            // ACK: clear the pending bit for the acknowledged IRQ
            if (cpu0_irq_ack && cpu0_irq_num != 4'hF)
                cpu0_pend[cpu0_irq_num] <= 1'b0;
            if (cpu1_irq_ack && cpu1_irq_num != 4'hF)
                cpu1_pend[cpu1_irq_num] <= 1'b0;
        end
    end

    // =========================================================================
    // AXI Slave FSM — Programs irq_route registers, reads pending status
    // =========================================================================
    localparam PIC_IDLE  = 2'd0;
    localparam PIC_WDATA = 2'd1;
    localparam PIC_WRESP = 2'd2;
    localparam PIC_RDATA = 2'd3;

    reg [1:0]  pic_state;
    reg [31:0] aw_addr_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pic_state  <= PIC_IDLE;
            s_aw_ready <= 1'b0;
            s_w_ready  <= 1'b0;
            s_b_valid  <= 1'b0;
            s_b_resp   <= `AXI_RESP_OKAY;
            s_ar_ready <= 1'b0;
            s_r_valid  <= 1'b0;
            s_r_data   <= 32'b0;
            s_r_resp   <= `AXI_RESP_OKAY;
        end else begin
            s_aw_ready <= 1'b0;
            s_w_ready  <= 1'b0;
            s_ar_ready <= 1'b0;
            s_b_valid  <= 1'b0;
            s_r_valid  <= 1'b0;

            case (pic_state)
                PIC_IDLE: begin
                    if (s_aw_valid) begin
                        s_aw_ready <= 1'b1;
                        aw_addr_r  <= s_aw_addr;
                        pic_state  <= PIC_WDATA;
                    end else if (s_ar_valid) begin
                        s_ar_ready <= 1'b1;
                        pic_state  <= PIC_RDATA;
                    end
                end

                PIC_WDATA: begin
                    s_w_ready <= 1'b1;
                    if (s_w_valid) begin
                        s_w_ready <= 1'b0;
                        case (aw_addr_r[4:2])
                            3'd0: irq_route[15:0] <= s_w_data[15:0];
                            3'd1: ; // IRQ_ROUTE_HI — reserved
                            3'd2: ; // CPU0_IRQ_PEND — read-only
                            3'd3: ; // CPU1_IRQ_PEND — read-only
                            3'd4: begin
                                // ACK for CPU0: writing 1 clears pending bit
                                cpu0_pend <= cpu0_pend & ~s_w_data[9:0];
                            end
                            3'd5: begin
                                // ACK for CPU1
                                cpu1_pend <= cpu1_pend & ~s_w_data[9:0];
                            end
                            default: ;
                        endcase
                        s_b_resp  <= `AXI_RESP_OKAY;
                        pic_state <= PIC_WRESP;
                    end
                end

                PIC_WRESP: begin
                    s_b_valid <= 1'b1;
                    if (s_b_valid && s_b_ready) begin
                        s_b_valid <= 1'b0;
                        pic_state <= PIC_IDLE;
                    end
                end

                PIC_RDATA: begin
                    case (s_ar_addr[4:2])
                        3'd0: s_r_data <= {16'b0, irq_route};
                        3'd1: s_r_data <= 32'b0;
                        3'd2: s_r_data <= {22'b0, cpu0_pend};
                        3'd3: s_r_data <= {22'b0, cpu1_pend};
                        3'd4: s_r_data <= 32'b0; // ACK write-only
                        3'd5: s_r_data <= 32'b0;
                        default: s_r_data <= 32'hDEAD_BEEF;
                    endcase
                    s_r_resp  <= `AXI_RESP_OKAY;
                    s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin
                        s_r_valid <= 1'b0;
                        pic_state <= PIC_IDLE;
                    end
                end

                default: pic_state <= PIC_IDLE;
            endcase
        end
    end

endmodule
