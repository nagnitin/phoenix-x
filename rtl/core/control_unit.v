// =============================================================================
// Module      : instruction_decoder.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Instruction Decoder — extracts all fields from the 32-bit
//               instruction word and drives the control unit with opcode,
//               register addresses, and immediate values.
//
// Instruction Formats:
//
//  R-Type: [31:26]=opcode [25:21]=rd [20:16]=rs1 [15:11]=rs2 [10:0]=func
//  I-Type: [31:26]=opcode [25:21]=rd [20:16]=rs1 [15:0]=imm16
//  J-Type: [31:26]=opcode [25:0]=target26
//
// Sign Extension:
//  imm16 is sign-extended to 32 bits for arithmetic/memory instructions.
//
// Opcode Definitions — matches the ISA table in the implementation plan.
// =============================================================================

`timescale 1ns/1ps

module instruction_decoder (
    input  wire [31:0] instruction,

    // Extracted fields
    output wire [5:0]  opcode,
    output wire [4:0]  rd,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [10:0] func,
    output wire [15:0] imm16,
    output wire [25:0] target26,
    output wire [31:0] imm32_signed   // Sign-extended immediate
);

    // -------------------------------------------------------------------------
    // Field extraction (combinational)
    // -------------------------------------------------------------------------
    assign opcode    = instruction[31:26];
    assign rd        = instruction[25:21];
    assign rs1       = instruction[20:16];
    assign rs2       = instruction[15:11];
    assign func      = instruction[10:0];
    assign imm16     = instruction[15:0];
    assign target26  = instruction[25:0];

    // Sign-extend 16-bit immediate to 32 bits
    assign imm32_signed = {{16{imm16[15]}}, imm16};

endmodule


// =============================================================================
// Module      : control_unit.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Main Control Unit — decodes opcode and generates all pipeline
//               control signals for the ID stage. Pure combinational logic.
//
// For each opcode this unit sets:
//   alu_op            — ALU operation to perform (5 bits)
//   alu_src           — ALU operand B source: 0=rs2, 1=immediate
//   mem_read          — Data memory read enable
//   mem_write         — Data memory write enable
//   mem_byte          — Byte-width memory access
//   reg_write         — Register file write enable
//   branch            — Conditional branch instruction
//   jump              — Unconditional jump (JMP/CALL/RET)
//   mem_to_reg        — WB data source: 0=ALU, 1=memory
//   alu_update_flags  — Update status register from ALU result
//   is_call           — CALL instruction (saves return address to rd)
//   is_ret            — RET instruction (PC from register)
//   is_push           — PUSH instruction
//   is_pop            — POP instruction
//   halt              — HALT instruction
//   is_io_in          — IN instruction (read peripheral)
//   is_io_out         — OUT instruction (write peripheral)
// =============================================================================

module control_unit (
    input  wire [5:0]  opcode,

    output reg  [4:0]  alu_op,
    output reg         alu_src,
    output reg         mem_read,
    output reg         mem_write,
    output reg         mem_byte,
    output reg         reg_write,
    output reg         branch,
    output reg         jump,
    output reg         mem_to_reg,
    output reg         alu_update_flags,
    output reg         is_call,
    output reg         is_ret,
    output reg         is_push,
    output reg         is_pop,
    output reg         halt,
    output reg         is_io_in,
    output reg         is_io_out
);

    // Opcode definitions — must match assembler and ISA table
    localparam OP_NOP   = 6'h00;
    localparam OP_ADD   = 6'h01;
    localparam OP_ADDI  = 6'h02;
    localparam OP_SUB   = 6'h03;
    localparam OP_MUL   = 6'h04;
    localparam OP_DIV   = 6'h05;
    localparam OP_INC   = 6'h06;
    localparam OP_DEC   = 6'h07;
    localparam OP_AND   = 6'h08;
    localparam OP_OR    = 6'h09;
    localparam OP_XOR   = 6'h0A;
    localparam OP_NOT   = 6'h0B;
    localparam OP_NAND  = 6'h0C;
    localparam OP_NOR   = 6'h0D;
    localparam OP_LSL   = 6'h0E;
    localparam OP_LSR   = 6'h0F;
    localparam OP_ASR   = 6'h10;
    localparam OP_ROL   = 6'h11;
    localparam OP_ROR   = 6'h12;
    localparam OP_CMP   = 6'h13;
    localparam OP_SLT   = 6'h14;
    localparam OP_LOAD  = 6'h15;
    localparam OP_STORE = 6'h16;
    localparam OP_LOADB = 6'h17;
    localparam OP_STOREB= 6'h18;
    localparam OP_JMP   = 6'h19;
    localparam OP_CALL  = 6'h1A;
    localparam OP_RET   = 6'h1B;
    localparam OP_BEQ   = 6'h1C;
    localparam OP_BNE   = 6'h1D;
    localparam OP_BLT   = 6'h1E;
    localparam OP_BGT   = 6'h1F;
    localparam OP_PUSH  = 6'h20;
    localparam OP_POP   = 6'h21;
    localparam OP_IN    = 6'h22;
    localparam OP_OUT   = 6'h23;
    localparam OP_INT   = 6'h24;
    localparam OP_IRET  = 6'h25;
    localparam OP_HALT  = 6'h3F;

    // ALU op codes (must match alu.v)
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
    localparam ALU_PASSB = 5'h14;

    always @(*) begin
        // ---- Safe defaults ----
        alu_op           = ALU_ADD;
        alu_src          = 1'b0;
        mem_read         = 1'b0;
        mem_write        = 1'b0;
        mem_byte         = 1'b0;
        reg_write        = 1'b0;
        branch           = 1'b0;
        jump             = 1'b0;
        mem_to_reg       = 1'b0;
        alu_update_flags = 1'b0;
        is_call          = 1'b0;
        is_ret           = 1'b0;
        is_push          = 1'b0;
        is_pop           = 1'b0;
        halt             = 1'b0;
        is_io_in         = 1'b0;
        is_io_out        = 1'b0;

        case (opcode)
            OP_NOP:  ;   // All defaults — no operation

            // --- Arithmetic (R-type) ---
            OP_ADD:  begin alu_op = ALU_ADD;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_ADDI: begin alu_op = ALU_ADD;  reg_write = 1'b1; alu_src = 1'b1; alu_update_flags = 1'b1; end
            OP_SUB:  begin alu_op = ALU_SUB;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_MUL:  begin alu_op = ALU_MUL;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_DIV:  begin alu_op = ALU_DIV;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_INC:  begin alu_op = ALU_INC;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_DEC:  begin alu_op = ALU_DEC;  reg_write = 1'b1; alu_update_flags = 1'b1; end

            // --- Logical (R-type) ---
            OP_AND:  begin alu_op = ALU_AND;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_OR:   begin alu_op = ALU_OR;   reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_XOR:  begin alu_op = ALU_XOR;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_NOT:  begin alu_op = ALU_NOT;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_NAND: begin alu_op = ALU_NAND; reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_NOR:  begin alu_op = ALU_NOR;  reg_write = 1'b1; alu_update_flags = 1'b1; end

            // --- Shift/Rotate (R-type) ---
            OP_LSL:  begin alu_op = ALU_LSL;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_LSR:  begin alu_op = ALU_LSR;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_ASR:  begin alu_op = ALU_ASR;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_ROL:  begin alu_op = ALU_ROL;  reg_write = 1'b1; alu_update_flags = 1'b1; end
            OP_ROR:  begin alu_op = ALU_ROR;  reg_write = 1'b1; alu_update_flags = 1'b1; end

            // --- Comparison (R-type, no write) ---
            OP_CMP:  begin alu_op = ALU_CMP;  alu_update_flags = 1'b1; end
            OP_SLT:  begin alu_op = ALU_SLT;  reg_write = 1'b1; end

            // --- Memory (I-type) ---
            OP_LOAD:  begin alu_op = ALU_ADD; alu_src = 1'b1; mem_read = 1'b1;  reg_write = 1'b1; mem_to_reg = 1'b1; end
            OP_STORE: begin alu_op = ALU_ADD; alu_src = 1'b1; mem_write = 1'b1; end
            OP_LOADB: begin alu_op = ALU_ADD; alu_src = 1'b1; mem_read = 1'b1;  reg_write = 1'b1; mem_to_reg = 1'b1; mem_byte = 1'b1; end
            OP_STOREB:begin alu_op = ALU_ADD; alu_src = 1'b1; mem_write = 1'b1; mem_byte = 1'b1; end

            // --- Branches (I-type, branch flag) ---
            OP_BEQ:  begin alu_op = ALU_CMP; branch = 1'b1; alu_src = 1'b0; end
            OP_BNE:  begin alu_op = ALU_CMP; branch = 1'b1; alu_src = 1'b0; end
            OP_BLT:  begin alu_op = ALU_CMP; branch = 1'b1; alu_src = 1'b0; end
            OP_BGT:  begin alu_op = ALU_CMP; branch = 1'b1; alu_src = 1'b0; end

            // --- Jumps (J-type) ---
            OP_JMP:  begin jump = 1'b1; end
            OP_CALL: begin jump = 1'b1; is_call = 1'b1; reg_write = 1'b1; end  // Save PC+4 to rd (R29/LR)
            OP_RET:  begin jump = 1'b1; is_ret = 1'b1; end

            // --- Stack ---
            OP_PUSH: begin alu_op = ALU_SUB; mem_write = 1'b1; is_push = 1'b1; end
            OP_POP:  begin alu_op = ALU_ADD; mem_read  = 1'b1; is_pop  = 1'b1; reg_write = 1'b1; mem_to_reg = 1'b1; end

            // --- I/O ---
            OP_IN:   begin is_io_in  = 1'b1; reg_write = 1'b1; end
            OP_OUT:  begin is_io_out = 1'b1; end

            // --- System ---
            OP_INT:  begin jump = 1'b1; end   // Software interrupt
            OP_IRET: begin jump = 1'b1; is_ret = 1'b1; end
            OP_HALT: begin halt = 1'b1; end

            default: ;   // Unknown opcode → NOP
        endcase
    end

endmodule
