// =============================================================================
// Module      : if_id_reg.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : IF/ID Pipeline Register — latches outputs of the Instruction
//               Fetch stage and presents them to the Instruction Decode stage.
//
// Contents latched:
//   • PC+4 (address of next instruction — used for CALL return address)
//   • Raw 32-bit instruction word
//
// Control:
//   stall=1 → Hold all values (hazard stall)
//   flush=1 → Insert NOP bubble (branch mispredict / interrupt taken)
// =============================================================================

`timescale 1ns/1ps

module if_id_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,           // Freeze this register
    input  wire        flush,           // Inject NOP bubble

    // From IF stage
    input  wire [31:0] if_pc_plus4,    // PC + 4
    input  wire [31:0] if_instruction, // Raw instruction

    // To ID stage
    output reg  [31:0] id_pc_plus4,
    output reg  [31:0] id_instruction
);

    localparam NOP = 32'h0000_0000;

    always @(posedge clk) begin
        if (!rst_n || flush) begin
            id_pc_plus4    <= 32'h0;
            id_instruction <= NOP;
        end else if (!stall) begin
            id_pc_plus4    <= if_pc_plus4;
            id_instruction <= if_instruction;
        end
        // stall: hold all values unchanged
    end

endmodule
