// =============================================================================
// Module      : npu_top
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T (Nexys A7-100T)
// Description : Dedicated Neural Processing Unit (NPU) Top-Level Module.
//               Executes hardware GEMM (General Matrix Multiply) operations on
//               INT8 tensors using a 4×4 Systolic MAC Array.
//
// AXI SLAVE REGISTERS (base: 0x0020_0500):
//   0x00: MAT_A_ADDR   (32-bit byte address of Matrix A in SRAM/DRAM)
//   0x04: MAT_B_ADDR   (32-bit byte address of Matrix B in SRAM/DRAM)
//   0x08: MAT_C_ADDR   (32-bit byte address of Output Matrix C)
//   0x0C: CTRL         [0]=START, [2:1]=ACT_MODE (0=None, 1=ReLU, 2=LeakyReLU)
//   0x10: STATUS       [0]=BUSY, [1]=DONE
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module npu_top (
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // AXI-4 Lite Slave Port (Configuration Registers)
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
    // AXI-4 Lite Master Port (Memory Data Streaming for Weights & Feature Maps)
    // -------------------------------------------------------------------------
    output reg  [31:0] m_ar_addr,
    output reg         m_ar_valid,
    input  wire        m_ar_ready,
    input  wire [31:0] m_r_data,
    input  wire [ 1:0] m_r_resp,
    input  wire        m_r_valid,
    output reg         m_r_ready,
    output reg  [31:0] m_aw_addr,
    output reg         m_aw_valid,
    input  wire        m_aw_ready,
    output reg  [31:0] m_w_data,
    output reg  [ 3:0] m_w_strb,
    output reg         m_w_valid,
    input  wire        m_w_ready,
    input  wire [ 1:0] m_b_resp,
    input  wire        m_b_valid,
    output reg         m_b_ready,

    // Status / IRQ
    output reg         npu_busy,
    output reg         npu_done_irq
);

    // -------------------------------------------------------------------------
    // Configuration Registers
    // -------------------------------------------------------------------------
    reg [31:0] mat_a_addr;
    reg [31:0] mat_b_addr;
    reg [31:0] mat_c_addr;
    reg [ 1:0] act_mode;
    reg        start_cmd;

    // -------------------------------------------------------------------------
    // AXI Slave FSM
    // -------------------------------------------------------------------------
    localparam ST_SL_IDLE  = 2'd0;
    localparam ST_SL_WDATA = 2'd1;
    localparam ST_SL_WRESP = 2'd2;
    localparam ST_SL_RDATA = 2'd3;

    reg [1:0]  sl_state;
    reg [31:0] aw_addr_r, ar_addr_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sl_state    <= ST_SL_IDLE;
            s_aw_ready  <= 1'b0;
            s_w_ready   <= 1'b0;
            s_b_valid   <= 1'b0;
            s_b_resp    <= `AXI_RESP_OKAY;
            s_ar_ready  <= 1'b0;
            s_r_valid   <= 1'b0;
            s_r_data    <= 32'b0;
            s_r_resp    <= `AXI_RESP_OKAY;
            mat_a_addr  <= 32'b0;
            mat_b_addr  <= 32'b0;
            mat_c_addr  <= 32'b0;
            act_mode    <= 2'b0;
            start_cmd   <= 1'b0;
        end else begin
            s_aw_ready <= 1'b0;
            s_w_ready  <= 1'b0;
            s_ar_ready <= 1'b0;
            s_b_valid  <= 1'b0;
            s_r_valid  <= 1'b0;
            start_cmd  <= 1'b0;

            case (sl_state)
                ST_SL_IDLE: begin
                    if (s_aw_valid) begin
                        s_aw_ready <= 1'b1;
                        aw_addr_r  <= s_aw_addr;
                        sl_state   <= ST_SL_WDATA;
                    end else if (s_ar_valid) begin
                        s_ar_ready <= 1'b1;
                        ar_addr_r  <= s_ar_addr;
                        sl_state   <= ST_SL_RDATA;
                    end
                end

                ST_SL_WDATA: begin
                    s_w_ready <= 1'b1;
                    if (s_w_valid) begin
                        s_w_ready <= 1'b0;
                        case (aw_addr_r[4:2])
                            3'd0: mat_a_addr <= s_w_data;
                            3'd1: mat_b_addr <= s_w_data;
                            3'd2: mat_c_addr <= s_w_data;
                            3'd3: begin
                                act_mode  <= s_w_data[2:1];
                                start_cmd <= s_w_data[0];
                            end
                            default: ;
                        endcase
                        s_b_resp <= `AXI_RESP_OKAY;
                        sl_state <= ST_SL_WRESP;
                    end
                end

                ST_SL_WRESP: begin
                    s_b_valid <= 1'b1;
                    if (s_b_valid && s_b_ready) begin
                        s_b_valid <= 1'b0;
                        sl_state  <= ST_SL_IDLE;
                    end
                end

                ST_SL_RDATA: begin
                    case (ar_addr_r[4:2])
                        3'd0: s_r_data <= mat_a_addr;
                        3'd1: s_r_data <= mat_b_addr;
                        3'd2: s_r_data <= mat_c_addr;
                        3'd3: s_r_data <= {29'b0, act_mode, start_cmd};
                        3'd4: s_r_data <= {30'b0, npu_done_irq, npu_busy};
                        default: s_r_data <= 32'h4E50_0001;
                    endcase
                    s_r_resp  <= `AXI_RESP_OKAY;
                    s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin
                        s_r_valid <= 1'b0;
                        sl_state  <= ST_SL_IDLE;
                    end
                end

                default: sl_state <= ST_SL_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // NPU Execution FSM
    // -------------------------------------------------------------------------
    localparam NPU_IDLE    = 3'd0;
    localparam NPU_READ_A  = 3'd1;
    localparam NPU_READ_B  = 3'd2;
    localparam NPU_COMPUTE = 3'd3;
    localparam NPU_WRITE_C = 3'd4;
    localparam NPU_DONE    = 3'd5;

    reg [2:0] npu_state;
    reg [2:0] word_cnt;

    // MAC signals
    reg        clear_acc;
    reg        mac_enable;
    reg  signed [7:0] a_row0, a_row1, a_row2, a_row3;
    reg  signed [7:0] b_col0, b_col1, b_col2, b_col3;
    wire [511:0] c_out_flat;
    wire signed [31:0] c_out [0:3][0:3];
    reg signed [7:0] mat_a [0:3][0:3];
    reg signed [7:0] mat_b [0:3][0:3];
    reg [1:0] comp_step;

    genvar pi, pj;
    generate
        for (pi = 0; pi < 4; pi = pi + 1) begin : unpack_r
            for (pj = 0; pj < 4; pj = pj + 1) begin : unpack_c
                assign c_out[pi][pj] = c_out_flat[(pi*4 + pj)*32 +: 32];
            end
        end
    endgenerate

    // Instantiate MAC Array
    npu_mac_array u_mac_array (
        .clk        (clk),
        .rst_n      (rst_n),
        .clear_acc  (clear_acc),
        .enable     (mac_enable),
        .a_row0     (a_row0), .a_row1(a_row1), .a_row2(a_row2), .a_row3(a_row3),
        .b_col0     (b_col0), .b_col1(b_col1), .b_col2(b_col2), .b_col3(b_col3),
        .c_out_flat (c_out_flat)
    );

    // Activation Unit outputs
    wire signed [7:0] act_c [0:3][0:3];
    genvar gi, gj;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : act_row
            for (gj = 0; gj < 4; gj = gj + 1) begin : act_col
                npu_activation u_act (
                    .act_mode(act_mode),
                    .val_in  (c_out[gi][gj]),
                    .val_out (act_c[gi][gj])
                );
            end
        end
    endgenerate

    // Execution FSM Body
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            npu_state    <= NPU_IDLE;
            npu_busy     <= 1'b0;
            npu_done_irq <= 1'b0;
            clear_acc    <= 1'b0;
            mac_enable   <= 1'b0;
            word_cnt     <= 3'd0;
            comp_step    <= 2'd0;
            m_ar_valid   <= 1'b0;
            m_ar_addr    <= 32'b0;
            m_r_ready    <= 1'b0;
            m_aw_valid   <= 1'b0;
            m_aw_addr    <= 32'b0;
            m_w_valid    <= 1'b0;
            m_w_data     <= 32'b0;
            m_w_strb     <= 4'hF;
            m_b_ready    <= 1'b0;
            a_row0 <= 0; a_row1 <= 0; a_row2 <= 0; a_row3 <= 0;
            b_col0 <= 0; b_col1 <= 0; b_col2 <= 0; b_col3 <= 0;
            begin : init_mat
                integer i, j;
                for (i = 0; i < 4; i = i + 1)
                    for (j = 0; j < 4; j = j + 1) begin
                        mat_a[i][j] <= 8'sd0;
                        mat_b[i][j] <= 8'sd0;
                    end
            end
        end else begin
            npu_done_irq <= 1'b0;
            clear_acc    <= 1'b0;
            mac_enable   <= 1'b0;

            case (npu_state)
                NPU_IDLE: begin
                    if (start_cmd) begin
                        npu_busy   <= 1'b1;
                        clear_acc  <= 1'b1;
                        word_cnt   <= 3'd0;
                        npu_state  <= NPU_READ_A;
                    end
                end

                NPU_READ_A: begin
                    m_ar_addr  <= mat_a_addr + {27'b0, word_cnt, 2'b00};
                    m_ar_valid <= 1'b1;
                    if (m_ar_valid && m_ar_ready) begin
                        m_ar_valid <= 1'b0;
                        m_r_ready  <= 1'b1;
                    end
                    if (m_r_valid && m_r_ready) begin
                        m_r_ready <= 1'b0;
                        mat_a[word_cnt][0] <= m_r_data[ 7: 0];
                        mat_a[word_cnt][1] <= m_r_data[15: 8];
                        mat_a[word_cnt][2] <= m_r_data[23:16];
                        mat_a[word_cnt][3] <= m_r_data[31:24];
                        if (word_cnt == 3'd3) begin
                            word_cnt  <= 3'd0;
                            npu_state <= NPU_READ_B;
                        end else begin
                            word_cnt <= word_cnt + 3'd1;
                        end
                    end
                end

                NPU_READ_B: begin
                    m_ar_addr  <= mat_b_addr + {27'b0, word_cnt, 2'b00};
                    m_ar_valid <= 1'b1;
                    if (m_ar_valid && m_ar_ready) begin
                        m_ar_valid <= 1'b0;
                        m_r_ready  <= 1'b1;
                    end
                    if (m_r_valid && m_r_ready) begin
                        m_r_ready <= 1'b0;
                        mat_b[word_cnt][0] <= m_r_data[ 7: 0];
                        mat_b[word_cnt][1] <= m_r_data[15: 8];
                        mat_b[word_cnt][2] <= m_r_data[23:16];
                        mat_b[word_cnt][3] <= m_r_data[31:24];
                        if (word_cnt == 3'd3) begin
                            word_cnt  <= 3'd0;
                            comp_step <= 2'd0;
                            npu_state <= NPU_COMPUTE;
                        end else begin
                            word_cnt <= word_cnt + 3'd1;
                        end
                    end
                end

                NPU_COMPUTE: begin
                    a_row0 <= mat_a[0][comp_step];
                    a_row1 <= mat_a[1][comp_step];
                    a_row2 <= mat_a[2][comp_step];
                    a_row3 <= mat_a[3][comp_step];

                    b_col0 <= mat_b[comp_step][0];
                    b_col1 <= mat_b[comp_step][1];
                    b_col2 <= mat_b[comp_step][2];
                    b_col3 <= mat_b[comp_step][3];

                    mac_enable <= 1'b1;

                    if (comp_step == 2'd3) begin
                        word_cnt  <= 3'd0;
                        npu_state <= NPU_WRITE_C;
                    end else begin
                        comp_step <= comp_step + 2'd1;
                    end
                end

                NPU_WRITE_C: begin
                    m_aw_addr  <= mat_c_addr + {27'b0, word_cnt, 2'b00};
                    m_aw_valid <= 1'b1;
                    m_w_data   <= {act_c[word_cnt][3], act_c[word_cnt][2], act_c[word_cnt][1], act_c[word_cnt][0]};
                    m_w_valid  <= 1'b1;
                    m_w_strb   <= 4'hF;
                    if (m_aw_valid && m_aw_ready && m_w_valid && m_w_ready) begin
                        m_aw_valid <= 1'b0;
                        m_w_valid  <= 1'b0;
                        m_b_ready  <= 1'b1;
                    end
                    if (m_b_valid && m_b_ready) begin
                        m_b_ready <= 1'b0;
                        if (word_cnt == 3'd3) begin
                            npu_state <= NPU_DONE;
                        end else begin
                            word_cnt <= word_cnt + 3'd1;
                        end
                    end
                end

                NPU_DONE: begin
                    npu_busy     <= 1'b0;
                    npu_done_irq <= 1'b1;
                    npu_state    <= NPU_IDLE;
                end

                default: npu_state <= NPU_IDLE;
            endcase
        end
    end

endmodule
