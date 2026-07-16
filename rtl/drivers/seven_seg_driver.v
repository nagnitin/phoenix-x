// =============================================================================
// Module      : seven_seg_driver.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Seven-Segment Display Multiplexer Driver.
//               Drives a 4-digit multiplexed common-anode/cathode display.
//               Automatically decodes hex values 0-F to 7-segment patterns.
//
// Memory-Mapped Registers (base 0xFFFF09C0):
//   0x00: SEG_DATA [31:0] RW  Packed hex values for the 4 digits:
//                             [7:0]   Digit 0 (rightmost)
//                             [15:8]  Digit 1
//                             [23:16] Digit 2
//                             [31:24] Digit 3 (leftmost)
//   0x04: SEG_CTRL [7:0]  RW  [3:0]=Digit Enable Mask, [7]=Common Cathode (0) / Anode (1) select
//   0x08: SEG_DP   [3:0]  RW  Decimal Point Enable per digit
//
// Outputs:
//   anodes   [3:0] — Digit select lines (active low/high depending on ctrl)
//   segments [7:0] — Segment drive lines: [7]=DP, [6]=G, [5]=F, [4]=E, [3]=D, [2]=C, [1]=B, [0]=A
// =============================================================================

`timescale 1ns/1ps

module seven_seg_driver (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [1:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Physical seven-segment connections
    output reg  [3:0]  anodes,
    output reg  [7:0]  segments
);

    // Registers
    reg [31:0] seg_data;
    reg [7:0]  seg_ctrl;
    reg [3:0]  seg_dp;

    // Refresh clock divider (100 MHz -> ~200 Hz per digit refresh: divider = 125,000)
    reg [16:0] clk_div;
    reg [1:0]  digit_select; // Cycle through 0 to 3

    // Segment decoder function
    function [6:0] hex_to_seg;
        input [3:0] hex;
        begin
            case (hex)
                // Segment map: GFEDCBA
                4'h0: hex_to_seg = 7'b0111111;
                4'h1: hex_to_seg = 7'b0000110;
                4'h2: hex_to_seg = 7'b1011011;
                4'h3: hex_to_seg = 7'b1001111;
                4'h4: hex_to_seg = 7'b1100110;
                4'h5: hex_to_seg = 7'b1101101;
                4'h6: hex_to_seg = 7'b1111101;
                4'h7: hex_to_seg = 7'b0000111;
                4'h8: hex_to_seg = 7'b1111111;
                4'h9: hex_to_seg = 7'b1101111;
                4'hA: hex_to_seg = 7'b1110111;
                4'hB: hex_to_seg = 7'b1111100;
                4'hC: hex_to_seg = 7'b0111001;
                4'hD: hex_to_seg = 7'b1011110;
                4'hE: hex_to_seg = 7'b1111001;
                4'hF: hex_to_seg = 7'b1110001;
                default: hex_to_seg = 7'b0000000;
            endcase
        end
    endfunction

    // Timer divider to swap active digit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div      <= 0;
            digit_select <= 0;
        end else begin
            if (clk_div >= 17'd125_000) begin
                clk_div      <= 0;
                digit_select <= digit_select + 1;
            end else begin
                clk_div <= clk_div + 1;
            end
        end
    end

    // Hex digit selector logic
    reg [3:0] active_hex;
    reg       active_dp;
    always @(*) begin
        case (digit_select)
            2'd0: begin
                active_hex = seg_data[3:0];
                active_dp  = seg_dp[0];
            end
            2'd1: begin
                active_hex = seg_data[11:8];
                active_dp  = seg_dp[1];
            end
            2'd2: begin
                active_hex = seg_data[19:16];
                active_dp  = seg_dp[2];
            end
            2'd3: begin
                active_hex = seg_data[27:24];
                active_dp  = seg_dp[3];
            end
        endcase
    end

    // Seven segment drive logic
    wire [6:0] decoded_segments = hex_to_seg(active_hex);
    wire [7:0] raw_segments     = {active_dp, decoded_segments}; // DP is MSB

    // Handle common-anode / common-cathode translation
    wire common_anode = seg_ctrl[7];
    wire [3:0] active_anodes_mask = seg_ctrl[3:0];

    always @(*) begin
        // Anode/Cathode activation logic
        anodes   = 4'hF; // default off (for common anode, high is off; for common cathode, low is off)
        segments = 8'h00;

        if (active_anodes_mask[digit_select]) begin
            if (common_anode) begin
                // Common Anode: Active digits are LOW, active segments are LOW
                case (digit_select)
                    2'd0: anodes = 4'b1110;
                    2'd1: anodes = 4'b1101;
                    2'd2: anodes = 4'b1011;
                    2'd3: anodes = 4'b0111;
                endcase
                segments = ~raw_segments;
            end else begin
                // Common Cathode: Active digits are HIGH, active segments are HIGH
                case (digit_select)
                    2'd0: anodes = 4'b0001;
                    2'd1: anodes = 4'b0010;
                    2'd2: anodes = 4'b0100;
                    2'd3: anodes = 4'b1000;
                endcase
                segments = raw_segments;
            end
        end
    end

    // Register writes
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg_data <= 32'h0;
            seg_ctrl <= 8'h0F; // Default: Enable all digits, common cathode (0)
            seg_dp   <= 4'h0;  // All decimal points off
        end else if (reg_we) begin
            case (reg_addr)
                2'h0: seg_data <= reg_wdata;
                2'h1: seg_ctrl <= reg_wdata[7:0];
                2'h2: seg_dp   <= reg_wdata[3:0];
                default: ;
            endcase
        end
    end

    // Register reads
    always @(*) begin
        case (reg_addr)
            2'h0: reg_rdata = seg_data;
            2'h1: reg_rdata = {24'h0, seg_ctrl};
            2'h2: reg_rdata = {28'h0, seg_dp};
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
