// =============================================================================
// Module      : npu_mac_array
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : 4×4 Systolic Multiply-Accumulate (MAC) Array for INT8.
//               Computes C = A × B where A and B are 4×4 signed 8-bit matrices,
//               accumulating into 32-bit output registers.
//               Flat 512-bit vector output for 100% IEEE 1364-2001 Verilog compliance.
// =============================================================================

`timescale 1ns/1ps

module npu_mac_array (
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        clear_acc,     // Clear all accumulators to 0
    input  wire        enable,        // Enable MAC execution step

    // Inputs: Matrix A row elements, Matrix B column elements
    input  wire signed [7:0] a_row0, a_row1, a_row2, a_row3,
    input  wire signed [7:0] b_col0, b_col1, b_col2, b_col3,

    // Outputs: Flattened 512-bit vector representing 4×4 Matrix C (16 × 32-bit)
    output wire [511:0] c_out_flat
);

    reg signed [31:0] c_out [0:3][0:3];
    integer i, j;

    // Pack 2D array to flattened 512-bit vector output
    genvar r, c;
    generate
        for (r = 0; r < 4; r = r + 1) begin : pack_r
            for (c = 0; c < 4; c = c + 1) begin : pack_c
                assign c_out_flat[(r*4 + c)*32 +: 32] = c_out[r][c];
            end
        end
    endgenerate

    // 4×4 Systolic MAC Computation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 4; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    c_out[i][j] <= 32'sd0;
                end
            end
        end else if (clear_acc) begin
            for (i = 0; i < 4; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    c_out[i][j] <= 32'sd0;
                end
            end
        end else if (enable) begin
            c_out[0][0] <= c_out[0][0] + (a_row0 * b_col0);
            c_out[0][1] <= c_out[0][1] + (a_row0 * b_col1);
            c_out[0][2] <= c_out[0][2] + (a_row0 * b_col2);
            c_out[0][3] <= c_out[0][3] + (a_row0 * b_col3);

            c_out[1][0] <= c_out[1][0] + (a_row1 * b_col0);
            c_out[1][1] <= c_out[1][1] + (a_row1 * b_col1);
            c_out[1][2] <= c_out[1][2] + (a_row1 * b_col2);
            c_out[1][3] <= c_out[1][3] + (a_row1 * b_col3);

            c_out[2][0] <= c_out[2][0] + (a_row2 * b_col0);
            c_out[2][1] <= c_out[2][1] + (a_row2 * b_col1);
            c_out[2][2] <= c_out[2][2] + (a_row2 * b_col2);
            c_out[2][3] <= c_out[2][3] + (a_row2 * b_col3);

            c_out[3][0] <= c_out[3][0] + (a_row3 * b_col0);
            c_out[3][1] <= c_out[3][1] + (a_row3 * b_col1);
            c_out[3][2] <= c_out[3][2] + (a_row3 * b_col2);
            c_out[3][3] <= c_out[3][3] + (a_row3 * b_col3);
        end
    end

endmodule
