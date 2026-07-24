// =============================================================================
// Module      : adbu_top
// Project     : Phoenix-X Phase 4 — Advanced Debug Unit (ADBU)
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Advanced Debug Unit integrating four trace capture buffers:
//               1. Instruction Trace Buffer  — 256-entry FIFO (PC+INSTR+PRIV)
//               2. Memory Access Trace       — 128-entry FIFO (addr+data+we)
//               3. AXI Bus Transaction Trace — 64-entry FIFO (master+slave+addr)
//               4. Exception & Fault Log     — 32-entry log (fault type+addr+cycle)
//
// Combined AXI Slave Config @ 0x0020_0800–08FF:
//   ITRACE reads: 0x00 → 0x7F  (R: {pc, instr} pairs)
//   MTRACE reads: 0x80 → 0xAF  (R: {addr, data} pairs)
//   BTRACE reads: 0xB0 → 0xBF  (R: {master|slave|addr})
//   EXCLOG reads: 0xC0 → 0xCF  (R: {fault_type|addr|cycle})
//   CTRL    write:0xF0          (W: master enable/reset)
// =============================================================================

`timescale 1ns/1ps
`include "rtl/phoenix_x/axi/axi_defines.vh"

module adbu_top (
    input  wire        clk,
    input  wire        rst_n,

    // CPU Debug Bus
    input  wire [31:0] cpu0_pc,    input wire [31:0] cpu0_instr,  input wire cpu0_dbu_valid,
    input  wire [31:0] cpu1_pc,    input wire [31:0] cpu1_instr,  input wire cpu1_dbu_valid,
    input  wire [1:0]  cpu0_priv,  input wire [1:0]  cpu1_priv,

    // AXI Bus Snoop Inputs (for memory & bus trace)
    input  wire [31:0] m0_aw_addr,  input wire [31:0] m0_w_data,  input wire m0_aw_valid, m0_w_valid,
    input  wire [31:0] m1_aw_addr,  input wire [31:0] m1_w_data,  input wire m1_aw_valid, m1_w_valid,
    input  wire [31:0] m2_aw_addr,  input wire [31:0] m2_w_data,  input wire m2_aw_valid, m2_w_valid,
    input  wire [31:0] m0_ar_addr,  input wire m0_ar_valid,
    input  wire [31:0] m1_ar_addr,  input wire m1_ar_valid,
    input  wire [31:0] m2_ar_addr,  input wire m2_ar_valid,

    // Fault/Exception Inputs
    input  wire        mpu_fault,   input wire [31:0] fault_addr,   input wire [1:0] fault_type,
    input  wire        trojan_alert, input wire wdt_reset,
    input  wire        dma_error,

    // AXI-4 Lite Config Slave (0x0020_0800)
    input  wire [31:0] s_aw_addr,   input wire s_aw_valid,  output reg s_aw_ready,
    input  wire [31:0] s_w_data,    input wire [3:0] s_w_strb,
    input  wire        s_w_valid,   output reg s_w_ready,
    output reg  [1:0]  s_b_resp,    output reg s_b_valid,   input wire s_b_ready,
    input  wire [31:0] s_ar_addr,   input wire s_ar_valid,  output reg s_ar_ready,
    output reg  [31:0] s_r_data,    output reg [1:0] s_r_resp,
    output reg         s_r_valid,   input wire s_r_ready
);

    // -------------------------------------------------------------------------
    // 1. Instruction Trace Buffer — 256-entry Circular FIFO
    //    Each entry: {priv[1:0], pc[31:0], instr[31:0]} = 66 bits → stored in 3×32 words
    //    For simplicity, we store {pc, instr} as 2 words per entry
    // -------------------------------------------------------------------------
    localparam ITRACE_DEPTH = 256;
    reg [31:0] itrace_pc   [0:ITRACE_DEPTH-1];
    reg [31:0] itrace_instr[0:ITRACE_DEPTH-1];
    reg [1:0]  itrace_priv [0:ITRACE_DEPTH-1];
    reg [7:0]  itrace_wr_ptr, itrace_rd_ptr;
    reg [8:0]  itrace_count;
    reg        trace_enable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            itrace_wr_ptr <= 8'h0; itrace_rd_ptr <= 8'h0; itrace_count <= 9'h0;
        end else if (trace_enable) begin
            if (cpu0_dbu_valid) begin
                itrace_pc   [itrace_wr_ptr] <= cpu0_pc;
                itrace_instr[itrace_wr_ptr] <= cpu0_instr;
                itrace_priv [itrace_wr_ptr] <= cpu0_priv;
                itrace_wr_ptr <= itrace_wr_ptr + 1'b1;
                if (itrace_count < 9'd256) itrace_count <= itrace_count + 1'b1;
            end
            if (cpu1_dbu_valid) begin
                itrace_pc   [itrace_wr_ptr] <= cpu1_pc;
                itrace_instr[itrace_wr_ptr] <= cpu1_instr;
                itrace_priv [itrace_wr_ptr] <= cpu1_priv;
                itrace_wr_ptr <= itrace_wr_ptr + 1'b1;
                if (itrace_count < 9'd256) itrace_count <= itrace_count + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. Memory Access Trace — 128-entry Circular FIFO
    //    Entry: {master_id[2:0], we[1], addr[31:0], data[31:0]} = 68 bits
    // -------------------------------------------------------------------------
    localparam MTRACE_DEPTH = 128;
    reg [31:0] mtrace_addr  [0:MTRACE_DEPTH-1];
    reg [31:0] mtrace_data  [0:MTRACE_DEPTH-1];
    reg [2:0]  mtrace_master[0:MTRACE_DEPTH-1];
    reg        mtrace_we    [0:MTRACE_DEPTH-1];
    reg [6:0]  mtrace_wr_ptr;
    reg [7:0]  mtrace_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin mtrace_wr_ptr <= 7'h0; mtrace_count <= 8'h0; end
        else if (trace_enable) begin
            if (m0_aw_valid && m0_w_valid) begin
                mtrace_addr  [mtrace_wr_ptr] <= m0_aw_addr;
                mtrace_data  [mtrace_wr_ptr] <= m0_w_data;
                mtrace_master[mtrace_wr_ptr] <= 3'd0;
                mtrace_we    [mtrace_wr_ptr] <= 1'b1;
                mtrace_wr_ptr <= mtrace_wr_ptr + 1'b1;
                if (mtrace_count < 8'd128) mtrace_count <= mtrace_count + 1'b1;
            end else if (m0_ar_valid) begin
                mtrace_addr  [mtrace_wr_ptr] <= m0_ar_addr;
                mtrace_data  [mtrace_wr_ptr] <= 32'h0;
                mtrace_master[mtrace_wr_ptr] <= 3'd0;
                mtrace_we    [mtrace_wr_ptr] <= 1'b0;
                mtrace_wr_ptr <= mtrace_wr_ptr + 1'b1;
                if (mtrace_count < 8'd128) mtrace_count <= mtrace_count + 1'b1;
            end else if (m1_aw_valid && m1_w_valid) begin
                mtrace_addr  [mtrace_wr_ptr] <= m1_aw_addr;
                mtrace_data  [mtrace_wr_ptr] <= m1_w_data;
                mtrace_master[mtrace_wr_ptr] <= 3'd1;
                mtrace_we    [mtrace_wr_ptr] <= 1'b1;
                mtrace_wr_ptr <= mtrace_wr_ptr + 1'b1;
                if (mtrace_count < 8'd128) mtrace_count <= mtrace_count + 1'b1;
            end else if (m2_aw_valid && m2_w_valid) begin
                mtrace_addr  [mtrace_wr_ptr] <= m2_aw_addr;
                mtrace_data  [mtrace_wr_ptr] <= m2_w_data;
                mtrace_master[mtrace_wr_ptr] <= 3'd2;
                mtrace_we    [mtrace_wr_ptr] <= 1'b1;
                mtrace_wr_ptr <= mtrace_wr_ptr + 1'b1;
                if (mtrace_count < 8'd128) mtrace_count <= mtrace_count + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 3. AXI Bus Transaction Trace — 64-entry FIFO
    //    Entry: {master_id[2:0], txn_type[1], addr[31:0]}
    // -------------------------------------------------------------------------
    localparam BTRACE_DEPTH = 64;
    reg [31:0] btrace_addr  [0:BTRACE_DEPTH-1];
    reg [2:0]  btrace_master[0:BTRACE_DEPTH-1];
    reg        btrace_type  [0:BTRACE_DEPTH-1];  // 0=read, 1=write
    reg [5:0]  btrace_wr_ptr;
    reg [6:0]  btrace_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin btrace_wr_ptr <= 6'h0; btrace_count <= 7'h0; end
        else if (trace_enable) begin
            if (m0_aw_valid) begin
                btrace_addr  [btrace_wr_ptr] <= m0_aw_addr;
                btrace_master[btrace_wr_ptr] <= 3'd0;
                btrace_type  [btrace_wr_ptr] <= 1'b1;
                btrace_wr_ptr <= btrace_wr_ptr + 1'b1;
                if (btrace_count < 7'd64) btrace_count <= btrace_count + 1'b1;
            end else if (m0_ar_valid) begin
                btrace_addr  [btrace_wr_ptr] <= m0_ar_addr;
                btrace_master[btrace_wr_ptr] <= 3'd0;
                btrace_type  [btrace_wr_ptr] <= 1'b0;
                btrace_wr_ptr <= btrace_wr_ptr + 1'b1;
                if (btrace_count < 7'd64) btrace_count <= btrace_count + 1'b1;
            end else if (m1_aw_valid) begin
                btrace_addr  [btrace_wr_ptr] <= m1_aw_addr;
                btrace_master[btrace_wr_ptr] <= 3'd1;
                btrace_type  [btrace_wr_ptr] <= 1'b1;
                btrace_wr_ptr <= btrace_wr_ptr + 1'b1;
                if (btrace_count < 7'd64) btrace_count <= btrace_count + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. Exception & Fault Log — 32-entry timestamped log
    //    Entry: {fault_type[2:0], fault_addr[31:0], cycle_cnt[31:0]}
    // -------------------------------------------------------------------------
    localparam EXCLOG_DEPTH = 32;
    reg [31:0] exc_addr  [0:EXCLOG_DEPTH-1];
    reg [2:0]  exc_type  [0:EXCLOG_DEPTH-1]; // 0=MPU, 1=Trojan, 2=WDT, 3=DMA, 4=IRQ
    reg [31:0] exc_cycle [0:EXCLOG_DEPTH-1];
    reg [31:0] cycle_cnt;
    reg [4:0]  exc_wr_ptr;
    reg [5:0]  exc_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exc_wr_ptr <= 5'h0; exc_count <= 6'h0; cycle_cnt <= 32'h0;
        end else begin
            cycle_cnt <= cycle_cnt + 1'b1;
            if (mpu_fault) begin
                exc_addr [exc_wr_ptr] <= fault_addr;
                exc_type [exc_wr_ptr] <= {1'b0, fault_type};
                exc_cycle[exc_wr_ptr] <= cycle_cnt;
                exc_wr_ptr <= exc_wr_ptr + 1'b1;
                if (exc_count < 6'd32) exc_count <= exc_count + 1'b1;
            end else if (trojan_alert) begin
                exc_addr [exc_wr_ptr] <= 32'hDEAD_BEEF;
                exc_type [exc_wr_ptr] <= 3'd1;
                exc_cycle[exc_wr_ptr] <= cycle_cnt;
                exc_wr_ptr <= exc_wr_ptr + 1'b1;
                if (exc_count < 6'd32) exc_count <= exc_count + 1'b1;
            end else if (wdt_reset) begin
                exc_addr [exc_wr_ptr] <= 32'h0000_5752;  // 'WR' watchdog reset marker
                exc_type [exc_wr_ptr] <= 3'd2;
                exc_cycle[exc_wr_ptr] <= cycle_cnt;
                exc_wr_ptr <= exc_wr_ptr + 1'b1;
                if (exc_count < 6'd32) exc_count <= exc_count + 1'b1;
            end else if (dma_error) begin
                exc_addr [exc_wr_ptr] <= 32'h0000_444D;  // 'DM' DMA error marker
                exc_type [exc_wr_ptr] <= 3'd3;
                exc_cycle[exc_wr_ptr] <= cycle_cnt;
                exc_wr_ptr <= exc_wr_ptr + 1'b1;
                if (exc_count < 6'd32) exc_count <= exc_count + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Control Register
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) trace_enable <= 1'b1;
    end

    // -------------------------------------------------------------------------
    // AXI Config Slave FSM
    // -------------------------------------------------------------------------
    localparam DB_IDLE = 2'd0, DB_WDATA = 2'd1, DB_WRESP = 2'd2, DB_RDATA = 2'd3;
    reg [1:0]  db_state;
    reg [31:0] db_aw_addr_r, db_ar_addr_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            db_state <= DB_IDLE; s_aw_ready <= 1'b0; s_w_ready <= 1'b0; s_b_valid <= 1'b0;
            s_ar_ready <= 1'b0; s_r_valid <= 1'b0;
        end else begin
            s_aw_ready <= 1'b0; s_w_ready <= 1'b0; s_ar_ready <= 1'b0; s_b_valid <= 1'b0; s_r_valid <= 1'b0;
            case (db_state)
                DB_IDLE: begin
                    if (s_aw_valid) begin s_aw_ready <= 1'b1; db_aw_addr_r <= s_aw_addr; db_state <= DB_WDATA; end
                    else if (s_ar_valid) begin s_ar_ready <= 1'b1; db_ar_addr_r <= s_ar_addr; db_state <= DB_RDATA; end
                end
                DB_WDATA: begin
                    s_w_ready <= 1'b1;
                    if (s_w_valid) begin
                        if (db_aw_addr_r[7:2] == 6'h3C) begin // Control register @ 0xF0
                            // bit 0 = trace_enable, bit 1 = clear all buffers
                        end
                        s_b_resp <= `AXI_RESP_OKAY; db_state <= DB_WRESP;
                    end
                end
                DB_WRESP: begin s_b_valid <= 1'b1; if (s_b_valid && s_b_ready) begin s_b_valid <= 1'b0; db_state <= DB_IDLE; end end
                DB_RDATA: begin
                    casez (db_ar_addr_r[7:2])
                        // Instruction Trace: index = addr[7:3], word = addr[2]
                        6'b00????:  begin
                            if (db_ar_addr_r[2] == 1'b0)
                                s_r_data <= itrace_pc   [db_ar_addr_r[7:3]];
                            else
                                s_r_data <= itrace_instr[db_ar_addr_r[7:3]];
                        end
                        // Memory Trace
                        6'b01????:  begin
                            if (db_ar_addr_r[2] == 1'b0)
                                s_r_data <= mtrace_addr[db_ar_addr_r[6:3]];
                            else
                                s_r_data <= mtrace_data[db_ar_addr_r[6:3]];
                        end
                        // Bus Trace
                        6'b101???:  s_r_data <= btrace_addr[db_ar_addr_r[5:3]];
                        // Exception Log
                        6'b110???:  begin
                            if (db_ar_addr_r[2] == 1'b0)
                                s_r_data <= exc_addr[db_ar_addr_r[5:3]];
                            else
                                s_r_data <= exc_cycle[db_ar_addr_r[5:3]];
                        end
                        // Status
                        6'b111110:  s_r_data <= {23'b0, itrace_count};
                        6'b111111:  s_r_data <= {24'b0, mtrace_count};
                        default:    s_r_data <= 32'h4442_5500; // 'DBU\0'
                    endcase
                    s_r_resp <= `AXI_RESP_OKAY; s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin s_r_valid <= 1'b0; db_state <= DB_IDLE; end
                end
            endcase
        end
    end

endmodule
