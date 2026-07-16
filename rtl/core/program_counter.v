// =============================================================================
// Module      : program_counter.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : 32-bit Program Counter with priority-encoded update logic.
//
// Update priority (highest wins):
//   1. rst_n    — Reset PC to BOOT_ADDR (Boot ROM entry)
//   2. irq_load — Load interrupt vector (entering ISR)
//   3. pc_load  — Load arbitrary value (JMP / CALL / RET / branch taken)
//   4. stall    — Hold current value (pipeline stall — no increment)
//   5. inc      — Increment by 4 (normal sequential execution)
//
// Address space: word-addressed, 4-byte aligned.
// Boot ROM base: 0x00000000
// =============================================================================

`timescale 1ns/1ps

module program_counter (
    input  wire        clk,
    input  wire        rst_n,

    // Stall from hazard detection unit (hold PC)
    input  wire        stall,

    // Branch / jump load (from branch_unit or control_unit)
    input  wire        pc_load,
    input  wire [31:0] pc_load_addr,

    // Interrupt vector load (from interrupt controller)
    input  wire        irq_load,
    input  wire [31:0] irq_vector,

    // Current PC output (fed to IF stage)
    output reg  [31:0] pc_out
);

    // Boot ROM / reset vector
    localparam BOOT_ADDR = 32'h0000_0000;

    always @(posedge clk) begin
        if (!rst_n) begin
            pc_out <= BOOT_ADDR;
        end else if (irq_load) begin
            // Interrupt overrides everything — jump to ISR vector
            pc_out <= irq_vector;
        end else if (pc_load) begin
            // Explicit load: JMP, CALL, RET, taken branch
            pc_out <= pc_load_addr;
        end else if (!stall) begin
            // Normal sequential advance: PC = PC + 4 (byte addressing)
            pc_out <= pc_out + 32'h4;
        end
        // stall && !irq_load && !pc_load: PC unchanged
    end

endmodule
