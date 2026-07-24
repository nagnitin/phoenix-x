// =============================================================================
// Module      : power_monitor
// Project     : Phoenix-X Phase 4 — Dynamic Power Optimization Unit (DPOU)
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Dynamic Power Optimization Unit implementing:
//               1. Fine-grained BUFGCE Clock Gating per compute unit
//               2. Operand Isolation to prevent spurious switching activity
//               3. Power Domain Controller (SW-controlled unit shutdown)
//               4. Toggle Rate Sampler for dynamic power estimation
//
// Power Measurement Methodology:
//   Dynamic Power ∝ α × C × V² × f × toggle_rate
//   where α = activity factor (measured via XOR-based toggle counter)
//
// Idle Detection:
//   A unit is declared IDLE if no valid transaction occurs for IDLE_THRESH
//   consecutive cycles (default 256). Clock is then gated via BUFGCE.
//
// AXI Slave Config @ 0x0020_0700:
//   0x00: POWER_CTRL    — SW power domain enable [4:0] (1=ON)
//   0x04: IDLE_THRESH   — Idle detection threshold (default 256)
//   0x08: SAMPLE_PERIOD — Toggle rate sample window (default 4096)
//   0x10: STATUS_GPU    — GPU toggle count (read-only)
//   0x14: STATUS_NPU    — NPU toggle count (read-only)
//   0x18: STATUS_CPU0   — CPU0 toggle count (read-only)
//   0x1C: STATUS_CPU1   — CPU1 toggle count (read-only)
//   0x20: STATUS_DMA    — DMA toggle count (read-only)
//   0x24: CLOCK_ACTIVE  — Clock activity % × 100 (estimated)
// =============================================================================

`timescale 1ns/1ps
`include "rtl/phoenix_x/axi/axi_defines.vh"

module power_monitor (
    input  wire        clk,
    input  wire        rst_n,

    // Unit Activity Signals (used for idle detection & toggle counting)
    input  wire        gpu_busy,
    input  wire        npu_busy,
    input  wire        cpu0_pipe_valid,
    input  wire        cpu1_pipe_valid,
    input  wire        dma_active,

    // AXI Activity (for toggle counting)
    input  wire        m0_aw_valid, m0_ar_valid,
    input  wire        m1_aw_valid, m1_ar_valid,
    input  wire        m3_aw_valid,   // GPU AXI
    input  wire        m4_ar_valid,   // NPU AXI

    // Clock Gate Enable Outputs (active HIGH = clock runs)
    output reg         clk_en_gpu,
    output reg         clk_en_npu,
    output reg         clk_en_cpu0,
    output reg         clk_en_cpu1,
    output reg         clk_en_dma,

    // Operand Isolation Enables (HIGH = isolate/zero inputs)
    output reg         iso_gpu,
    output reg         iso_npu,

    // AXI-4 Lite Config Slave
    input  wire [31:0] s_aw_addr,   input wire s_aw_valid,  output reg s_aw_ready,
    input  wire [31:0] s_w_data,    input wire [3:0] s_w_strb,
    input  wire        s_w_valid,   output reg s_w_ready,
    output reg  [1:0]  s_b_resp,    output reg s_b_valid,   input wire s_b_ready,
    input  wire [31:0] s_ar_addr,   input wire s_ar_valid,  output reg s_ar_ready,
    output reg  [31:0] s_r_data,    output reg [1:0] s_r_resp,
    output reg         s_r_valid,   input wire s_r_ready
);

    // -------------------------------------------------------------------------
    // Configuration Registers
    // -------------------------------------------------------------------------
    reg [4:0]  reg_power_ctrl;      // bit i: 1=unit i powered ON
    reg [15:0] reg_idle_thresh;     // Idle detection threshold (default 256)
    reg [15:0] reg_sample_period;   // Toggle rate sample window (default 4096)

    // -------------------------------------------------------------------------
    // Idle Detection Counters per Unit
    // -------------------------------------------------------------------------
    reg [15:0] idle_gpu, idle_npu, idle_cpu0, idle_cpu1, idle_dma;

    // -------------------------------------------------------------------------
    // Toggle Rate Counters (XOR-based activity counting)
    // prev_* registers track last-cycle value; XOR detects bit transitions
    // -------------------------------------------------------------------------
    reg [31:0] toggle_gpu_cnt, toggle_npu_cnt, toggle_cpu0_cnt, toggle_cpu1_cnt, toggle_dma_cnt;
    reg [31:0] sample_cnt;
    reg        gpu_busy_prev, npu_busy_prev, cpu0_prev, cpu1_prev, dma_prev;

    // Toggle rate snapshot registers (updated each sample window)
    reg [31:0] snap_gpu, snap_npu, snap_cpu0, snap_cpu1, snap_dma;
    reg [31:0] clock_active_pct;  // Estimated clock activity %

    // -------------------------------------------------------------------------
    // Idle Detection & Clock Gate Control
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idle_gpu <= 16'h0; idle_npu <= 16'h0; idle_cpu0 <= 16'h0;
            idle_cpu1 <= 16'h0; idle_dma <= 16'h0;
            clk_en_gpu <= 1'b1; clk_en_npu <= 1'b1;
            clk_en_cpu0 <= 1'b1; clk_en_cpu1 <= 1'b1; clk_en_dma <= 1'b1;
            iso_gpu <= 1'b0; iso_npu <= 1'b0;
            reg_power_ctrl <= 5'b11111;
            reg_idle_thresh <= 16'd256;
            reg_sample_period <= 16'd4096;
        end else begin
            // GPU Idle Detection
            if (gpu_busy | m3_aw_valid) idle_gpu <= 16'h0;
            else if (idle_gpu < reg_idle_thresh) idle_gpu <= idle_gpu + 1'b1;
            clk_en_gpu  <= reg_power_ctrl[2] & (idle_gpu < reg_idle_thresh);
            iso_gpu     <= ~clk_en_gpu;

            // NPU Idle Detection
            if (npu_busy | m4_ar_valid) idle_npu <= 16'h0;
            else if (idle_npu < reg_idle_thresh) idle_npu <= idle_npu + 1'b1;
            clk_en_npu  <= reg_power_ctrl[3] & (idle_npu < reg_idle_thresh);
            iso_npu     <= ~clk_en_npu;

            // CPU0 Idle Detection
            if (cpu0_pipe_valid | m0_aw_valid | m0_ar_valid) idle_cpu0 <= 16'h0;
            else if (idle_cpu0 < reg_idle_thresh) idle_cpu0 <= idle_cpu0 + 1'b1;
            clk_en_cpu0 <= reg_power_ctrl[0] & (idle_cpu0 < reg_idle_thresh);

            // CPU1 Idle Detection
            if (cpu1_pipe_valid | m1_aw_valid | m1_ar_valid) idle_cpu1 <= 16'h0;
            else if (idle_cpu1 < reg_idle_thresh) idle_cpu1 <= idle_cpu1 + 1'b1;
            clk_en_cpu1 <= reg_power_ctrl[1] & (idle_cpu1 < reg_idle_thresh);

            // DMA Idle Detection
            if (dma_active) idle_dma <= 16'h0;
            else if (idle_dma < reg_idle_thresh) idle_dma <= idle_dma + 1'b1;
            clk_en_dma  <= reg_power_ctrl[4] & (idle_dma < reg_idle_thresh);
        end
    end

    // -------------------------------------------------------------------------
    // Toggle Rate Measurement
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            toggle_gpu_cnt <= 32'h0; toggle_npu_cnt <= 32'h0;
            toggle_cpu0_cnt <= 32'h0; toggle_cpu1_cnt <= 32'h0; toggle_dma_cnt <= 32'h0;
            gpu_busy_prev <= 1'b0; npu_busy_prev <= 1'b0;
            cpu0_prev <= 1'b0; cpu1_prev <= 1'b0; dma_prev <= 1'b0;
            sample_cnt <= 32'h0;
            snap_gpu <= 32'h0; snap_npu <= 32'h0; snap_cpu0 <= 32'h0; snap_cpu1 <= 32'h0; snap_dma <= 32'h0;
            clock_active_pct <= 32'h0;
        end else begin
            // XOR-based toggle counting (1 = a bit changed)
            if (gpu_busy ^ gpu_busy_prev)   toggle_gpu_cnt  <= toggle_gpu_cnt  + 1'b1;
            if (npu_busy ^ npu_busy_prev)   toggle_npu_cnt  <= toggle_npu_cnt  + 1'b1;
            if (cpu0_pipe_valid ^ cpu0_prev) toggle_cpu0_cnt <= toggle_cpu0_cnt + 1'b1;
            if (cpu1_pipe_valid ^ cpu1_prev) toggle_cpu1_cnt <= toggle_cpu1_cnt + 1'b1;
            if (dma_active ^ dma_prev)       toggle_dma_cnt  <= toggle_dma_cnt  + 1'b1;

            gpu_busy_prev <= gpu_busy; npu_busy_prev <= npu_busy;
            cpu0_prev <= cpu0_pipe_valid; cpu1_prev <= cpu1_pipe_valid; dma_prev <= dma_active;

            sample_cnt <= sample_cnt + 1'b1;
            if (sample_cnt >= {16'h0, reg_sample_period}) begin
                sample_cnt <= 32'h0;
                snap_gpu   <= toggle_gpu_cnt;  toggle_gpu_cnt  <= 32'h0;
                snap_npu   <= toggle_npu_cnt;  toggle_npu_cnt  <= 32'h0;
                snap_cpu0  <= toggle_cpu0_cnt; toggle_cpu0_cnt <= 32'h0;
                snap_cpu1  <= toggle_cpu1_cnt; toggle_cpu1_cnt <= 32'h0;
                snap_dma   <= toggle_dma_cnt;  toggle_dma_cnt  <= 32'h0;
                // Clock activity % = (clk_en units / total units) × 100
                clock_active_pct <= ((clk_en_gpu + clk_en_npu + clk_en_cpu0 + clk_en_cpu1 + clk_en_dma) * 32'd20);
            end
        end
    end

    // -------------------------------------------------------------------------
    // AXI Config Slave FSM
    // -------------------------------------------------------------------------
    localparam PM_IDLE = 2'd0, PM_WDATA = 2'd1, PM_WRESP = 2'd2, PM_RDATA = 2'd3;
    reg [1:0]  pm_state;
    reg [31:0] pm_aw_addr_r, pm_ar_addr_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pm_state <= PM_IDLE; s_aw_ready <= 1'b0; s_w_ready <= 1'b0; s_b_valid <= 1'b0;
            s_ar_ready <= 1'b0; s_r_valid <= 1'b0;
        end else begin
            s_aw_ready <= 1'b0; s_w_ready <= 1'b0; s_ar_ready <= 1'b0; s_b_valid <= 1'b0; s_r_valid <= 1'b0;
            case (pm_state)
                PM_IDLE: begin
                    if (s_aw_valid) begin s_aw_ready <= 1'b1; pm_aw_addr_r <= s_aw_addr; pm_state <= PM_WDATA; end
                    else if (s_ar_valid) begin s_ar_ready <= 1'b1; pm_ar_addr_r <= s_ar_addr; pm_state <= PM_RDATA; end
                end
                PM_WDATA: begin
                    s_w_ready <= 1'b1;
                    if (s_w_valid) begin
                        case (pm_aw_addr_r[4:2])
                            3'd0: reg_power_ctrl    <= s_w_data[4:0];
                            3'd1: reg_idle_thresh   <= s_w_data[15:0];
                            3'd2: reg_sample_period <= s_w_data[15:0];
                            default: ;
                        endcase
                        s_b_resp <= `AXI_RESP_OKAY; pm_state <= PM_WRESP;
                    end
                end
                PM_WRESP: begin s_b_valid <= 1'b1; if (s_b_valid && s_b_ready) begin s_b_valid <= 1'b0; pm_state <= PM_IDLE; end end
                PM_RDATA: begin
                    case (pm_ar_addr_r[4:2])
                        3'd0: s_r_data <= {27'b0, reg_power_ctrl};
                        3'd1: s_r_data <= {16'b0, reg_idle_thresh};
                        3'd2: s_r_data <= {16'b0, reg_sample_period};
                        3'd3: s_r_data <= {12'b0, idle_gpu, 4'b0};
                        3'd4: s_r_data <= snap_gpu;
                        3'd5: s_r_data <= snap_npu;
                        3'd6: s_r_data <= snap_cpu0;
                        3'd7: s_r_data <= snap_cpu1;
                        default: s_r_data <= clock_active_pct;
                    endcase
                    s_r_resp <= `AXI_RESP_OKAY; s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin s_r_valid <= 1'b0; pm_state <= PM_IDLE; end
                end
            endcase
        end
    end

endmodule
