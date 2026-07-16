// =============================================================================
// Module      : alu.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Arithmetic Logic Unit — performs all 21 operations including
//               hardware multiply (32-bit result), barrel shift, rotate, and
//               comparison. Generates Zero, Negative, Carry, and Overflow flags.
//
// Inputs      : operand_a [31:0] — first operand (rs1)
//               operand_b [31:0] — second operand (rs2 or immediate)
//               alu_op    [4:0]  — selects operation (see ALU_OP_* defines)
//
// Outputs     : result    [31:0] — ALU output
//               flag_z           — Zero flag
//               flag_n           — Negative flag  (result[31])
//               flag_c           — Carry flag
//               flag_v           — Overflow flag
//
// ALU Operation Encoding (alu_op[4:0]):
//   0x00 ADD    0x01 ADDI(same)  0x02 SUB    0x03 MUL
//   0x04 DIV    0x05 INC         0x06 DEC    0x07 AND
//   0x08 OR     0x09 XOR         0x0A NOT    0x0B NAND
//   0x0C NOR    0x0D LSL         0x0E LSR    0x0F ASR
//   0x10 ROL    0x11 ROR         0x12 CMP    0x13 SLT
//   0x14 PASS_B (for LOAD/STORE address calculation)
// =============================================================================

`timescale 1ns/1ps

module alu (
    input  wire [31:0] operand_a,       // First operand
    input  wire [31:0] operand_b,       // Second operand or immediate
    input  wire [4:0]  alu_op,          // Operation select
    output reg  [31:0] result,          // ALU result
    output wire        flag_z,          // Zero flag
    output wire        flag_n,          // Negative flag
    output reg         flag_c,          // Carry flag
    output reg         flag_v           // Overflow flag
);

    // -------------------------------------------------------------------------
    // ALU Operation Codes
    // -------------------------------------------------------------------------
    localparam ALU_ADD   = 5'h00;
    localparam ALU_SUB   = 5'h02;
    localparam ALU_MUL   = 5'h03;
    localparam ALU_DIV   = 5'h04;
    localparam ALU_INC   = 5'h05;
    localparam ALU_DEC   = 5'h06;
    localparam ALU_AND   = 5'h07;
    localparam ALU_OR    = 5'h08;
    localparam ALU_XOR   = 5'h09;
    localparam ALU_NOT   = 5'h0A;
    localparam ALU_NAND  = 5'h0B;
    localparam ALU_NOR   = 5'h0C;
    localparam ALU_LSL   = 5'h0D;
    localparam ALU_LSR   = 5'h0E;
    localparam ALU_ASR   = 5'h0F;
    localparam ALU_ROL   = 5'h10;
    localparam ALU_ROR   = 5'h11;
    localparam ALU_CMP   = 5'h12;
    localparam ALU_SLT   = 5'h13;
    localparam ALU_PASSB = 5'h14;   // Pass operand_b (address offset)

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    wire [32:0] add_result;     // 33-bit for carry detection
    wire [32:0] sub_result;     // 33-bit for borrow detection
    wire [63:0] mul_result;     // 64-bit hardware multiplier output
    wire [31:0] div_result;     // Division result
    wire [4:0]  shamt;          // Shift amount (lower 5 bits of operand_b)

    // -------------------------------------------------------------------------
    // Hardware Multiplier (32x32 → 64-bit, use lower 32 bits as result)
    // -------------------------------------------------------------------------
    assign mul_result = operand_a * operand_b;

    // -------------------------------------------------------------------------
    // Hardware Divider (signed, returns quotient)
    // -------------------------------------------------------------------------
    assign div_result = (operand_b != 32'h0) ? (operand_a / operand_b) : 32'hDEAD_BEEF;

    // -------------------------------------------------------------------------
    // Adder / Subtractor with carry/overflow detection
    // -------------------------------------------------------------------------
    assign add_result = {1'b0, operand_a} + {1'b0, operand_b};
    assign sub_result = {1'b0, operand_a} - {1'b0, operand_b};

    // Shift amount: lower 5 bits of operand_b (for 32-bit shifts 0..31)
    assign shamt = operand_b[4:0];

    // -------------------------------------------------------------------------
    // Zero and Negative flags (combinational, derived from result)
    // -------------------------------------------------------------------------
    assign flag_z = (result == 32'h0);
    assign flag_n = result[31];

    // -------------------------------------------------------------------------
    // Main ALU operation select
    // -------------------------------------------------------------------------
    always @(*) begin
        // Default: no carry/overflow
        flag_c = 1'b0;
        flag_v = 1'b0;
        result = 32'h0;

        case (alu_op)
            // -----------------------------------------------------------------
            // Arithmetic Operations
            // -----------------------------------------------------------------
            ALU_ADD: begin
                result = add_result[31:0];
                flag_c = add_result[32];
                // Signed overflow: pos+pos=neg or neg+neg=pos
                flag_v = (~operand_a[31] & ~operand_b[31] & result[31]) |
                         ( operand_a[31] &  operand_b[31] & ~result[31]);
            end

            ALU_SUB: begin
                result = sub_result[31:0];
                flag_c = sub_result[32];    // Borrow flag
                // Signed overflow: pos-neg=neg or neg-pos=pos
                flag_v = (~operand_a[31] &  operand_b[31] & result[31]) |
                         ( operand_a[31] & ~operand_b[31] & ~result[31]);
            end

            ALU_MUL: begin
                result = mul_result[31:0];
                flag_c = |mul_result[63:32];  // High word non-zero → carry
                flag_v = |mul_result[63:32];
            end

            ALU_DIV: begin
                result = div_result;
                flag_c = 1'b0;
                flag_v = (operand_b == 32'h0);  // Division by zero
            end

            ALU_INC: begin
                {flag_c, result} = {1'b0, operand_a} + 33'h1;
                flag_v = (~operand_a[31] & result[31]);
            end

            ALU_DEC: begin
                {flag_c, result} = {1'b0, operand_a} - 33'h1;
                flag_v = (operand_a[31] & ~result[31]);
            end

            // -----------------------------------------------------------------
            // Logical Operations
            // -----------------------------------------------------------------
            ALU_AND:  result = operand_a & operand_b;
            ALU_OR:   result = operand_a | operand_b;
            ALU_XOR:  result = operand_a ^ operand_b;
            ALU_NOT:  result = ~operand_a;
            ALU_NAND: result = ~(operand_a & operand_b);
            ALU_NOR:  result = ~(operand_a | operand_b);

            // -----------------------------------------------------------------
            // Barrel Shifter Operations
            // -----------------------------------------------------------------
            ALU_LSL: begin
                result = operand_a << shamt;
                flag_c = (shamt != 5'h0) ? operand_a[32 - shamt] : 1'b0;
            end

            ALU_LSR: begin
                result = operand_a >> shamt;
                flag_c = (shamt != 5'h0) ? operand_a[shamt - 5'h1] : 1'b0;
            end

            ALU_ASR: begin
                // Arithmetic shift: fill with sign bit
                result = $signed(operand_a) >>> shamt;
                flag_c = (shamt != 5'h0) ? operand_a[shamt - 5'h1] : 1'b0;
            end

            ALU_ROL: begin
                // Rotate left: bits shifted out wrap around to LSB
                result = (operand_a << shamt) | (operand_a >> (32 - shamt));
                flag_c = result[0];
            end

            ALU_ROR: begin
                // Rotate right: bits shifted out wrap around to MSB
                result = (operand_a >> shamt) | (operand_a << (32 - shamt));
                flag_c = result[31];
            end

            // -----------------------------------------------------------------
            // Comparison (CMP: same as SUB but result discarded by control unit)
            // -----------------------------------------------------------------
            ALU_CMP: begin
                result = sub_result[31:0];
                flag_c = sub_result[32];
                flag_v = (~operand_a[31] &  operand_b[31] & result[31]) |
                         ( operand_a[31] & ~operand_b[31] & ~result[31]);
            end

            // -----------------------------------------------------------------
            // Set Less Than (SLT): rd = 1 if rs1 < rs2 (signed), else 0
            // -----------------------------------------------------------------
            ALU_SLT: begin
                result = ($signed(operand_a) < $signed(operand_b)) ? 32'h1 : 32'h0;
            end

            // -----------------------------------------------------------------
            // Pass Operand B (used for address computation base)
            // -----------------------------------------------------------------
            ALU_PASSB: begin
                result = operand_b;
            end

            default: result = 32'h0;
        endcase
    end

endmodule
