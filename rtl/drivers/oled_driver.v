// =============================================================================
// Module      : oled_driver.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : SSD1306 OLED Display Driver over I2C. Handles OLED initialization
//               and sends commands/data via an internal simplified I2C state machine.
//
// Memory-Mapped Registers (base 0xFFFF0940):
//   0x00: OLED_CTRL   [7:0]  RW  [0]=INIT_TRIGGER, [1]=CLEAR_TRIGGER, [7]=BUSY (RO)
//   0x04: OLED_DATA   [7:0]  WO  Write data byte to display GDDRAM
//   0x08: OLED_CMD    [7:0]  WO  Write command byte to SSD1306
//
// Hardware Address:
//   SSD1306 I2C address is fixed at 7'h3C.
// =============================================================================

`timescale 1ns/1ps

module oled_driver (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [1:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // I2C interface to physical OLED panel
    output reg         scl_oe,
    output reg         sda_oe,
    input  wire        scl_in,
    input  wire        sda_in
);

    // States for internal I2C transmission sequencer
    localparam ST_IDLE       = 4'd0;
    localparam ST_START      = 4'd1;
    localparam ST_DEV_ADDR   = 4'd2;
    localparam ST_DEV_ACK    = 4'd3;
    localparam ST_CTRL_BYTE  = 4'd4;
    localparam ST_CTRL_ACK   = 4'd5;
    localparam ST_DATA_BYTE  = 4'd6;
    localparam ST_DATA_ACK   = 4'd7;
    localparam ST_STOP       = 4'd8;
    localparam ST_STOP_WAIT  = 4'd9;
    localparam ST_INIT_SEQ   = 4'd10;

    reg [3:0]  state;
    reg [3:0]  next_state_after_ack;
    reg [7:0]  tx_byte;
    reg [3:0]  bit_cnt;
    reg [15:0] delay_cnt;
    reg        clk_phase;
    reg        busy;

    // OLED control variables
    reg        init_req;
    reg        clear_req;
    reg [7:0]  init_step;
    reg [7:0]  clear_step;

    // SSD1306 Initialization commands
    reg [7:0]  init_cmds [0:14];
    initial begin
        init_cmds[0]  = 8'hAE; // Display OFF
        init_cmds[1]  = 8'hD5; // Set Display Clock Divide Ratio
        init_cmds[2]  = 8'h80; // Suggested ratio
        init_cmds[3]  = 8'hA8; // Set Multiplex Ratio
        init_cmds[4]  = 8'h3F; // 1/64 duty
        init_cmds[5]  = 8'hD3; // Set Display Offset
        init_cmds[6]  = 8'h00; // No offset
        init_cmds[7]  = 8'h40; // Set Start Line
        init_cmds[8]  = 8'h8D; // Charge Pump
        init_cmds[9]  = 8'h14; // Enable Charge Pump
        init_cmds[10] = 8'h20; // Set Memory Addressing Mode
        init_cmds[11] = 8'h00; // Horizontal Addressing Mode
        init_cmds[12] = 8'hA1; // Segment Re-map
        init_cmds[13] = 8'hC8; // COM Output Scan Direction
        init_cmds[14] = 8'hAF; // Display ON
    end

    // I2C Clock generator divider (100 MHz -> ~400 kHz)
    localparam I2C_DIV = 16'd125;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            scl_oe       <= 1'b0;
            sda_oe       <= 1'b0;
            bit_cnt      <= 0;
            delay_cnt    <= 0;
            clk_phase    <= 0;
            busy         <= 1'b0;
            init_req     <= 1'b0;
            clear_req    <= 1'b0;
            init_step    <= 0;
            clear_step   <= 0;
            tx_byte      <= 8'h0;
        end else begin
            // Register writes
            if (reg_we && state == ST_IDLE) begin
                case (reg_addr)
                    2'h0: begin // OLED_CTRL
                        init_req  <= reg_wdata[0];
                        clear_req <= reg_wdata[1];
                    end
                    2'h1: begin // OLED_DATA
                        tx_byte              <= reg_wdata[7:0];
                        state                <= ST_START;
                        busy                 <= 1'b1;
                        next_state_after_ack <= ST_DATA_BYTE;
                    end
                    2'h2: begin // OLED_CMD
                        tx_byte              <= reg_wdata[7:0];
                        state                <= ST_START;
                        busy                 <= 1'b1;
                        next_state_after_ack <= ST_CTRL_BYTE;
                    end
                endcase
            end

            // Main hardware initialization sequence router
            if (init_req && state == ST_IDLE) begin
                init_step <= 0;
                state     <= ST_INIT_SEQ;
                busy      <= 1'b1;
                init_req  <= 1'b0;
            end

            // I2C clock generator delay counters
            if (state != ST_IDLE && state != ST_INIT_SEQ) begin
                if (delay_cnt >= I2C_DIV) begin
                    delay_cnt <= 0;
                    clk_phase <= ~clk_phase;
                end else begin
                    delay_cnt <= delay_cnt + 1;
                end
            end

            case (state)
                ST_INIT_SEQ: begin
                    if (init_step < 15) begin
                        tx_byte              <= init_cmds[init_step];
                        state                <= ST_START;
                        next_state_after_ack <= ST_CTRL_BYTE; // Send as command
                        init_step            <= init_step + 1;
                    end else begin
                        state <= ST_IDLE;
                        busy  <= 1'b0;
                    end
                end

                ST_START: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b1; // SDA goes low (START condition)
                        scl_oe <= 1'b1; // SCL goes low
                        bit_cnt<= 4'd7;
                        state  <= ST_DEV_ADDR;
                    end
                end

                ST_DEV_ADDR: begin
                    if (!clk_phase) begin
                        // Send I2C Address 0x3C << 1 | WriteBit(0) = 0x78
                        sda_oe <= ~((8'h78 >> bit_cnt) & 1'b1);
                    end else begin
                        scl_oe <= 1'b0; // SCL goes high (release)
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe <= 1'b1; // SCL goes low
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
                        sda_oe <= 1'b0; // Release SDA for ACK
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe  <= 1'b1;
                            bit_cnt <= 4'd7;
                            state   <= next_state_after_ack;
                        end
                    end
                end

                ST_CTRL_BYTE: begin
                    // Command control byte is 0x00
                    if (!clk_phase) begin
                        sda_oe <= ~((8'h00 >> bit_cnt) & 1'b1);
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe <= 1'b1;
                            if (bit_cnt == 0) begin
                                state <= ST_CTRL_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                ST_CTRL_ACK: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0;
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe  <= 1'b1;
                            bit_cnt <= 4'd7;
                            state   <= ST_DATA_BYTE; // Send the actual payload byte next
                        end
                    end
                end

                ST_DATA_BYTE: begin
                    if (!clk_phase) begin
                        sda_oe <= ~((tx_byte >> bit_cnt) & 1'b1);
                    end else begin
                        scl_oe <= 1'b0;
                        if (delay_cnt == I2C_DIV) begin
                            scl_oe <= 1'b1;
                            if (bit_cnt == 0) begin
                                state <= ST_DATA_ACK;
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end

                ST_DATA_ACK: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0;
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
                        sda_oe <= 1'b1; // SDA low
                    end else begin
                        scl_oe <= 1'b0; // Release SCL high
                        if (delay_cnt == I2C_DIV) begin
                            sda_oe <= 1'b0; // Release SDA high (STOP condition)
                            state  <= ST_STOP_WAIT;
                        end
                    end
                end

                ST_STOP_WAIT: begin
                    if (init_step > 0 && init_step < 15) begin
                        state <= ST_INIT_SEQ; // Loop back to send next init command
                    end else begin
                        state <= ST_IDLE;
                        busy  <= 1'b0;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // Register reads
    always @(*) begin
        case (reg_addr)
            2'h0: reg_rdata = {24'h0, busy, 5'h0, clear_req, init_req};
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
