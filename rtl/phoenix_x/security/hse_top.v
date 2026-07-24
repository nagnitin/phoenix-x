// =============================================================================
// Module      : hse_top
// Project     : Phoenix-X Phase 4 — Hardware Security Engine (HSE)
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Hardware Security Engine top-level integrating:
//               - Memory Protection Unit (mpu.v)        @ 0x0020_0600–062F
//               - Hardware Trojan Detection Engine       @ 0x0020_0640–065F
//               Combined AXI Slave config interface at   0x0020_0600–06FF
//               Combined IRQ output to Shared PIC.
// =============================================================================

`timescale 1ns/1ps
`include "rtl/phoenix_x/axi/axi_defines.vh"

module hse_top (
    input  wire        clk,
    input  wire        rst_n,

    // CPU Privilege Levels
    input  wire [1:0]  cpu0_priv_level,
    input  wire [1:0]  cpu1_priv_level,

    // CPU Pipeline Activity & Debug Bus
    input  wire        cpu0_pipe_valid,
    input  wire        cpu1_pipe_valid,
    input  wire [31:0] cpu0_pc,    input wire [31:0] cpu0_instr,  input wire cpu0_dbu_valid,
    input  wire [31:0] cpu1_pc,    input wire [31:0] cpu1_instr,  input wire cpu1_dbu_valid,

    // AXI Transaction Monitor (from AXI crossbar snoops)
    input  wire [31:0] m0_aw_addr,  input wire m0_aw_valid,
    input  wire [31:0] m0_ar_addr,  input wire m0_ar_valid,
    input  wire [31:0] m1_aw_addr,  input wire m1_aw_valid,
    input  wire [31:0] m1_ar_addr,  input wire m1_ar_valid,
    input  wire [31:0] m2_aw_addr,  input wire m2_aw_valid,
    input  wire [31:0] m2_ar_addr,  input wire m2_ar_valid,
    input  wire        m3_aw_valid, m4_aw_valid,

    // Security Outputs
    output wire        mpu_fault,
    output wire [31:0] fault_addr,
    output wire [1:0]  fault_type,
    output wire        trojan_alert,
    output wire [31:0] trojan_fault_report,
    output wire        hse_irq,          // Combined IRQ to Shared PIC

    // AXI-4 Lite Config Slave (0x0020_0600–06FF)
    input  wire [31:0] s_aw_addr,   input wire s_aw_valid,  output wire s_aw_ready,
    input  wire [31:0] s_w_data,    input wire [3:0] s_w_strb,
    input  wire        s_w_valid,   output wire s_w_ready,
    output wire [1:0]  s_b_resp,    output wire s_b_valid,  input wire s_b_ready,
    input  wire [31:0] s_ar_addr,   input wire s_ar_valid,  output wire s_ar_ready,
    output wire [31:0] s_r_data,    output wire [1:0] s_r_resp,
    output wire        s_r_valid,   input wire s_r_ready
);

    // Sub-module decode: offset < 0x40 → MPU, offset >= 0x40 → Trojan Monitor
    wire is_mpu     = (s_aw_addr[7:6] == 2'b00) | (s_ar_addr[7:6] == 2'b00);
    wire is_trojan  = (s_aw_addr[7:6] != 2'b00) | (s_ar_addr[7:6] != 2'b00);

    wire mpu_irq, trojan_irq;
    wire [2:0] fault_master_id;
    wire [4:0] trojan_alert_ch;

    // MPU AXI signals
    wire [31:0] mpu_r_data; wire [1:0] mpu_r_resp, mpu_b_resp;
    wire        mpu_aw_ready, mpu_w_ready, mpu_b_valid, mpu_ar_ready, mpu_r_valid;

    // Trojan Monitor AXI signals
    wire [31:0] td_r_data;  wire [1:0] td_r_resp, td_b_resp;
    wire        td_aw_ready, td_w_ready, td_b_valid, td_ar_ready, td_r_valid;

    // -------------------------------------------------------------------------
    // Sub-module: Memory Protection Unit
    // -------------------------------------------------------------------------
    mpu u_mpu (
        .clk(clk), .rst_n(rst_n),
        .cpu0_priv_level(cpu0_priv_level), .cpu1_priv_level(cpu1_priv_level),
        .m0_aw_addr(m0_aw_addr), .m0_aw_valid(m0_aw_valid),
        .m0_ar_addr(m0_ar_addr), .m0_ar_valid(m0_ar_valid),
        .m1_aw_addr(m1_aw_addr), .m1_aw_valid(m1_aw_valid),
        .m1_ar_addr(m1_ar_addr), .m1_ar_valid(m1_ar_valid),
        .m2_aw_addr(m2_aw_addr), .m2_aw_valid(m2_aw_valid),
        .m2_ar_addr(m2_ar_addr), .m2_ar_valid(m2_ar_valid),
        .mpu_fault(mpu_fault), .fault_addr(fault_addr), .fault_type(fault_type),
        .fault_master_id(fault_master_id), .mpu_irq(mpu_irq),
        .s_aw_addr(s_aw_addr), .s_aw_valid(s_aw_valid & is_mpu), .s_aw_ready(mpu_aw_ready),
        .s_w_data(s_w_data),   .s_w_strb(s_w_strb),  .s_w_valid(s_w_valid), .s_w_ready(mpu_w_ready),
        .s_b_resp(mpu_b_resp), .s_b_valid(mpu_b_valid), .s_b_ready(s_b_ready),
        .s_ar_addr(s_ar_addr), .s_ar_valid(s_ar_valid & is_mpu), .s_ar_ready(mpu_ar_ready),
        .s_r_data(mpu_r_data), .s_r_resp(mpu_r_resp), .s_r_valid(mpu_r_valid), .s_r_ready(s_r_ready)
    );

    // -------------------------------------------------------------------------
    // Sub-module: Hardware Trojan Detection Engine
    // -------------------------------------------------------------------------
    trojan_monitor u_trojan (
        .clk(clk), .rst_n(rst_n),
        .m0_ar_valid(m0_ar_valid), .m0_aw_valid(m0_aw_valid),
        .m1_ar_valid(m1_ar_valid), .m1_aw_valid(m1_aw_valid),
        .m2_ar_valid(m2_ar_valid), .m2_aw_valid(m2_aw_valid),
        .m3_aw_valid(m3_aw_valid), .m4_aw_valid(m4_aw_valid),
        .cpu0_pipe_valid(cpu0_pipe_valid), .cpu1_pipe_valid(cpu1_pipe_valid),
        .cpu0_pc(cpu0_pc), .cpu0_instr(cpu0_instr), .cpu0_dbu_valid(cpu0_dbu_valid),
        .cpu1_pc(cpu1_pc), .cpu1_instr(cpu1_instr), .cpu1_dbu_valid(cpu1_dbu_valid),
        .mpu_fault(mpu_fault),
        .trojan_alert(trojan_alert), .trojan_irq(trojan_irq),
        .fault_report(trojan_fault_report), .alert_channel(trojan_alert_ch),
        .s_aw_addr(s_aw_addr), .s_aw_valid(s_aw_valid & is_trojan), .s_aw_ready(td_aw_ready),
        .s_w_data(s_w_data),   .s_w_strb(s_w_strb),  .s_w_valid(s_w_valid), .s_w_ready(td_w_ready),
        .s_b_resp(td_b_resp),  .s_b_valid(td_b_valid), .s_b_ready(s_b_ready),
        .s_ar_addr(s_ar_addr), .s_ar_valid(s_ar_valid & is_trojan), .s_ar_ready(td_ar_ready),
        .s_r_data(td_r_data),  .s_r_resp(td_r_resp), .s_r_valid(td_r_valid), .s_r_ready(s_r_ready)
    );

    // -------------------------------------------------------------------------
    // Mux AXI response back to master based on which sub-slave was addressed
    // -------------------------------------------------------------------------
    assign s_aw_ready = is_mpu     ? mpu_aw_ready : td_aw_ready;
    assign s_w_ready  = is_mpu     ? mpu_w_ready  : td_w_ready;
    assign s_b_resp   = is_mpu     ? mpu_b_resp   : td_b_resp;
    assign s_b_valid  = is_mpu     ? mpu_b_valid  : td_b_valid;
    assign s_ar_ready = is_mpu     ? mpu_ar_ready : td_ar_ready;
    assign s_r_data   = is_mpu     ? mpu_r_data   : td_r_data;
    assign s_r_resp   = is_mpu     ? mpu_r_resp   : td_r_resp;
    assign s_r_valid  = is_mpu     ? mpu_r_valid  : td_r_valid;

    // Combined IRQ to Shared PIC
    assign hse_irq = mpu_irq | trojan_irq;

endmodule
