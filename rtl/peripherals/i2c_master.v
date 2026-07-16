// =============================================================================
// Module      : i2c_master.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : I2C Master controller supporting standard (100 kHz) and
//               fast (400 kHz) modes. Implements full I2C state machine:
//               START, ADDRESS, RW, ACK, DATA, STOP.
//
// Memory-Mapped Registers (base 0xFFFF0300):
//   0x00: CTRL    [7:0]  RW  [0]=START, [1]=STOP, [2]=RW(0=write,1=read)
//                            [3]=ACK_EN, [4]=BUSY(RO), [5]=ACK_RCVD(RO)
//   0x04: ADDR    [6:0]  RW  7-bit slave address
//   0x08: TX_DATA [7:0]  WO  Byte to transmit
//   0x0C: RX_DATA [7:0]  RO  Received byte
//   0x10: DIVIDER [15:0] RW  SCL period divider (SCL = SYS_CLK / DIVIDER)
//   0x14: STATUS  [7:0]  RO  [0]=DONE, [1]=BUSY, [2]=ACK, [3]=NACK, [4]=ARB_LOST
//
// I2C bus signals use open-drain behaviour via tristate output enables.
// =============================================================================

`timescale 1ns/1ps

module i2c_master (
    input  wire        clk,
    input  wire        rst_n,

    // I2C bus (open-drain: drive low or release)
    output reg         scl_oe,     // 1 = drive SCL low, 0 = release (pullup)
    output reg         sda_oe,     // 1 = drive SDA low, 0 = release (pullup)
    input  wire        scl_in,     // SCL sampled value
    input  wire        sda_in,     // SDA sampled value

    // Register interface
    input  wire [2:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Interrupt
    output reg         irq
);

    // -------------------------------------------------------------------------
    // Configuration
    // -------------------------------------------------------------------------
    reg [6:0]  slave_addr;
    reg [15:0] divider;      // Default 250 for 400 kHz (100 MHz / 400 kHz / 2 = 125)
    reg        rw_bit;       // 0=write, 1=read
    reg        send_start;
    reg        send_stop;
    reg [7:0]  tx_data;
    reg [7:0]  rx_data;
    reg        ack_en;

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    localparam ST_IDLE      = 4'h0;
    localparam ST_START     = 4'h1;
    localparam ST_ADDR      = 4'h2;
    localparam ST_ADDR_ACK  = 4'h3;
    localparam ST_WRITE     = 4'h4;
    localparam ST_WRITE_ACK = 4'h5;
    localparam ST_READ      = 4'h6;
    localparam ST_READ_ACK  = 4'h7;
    localparam ST_STOP      = 4'h8;
    localparam ST_DONE      = 4'h9;

    reg [3:0]  state;
    reg [3:0]  bit_cnt;
    reg [7:0]  shift_reg;
    reg [15:0] div_cnt;
    reg        clk_phase;    // 0=low half, 1=high half
    reg        ack_rcvd;
    reg        busy;
    reg        done;
    reg        nack;

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            scl_oe     <= 1'b0;    // Release SCL
            sda_oe     <= 1'b0;    // Release SDA
            divider    <= 16'd125;
            slave_addr <= 7'h0;
            rw_bit     <= 1'b0;
            send_start <= 1'b0;
            send_stop  <= 1'b0;
            tx_data    <= 8'h0;
            rx_data    <= 8'h0;
            ack_rcvd   <= 1'b0;
            busy       <= 1'b0;
            done       <= 1'b0;
            nack       <= 1'b0;
            irq        <= 1'b0;
            div_cnt    <= 0;
            clk_phase  <= 1'b0;
            bit_cnt    <= 0;
            shift_reg  <= 8'h0;
            ack_en     <= 1'b1;
        end else begin
            irq  <= 1'b0;
            done <= 1'b0;

            // Register writes
            if (reg_we) begin
                case (reg_addr)
                    3'h0: begin
                        send_start <= reg_wdata[0];
                        send_stop  <= reg_wdata[1];
                        rw_bit     <= reg_wdata[2];
                        ack_en     <= reg_wdata[3];
                    end
                    3'h1: slave_addr <= reg_wdata[6:0];
                    3'h2: tx_data    <= reg_wdata[7:0];
                    3'h4: divider    <= reg_wdata[15:0];
                    default: ;
                endcase
            end

            // Clock phase counter
            if (div_cnt >= divider - 1) begin
                div_cnt   <= 0;
                clk_phase <= ~clk_phase;
            end else begin
                div_cnt <= div_cnt + 1;
            end

            case (state)
                ST_IDLE: begin
                    scl_oe <= 1'b0;
                    sda_oe <= 1'b0;
                    busy   <= 1'b0;
                    if (send_start) begin
                        send_start <= 1'b0;
                        state      <= ST_START;
                        busy       <= 1'b1;
                        div_cnt    <= 0;
                        clk_phase  <= 1'b0;
                    end
                end

                ST_START: begin
                    // START: SDA falls while SCL is high
                    if (!clk_phase) begin
                        sda_oe <= 1'b1;   // Pull SDA low
                        scl_oe <= 1'b1;   // Then pull SCL low
                        shift_reg <= {slave_addr, rw_bit};
                        bit_cnt   <= 0;
                        state     <= ST_ADDR;
                    end
                end

                ST_ADDR: begin
                    if (!clk_phase) begin
                        // Drive SDA with address bit
                        sda_oe <= ~shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0};
                    end else begin
                        // Release SCL for high phase
                        scl_oe <= 1'b0;
                        if (div_cnt == divider - 1) begin
                            scl_oe  <= 1'b1;
                            bit_cnt <= bit_cnt + 1;
                            if (bit_cnt == 7) state <= ST_ADDR_ACK;
                        end
                    end
                end

                ST_ADDR_ACK: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0;   // Release SDA for ACK
                    end else begin
                        scl_oe  <= 1'b0;  // Release SCL
                        ack_rcvd<= ~sda_in;  // ACK = SDA low
                        if (div_cnt == divider - 1) begin
                            scl_oe  <= 1'b1;
                            nack    <= sda_in;
                            if (!sda_in) begin
                                shift_reg <= rw_bit ? 8'hFF : tx_data;
                                bit_cnt   <= 0;
                                state     <= rw_bit ? ST_READ : ST_WRITE;
                            end else begin
                                state <= ST_STOP;
                            end
                        end
                    end
                end

                ST_WRITE: begin
                    if (!clk_phase) begin
                        sda_oe  <= ~shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0};
                    end else begin
                        scl_oe <= 1'b0;
                        if (div_cnt == divider - 1) begin
                            scl_oe  <= 1'b1;
                            bit_cnt <= bit_cnt + 1;
                            if (bit_cnt == 7) state <= ST_WRITE_ACK;
                        end
                    end
                end

                ST_WRITE_ACK: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0;
                    end else begin
                        scl_oe   <= 1'b0;
                        ack_rcvd <= ~sda_in;
                        if (div_cnt == divider - 1) begin
                            scl_oe <= 1'b1;
                            state  <= send_stop ? ST_STOP : ST_DONE;
                        end
                    end
                end

                ST_READ: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b0;   // Release for input
                    end else begin
                        scl_oe    <= 1'b0;
                        shift_reg <= {shift_reg[6:0], sda_in};
                        if (div_cnt == divider - 1) begin
                            scl_oe  <= 1'b1;
                            bit_cnt <= bit_cnt + 1;
                            if (bit_cnt == 7) begin
                                rx_data <= {shift_reg[6:0], sda_in};
                                state   <= ST_READ_ACK;
                            end
                        end
                    end
                end

                ST_READ_ACK: begin
                    if (!clk_phase) begin
                        // Master sends ACK (low) or NACK (high)
                        sda_oe <= ack_en;  // Pull low = ACK
                    end else begin
                        scl_oe <= 1'b0;
                        if (div_cnt == divider - 1) begin
                            scl_oe <= 1'b1;
                            state  <= send_stop ? ST_STOP : ST_DONE;
                        end
                    end
                end

                ST_STOP: begin
                    if (!clk_phase) begin
                        sda_oe <= 1'b1;   // Pull SDA low
                    end else begin
                        scl_oe <= 1'b0;   // Release SCL
                        if (div_cnt == divider - 1) begin
                            sda_oe <= 1'b0;  // Release SDA → STOP condition
                            state  <= ST_DONE;
                        end
                    end
                end

                ST_DONE: begin
                    done  <= 1'b1;
                    irq   <= 1'b1;
                    busy  <= 1'b0;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // Register reads
    always @(*) begin
        case (reg_addr)
            3'h0: reg_rdata = {27'h0, ack_rcvd, ack_en, rw_bit, send_stop, send_start};
            3'h1: reg_rdata = {25'h0, slave_addr};
            3'h3: reg_rdata = {24'h0, rx_data};
            3'h4: reg_rdata = {16'h0, divider};
            3'h5: reg_rdata = {27'h0, nack, ack_rcvd, busy, busy, done};
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
