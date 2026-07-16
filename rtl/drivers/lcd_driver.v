// =============================================================================
// Module      : lcd_driver.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Hardware driver for standard 16x2 character LCD (HD44780 controller).
//               Operates in 8-bit parallel mode and automates setup/hold/pulse
//               timings for reliable LCD operation from 100 MHz clock.
//
// Memory-Mapped Registers (base 0xFFFF0900):
//   0x00: LCD_CTRL   [7:0]  RW  [0]=EN, [1]=RS, [2]=RW, [7]=BUSY (RO)
//   0x04: LCD_DATA   [7:0]  RW  Write starts transmission of data (RS=1)
//   0x08: LCD_CMD    [7:0]  WO  Write starts transmission of command (RS=0)
//
// Physical LCD Interface:
//   lcd_rs   — Register Select (0=command, 1=data)
//   lcd_rw   — Read/Write (0=write, 1=read)
//   lcd_e    — Enable pulse (latch data on falling edge)
//   lcd_db   — 8-bit data bus [7:0]
// =============================================================================

`timescale 1ns/1ps

module lcd_driver (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [1:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Physical LCD pins
    output reg         lcd_rs,
    output reg         lcd_rw,
    output reg         lcd_e,
    output reg  [7:0]  lcd_db
);

    // States for LCD controller state machine
    localparam ST_IDLE   = 3'h0;
    localparam ST_SETUP  = 3'h1;
    localparam ST_PULSE  = 3'h2;
    localparam ST_HOLD   = 3'h3;
    localparam ST_DELAY  = 3'h4;

    reg [2:0]  state;
    reg [19:0] delay_cnt;    // Counter for pulse width and instruction delay
    reg [7:0]  tx_byte;
    reg        tx_rs;
    reg        busy;

    // Time constants at 100 MHz (10ns period)
    // Setup time: ~100ns (10 cycles)
    // Pulse width EN: ~500ns (50 cycles)
    // Hold time: ~100ns (10 cycles)
    // Execution delay: ~50us (5000 cycles) for general commands, or 2ms for clear
    localparam T_SETUP = 20'd10;
    localparam T_PULSE = 20'd50;
    localparam T_HOLD  = 20'd10;
    localparam T_DELAY = 20'd5000;      // default 50 us delay after writing

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            delay_cnt <= 0;
            tx_byte   <= 8'h0;
            tx_rs     <= 1'b0;
            busy      <= 1'b0;
            lcd_rs    <= 1'b0;
            lcd_rw    <= 1'b0;
            lcd_e     <= 1'b0;
            lcd_db    <= 8'h0;
        end else begin
            case (state)
                ST_IDLE: begin
                    lcd_e <= 1'b0;
                    busy  <= 1'b0;
                    if (reg_we) begin
                        if (reg_addr == 2'h1) begin // Write LCD_DATA
                            tx_byte <= reg_wdata[7:0];
                            tx_rs   <= 1'b1; // RS=1 for Data
                            state   <= ST_SETUP;
                            busy    <= 1'b1;
                        end else if (reg_addr == 2'h2) begin // Write LCD_CMD
                            tx_byte <= reg_wdata[7:0];
                            tx_rs   <= 1'b0; // RS=0 for Command
                            state   <= ST_SETUP;
                            busy    <= 1'b1;
                        end
                    end
                end

                ST_SETUP: begin
                    lcd_rs    <= tx_rs;
                    lcd_rw    <= 1'b0; // Write mode
                    lcd_db    <= tx_byte;
                    delay_cnt <= delay_cnt + 1;
                    if (delay_cnt >= T_SETUP) begin
                        delay_cnt <= 0;
                        state     <= ST_PULSE;
                    end
                end

                ST_PULSE: begin
                    lcd_e     <= 1'b1; // Drive Enable High
                    delay_cnt <= delay_cnt + 1;
                    if (delay_cnt >= T_PULSE) begin
                        delay_cnt <= 0;
                        state     <= ST_HOLD;
                    end
                end

                ST_HOLD: begin
                    lcd_e     <= 1'b0; // Drive Enable Low (latch edge)
                    delay_cnt <= delay_cnt + 1;
                    if (delay_cnt >= T_HOLD) begin
                        delay_cnt <= 0;
                        state     <= ST_DELAY;
                    end
                end

                ST_DELAY: begin
                    // Wait for the LCD to process the character/command
                    delay_cnt <= delay_cnt + 1;
                    if (delay_cnt >= T_DELAY) begin
                        delay_cnt <= 0;
                        state     <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // Register reads
    always @(*) begin
        case (reg_addr)
            2'h0: reg_rdata = {24'h0, busy, 5'h0, lcd_rw, lcd_rs}; // Status/Ctrl
            2'h1: reg_rdata = {24'h0, tx_byte};
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
