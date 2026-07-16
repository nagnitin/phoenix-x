// =============================================================================
// Module      : boot_rom.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Boot ROM — 1 KB read-only memory at address 0x00000000.
//               Contains the startup sequence that:
//                 1. Initialises all registers to zero.
//                 2. Sets up the Stack Pointer (R29) to top of Data RAM.
//                 3. Copies the first 64 bytes of Data RAM to scratch space.
//                 4. Jumps to the main program entry point at 0x00001000
//                    (start of Instruction ROM region).
//
// The ROM is hardcoded with the boot sequence instructions.
// The hex representation is embedded using $readmemh with boot.hex.
// For synthesis the ROM is inferred as LUTRAM or Block RAM.
// =============================================================================

`timescale 1ns/1ps

module boot_rom (
    input  wire        clk,
    input  wire [7:0]  addr,      // 256 word address (1KB / 4)
    output reg  [31:0] data_out
);

    // -------------------------------------------------------------------------
    // Boot ROM contents (256 × 32-bit words = 1 KB)
    // Pre-encoded boot sequence instructions:
    //
    //  0: ADDI R29, R0, 0x7FFC   ; SP = 0x0001_7FFC (top of 32KB RAM)
    //  1: ADDI R1,  R0, 0        ; R1 = 0
    //  2: ADDI R2,  R0, 0        ; R2 = 0
    //  ... (clear all registers R1–R28)
    // 28: JMP  0x00001000        ; Jump to main program
    //
    // Encoding per ISA:
    //   ADDI R29, R0, 0x7FFC:
    //     opcode=0x02, rd=29(11101), rs1=0(00000), imm=0x7FFC
    //     [31:26]=000010 [25:21]=11101 [20:16]=00000 [15:0]=0111111111111100
    //     = 32'h0BE07FFC
    //   JMP 0x00001000:
    //     opcode=0x19, target26=0x00001000>>2=0x400
    //     [31:26]=011001 [25:0]=00_0000_0000_0100_0000_0000_00
    //     = 32'h64000400
    // -------------------------------------------------------------------------
    reg [31:0] boot_mem [0:255];

    integer i;
    initial begin
        // Zero all entries (NOP)
        for (i = 0; i < 256; i = i + 1)
            boot_mem[i] = 32'h0000_0000;

        // --- Boot sequence (hand-encoded) ---
        // ADDI R29, R0, 0x7FFC  ; Init stack pointer to top of Data RAM
        boot_mem[0]  = 32'h0BA0_7FFC;
        // ADDI R1..R28 = 0 (clear GPRs using ADDI Rn, R0, 0)
        // ADDI Rn, R0, 0: opcode=0x02, rd=n, rs1=0, imm=0
        // Pattern: {6'h02, rd[4:0], 5'h00, 16'h0000}
        boot_mem[1]  = {6'h02, 5'd1,  5'd0, 16'h0000};
        boot_mem[2]  = {6'h02, 5'd2,  5'd0, 16'h0000};
        boot_mem[3]  = {6'h02, 5'd3,  5'd0, 16'h0000};
        boot_mem[4]  = {6'h02, 5'd4,  5'd0, 16'h0000};
        boot_mem[5]  = {6'h02, 5'd5,  5'd0, 16'h0000};
        boot_mem[6]  = {6'h02, 5'd6,  5'd0, 16'h0000};
        boot_mem[7]  = {6'h02, 5'd7,  5'd0, 16'h0000};
        boot_mem[8]  = {6'h02, 5'd8,  5'd0, 16'h0000};
        boot_mem[9]  = {6'h02, 5'd9,  5'd0, 16'h0000};
        boot_mem[10] = {6'h02, 5'd10, 5'd0, 16'h0000};
        boot_mem[11] = {6'h02, 5'd11, 5'd0, 16'h0000};
        boot_mem[12] = {6'h02, 5'd12, 5'd0, 16'h0000};
        boot_mem[13] = {6'h02, 5'd13, 5'd0, 16'h0000};
        boot_mem[14] = {6'h02, 5'd14, 5'd0, 16'h0000};
        boot_mem[15] = {6'h02, 5'd15, 5'd0, 16'h0000};
        boot_mem[16] = {6'h02, 5'd16, 5'd0, 16'h0000};
        boot_mem[17] = {6'h02, 5'd17, 5'd0, 16'h0000};
        boot_mem[18] = {6'h02, 5'd18, 5'd0, 16'h0000};
        boot_mem[19] = {6'h02, 5'd19, 5'd0, 16'h0000};
        boot_mem[20] = {6'h02, 5'd20, 5'd0, 16'h0000};
        boot_mem[21] = {6'h02, 5'd21, 5'd0, 16'h0000};
        boot_mem[22] = {6'h02, 5'd22, 5'd0, 16'h0000};
        boot_mem[23] = {6'h02, 5'd23, 5'd0, 16'h0000};
        boot_mem[24] = {6'h02, 5'd24, 5'd0, 16'h0000};
        boot_mem[25] = {6'h02, 5'd25, 5'd0, 16'h0000};
        boot_mem[26] = {6'h02, 5'd26, 5'd0, 16'h0000};
        boot_mem[27] = {6'h02, 5'd27, 5'd0, 16'h0000};
        boot_mem[28] = {6'h02, 5'd28, 5'd0, 16'h0000};
        // JMP 0x00001000 — target26 = 0x00001000/4 = 0x400
        // opcode=0x19=011001, target26=26'h0000400
        boot_mem[29] = {6'h19, 26'h000_0400};
    end

    // Synchronous read
    always @(posedge clk) begin
        data_out <= boot_mem[addr];
    end

endmodule
