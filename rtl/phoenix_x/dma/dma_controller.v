// =============================================================================
// Module      : dma_controller
// Project     : Phoenix-X Heterogeneous SoC
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : 4-Channel DMA Controller — Phase 1: Memory-to-Memory only.
//
// OVERVIEW:
//   DMA (Direct Memory Access) moves data between memory regions without CPU
//   involvement. The CPU configures the DMA via AXI writes (slave port), then
//   the DMA autonomously reads from a source address and writes to a destination
//   address using its own AXI master port.
//
// WHY DMA?
//   Consider copying 4KB of data:
//   Without DMA: 1024 LOAD instructions + 1024 STORE instructions = 2048 cycles,
//     CPU cannot do anything else during this time.
//   With DMA: CPU writes 3 registers (~6 cycles), then is completely free.
//     DMA handles all 1024 AXI read + 1024 AXI write transactions independently.
//   For a 32KB shared memory buffer with 100 MHz clock, DMA finishes in ~16us
//   while both CPUs continue executing unrelated code.
//
// CHANNEL CONFIGURATION REGISTERS (AXI slave, 4 channels × 32 bytes):
//
//   Base address for channel N: 0x0020_0100 + N × 0x20
//   Offset 0x00: SRC_ADDR    — source byte address (must be word-aligned)
//   Offset 0x04: DST_ADDR    — destination byte address (must be word-aligned)
//   Offset 0x08: XFER_LEN    — number of 32-bit words to transfer
//   Offset 0x0C: CTRL        — control register:
//                 [0]  = ENABLE   (write 1 to start, auto-clears when done)
//                 [1]  = IRQ_EN   (assert irq[N] when complete)
//                 [4]  = CIRC     (circular mode: auto-restart after done)
//   Offset 0x10: STATUS      — status register (read-only):
//                 [0]  = BUSY     (transfer in progress)
//                 [1]  = DONE     (transfer complete, clears on CTRL write)
//                 [2]  = ERR      (AXI error occurred)
//
// AXI SLAVE PORT:
//   Address range: 0x0020_0100 – 0x0020_017F (128 bytes, 4 channels)
//   Write: configure registers, start channel
//   Read : check status
//
// AXI MASTER PORT:
//   Issues sequential ARVALID (source read) then AWVALID+WVALID (dest write)
//   for each 32-bit word in the transfer.
//   Channels are serviced in round-robin order when multiple are active.
//
// Phase 1 Limitations (Phase 2 will add):
//   - Mem→Mem only (no peripheral FIFO handshake)
//   - Single-word AXI transfers (Phase 2: burst transfers)
//   - No scatter-gather (Phase 3)
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module dma_controller (
    input  wire        clk,
    input  wire        rst_n,

    // =========================================================================
    // AXI-4 Lite Slave Port — CPU configures DMA via this port
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

    // =========================================================================
    // AXI-4 Lite Master Port — DMA issues memory transfers on this port
    // =========================================================================
    // Read Address Channel (source)
    output reg  [31:0] m_ar_addr,
    output reg         m_ar_valid,
    input  wire        m_ar_ready,
    // Read Data Channel
    input  wire [31:0] m_r_data,
    input  wire [ 1:0] m_r_resp,
    input  wire        m_r_valid,
    output reg         m_r_ready,
    // Write Address Channel (destination)
    output reg  [31:0] m_aw_addr,
    output reg         m_aw_valid,
    input  wire        m_aw_ready,
    // Write Data Channel
    output reg  [31:0] m_w_data,
    output reg  [ 3:0] m_w_strb,
    output reg         m_w_valid,
    input  wire        m_w_ready,
    // Write Response Channel
    input  wire [ 1:0] m_b_resp,
    input  wire        m_b_valid,
    output reg         m_b_ready,

    // =========================================================================
    // Interrupt outputs (one per channel)
    // =========================================================================
    output reg  [3:0]  dma_irq   // Asserted for 1 cycle when channel N completes
);

    // =========================================================================
    // Channel Registers (4 channels)
    // =========================================================================
    reg [31:0] src_addr  [0:3];   // Source address
    reg [31:0] dst_addr  [0:3];   // Destination address
    reg [31:0] xfer_len  [0:3];   // Transfer length in words
    reg [ 4:0] ctrl      [0:3];   // {CIRC[4], IRQ_EN[1], ENABLE[0]}
    reg [ 2:0] status    [0:3];   // {ERR[2], DONE[1], BUSY[0]}

    // Runtime counters per channel
    reg [31:0] xfer_cnt  [0:3];   // Words transferred so far
    reg [31:0] cur_src   [0:3];   // Current source pointer
    reg [31:0] cur_dst   [0:3];   // Current destination pointer

    // =========================================================================
    // AXI Slave FSM — Accepts CPU configuration writes/reads
    // =========================================================================
    localparam SL_IDLE   = 2'd0;
    localparam SL_WDATA  = 2'd1;  // Waiting for write data
    localparam SL_WRESP  = 2'd2;  // Sending write response
    localparam SL_RDATA  = 2'd3;  // Sending read response

    reg [1:0]  sl_state;
    reg [31:0] sl_aw_addr_r;      // Latched write address
    reg [31:0] sl_ar_addr_r;      // Latched read address

    wire [1:0] sl_aw_ch = sl_aw_addr_r[6:5];
    wire [2:0] sl_aw_rg = sl_aw_addr_r[4:2];
    wire [1:0] sl_ar_ch = sl_ar_addr_r[6:5];
    wire [2:0] sl_ar_rg = sl_ar_addr_r[4:2];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sl_state   <= SL_IDLE;
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

            case (sl_state)
                SL_IDLE: begin
                    if (s_aw_valid) begin
                        s_aw_ready    <= 1'b1;
                        sl_aw_addr_r  <= s_aw_addr;
                        sl_state      <= SL_WDATA;
                    end else if (s_ar_valid) begin
                        s_ar_ready    <= 1'b1;
                        sl_ar_addr_r  <= s_ar_addr;
                        sl_state      <= SL_RDATA;
                    end
                end

                SL_WDATA: begin
                    s_w_ready <= 1'b1;
                    if (s_w_valid) begin
                        case (sl_aw_rg)
                            3'd0: src_addr[sl_aw_ch] <= s_w_data;
                            3'd1: dst_addr[sl_aw_ch] <= s_w_data;
                            3'd2: xfer_len[sl_aw_ch] <= s_w_data;
                            3'd3: begin
                                ctrl[sl_aw_ch] <= s_w_data[4:0];
                                // Starting a channel: initialize counters
                                if (s_w_data[0]) begin
                                    cur_src[sl_aw_ch]  <= src_addr[sl_aw_ch];
                                    cur_dst[sl_aw_ch]  <= dst_addr[sl_aw_ch];
                                    xfer_cnt[sl_aw_ch] <= 32'b0;
                                    status[sl_aw_ch]   <= 3'b001; // BUSY
                                end
                            end
                            3'd4: ; // STATUS is read-only; ignore writes
                            default: ;
                        endcase
                        s_w_ready <= 1'b0;
                        s_b_resp  <= `AXI_RESP_OKAY;
                        sl_state  <= SL_WRESP;
                    end
                end

                SL_WRESP: begin
                    s_b_valid <= 1'b1;
                    if (s_b_valid && s_b_ready) begin
                        s_b_valid <= 1'b0;
                        sl_state  <= SL_IDLE;
                    end
                end

                SL_RDATA: begin
                    case (sl_ar_rg)
                        3'd0: s_r_data <= src_addr[sl_ar_ch];
                        3'd1: s_r_data <= dst_addr[sl_ar_ch];
                        3'd2: s_r_data <= xfer_len[sl_ar_ch];
                        3'd3: s_r_data <= {27'b0, ctrl[sl_ar_ch]};
                        3'd4: s_r_data <= {29'b0, status[sl_ar_ch]};
                        default: s_r_data <= 32'hDEAD_BEEF;
                    endcase
                    s_r_resp  <= `AXI_RESP_OKAY;
                    s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin
                        s_r_valid <= 1'b0;
                        sl_state  <= SL_IDLE;
                    end
                end

                default: sl_state <= SL_IDLE;
            endcase
        end
    end

    // =========================================================================
    // DMA Master FSM — Executes transfers for active channels (round-robin)
    // States: IDLE → SELECT → READ_ADDR → READ_DATA → WRITE_ADDR → WRITE_DATA
    //         → WRITE_RESP → DONE_CHECK
    // =========================================================================
    localparam DMA_IDLE       = 3'd0;
    localparam DMA_SELECT     = 3'd1;
    localparam DMA_READ_ADDR  = 3'd2;
    localparam DMA_READ_DATA  = 3'd3;
    localparam DMA_WRITE_ADDR = 3'd4;
    localparam DMA_WRITE_DATA = 3'd5;
    localparam DMA_WRITE_RESP = 3'd6;
    localparam DMA_DONE_CHECK = 3'd7;

    reg [2:0]  dma_state;
    reg [1:0]  active_ch;      // Currently executing channel
    reg [1:0]  rr_token;       // Round-robin selection token
    reg [31:0] fetch_data_r;   // Data read from source, held for write

    // Round-robin channel selector
    function [1:0] next_active_channel;
        input [1:0] token;
        input [3:0] busy;
        reg [31:0] i;
        reg [1:0] found;
        reg       has_found;
        reg [1:0] idx;
        begin
            found     = 2'd0;
            has_found = 1'b0;
            for (i = 0; i < 4 && !has_found; i = i + 1) begin
                idx = (token + 1'b1 + i[1:0]);
                if (busy[idx] && !has_found) begin
                    found     = idx;
                    has_found = 1'b1;
                end
            end
            next_active_channel = found;
        end
    endfunction

    // Which channels are actively transferring?
    wire [3:0] ch_busy = {status[3][0], status[2][0], status[1][0], status[0][0]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_state   <= DMA_IDLE;
            active_ch   <= 2'd0;
            rr_token    <= 2'd0;
            fetch_data_r<= 32'b0;
            m_ar_valid  <= 1'b0;
            m_ar_addr   <= 32'b0;
            m_r_ready   <= 1'b0;
            m_aw_valid  <= 1'b0;
            m_aw_addr   <= 32'b0;
            m_w_valid   <= 1'b0;
            m_w_data    <= 32'b0;
            m_w_strb    <= 4'hF;
            m_b_ready   <= 1'b0;
            dma_irq     <= 4'b0;
            // Initialize registers
            begin : init_regs
                integer ii;
                for (ii = 0; ii < 4; ii = ii + 1) begin
                    src_addr[ii] <= 32'b0;
                    dst_addr[ii] <= 32'b0;
                    xfer_len[ii] <= 32'b0;
                    ctrl[ii]     <= 5'b0;
                    status[ii]   <= 3'b0;
                    xfer_cnt[ii] <= 32'b0;
                    cur_src[ii]  <= 32'b0;
                    cur_dst[ii]  <= 32'b0;
                end
            end
        end else begin
            dma_irq <= 4'b0;  // Default: de-assert IRQs

            case (dma_state)

                DMA_IDLE: begin
                    m_ar_valid <= 1'b0;
                    m_aw_valid <= 1'b0;
                    m_w_valid  <= 1'b0;
                    m_b_ready  <= 1'b0;
                    m_r_ready  <= 1'b0;
                    if (|ch_busy) begin
                        dma_state <= DMA_SELECT;
                    end
                end

                DMA_SELECT: begin
                    // Choose next active channel (round-robin)
                    active_ch <= next_active_channel(rr_token, ch_busy);
                    dma_state <= DMA_READ_ADDR;
                end

                DMA_READ_ADDR: begin
                    // Issue AXI read for next source word
                    m_ar_addr  <= cur_src[active_ch];
                    m_ar_valid <= 1'b1;
                    m_r_ready  <= 1'b0;
                    if (m_ar_valid && m_ar_ready) begin
                        m_ar_valid <= 1'b0;
                        m_r_ready  <= 1'b1;
                        dma_state  <= DMA_READ_DATA;
                    end
                end

                DMA_READ_DATA: begin
                    if (m_r_valid && m_r_ready) begin
                        m_r_ready    <= 1'b0;
                        fetch_data_r <= m_r_data;  // Hold data for write
                        // Advance source pointer
                        cur_src[active_ch] <= cur_src[active_ch] + 32'd4;
                        // Check for AXI error
                        if (m_r_resp != `AXI_RESP_OKAY)
                            status[active_ch][2] <= 1'b1;  // ERR bit
                        dma_state <= DMA_WRITE_ADDR;
                    end
                end

                DMA_WRITE_ADDR: begin
                    // Issue AXI write address for destination
                    m_aw_addr  <= cur_dst[active_ch];
                    m_aw_valid <= 1'b1;
                    if (m_aw_valid && m_aw_ready) begin
                        m_aw_valid <= 1'b0;
                        dma_state  <= DMA_WRITE_DATA;
                    end
                end

                DMA_WRITE_DATA: begin
                    m_w_data  <= fetch_data_r;
                    m_w_strb  <= 4'hF;
                    m_w_valid <= 1'b1;
                    if (m_w_valid && m_w_ready) begin
                        m_w_valid <= 1'b0;
                        m_b_ready <= 1'b1;
                        dma_state <= DMA_WRITE_RESP;
                    end
                end

                DMA_WRITE_RESP: begin
                    if (m_b_valid && m_b_ready) begin
                        m_b_ready <= 1'b0;
                        // Advance destination pointer and count
                        cur_dst[active_ch]  <= cur_dst[active_ch] + 32'd4;
                        xfer_cnt[active_ch] <= xfer_cnt[active_ch] + 32'd1;
                        dma_state <= DMA_DONE_CHECK;
                    end
                end

                DMA_DONE_CHECK: begin
                    if (xfer_cnt[active_ch] >= xfer_len[active_ch]) begin
                        // Channel transfer complete
                        status[active_ch][0] <= 1'b0;  // Clear BUSY
                        status[active_ch][1] <= 1'b1;  // Set DONE

                        if (ctrl[active_ch][4]) begin
                            // Circular mode: restart from original addresses
                            cur_src[active_ch] <= src_addr[active_ch];
                            cur_dst[active_ch] <= dst_addr[active_ch];
                            xfer_cnt[active_ch]<= 32'b0;
                            status[active_ch][0]<= 1'b1;
                        end else begin
                            ctrl[active_ch][0] <= 1'b0;  // Clear ENABLE
                        end

                        // Fire IRQ if enabled
                        if (ctrl[active_ch][1])
                            dma_irq[active_ch] <= 1'b1;

                        rr_token  <= active_ch;
                        dma_state <= DMA_IDLE;
                    end else begin
                        // More words to transfer — advance to next channel then continue
                        rr_token  <= active_ch;
                        dma_state <= (|ch_busy) ? DMA_SELECT : DMA_IDLE;
                    end
                end

                default: dma_state <= DMA_IDLE;
            endcase
        end
    end

endmodule
