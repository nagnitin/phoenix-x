// =============================================================================
// Module      : instruction_rom.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Instruction ROM — 16 KB synchronous read-only memory that
//               holds the user program. Initialized from a hex file at
//               synthesis/simulation time using $readmemh.
//
// Parameters:
//   ADDR_WIDTH  — Address bits (default 12 → 4096 words × 4 bytes = 16 KB)
//   MEM_FILE    — Path to hex initialization file (e.g., "prog.hex")
//
// Interface:
//   addr        — Word address (byte address >> 2)
//   data_out    — 32-bit instruction word (output registered for 1-cycle latency)
//
// Notes:
//   • Only the lower ADDR_WIDTH bits of addr are used.
//   • Uninitialized locations contain NOP (0x00000000).
//   • The ROM is synthesized as Block RAM on Xilinx FPGAs.
// =============================================================================

`timescale 1ns/1ps

module instruction_rom #(
    parameter ADDR_WIDTH = 12,              // 4096 words = 16 KB
    parameter MEM_FILE   = "prog.hex"
) (
    input  wire                  clk,
    input  wire [ADDR_WIDTH-1:0] addr,      // Word address
    output reg  [31:0]           data_out   // Instruction word
);

    // -------------------------------------------------------------------------
    // Memory array: 2^ADDR_WIDTH words of 32 bits
    // -------------------------------------------------------------------------
    reg [31:0] mem [0:(1 << ADDR_WIDTH) - 1];

    integer i;

    // Initialize all locations to NOP, then overlay hex file
    initial begin
        for (i = 0; i < (1 << ADDR_WIDTH); i = i + 1)
            mem[i] = 32'h0000_0000;   // NOP
        // Load program — suppress error if file not found in simulation
        if (MEM_FILE != "") begin
            $readmemh(MEM_FILE, mem);
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous read — one cycle latency
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        data_out <= mem[addr];
    end

endmodule
