// =============================================================================
// Module      : data_ram.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Data RAM — 32 KB synchronous read/write memory with
//               byte-enable support for byte and word accesses.
//
// Parameters:
//   ADDR_WIDTH  — Address bits (default 13 → 8192 words × 4 bytes = 32 KB)
//
// Interface:
//   addr        — Word address (byte address >> 2)
//   we          — Word write enable
//   be          — Byte enables [3:0] (1 bit per byte lane)
//   wdata       — 32-bit write data
//   rdata       — 32-bit read data (registered, 1-cycle latency)
//
// Byte Enables:
//   be[0] = byte 0 (bits  7:0  )
//   be[1] = byte 1 (bits 15:8  )
//   be[2] = byte 2 (bits 23:16 )
//   be[3] = byte 3 (bits 31:24 )
//
// Notes:
//   • Reads are synchronous — data available the cycle after addr is presented.
//   • Synthesized as Block RAM with byte-write enables on Xilinx.
//   • Initial contents are all zero.
// =============================================================================

`timescale 1ns/1ps

module data_ram #(
    parameter ADDR_WIDTH = 13    // 8192 words = 32 KB
) (
    input  wire                  clk,
    input  wire                  we,            // Write enable
    input  wire [3:0]            be,            // Byte enables
    input  wire [ADDR_WIDTH-1:0] addr,          // Word address
    input  wire [31:0]           wdata,         // Write data
    output reg  [31:0]           rdata          // Read data
);

    // -------------------------------------------------------------------------
    // Memory array
    // -------------------------------------------------------------------------
    reg [31:0] mem [0:(1 << ADDR_WIDTH) - 1];

    integer i;
    initial begin
        for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1)
            mem[i] = 32'h0;
    end

    // -------------------------------------------------------------------------
    // Synchronous write with byte enables
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (we) begin
            if (be[0]) mem[addr][ 7: 0] <= wdata[ 7: 0];
            if (be[1]) mem[addr][15: 8] <= wdata[15: 8];
            if (be[2]) mem[addr][23:16] <= wdata[23:16];
            if (be[3]) mem[addr][31:24] <= wdata[31:24];
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous read — 1 cycle latency
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        rdata <= mem[addr];
    end

endmodule
