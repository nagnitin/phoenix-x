// =============================================================================
// Module      : axi_crossbar
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : AXI-4 Lite shared-bus interconnect for 5 Masters and 9 Slaves.
//               Masters: CPU0, CPU1, DMA, GPU, NPU.
//               Slaves: BootROM, IROM, DRAM0, DRAM1, Shared SRAM, SysCtrl,
//                       Peripherals, GPU Config, NPU Config.
// =============================================================================

`timescale 1ns/1ps
`include "axi_defines.vh"

module axi_crossbar (
    input  wire        clk,
    input  wire        rst_n,

    // --- Master 0: CPU0 ---
    input  wire [31:0] m0_aw_addr, input wire m0_aw_valid, output wire m0_aw_ready,
    input  wire [31:0] m0_w_data,  input wire [3:0] m0_w_strb, input wire m0_w_valid, output wire m0_w_ready,
    output wire [ 1:0] m0_b_resp,  output wire m0_b_valid, input wire m0_b_ready,
    input  wire [31:0] m0_ar_addr, input wire m0_ar_valid, output wire m0_ar_ready,
    output wire [31:0] m0_r_data,  output wire [1:0] m0_r_resp, output wire m0_r_valid, input wire m0_r_ready,

    // --- Master 1: CPU1 ---
    input  wire [31:0] m1_aw_addr, input wire m1_aw_valid, output wire m1_aw_ready,
    input  wire [31:0] m1_w_data,  input wire [3:0] m1_w_strb, input wire m1_w_valid, output wire m1_w_ready,
    output wire [ 1:0] m1_b_resp,  output wire m1_b_valid, input wire m1_b_ready,
    input  wire [31:0] m1_ar_addr, input wire m1_ar_valid, output wire m1_ar_ready,
    output wire [31:0] m1_r_data,  output wire [1:0] m1_r_resp, output wire m1_r_valid, input wire m1_r_ready,

    // --- Master 2: DMA ---
    input  wire [31:0] m2_aw_addr, input wire m2_aw_valid, output wire m2_aw_ready,
    input  wire [31:0] m2_w_data,  input wire [3:0] m2_w_strb, input wire m2_w_valid, output wire m2_w_ready,
    output wire [ 1:0] m2_b_resp,  output wire m2_b_valid, input wire m2_b_ready,
    input  wire [31:0] m2_ar_addr, input wire m2_ar_valid, output wire m2_ar_ready,
    output wire [31:0] m2_r_data,  output wire [1:0] m2_r_resp, output wire m2_r_valid, input wire m2_r_ready,

    // --- Master 3: GPU Frame Buffer Writer ---
    input  wire [31:0] m3_aw_addr, input wire m3_aw_valid, output wire m3_aw_ready,
    input  wire [31:0] m3_w_data,  input wire [3:0] m3_w_strb, input wire m3_w_valid, output wire m3_w_ready,
    output wire [ 1:0] m3_b_resp,  output wire m3_b_valid, input wire m3_b_ready,
    input  wire [31:0] m3_ar_addr, input wire m3_ar_valid, output wire m3_ar_ready,
    output wire [31:0] m3_r_data,  output wire [1:0] m3_r_resp, output wire m3_r_valid, input wire m3_r_ready,

    // --- Master 4: NPU Tensor Streamer ---
    input  wire [31:0] m4_aw_addr, input wire m4_aw_valid, output wire m4_aw_ready,
    input  wire [31:0] m4_w_data,  input wire [3:0] m4_w_strb, input wire m4_w_valid, output wire m4_w_ready,
    output wire [ 1:0] m4_b_resp,  output wire m4_b_valid, input wire m4_b_ready,
    input  wire [31:0] m4_ar_addr, input wire m4_ar_valid, output wire m4_ar_ready,
    output wire [31:0] m4_r_data,  output wire [1:0] m4_r_resp, output wire m4_r_valid, input wire m4_r_ready,

    // --- Slaves 0..8 ---
    // Slave 0: BootROM
    output wire [31:0] s0_ar_addr, output wire s0_ar_valid, input wire s0_ar_ready,
    input  wire [31:0] s0_r_data,  input wire [1:0] s0_r_resp, input wire s0_r_valid, output wire s0_r_ready,

    // Slave 1: Instruction ROM
    output wire [31:0] s1_ar_addr, output wire s1_ar_valid, input wire s1_ar_ready,
    input  wire [31:0] s1_r_data,  input wire [1:0] s1_r_resp, input wire s1_r_valid, output wire s1_r_ready,

    // Slave 2: DRAM Bank 0
    output wire [31:0] s2_aw_addr, output wire [31:0] s2_w_data, output wire [3:0] s2_w_strb,
    output wire s2_aw_valid, input wire s2_aw_ready, output wire s2_w_valid, input wire s2_w_ready,
    input wire [1:0] s2_b_resp, input wire s2_b_valid, output wire s2_b_ready,
    output wire [31:0] s2_ar_addr, output wire s2_ar_valid, input wire s2_ar_ready,
    input wire [31:0] s2_r_data, input wire [1:0] s2_r_resp, input wire s2_r_valid, output wire s2_r_ready,

    // Slave 3: DRAM Bank 1
    output wire [31:0] s3_aw_addr, output wire [31:0] s3_w_data, output wire [3:0] s3_w_strb,
    output wire s3_aw_valid, input wire s3_aw_ready, output wire s3_w_valid, input wire s3_w_ready,
    input wire [1:0] s3_b_resp, input wire s3_b_valid, output wire s3_b_ready,
    output wire [31:0] s3_ar_addr, output wire s3_ar_valid, input wire s3_ar_ready,
    input wire [31:0] s3_r_data, input wire [1:0] s3_r_resp, input wire s3_r_valid, output wire s3_r_ready,

    // Slave 4: Shared SRAM
    output wire [31:0] s4_aw_addr, output wire [31:0] s4_w_data, output wire [3:0] s4_w_strb,
    output wire s4_aw_valid, input wire s4_aw_ready, output wire s4_w_valid, input wire s4_w_ready,
    input wire [1:0] s4_b_resp, input wire s4_b_valid, output wire s4_b_ready,
    output wire [31:0] s4_ar_addr, output wire s4_ar_valid, input wire s4_ar_ready,
    input wire [31:0] s4_r_data, input wire [1:0] s4_r_resp, input wire s4_r_valid, output wire s4_r_ready,

    // Slave 5: SysCtrl (IPC + Scheduler + PMU + PIC)
    output wire [31:0] s5_aw_addr, output wire [31:0] s5_w_data, output wire [3:0] s5_w_strb,
    output wire s5_aw_valid, input wire s5_aw_ready, output wire s5_w_valid, input wire s5_w_ready,
    input wire [1:0] s5_b_resp, input wire s5_b_valid, output wire s5_b_ready,
    output wire [31:0] s5_ar_addr, output wire s5_ar_valid, input wire s5_ar_ready,
    input wire [31:0] s5_r_data, input wire [1:0] s5_r_resp, input wire s5_r_valid, output wire s5_r_ready,

    // Slave 6: Legacy Peripherals
    output wire [31:0] s6_aw_addr, output wire [31:0] s6_w_data, output wire [3:0] s6_w_strb,
    output wire s6_aw_valid, input wire s6_aw_ready, output wire s6_w_valid, input wire s6_w_ready,
    input wire [1:0] s6_b_resp, input wire s6_b_valid, output wire s6_b_ready,
    output wire [31:0] s6_ar_addr, output wire s6_ar_valid, input wire s6_ar_ready,
    input wire [31:0] s6_r_data, input wire [1:0] s6_r_resp, input wire s6_r_valid, output wire s6_r_ready,

    // Slave 7: GPU Config Registers
    output wire [31:0] s7_aw_addr, output wire [31:0] s7_w_data, output wire [3:0] s7_w_strb,
    output wire s7_aw_valid, input wire s7_aw_ready, output wire s7_w_valid, input wire s7_w_ready,
    input wire [1:0] s7_b_resp, input wire s7_b_valid, output wire s7_b_ready,
    output wire [31:0] s7_ar_addr, output wire s7_ar_valid, input wire s7_ar_ready,
    input wire [31:0] s7_r_data, input wire [1:0] s7_r_resp, input wire s7_r_valid, output wire s7_r_ready,

    // Slave 8: NPU Config Registers
    output wire [31:0] s8_aw_addr, output wire [31:0] s8_w_data, output wire [3:0] s8_w_strb,
    output wire s8_aw_valid, input wire s8_aw_ready, output wire s8_w_valid, input wire s8_w_ready,
    input wire [1:0] s8_b_resp, input wire s8_b_valid, output wire s8_b_ready,
    output wire [31:0] s8_ar_addr, output wire s8_ar_valid, input wire s8_ar_ready,
    input wire [31:0] s8_r_data, input wire [1:0] s8_r_resp, input wire s8_r_valid, output wire s8_r_ready,

    // Snoop output
    output reg  [31:0] snoop_addr,
    output reg         snoop_wr_valid,
    output wire        axi_read_pulse,
    output wire        axi_write_pulse
);

    // -------------------------------------------------------------------------
    // Arbiter & Decoder
    // -------------------------------------------------------------------------
    wire [4:0] req;
    assign req[0] = m0_aw_valid | m0_ar_valid;
    assign req[1] = m1_aw_valid | m1_ar_valid;
    assign req[2] = m2_aw_valid | m2_ar_valid;
    assign req[3] = m3_aw_valid | m3_ar_valid;
    assign req[4] = m4_aw_valid | m4_ar_valid;

    wire       txn_done;
    wire [2:0] grant_id;
    wire       grant_valid;

    axi_bus_arbiter u_arbiter (
        .clk        (clk),
        .rst_n      (rst_n),
        .req        (req),
        .txn_done   (txn_done),
        .grant_id   (grant_id),
        .grant_valid(grant_valid)
    );

    wire [31:0] g_aw_addr = (grant_id == 3'd0) ? m0_aw_addr : (grant_id == 3'd1) ? m1_aw_addr : (grant_id == 3'd2) ? m2_aw_addr : (grant_id == 3'd3) ? m3_aw_addr : m4_aw_addr;
    wire [31:0] g_ar_addr = (grant_id == 3'd0) ? m0_ar_addr : (grant_id == 3'd1) ? m1_ar_addr : (grant_id == 3'd2) ? m2_ar_addr : (grant_id == 3'd3) ? m3_ar_addr : m4_ar_addr;
    wire        g_aw_val  = grant_valid & ((grant_id == 3'd0) ? m0_aw_valid : (grant_id == 3'd1) ? m1_aw_valid : (grant_id == 3'd2) ? m2_aw_valid : (grant_id == 3'd3) ? m3_aw_valid : m4_aw_valid);
    wire        g_ar_val  = grant_valid & ((grant_id == 3'd0) ? m0_ar_valid : (grant_id == 3'd1) ? m1_ar_valid : (grant_id == 3'd2) ? m2_ar_valid : (grant_id == 3'd3) ? m3_ar_valid : m4_ar_valid);

    wire [3:0] slave_sel_wr, slave_sel_rd;
    wire       err_wr, err_rd;

    axi_address_decoder u_aw_dec (.addr(g_aw_addr), .slave_sel(slave_sel_wr), .decode_err(err_wr));
    axi_address_decoder u_ar_dec (.addr(g_ar_addr), .slave_sel(slave_sel_rd), .decode_err(err_rd));

    wire is_write = g_aw_val;
    wire is_read  = g_ar_val & ~g_aw_val;

    // Response Muxing
    wire slv_b_valid = (slave_sel_wr == 4'd2) ? s2_b_valid : (slave_sel_wr == 4'd3) ? s3_b_valid : (slave_sel_wr == 4'd4) ? s4_b_valid : (slave_sel_wr == 4'd5) ? s5_b_valid : (slave_sel_wr == 4'd6) ? s6_b_valid : (slave_sel_wr == 4'd7) ? s7_b_valid : (slave_sel_wr == 4'd8) ? s8_b_valid : 1'b0;
    wire slv_r_valid = (slave_sel_rd == 4'd0) ? s0_r_valid : (slave_sel_rd == 4'd1) ? s1_r_valid : (slave_sel_rd == 4'd2) ? s2_r_valid : (slave_sel_rd == 4'd3) ? s3_r_valid : (slave_sel_rd == 4'd4) ? s4_r_valid : (slave_sel_rd == 4'd5) ? s5_r_valid : (slave_sel_rd == 4'd6) ? s6_r_valid : (slave_sel_rd == 4'd7) ? s7_r_valid : (slave_sel_rd == 4'd8) ? s8_r_valid : 1'b0;

    wire g_b_ready = (grant_id == 3'd0) ? m0_b_ready : (grant_id == 3'd1) ? m1_b_ready : (grant_id == 3'd2) ? m2_b_ready : (grant_id == 3'd3) ? m3_b_ready : m4_b_ready;
    wire g_r_ready = (grant_id == 3'd0) ? m0_r_ready : (grant_id == 3'd1) ? m1_r_ready : (grant_id == 3'd2) ? m2_r_ready : (grant_id == 3'd3) ? m3_r_ready : m4_r_ready;

    assign txn_done = (is_write & slv_b_valid & g_b_ready) | (is_read & slv_r_valid & g_r_ready);

    assign axi_read_pulse  = is_read & slv_r_valid & g_r_ready;
    assign axi_write_pulse = is_write & slv_b_valid & g_b_ready;

    // Master Response Routing
    wire [31:0] slv_r_data = (slave_sel_rd == 4'd0) ? s0_r_data : (slave_sel_rd == 4'd1) ? s1_r_data : (slave_sel_rd == 4'd2) ? s2_r_data : (slave_sel_rd == 4'd3) ? s3_r_data : (slave_sel_rd == 4'd4) ? s4_r_data : (slave_sel_rd == 4'd5) ? s5_r_data : (slave_sel_rd == 4'd6) ? s6_r_data : (slave_sel_rd == 4'd7) ? s7_r_data : (slave_sel_rd == 4'd8) ? s8_r_data : 32'hDEAD_BEEF;

    assign m0_r_data = (grant_id == 3'd0 && grant_valid) ? slv_r_data : 32'b0;
    assign m0_r_valid= (grant_id == 3'd0 && grant_valid) ? slv_r_valid : 1'b0;
    assign m0_b_valid= (grant_id == 3'd0 && grant_valid) ? slv_b_valid : 1'b0;

    assign m1_r_data = (grant_id == 3'd1 && grant_valid) ? slv_r_data : 32'b0;
    assign m1_r_valid= (grant_id == 3'd1 && grant_valid) ? slv_r_valid : 1'b0;
    assign m1_b_valid= (grant_id == 3'd1 && grant_valid) ? slv_b_valid : 1'b0;

    assign m2_r_data = (grant_id == 3'd2 && grant_valid) ? slv_r_data : 32'b0;
    assign m2_r_valid= (grant_id == 3'd2 && grant_valid) ? slv_r_valid : 1'b0;
    assign m2_b_valid= (grant_id == 3'd2 && grant_valid) ? slv_b_valid : 1'b0;

    assign m3_r_data = (grant_id == 3'd3 && grant_valid) ? slv_r_data : 32'b0;
    assign m3_r_valid= (grant_id == 3'd3 && grant_valid) ? slv_r_valid : 1'b0;
    assign m3_b_valid= (grant_id == 3'd3 && grant_valid) ? slv_b_valid : 1'b0;

    assign m4_r_data = (grant_id == 3'd4 && grant_valid) ? slv_r_data : 32'b0;
    assign m4_r_valid= (grant_id == 3'd4 && grant_valid) ? slv_r_valid : 1'b0;
    assign m4_b_valid= (grant_id == 3'd4 && grant_valid) ? slv_b_valid : 1'b0;

    // Master Ready Routing
    assign m0_ar_ready = (grant_id == 3'd0 && is_read) ? 1'b1 : 1'b0;
    assign m0_aw_ready = (grant_id == 3'd0 && is_write) ? 1'b1 : 1'b0;
    assign m0_w_ready  = (grant_id == 3'd0 && is_write) ? 1'b1 : 1'b0;

    assign m1_ar_ready = (grant_id == 3'd1 && is_read) ? 1'b1 : 1'b0;
    assign m1_aw_ready = (grant_id == 3'd1 && is_write) ? 1'b1 : 1'b0;
    assign m1_w_ready  = (grant_id == 3'd1 && is_write) ? 1'b1 : 1'b0;

    assign m2_ar_ready = (grant_id == 3'd2 && is_read) ? 1'b1 : 1'b0;
    assign m2_aw_ready = (grant_id == 3'd2 && is_write) ? 1'b1 : 1'b0;
    assign m2_w_ready  = (grant_id == 3'd2 && is_write) ? 1'b1 : 1'b0;

    assign m3_ar_ready = (grant_id == 3'd3 && is_read) ? 1'b1 : 1'b0;
    assign m3_aw_ready = (grant_id == 3'd3 && is_write) ? 1'b1 : 1'b0;
    assign m3_w_ready  = (grant_id == 3'd3 && is_write) ? 1'b1 : 1'b0;

    assign m4_ar_ready = (grant_id == 3'd4 && is_read) ? 1'b1 : 1'b0;
    assign m4_aw_ready = (grant_id == 3'd4 && is_write) ? 1'b1 : 1'b0;
    assign m4_w_ready  = (grant_id == 3'd4 && is_write) ? 1'b1 : 1'b0;

    // Slave Port Connections
    assign s0_ar_addr = (is_read && slave_sel_rd == 4'd0) ? g_ar_addr : 32'b0;
    assign s0_ar_valid= (is_read && slave_sel_rd == 4'd0) ? g_ar_val  : 1'b0;

    assign s1_ar_addr = (is_read && slave_sel_rd == 4'd1) ? g_ar_addr : 32'b0;
    assign s1_ar_valid= (is_read && slave_sel_rd == 4'd1) ? g_ar_val  : 1'b0;

    assign s4_aw_addr = (is_write && slave_sel_wr == 4'd4) ? g_aw_addr : 32'b0;
    assign s4_aw_valid= (is_write && slave_sel_wr == 4'd4) ? g_aw_val  : 1'b0;
    assign s4_ar_addr = (is_read  && slave_sel_rd == 4'd4) ? g_ar_addr : 32'b0;
    assign s4_ar_valid= (is_read  && slave_sel_rd == 4'd4) ? g_ar_val  : 1'b0;

    assign s5_aw_addr = (is_write && slave_sel_wr == 4'd5) ? g_aw_addr : 32'b0;
    assign s5_aw_valid= (is_write && slave_sel_wr == 4'd5) ? g_aw_val  : 1'b0;
    assign s5_ar_addr = (is_read  && slave_sel_rd == 4'd5) ? g_ar_addr : 32'b0;
    assign s5_ar_valid= (is_read  && slave_sel_rd == 4'd5) ? g_ar_val  : 1'b0;

    assign s7_aw_addr = (is_write && slave_sel_wr == 4'd7) ? g_aw_addr : 32'b0;
    assign s7_aw_valid= (is_write && slave_sel_wr == 4'd7) ? g_aw_val  : 1'b0;
    assign s7_ar_addr = (is_read  && slave_sel_rd == 4'd7) ? g_ar_addr : 32'b0;
    assign s7_ar_valid= (is_read  && slave_sel_rd == 4'd7) ? g_ar_val  : 1'b0;

    assign s8_aw_addr = (is_write && slave_sel_wr == 4'd8) ? g_aw_addr : 32'b0;
    assign s8_aw_valid= (is_write && slave_sel_wr == 4'd8) ? g_aw_val  : 1'b0;
    assign s8_ar_addr = (is_read  && slave_sel_rd == 4'd8) ? g_ar_addr : 32'b0;
    assign s8_ar_valid= (is_read  && slave_sel_rd == 4'd8) ? g_ar_val  : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            snoop_addr     <= 32'b0;
            snoop_wr_valid <= 1'b0;
        end else begin
            snoop_wr_valid <= is_write & g_aw_val;
            snoop_addr     <= g_aw_addr;
        end
    end

endmodule
