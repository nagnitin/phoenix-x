// =============================================================================
// Module      : clock_divider.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Parameterized clock divider — generates a divided clock signal
//               or a single-cycle enable pulse at a configurable ratio.
//
// Parameters:
//   DIVISOR — System clock cycles per output period (default 100 → 1 MHz from 100 MHz)
//
// Outputs:
//   clk_out — Divided clock (50% duty cycle)
//   clk_en  — Single-cycle enable pulse at output frequency (for synchronous design)
//
// Usage Examples (100 MHz system clock):
//   DIVISOR=100     → 1 MHz   (SPI default)
//   DIVISOR=217     → ~460.8 kHz → UART 115200 baud (oversampled 4x)
//   DIVISOR=10000   → 10 kHz (slow debug)
//   DIVISOR=250     → 400 kHz (I2C fast mode)
// =============================================================================

`timescale 1ns/1ps

module clock_divider #(
    parameter DIVISOR = 100
) (
    input  wire clk,
    input  wire rst_n,
    output reg  clk_out,
    output reg  clk_en       // Synchronous enable pulse (recommended for synthesis)
);

    // Counter width automatically sized to hold DIVISOR value
    localparam CNT_W = $clog2(DIVISOR) + 1;

    reg [CNT_W-1:0] counter;

    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= 0;
            clk_out <= 1'b0;
            clk_en  <= 1'b0;
        end else begin
            clk_en <= 1'b0;  // Default: not enabled this cycle

            if (counter >= DIVISOR - 1) begin
                counter <= 0;
                clk_out <= ~clk_out;
                clk_en  <= 1'b1;  // Pulse once per DIVISOR cycles
            end else begin
                counter <= counter + 1;
            end
        end
    end

endmodule
