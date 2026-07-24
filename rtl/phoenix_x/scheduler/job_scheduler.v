// =============================================================================
// Module      : job_scheduler
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T (Nexys A7-100T)
// Description : Hardware Job Scheduler for Heterogeneous Engines (GPU, NPU, DMA).
//               Accepts acceleration job submissions from CPU cores into a FIFO,
//               dispatches tasks to target engines when IDLE, tracks status,
//               and generates completion interrupts to the Shared PIC.
//
// REGISTER MAP (base: 0x0020_0300):
//   0x00: JOB_TYPE     (0=DMA, 1=GPU, 2=NPU)
//   0x04: PARAM_0      (Source Addr / Command Word / Mat A Addr)
//   0x08: PARAM_1      (Dest Addr / Mat B Addr)
//   0x0C: PARAM_2      (Length / Mat C Addr)
//   0x10: SUBMIT_JOB   (Write 1 to push job to Hardware Queue)
//   0x14: STATUS       [0]=SCHED_BUSY, [1]=GPU_BUSY, [2]=NPU_BUSY, [3]=DMA_BUSY
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module job_scheduler (
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // AXI-4 Lite Slave Port (CPU queues jobs via registers)
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
    input  wire        s_r_ready,

    // -------------------------------------------------------------------------
    // Accelerator Signals (GPU, NPU, DMA)
    // -------------------------------------------------------------------------
    input  wire        gpu_busy,
    input  wire        gpu_done_irq,
    output reg  [31:0] gpu_cmd_word,
    output reg         gpu_cmd_valid,

    input  wire        npu_busy,
    input  wire        npu_done_irq,
    output reg  [31:0] npu_mat_a, npu_mat_b, npu_mat_c,
    output reg         npu_start_cmd,

    input  wire [3:0]  dma_busy,
    input  wire [3:0]  dma_done_irq,
    output reg  [31:0] dma_src, dma_dst, dma_len,
    output reg         dma_start_cmd,

    // Interrupt output to Shared PIC
    output reg         scheduler_irq
);

    // -------------------------------------------------------------------------
    // Config Registers
    // -------------------------------------------------------------------------
    reg [31:0] reg_job_type;
    reg [31:0] reg_param_0;
    reg [31:0] reg_param_1;
    reg [31:0] reg_param_2;
    reg        submit_pulse;

    // -------------------------------------------------------------------------
    // Job Queue FIFO (8 Job Descriptors)
    // -------------------------------------------------------------------------
    reg [31:0] q_job_type [0:7];
    reg [31:0] q_param_0  [0:7];
    reg [31:0] q_param_1  [0:7];
    reg [31:0] q_param_2  [0:7];
    reg [2:0]  q_head, q_tail;
    reg [3:0]  q_count;

    wire q_full  = (q_count == 4'd8);
    wire q_empty = (q_count == 4'd0);

    // -------------------------------------------------------------------------
    // AXI Slave Register FSM
    // -------------------------------------------------------------------------
    localparam ST_IDLE  = 2'd0;
    localparam ST_WDATA = 2'd1;
    localparam ST_WRESP = 2'd2;
    localparam ST_RDATA = 2'd3;

    reg [1:0]  sl_state;
    reg [31:0] aw_addr_r, ar_addr_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sl_state     <= ST_IDLE;
            s_aw_ready   <= 1'b0;
            s_w_ready    <= 1'b0;
            s_b_valid    <= 1'b0;
            s_b_resp     <= `AXI_RESP_OKAY;
            s_ar_ready   <= 1'b0;
            s_r_valid    <= 1'b0;
            s_r_data     <= 32'b0;
            s_r_resp     <= `AXI_RESP_OKAY;
            reg_job_type <= 32'b0;
            reg_param_0  <= 32'b0;
            reg_param_1  <= 32'b0;
            reg_param_2  <= 32'b0;
            submit_pulse <= 1'b0;
        end else begin
            s_aw_ready   <= 1'b0;
            s_w_ready    <= 1'b0;
            s_ar_ready   <= 1'b0;
            s_b_valid    <= 1'b0;
            s_r_valid    <= 1'b0;
            submit_pulse <= 1'b0;

            case (sl_state)
                ST_IDLE: begin
                    if (s_aw_valid) begin
                        s_aw_ready <= 1'b1;
                        aw_addr_r  <= s_aw_addr;
                        sl_state   <= ST_WDATA;
                    end else if (s_ar_valid) begin
                        s_ar_ready <= 1'b1;
                        ar_addr_r  <= s_ar_addr;
                        sl_state   <= ST_RDATA;
                    end
                end

                ST_WDATA: begin
                    s_w_ready <= 1'b1;
                    if (s_w_valid) begin
                        s_w_ready <= 1'b0;
                        case (aw_addr_r[4:2])
                            3'd0: reg_job_type <= s_w_data;
                            3'd1: reg_param_0  <= s_w_data;
                            3'd2: reg_param_1  <= s_w_data;
                            3'd3: reg_param_2  <= s_w_data;
                            3'd4: submit_pulse <= s_w_data[0];
                            default: ;
                        endcase
                        s_b_resp <= `AXI_RESP_OKAY;
                        sl_state <= ST_WRESP;
                    end
                end

                ST_WRESP: begin
                    s_b_valid <= 1'b1;
                    if (s_b_valid && s_b_ready) begin
                        s_b_valid <= 1'b0;
                        sl_state  <= ST_IDLE;
                    end
                end

                ST_RDATA: begin
                    case (ar_addr_r[4:2])
                        3'd0: s_r_data <= reg_job_type;
                        3'd1: s_r_data <= reg_param_0;
                        3'd2: s_r_data <= reg_param_1;
                        3'd3: s_r_data <= reg_param_2;
                        3'd5: s_r_data <= {28'b0, |dma_busy, npu_busy, gpu_busy, !q_empty};
                        default: s_r_data <= 32'h5343_0001;
                    endcase
                    s_r_resp  <= `AXI_RESP_OKAY;
                    s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin
                        s_r_valid <= 1'b0;
                        sl_state  <= ST_IDLE;
                    end
                end

                default: sl_state <= ST_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Queue Push & Dispatch Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_head        <= 3'd0;
            q_tail        <= 3'd0;
            q_count       <= 4'd0;
            gpu_cmd_word  <= 32'b0;
            gpu_cmd_valid <= 1'b0;
            npu_mat_a     <= 32'b0;
            npu_mat_b     <= 32'b0;
            npu_mat_c     <= 32'b0;
            npu_start_cmd <= 1'b0;
            dma_src       <= 32'b0;
            dma_dst       <= 32'b0;
            dma_len       <= 32'b0;
            dma_start_cmd <= 1'b0;
            scheduler_irq <= 1'b0;
        end else begin
            gpu_cmd_valid <= 1'b0;
            npu_start_cmd <= 1'b0;
            dma_start_cmd <= 1'b0;
            scheduler_irq <= gpu_done_irq | npu_done_irq | (|dma_done_irq);

            // Job Push
            if (submit_pulse && !q_full) begin
                q_job_type[q_tail] <= reg_job_type;
                q_param_0[q_tail]  <= reg_param_0;
                q_param_1[q_tail]  <= reg_param_1;
                q_param_2[q_tail]  <= reg_param_2;
                q_tail             <= q_tail + 3'd1;
                q_count            <= q_count + 4'd1;
            end

            // Job Dispatch to Engines when IDLE
            if (!q_empty) begin
                case (q_job_type[q_head])
                    32'd0: begin // DMA Job
                        if (!(|dma_busy)) begin
                            dma_src       <= q_param_0[q_head];
                            dma_dst       <= q_param_1[q_head];
                            dma_len       <= q_param_2[q_head];
                            dma_start_cmd <= 1'b1;
                            q_head        <= q_head + 3'd1;
                            q_count       <= q_count - 4'd1;
                        end
                    end

                    32'd1: begin // GPU Job
                        if (!gpu_busy) begin
                            gpu_cmd_word  <= q_param_0[q_head];
                            gpu_cmd_valid <= 1'b1;
                            q_head        <= q_head + 3'd1;
                            q_count       <= q_count - 4'd1;
                        end
                    end

                    32'd2: begin // NPU Job
                        if (!npu_busy) begin
                            npu_mat_a     <= q_param_0[q_head];
                            npu_mat_b     <= q_param_1[q_head];
                            npu_mat_c     <= q_param_2[q_head];
                            npu_start_cmd <= 1'b1;
                            q_head        <= q_head + 3'd1;
                            q_count       <= q_count - 4'd1;
                        end
                    end

                    default: begin
                        // Skip invalid job
                        q_head  <= q_head + 3'd1;
                        q_count <= q_count - 4'd1;
                    end
                endcase
            end
        end
    end

endmodule
