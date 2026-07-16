// =============================================================================
// Module      : instruction_register.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Instruction Register (IR) — latches the current instruction
//               from the Instruction ROM during the IF stage.
//
// Behaviour:
//   • flush=1    → IR loads NOP (0x00000000) — branch misprediction / interrupt
//   • stall=1    → IR holds current value    — load-use hazard
//   • otherwise  → IR latches instruction_in on rising edge
//
// NOP encoding = opcode 0x00 (all zeros) → register 0 + 0 + 0 = no-op
// =============================================================================

`timescale 1ns/1ps

module instruction_register (
    input  wire        clk,
    input  wire        rst_n,

    // Control inputs from hazard/branch units
    input  wire        stall,           // Hold current instruction
    input  wire        flush,           // Insert NOP bubble

    // Instruction from memory
    input  wire [31:0] instruction_in,

    // Latched instruction output
    output reg  [31:0] instruction_out
);

    localparam NOP_INSTR = 32'h0000_0000;   // NOP = opcode 0x00

    always @(posedge clk) begin
        if (!rst_n) begin
            instruction_out <= NOP_INSTR;
        end else if (flush) begin
            instruction_out <= NOP_INSTR;   // Bubble injection
        end else if (!stall) begin
            instruction_out <= instruction_in;
        end
        // stall && !flush: hold current instruction
    end

endmodule
