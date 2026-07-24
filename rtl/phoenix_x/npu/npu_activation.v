// =============================================================================
// Module      : npu_activation
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : NPU Activation Function Unit & Quantizer.
//               Applies ReLU / LeakyReLU activation to 32-bit accumulators
//               and quantizes/clamps the results into 8-bit signed integers (INT8).
// =============================================================================

`timescale 1ns/1ps

module npu_activation (
    input  wire [1:0]        act_mode,  // 0=NONE (Identity), 1=ReLU, 2=LeakyReLU
    input  wire signed [31:0] val_in,    // 32-bit accumulator input
    output reg  signed [7:0]  val_out    // Quantized 8-bit output (-128..127)
);

    reg signed [31:0] activated;

    always @(*) begin
        // 1. Activation Function
        case (act_mode)
            2'd1: activated = (val_in > 32'sd0) ? val_in : 32'sd0; // ReLU
            2'd2: activated = (val_in > 32'sd0) ? val_in : (val_in >>> 3); // LeakyReLU (0.125 slope)
            default: activated = val_in; // NONE / Identity
        endcase

        // 2. Clamping / Saturation to signed INT8 [-128 .. +127]
        if (activated > 32'sd127)
            val_out = 8'sd127;
        else if (activated < -32'sd128)
            val_out = -8'sd128;
        else
            val_out = activated[7:0];
    end

endmodule
