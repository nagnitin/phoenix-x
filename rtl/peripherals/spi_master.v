// =============================================================================
// Module      : spi_master.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : SPI Master controller supporting all four SPI modes (0–3),
//               configurable clock divider, and 8 or 16-bit transfers.
//
// SPI Modes:
//   Mode 0 (CPOL=0, CPHA=0): Clock idle low,  data sampled on rising  edge
//   Mode 1 (CPOL=0, CPHA=1): Clock idle low,  data sampled on falling edge
//   Mode 2 (CPOL=1, CPHA=0): Clock idle high, data sampled on falling edge
//   Mode 3 (CPOL=1, CPHA=1): Clock idle high, data sampled on rising  edge
//
// Memory-Mapped Registers (base 0xFFFF0200):
//   0x00: CTRL   [7:0]  RW  [1:0]=MODE, [2]=START, [3]=BUSY(RO)
//                           [4]=CS_AUTO (auto-assert chip select)
//   0x04: DIVIDER[15:0] RW  Clock divider (SPI_CLK = SYS_CLK / (2*(DIVIDER+1)))
//   0x08: TX_DATA[7:0]  WO  Byte to transmit
//   0x0C: RX_DATA[7:0]  RO  Received byte (valid after transfer complete)
//   0x10: STATUS [7:0]  RO  [0]=DONE, [1]=BUSY
//
// Outputs:
//   sclk     — SPI clock
//   mosi     — Master Out Slave In
//   miso     — Master In Slave Out (input)
//   cs_n     — Chip Select (active low)
//   irq      — Transfer complete interrupt
// =============================================================================

`timescale 1ns/1ps

module spi_master (
    input  wire        clk,
    input  wire        rst_n,

    // SPI bus
    output reg         sclk,
    output reg         mosi,
    input  wire        miso,
    output reg         cs_n,

    // Register interface
    input  wire [2:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Interrupt
    output reg         irq
);

    // -------------------------------------------------------------------------
    // Configuration registers
    // -------------------------------------------------------------------------
    reg [1:0]  spi_mode;        // CPOL/CPHA
    reg [15:0] spi_divider;     // Clock divider
    reg        cs_auto;
    reg [7:0]  tx_data_reg;
    reg [7:0]  rx_data_reg;
    reg        start;

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    localparam IDLE   = 2'h0;
    localparam ACTIVE = 2'h1;
    localparam DONE   = 2'h2;

    reg [1:0]  state;
    reg [3:0]  bit_cnt;         // 0..7 for 8-bit transfer
    reg [7:0]  shift_out;
    reg [7:0]  shift_in;
    reg [15:0] div_cnt;
    reg        sclk_phase;      // Current SPI clock phase
    reg        done;

    wire cpol = spi_mode[1];
    wire cpha = spi_mode[0];

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= IDLE;
            sclk        <= cpol;
            mosi        <= 1'b0;
            cs_n        <= 1'b1;
            bit_cnt     <= 0;
            div_cnt     <= 0;
            shift_out   <= 8'h0;
            shift_in    <= 8'h0;
            rx_data_reg <= 8'h0;
            spi_mode    <= 2'b00;
            spi_divider <= 16'd4;
            cs_auto     <= 1'b1;
            done        <= 1'b0;
            irq         <= 1'b0;
        end else begin
            irq  <= 1'b0;
            done <= 1'b0;

            // Register writes
            if (reg_we) begin
                case (reg_addr)
                    3'h0: begin
                        spi_mode <= reg_wdata[1:0];
                        cs_auto  <= reg_wdata[4];
                        if (reg_wdata[2] && state == IDLE) begin
                            start     <= 1'b1;
                            shift_out <= tx_data_reg;
                        end
                    end
                    3'h1: spi_divider <= reg_wdata[15:0];
                    3'h2: tx_data_reg <= reg_wdata[7:0];
                    default: ;
                endcase
            end

            case (state)
                IDLE: begin
                    sclk <= cpol;
                    if (start) begin
                        start   <= 1'b0;
                        bit_cnt <= 0;
                        div_cnt <= 0;
                        cs_n    <= cs_auto ? 1'b0 : cs_n;
                        // CPHA=0: present first bit before first clock edge
                        mosi    <= (cpha == 0) ? shift_out[7] : 1'b0;
                        state   <= ACTIVE;
                        sclk_phase <= cpol;
                    end
                end

                ACTIVE: begin
                    if (div_cnt >= spi_divider) begin
                        div_cnt    <= 0;
                        sclk_phase <= ~sclk_phase;
                        sclk       <= sclk_phase ^ cpol;

                        // Sample on appropriate edge
                        if (sclk_phase == cpha) begin
                            // Capture MISO
                            shift_in <= {shift_in[6:0], miso};
                            bit_cnt  <= bit_cnt + 1;
                        end else begin
                            // Drive MOSI
                            if (bit_cnt < 8) begin
                                mosi <= shift_out[7 - bit_cnt];
                            end
                        end

                        if (bit_cnt == 8) begin
                            state <= DONE;
                        end
                    end else begin
                        div_cnt <= div_cnt + 1;
                    end
                end

                DONE: begin
                    rx_data_reg <= shift_in;
                    cs_n        <= cs_auto ? 1'b1 : cs_n;
                    done        <= 1'b1;
                    irq         <= 1'b1;
                    sclk        <= cpol;
                    state       <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Register reads
    always @(*) begin
        case (reg_addr)
            3'h0: reg_rdata = {27'h0, cs_auto, 1'b0, (state != IDLE), (state != IDLE), spi_mode};
            3'h1: reg_rdata = {16'h0, spi_divider};
            3'h3: reg_rdata = {24'h0, rx_data_reg};
            3'h4: reg_rdata = {30'h0, (state != IDLE), done};
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
