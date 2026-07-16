// =============================================================================
// Module      : temp_sensor_driver.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Driver for LM75 series I2C Temperature Sensors.
//               Automatically queries the 16-bit temperature register from I2C
//               address 7'h48 and returns the Celsius value.
//
// Memory-Mapped Registers (base 0xFFFF0950 - shared OLED/Temp region):
//   0x00: TEMP_CTRL [7:0]  RW  [0]=READ_TRIGGER, [7]=BUSY (RO)
//   0x04: TEMP_VAL  [31:0] RO  Measured temperature (Integer value in Celsius)
//
// I2C Device Address:
//   LM75 address is fixed at 7'h48.
// =============================================================================

`timescale 1ns/1ps

module temp_sensor_driver (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [1:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // I2C interface to physical LM75 sensor
    output reg         scl_oe,
    output reg         sda_oe,
    input  wire        scl_in,
    input  wire        sda_in
);

    // FSM States
    localparam ST_IDLE       = 4'd0;
    localparam ST_START      = 4'd1;
    localparam ST_DEV_ADDR   = 4'd2;
    localparam ST_DEV_ACK    = 4'd3;
    localparam ST_RD_MSB     = 4'd4;
    localparam ST_ACK_MSB    = 4'd5;
    localparam ST_RD_LSB     = 4'd6;
    localparam ST_NACK_LSB   = 4'd7;
    localparam ST_STOP       = 4'd8;

    reg [3:0]  state;
    reg [3:0]  bit_cnt;
    reg [15:0] delay_cnt;
    reg        clk_phase;
    reg        busy;

    reg [7:0]  temp_msb;
    reg [7:0]  temp_lsb;
    reg [31:0] temperature;
    reg        read_req;

    // 100 MHz System Clock -> ~100 kHz I2C clock (divider = 500)
    localparam I2C_DIV = 16'd500;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            scl_oe      <= 1'b0;
            sda_oe      <= 1'b0;
            bit_cnt     <= 0;
            delay_cnt   <= 0;
            clk_phase   <= 0;
            busy        <= 1'b0;
            read_req    <= 1'b0;
            temp_msb    <= 8'h0;
            temp_lsb    <= 8'h0;
            temperature <= 32'h0;
        end else begin
            // Register writes
            if (reg_we && state == ST_IDLE) begin
                case (reg_addr)
                    2'h0: read_req <= reg_wdata[0];
                endcase
            end

            // Trigger read cycle
            if (read_req && state == ST_IDLE) begin
                busy      <= 1'b1;
                state     <= ST_START;
                delay_cnt <= 0;
                clk_phase <= 0;
                read_req  <= 1'b0;
            end

            // Divider
            if (state != ST_IDLE) begin
                if (delay_cnt >= I2C_DIV) begin
                    delay_cnt <= 0;
                    clk_phase <= ~clk_phase;
                end else begin
                    delay_cnt <= delay_cnt + 1;
                end
            end

            case (state)
                ST_START: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b1; // Pull SDA low
                        scl_oe <= 1'b1; // Pull SCL low
                        bit_cnt<= 4'd7;
                        state  <= ST_DEV_ADDR;
                    end
                end

                ST_DEV_ADDR: begin
                    if (!clk_phase) begin
                        // 7'h48 << 1 | ReadBit(1) = 0x91
                        sda_oe <= ~((8'h91 >> bit_cnt) & 1'b1);
                    end else begin
                        scl_oe <= 1'b0; // SCL high
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe <= 1'b1;
                            if (bit_cnt == 0) begin
                                state <= ST_DEV_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                ST_DEV_ACK: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0; // Release SDA
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe  <= 1'b1;
                            bit_cnt <= 4'd7;
                            state   <= ST_RD_MSB;
                        end
                    end
                end

                ST_RD_MSB: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0; // Input
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            temp_msb[bit_cnt] <= sda_in;
                            scl_oe <= 1'b1;
                            if (bit_cnt == 0) begin
                                state <= ST_ACK_MSB;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                ST_ACK_MSB: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b1; // Send ACK (low)
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe  <= 1'b1;
                            bit_cnt <= 4'd7;
                            state   <= ST_RD_LSB;
                        end
                    end
                end

                ST_RD_LSB: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0;
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            temp_lsb[bit_cnt] <= sda_in;
                            scl_oe <= 1'b1;
                            if (bit_cnt == 0) begin
                                state <= ST_NACK_LSB;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                ST_NACK_LSB: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0; // Send NACK (high)
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe <= 1'b1;
                            state  <= ST_STOP;
                        end
                    end
                end

                ST_STOP: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b1;
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            sda_oe      <= 1'b0;
                            state       <= ST_IDLE;
                            busy        <= 1'b0;
                            // Extract signed integer Celsius value (9-bit representation)
                            temperature <= {{24{temp_msb[7]}}, temp_msb};
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // Register reads
    always @(*) begin
        case (reg_addr)
            2'h0: reg_rdata = {24'h0, busy, 7'h0};
            2'h1: reg_rdata = temperature;
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
