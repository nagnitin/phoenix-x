// =============================================================================
// Module      : pmu_counters
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T (Nexys A7-100T)
// Description : Hardware Performance Monitoring Unit (PMU).
//               Measures real-time system telemetry:
//               - Total Clock Cycles
//               - CPU0 & CPU1 Executed Instruction Count
//               - GPU Active Utilization Cycles
//               - NPU Active Utilization Cycles
//               - AXI Read & Write Memory Bandwidth
//
// REGISTER MAP (base: 0x0020_0380):
//   0x00: CYCLES_LO          [31:0] Total system clock cycles (Lower 32-bit)
//   0x04: CYCLES_HI          [31:0] Total system clock cycles (Upper 32-bit)
//   0x08: CPU0_INSTR_COUNT   [31:0] Instructions executed by CPU0
//   0x0C: CPU1_INSTR_COUNT   [31:0] Instructions executed by CPU1
//   0x10: GPU_ACTIVE_CYCLES  [31:0] Clock cycles GPU was rendering
//   0x14: NPU_ACTIVE_CYCLES  [31:0] Clock cycles NPU was computing
//   0x18: AXI_READ_BYTES     [31:0] Total bytes read over AXI bus
//   0x1C: AXI_WRITE_BYTES    [31:0] Total bytes written over AXI bus
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module pmu_counters (
    input  wire        clk,
    input  wire        rst_n,

    // Performance telemetry inputs from hardware engines
    input  wire        cpu0_instr_valid,
    input  wire        cpu1_instr_valid,
    input  wire        gpu_busy,
    input  wire        npu_busy,
    input  wire        axi_read_pulse,     // 1-cycle pulse per 4-byte AXI read
    input  wire        axi_write_pulse,    // 1-cycle pulse per 4-byte AXI write

    // -------------------------------------------------------------------------
    // AXI-4 Lite Slave Port (CPU reads telemetry statistics)
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Hardware Counter Registers
    // -------------------------------------------------------------------------
    reg [63:0] total_cycles;
    reg [31:0] cpu0_instr_cnt;
    reg [31:0] cpu1_instr_cnt;
    reg [31:0] gpu_active_cycles;
    reg [31:0] npu_active_cycles;
    reg [31:0] axi_read_bytes;
    reg [31:0] axi_write_bytes;

    // Counter Increment Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_cycles      <= 64'd0;
            cpu0_instr_cnt    <= 32'd0;
            cpu1_instr_cnt    <= 32'd0;
            gpu_active_cycles <= 32'd0;
            npu_active_cycles <= 32'd0;
            axi_read_bytes    <= 32'd0;
            axi_write_bytes   <= 32'd0;
        end else begin
            total_cycles <= total_cycles + 64'd1;

            if (cpu0_instr_valid)
                cpu0_instr_cnt <= cpu0_instr_cnt + 32'd1;

            if (cpu1_instr_valid)
                cpu1_instr_cnt <= cpu1_instr_cnt + 32'd1;

            if (gpu_busy)
                gpu_active_cycles <= gpu_active_cycles + 32'd1;

            if (npu_busy)
                npu_active_cycles <= npu_active_cycles + 32'd1;

            if (axi_read_pulse)
                axi_read_bytes <= axi_read_bytes + 32'd4;

            if (axi_write_pulse)
                axi_write_bytes <= axi_write_bytes + 32'd4;
        end
    end

    // -------------------------------------------------------------------------
    // AXI Slave Interface (Read Telemetry)
    // -------------------------------------------------------------------------
    localparam ST_IDLE  = 2'd0;
    localparam ST_WDATA = 2'd1;
    localparam ST_WRESP = 2'd2;
    localparam ST_RDATA = 2'd3;

    reg [1:0]  state;
    reg [31:0] ar_addr_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
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

            case (state)
                ST_IDLE: begin
                    if (s_aw_valid) begin
                        s_aw_ready <= 1'b1;
                        state      <= ST_WDATA;
                    end else if (s_ar_valid) begin
                        s_ar_ready <= 1'b1;
                        ar_addr_r  <= s_ar_addr;
                        state      <= ST_RDATA;
                    end
                end

                ST_WDATA: begin
                    s_w_ready <= 1'b1;
                    if (s_w_valid) begin
                        s_w_ready <= 1'b0;
                        s_b_resp  <= `AXI_RESP_OKAY;
                        state     <= ST_WRESP;
                    end
                end

                ST_WRESP: begin
                    s_b_valid <= 1'b1;
                    if (s_b_valid && s_b_ready) begin
                        s_b_valid <= 1'b0;
                        state     <= ST_IDLE;
                    end
                end

                ST_RDATA: begin
                    case (ar_addr_r[4:2])
                        3'd0: s_r_data <= total_cycles[31:0];
                        3'd1: s_r_data <= total_cycles[63:32];
                        3'd2: s_r_data <= cpu0_instr_cnt;
                        3'd3: s_r_data <= cpu1_instr_cnt;
                        3'd4: s_r_data <= gpu_active_cycles;
                        3'd5: s_r_data <= npu_active_cycles;
                        3'd6: s_r_data <= axi_read_bytes;
                        3'd7: s_r_data <= axi_write_bytes;
                        default: s_r_data <= 32'h504D_0001;
                    endcase
                    s_r_resp  <= `AXI_RESP_OKAY;
                    s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin
                        s_r_valid <= 1'b0;
                        state     <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
