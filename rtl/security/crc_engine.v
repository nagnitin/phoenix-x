// =============================================================================
// Module      : crc_engine.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Hardware Cyclic Redundancy Check (CRC) engine.
//               Supports both CRC-16 and CRC-32 computation.
//
// Memory-Mapped Registers (base 0xFFFF0740 - shared watchdog/crc space):
//   0x00: CRC_CTRL   [7:0]  RW  [0]=EN, [1]=MODE (0=CRC-16, 1=CRC-32), [2]=RESET (WO)
//   0x04: CRC_DATA   [31:0] WO  Data input register (triggers computation on write)
//   0x08: CRC_RESULT [31:0] RO  CRC final checksum result
//
// Polynomials:
//   CRC-32: 0x04C11DB7 (reversed: 0xEDB88320)
//   CRC-16: 0x8005 (reversed: 0xA001) or CCITT 0x1021 (reversed: 0x8408)
//           We implement standard CRC-32 (0x04C11DB7) and CRC-16-CCITT (0x1021).
// =============================================================================

`timescale 1ns/1ps

module crc_engine (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [1:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    output reg         busy
);

    // CRC Registers
    reg        crc_en;
    reg        crc_mode; // 0 = CRC-16, 1 = CRC-32
    reg [31:0] crc_accum;

    // CRC polynomials
    localparam POLY_32 = 32'h04C11DB7;
    localparam POLY_16 = 16'h1021;

    // Internal calculation registers
    reg [5:0]  bit_count;
    reg [31:0] data_shift;
    reg        calc_in_progress;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_en           <= 1'b0;
            crc_mode         <= 1'b1; // Default to CRC-32
            crc_accum        <= 32'hFFFF_FFFF;
            data_shift       <= 32'h0;
            bit_count        <= 6'd0;
            calc_in_progress <= 1'b0;
            busy             <= 1'b0;
        end else begin
            // Register writes
            if (reg_we) begin
                case (reg_addr)
                    2'b00: begin // CRC_CTRL
                        crc_en   <= reg_wdata[0];
                        crc_mode <= reg_wdata[1];
                        if (reg_wdata[2]) begin // RESET
                            crc_accum <= reg_wdata[1] ? 32'hFFFF_FFFF : 32'h0000_FFFF;
                        end
                    end
                    2'b01: begin // CRC_DATA write triggers hardware shift
                        if (crc_en && !calc_in_progress) begin
                            data_shift       <= reg_wdata;
                            bit_count        <= 6'd32; // Calculate on 32-bit word
                            calc_in_progress <= 1'b1;
                            busy             <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end

            // Main CRC Bit-serial shift state machine
            if (calc_in_progress) begin
                if (bit_count > 0) begin
                    bit_count <= bit_count - 1;
                    if (crc_mode) begin // CRC-32 computation
                        if ((crc_accum[31] ^ data_shift[31]) == 1'b1) begin
                            crc_accum <= (crc_accum << 1) ^ POLY_32;
                        end else begin
                            crc_accum <= (crc_accum << 1);
                        end
                    end else begin // CRC-16 computation
                        if ((crc_accum[15] ^ data_shift[31]) == 1'b1) begin
                            crc_accum[15:0] <= (crc_accum[14:0] << 1) ^ POLY_16;
                        end else begin
                            crc_accum[15:0] <= (crc_accum[14:0] << 1);
                        end
                    end
                    data_shift <= data_shift << 1;
                end else begin
                    calc_in_progress <= 1'b0;
                    busy             <= 1'b0;
                end
            end
        end
    end

    // Register reads
    always @(*) begin
        case (reg_addr)
            2'b00:   reg_rdata = {29'h0, calc_in_progress, crc_mode, crc_en};
            2'b01:   reg_rdata = 32'h0; // Write-only input data
            2'd2:    reg_rdata = crc_accum; // CRC_RESULT
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
