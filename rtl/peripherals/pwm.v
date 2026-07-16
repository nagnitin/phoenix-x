// =============================================================================
// Module      : pwm.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Multi-channel PWM generator — 4 independent channels, each
//               with configurable period and duty cycle. Suitable for:
//               • Servo motor control (50 Hz, 1-2 ms pulse)
//               • DC motor speed control (high frequency PWM)
//               • RGB LED brightness control (variable duty)
//
// Memory-Mapped Registers (base 0xFFFF0500):
//   0x00: ENABLE   [3:0]  RW  Channel enable bits
//   Per channel n (n=0..3), base = 0x04 + n*0x08:
//     base+0x00: PERIOD  [31:0] RW  PWM period in clock cycles
//     base+0x04: DUTY    [31:0] RW  PWM duty cycle (cycles high)
//
// Channel 0: General purpose / Servo
// Channel 1: DC Motor
// Channel 2: RGB Red
// Channel 3: RGB Green (Blue via software GPIO)
// =============================================================================

`timescale 1ns/1ps

module pwm (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [4:0]  reg_addr,    // 5 bits for all channel registers
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // PWM output channels
    output wire [3:0]  pwm_out
);

    // -------------------------------------------------------------------------
    // Per-channel registers
    // -------------------------------------------------------------------------
    reg [31:0] period [0:3];
    reg [31:0] duty   [0:3];
    reg [3:0]  enable;

    // Per-channel counters
    reg [31:0] count  [0:3];
    reg [3:0]  out;

    assign pwm_out = out;

    integer i;

    // -------------------------------------------------------------------------
    // Register write decode
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            enable    <= 4'h0;
            for (i = 0; i < 4; i = i + 1) begin
                period[i] <= 32'd2_000_000;   // 50 Hz at 100 MHz
                duty[i]   <= 32'd150_000;     // 1.5 ms (servo center)
                count[i]  <= 32'h0;
            end
        end else begin
            if (reg_we) begin
                case (reg_addr)
                    5'h00: enable <= reg_wdata[3:0];
                    // Channel 0
                    5'h01: period[0] <= reg_wdata;
                    5'h02: duty[0]   <= reg_wdata;
                    // Channel 1
                    5'h03: period[1] <= reg_wdata;
                    5'h04: duty[1]   <= reg_wdata;
                    // Channel 2
                    5'h05: period[2] <= reg_wdata;
                    5'h06: duty[2]   <= reg_wdata;
                    // Channel 3
                    5'h07: period[3] <= reg_wdata;
                    5'h08: duty[3]   <= reg_wdata;
                    default: ;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Per-channel PWM generation
    // -------------------------------------------------------------------------
    genvar ch;
    generate
        for (ch = 0; ch < 4; ch = ch + 1) begin : pwm_gen
            always @(posedge clk) begin
                if (!rst_n) begin
                    count[ch] <= 32'h0;
                    out[ch]   <= 1'b0;
                end else if (enable[ch]) begin
                    if (count[ch] >= period[ch] - 1) begin
                        count[ch] <= 32'h0;
                    end else begin
                        count[ch] <= count[ch] + 1;
                    end
                    out[ch] <= (count[ch] < duty[ch]) ? 1'b1 : 1'b0;
                end else begin
                    out[ch]   <= 1'b0;
                    count[ch] <= 32'h0;
                end
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Register read
    // -------------------------------------------------------------------------
    always @(*) begin
        case (reg_addr)
            5'h00: reg_rdata = {28'h0, enable};
            5'h01: reg_rdata = period[0];
            5'h02: reg_rdata = duty[0];
            5'h03: reg_rdata = period[1];
            5'h04: reg_rdata = duty[1];
            5'h05: reg_rdata = period[2];
            5'h06: reg_rdata = duty[2];
            5'h07: reg_rdata = period[3];
            5'h08: reg_rdata = duty[3];
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
