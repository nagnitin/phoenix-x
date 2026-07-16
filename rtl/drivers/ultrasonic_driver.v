// =============================================================================
// Module      : ultrasonic_driver.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Driver for HC-SR04 Ultrasonic Distance Sensor.
//               Generates a 10us trigger pulse and measures the echo pulse width
//               to calculate distance in centimeters (cm).
//
// Formula:
//   Distance (cm) = (Echo High Time in seconds * 34000) / 2
//                 = Echo High Time in clock cycles * (10^-8 * 17000) at 100 MHz
//                 = Echo High Time in clock cycles / 5882
//
// Memory-Mapped Registers (base 0xFFFF09F0 - next free driver offset):
//   0x00: US_CTRL  [7:0]  RW  [0]=START_MEASURE, [7]=BUSY (RO)
//   0x04: US_DIST  [31:0] RO  Measured distance in centimeters (cm)
//
// Hardware Pins:
//   trigger — Output to sensor (10us trigger pulse)
//   echo    — Input from sensor (high duration proportional to distance)
// =============================================================================

`timescale 1ns/1ps

module ultrasonic_driver (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [1:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Sensor pins
    output reg         trigger,
    input  wire        echo
);

    // FSM States
    localparam ST_IDLE    = 3'd0;
    localparam ST_TRIG    = 3'd1;
    localparam ST_WAIT_HI = 3'd2;
    localparam ST_MEASURE = 3'd3;
    localparam ST_CALC    = 3'd4;

    reg [2:0]  state;
    reg [19:0] cnt;          // For timing the 10us trigger (1000 cycles) and timeout
    reg [31:0] echo_cnt;     // Clock cycle counter during echo high phase
    reg [31:0] distance_cm;
    reg        busy;

    // Double-flop synchronizer for echo input
    reg        echo_sync0;
    reg        echo_sync1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            echo_sync0 <= 1'b0;
            echo_sync1 <= 1'b0;
        end else begin
            echo_sync0 <= echo;
            echo_sync1 <= echo_sync0;
        end
    end

    // FSM Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            trigger     <= 1'b0;
            cnt         <= 0;
            echo_cnt    <= 0;
            distance_cm <= 0;
            busy        <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    busy    <= 1'b0;
                    trigger <= 1'b0;
                    cnt     <= 0;
                    if (reg_we && reg_addr == 2'h0 && reg_wdata[0]) begin
                        busy  <= 1'b1;
                        state <= ST_TRIG;
                    end
                end

                ST_TRIG: begin
                    trigger <= 1'b1;
                    cnt     <= cnt + 1;
                    if (cnt >= 20'd1000) begin // 10 us at 100 MHz
                        trigger <= 1'b0;
                        cnt     <= 0;
                        state   <= ST_WAIT_HI;
                    end
                end

                ST_WAIT_HI: begin
                    // Wait for echo to go high
                    cnt <= cnt + 1;
                    if (echo_sync1) begin
                        echo_cnt <= 0;
                        state    <= ST_MEASURE;
                    end else if (cnt >= 20'd100_000) begin // ~1ms timeout if sensor not connected
                        state <= ST_IDLE;
                    end
                end

                ST_MEASURE: begin
                    if (echo_sync1) begin
                        echo_cnt <= echo_cnt + 1;
                    end else begin
                        state <= ST_CALC;
                    end
                end

                ST_CALC: begin
                    // Distance = echo_cnt / 5882
                    // Approximate division: (echo_cnt * 11) >> 16
                    distance_cm <= (echo_cnt * 32'd11) >> 16;
                    state       <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // Register reads
    always @(*) begin
        case (reg_addr)
            2'h0: reg_rdata = {24'h0, busy, 7'h0};
            2'h1: reg_rdata = distance_cm;
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
