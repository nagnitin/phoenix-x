// =============================================================================
// Module      : eeprom_driver.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Driver for AT24C series I2C EEPROMs (e.g. AT24C32/64).
//               Implements hardware sequencing for 16-bit address reads and writes
//               using an internal I2C master core.
//
// Memory-Mapped Registers (base 0xFFFF0980):
//   0x00: EE_CTRL    [7:0]  RW  [0]=READ_START, [1]=WRITE_START, [7]=BUSY (RO)
//   0x04: EE_ADDR_H  [7:0]  RW  High byte of 16-bit EEPROM address
//   0x08: EE_ADDR_L  [7:0]  RW  Low byte of 16-bit EEPROM address
//   0x0C: EE_DATA    [7:0]  RW  Read data (RO) / Write data (WO)
//
// EEPROM I2C Address:
//   Hardcoded to 7'h50 (Standard for AT24C32/64).
// =============================================================================

`timescale 1ns/1ps

module eeprom_driver (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [1:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Physical I2C connections
    output reg         scl_oe,
    output reg         sda_oe,
    input  wire        scl_in,
    input  wire        sda_in
);

    // FSM States
    localparam ST_IDLE       = 4'd0;
    localparam ST_START      = 4'd1;
    localparam ST_DEV_WRITE  = 4'd2;
    localparam ST_DEV_ACK1   = 4'd3;
    localparam ST_ADDR_H     = 4'd4;
    localparam ST_ADDR_H_ACK = 4'd5;
    localparam ST_ADDR_L     = 4'd6;
    localparam ST_ADDR_L_ACK = 4'd7;
    // For Writes:
    localparam ST_WR_DATA    = 4'd8;
    localparam ST_WR_ACK     = 4'd9;
    // For Reads (Random Address Read):
    localparam ST_REP_START  = 4'd10;
    localparam ST_DEV_READ   = 4'd11;
    localparam ST_DEV_ACK2   = 4'd12;
    localparam ST_RD_DATA    = 4'd13;
    localparam ST_RD_NACK    = 4'd14;
    // Common:
    localparam ST_STOP       = 4'd15;

    reg [3:0]  state;
    reg [3:0]  bit_cnt;
    reg [15:0] delay_cnt;
    reg        clk_phase;
    reg        busy;

    // Registers
    reg [7:0]  ee_addr_h;
    reg [7:0]  ee_addr_l;
    reg [7:0]  ee_data_wr;
    reg [7:0]  ee_data_rd;
    reg        read_req;
    reg        write_req;

    // 100 MHz System Clock -> ~100 kHz I2C clock (divider = 500)
    localparam I2C_DIV = 16'd500;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            scl_oe     <= 1'b0;
            sda_oe     <= 1'b0;
            bit_cnt    <= 0;
            delay_cnt  <= 0;
            clk_phase  <= 0;
            busy       <= 1'b0;
            ee_addr_h  <= 8'h0;
            ee_addr_l  <= 8'h0;
            ee_data_wr <= 8'h0;
            ee_data_rd <= 8'h0;
            read_req   <= 1'b0;
            write_req  <= 1'b0;
        end else begin
            // Register writes
            if (reg_we && state == ST_IDLE) begin
                case (reg_addr)
                    2'h0: begin // EE_CTRL
                        read_req  <= reg_wdata[0];
                        write_req <= reg_wdata[1];
                    end
                    2'h1: ee_addr_h  <= reg_wdata[7:0];
                    2'h2: ee_addr_l  <= reg_wdata[7:0];
                    2'h3: ee_data_wr <= reg_wdata[7:0];
                endcase
            end

            // Start requests
            if (state == ST_IDLE && (read_req || write_req)) begin
                busy      <= 1'b1;
                state     <= ST_START;
                delay_cnt <= 0;
                clk_phase <= 0;
            end

            // Dividers
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
                        sda_oe <= 1'b1; // SDA low
                        scl_oe <= 1'b1; // SCL low
                        bit_cnt<= 4'd7;
                        state  <= ST_DEV_WRITE;
                    end
                end

                ST_DEV_WRITE: begin
                    if (!clk_phase) begin
                        // 7'h50 << 1 | WriteBit(0) = 0xA0
                        sda_oe <= ~((8'hA0 >> bit_cnt) & 1'b1);
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe <= 1'b1;
                            if (bit_cnt == 0) begin
                                state <= ST_DEV_ACK1;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                ST_DEV_ACK1: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0;
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe  <= 1'b1;
                            bit_cnt <= 4'd7;
                            state   <= ST_ADDR_H;
                        end
                    end
                end

                ST_ADDR_H: begin
                    if (!clk_phase) begin
                        sda_oe <= ~((ee_addr_h >> bit_cnt) & 1'b1);
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe <= 1'b1;
                            if (bit_cnt == 0) begin
                                state <= ST_ADDR_H_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                ST_ADDR_H_ACK: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0;
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe  <= 1'b1;
                            bit_cnt <= 4'd7;
                            state   <= ST_ADDR_L;
                        end
                    end
                end

                ST_ADDR_L: begin
                    if (!clk_phase) begin
                        sda_oe <= ~((ee_addr_l >> bit_cnt) & 1'b1);
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe <= 1'b1;
                            if (bit_cnt == 0) begin
                                state <= ST_ADDR_L_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                ST_ADDR_L_ACK: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0;
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe  <= 1'b1;
                            bit_cnt <= 4'd7;
                            if (write_req) begin
                                state <= ST_WR_DATA;
                            end else begin
                                state <= ST_REP_START;
                            end
                        end
                    end
                end

                ST_WR_DATA: begin
                    if (!clk_phase) begin
                        sda_oe <= ~((ee_data_wr >> bit_cnt) & 1'b1);
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe <= 1'b1;
                            if (bit_cnt == 0) begin
                                state <= ST_WR_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                ST_WR_ACK: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0;
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe    <= 1'b1;
                            write_req <= 1'b0;
                            state     <= ST_STOP;
                        end
                    end
                end

                ST_REP_START: begin
                    // Repeated start: Release SDA, let SCL rise, then SDA pull low
                    if (!clk_phase) begin
                        sda_oe <= 1'b0; // Release SDA
                        scl_oe <= 1'b0; // Release SCL
                    end else begin
                        if (delay_cnt == I2C_DIV) begin
                            sda_oe  <= 1'b1; // Pull SDA low
                            scl_oe  <= 1'b1; // Pull SCL low
                            bit_cnt <= 4'd7;
                            state   <= ST_DEV_READ;
                        end
                    end
                end

                ST_DEV_READ: begin
                    if (!clk_phase) begin
                        // 7'h50 << 1 | ReadBit(1) = 0xA1
                        sda_oe <= ~((8'hA1 >> bit_cnt) & 1'b1);
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe <= 1'b1;
                            if (bit_cnt == 0) begin
                                state <= ST_DEV_ACK2;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                ST_DEV_ACK2: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0;
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe  <= 1'b1;
                            bit_cnt <= 4'd7;
                            state   <= ST_RD_DATA;
                        end
                    end
                end

                ST_RD_DATA: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0; // Release for input
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            ee_data_rd[bit_cnt] <= sda_in;
                            scl_oe <= 1'b1;
                            if (bit_cnt == 0) begin
                                state <= ST_RD_NACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                ST_RD_NACK: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b1; // NACK = SDA high (release/pullup)
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe   <= 1'b1;
                            read_req <= 1'b0;
                            state    <= ST_STOP;
                        end
                    end
                end

                ST_STOP: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b1; // SDA low
                    end else begin
                        scl_oe <= 1'b0; // Release SCL high
                        if (delay_cnt == I2C_DIV) begin
                            sda_oe <= 1'b0; // Release SDA high
                            state  <= ST_IDLE;
                            busy   <= 1'b0;
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
            2'h0: reg_rdata = {24'h0, busy, 5'h0, write_req, read_req};
            2'h1: reg_rdata = {24'h0, ee_addr_h};
            2'h2: reg_rdata = {24'h0, ee_addr_l};
            2'h3: reg_rdata = {24'h0, ee_data_rd};
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
