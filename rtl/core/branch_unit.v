// =============================================================================
// Module      : branch_unit.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Branch Unit — evaluates branch conditions using CPU status
//               flags and computes the branch/jump target address.
//
// Branch Conditions (evaluated in EX stage):
//   BEQ : branch if Z=1            (equal)
//   BNE : branch if Z=0            (not equal)
//   BLT : branch if N^V=1         (less than, signed)
//   BGT : branch if Z=0 && N^V=0  (greater than, signed)
//   JMP : always taken             (unconditional)
//   CALL: always taken             (unconditional, saves return addr)
//   RET : always taken             (return, target from register)
//
// Branch Target Calculation:
//   Conditional  : PC + sign_extend(imm16) << 2   (PC-relative)
//   JMP/CALL     : {PC[31:28], target26, 2'b00}   (absolute J-type)
//   RET          : rs1_data                        (register-indirect)
//
// Output:
//   branch_taken  : whether to redirect the PC
//   branch_target : the new PC value
// =============================================================================

`timescale 1ns/1ps

module branch_unit (
    input  wire [31:0] pc_plus4,        // PC+4 (current instruction PC + 4)
    input  wire [31:0] rs1_data,        // Register rs1 (for RET)
    input  wire [31:0] immediate,       // Sign-extended immediate (branch offset)
    input  wire [25:0] jump_target,     // J-type target field

    // Instruction type flags (from control unit, in EX stage)
    input  wire        is_branch,       // Conditional branch (BEQ/BNE/BLT/BGT)
    input  wire        is_jump,         // Unconditional jump (JMP/CALL)
    input  wire        is_ret,          // Return (RET/IRET)
    input  wire [5:0]  opcode,          // Needed to distinguish BEQ/BNE/BLT/BGT

    // CPU status flags
    input  wire        flag_z,          // Zero
    input  wire        flag_n,          // Negative
    input  wire        flag_v,          // Overflow

    // Outputs
    output reg         branch_taken,
    output reg  [31:0] branch_target
);

    // Opcode reference
    localparam OP_BEQ  = 6'h1C;
    localparam OP_BNE  = 6'h1D;
    localparam OP_BLT  = 6'h1E;
    localparam OP_BGT  = 6'h1F;

    wire branch_cond;

    // Evaluate branch condition based on opcode and flags
    reg cond;
    always @(*) begin
        case (opcode)
            OP_BEQ:  cond = flag_z;
            OP_BNE:  cond = ~flag_z;
            OP_BLT:  cond = flag_n ^ flag_v;           // signed less than
            OP_BGT:  cond = (~flag_z) & ~(flag_n ^ flag_v); // signed greater than
            default: cond = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Branch / jump decision and target computation
    // -------------------------------------------------------------------------
    always @(*) begin
        branch_taken  = 1'b0;
        branch_target = 32'h0;

        if (is_ret) begin
            // RET: jump to address in rs1 register
            branch_taken  = 1'b1;
            branch_target = rs1_data;

        end else if (is_jump) begin
            // JMP / CALL: absolute J-type target
            // Target = { PC+4[31:28], target26, 2'b00 }
            branch_taken  = 1'b1;
            branch_target = {pc_plus4[31:28], jump_target, 2'b00};

        end else if (is_branch && cond) begin
            // Conditional branch taken: PC-relative
            // Offset = sign_extend(imm16) * 4 + PC+4 - 4 = PC + imm16*4
            branch_taken  = 1'b1;
            branch_target = pc_plus4 + (immediate << 2);
        end
    end

endmodule
