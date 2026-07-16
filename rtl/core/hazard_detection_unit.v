// =============================================================================
// Module      : hazard_detection_unit.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Hazard Detection Unit — identifies pipeline hazards that cannot
//               be resolved by forwarding alone, and generates stall/flush
//               signals to maintain correct execution.
//
// Hazards Detected:
//
// 1. LOAD-USE Hazard (structural):
//    A LOAD in EX stage is followed immediately by an instruction that reads
//    the loaded register. Forwarding cannot help because the data is not
//    available until after the MEM stage. Solution: stall 1 cycle.
//    Stall action: freeze IF and ID registers, inject NOP into EX.
//
// 2. Branch / Jump Hazard:
//    On a taken branch or jump the two instructions already fetched into IF
//    and ID are invalid. Solution: flush IF and ID registers (insert 2 NOPs).
//    The PC is corrected by the branch unit in the same cycle.
//
// 3. Interrupt Hazard:
//    When an interrupt is taken, flush IF and ID to prevent partially-fetched
//    instructions from executing.
// =============================================================================

`timescale 1ns/1ps

module hazard_detection_unit (
    // ID/EX register: instruction currently in EX stage
    input  wire        ex_mem_read,     // Is EX stage doing a memory read?
    input  wire [4:0]  ex_rd_addr,      // EX stage destination register

    // ID stage: instruction currently being decoded
    input  wire [4:0]  id_rs1_addr,     // Source register 1 being read
    input  wire [4:0]  id_rs2_addr,     // Source register 2 being read

    // Branch/jump resolution (from branch_unit in EX stage)
    input  wire        branch_taken,    // Branch/jump target decided
    input  wire        jump_taken,      // Unconditional jump

    // Interrupt taken signal (from interrupt controller)
    input  wire        irq_taken,

    // Hazard outputs
    output reg         stall_if,        // Freeze IF/ID register
    output reg         stall_id,        // Freeze ID/EX register (same signal)
    output reg         flush_if,        // Flush IF/ID (insert NOP)
    output reg         flush_id,        // Flush ID/EX (insert NOP)
    output reg         flush_ex         // Flush EX/MEM (insert NOP)
);

    always @(*) begin
        // Default: no hazard
        stall_if = 1'b0;
        stall_id = 1'b0;
        flush_if = 1'b0;
        flush_id = 1'b0;
        flush_ex = 1'b0;

        // -----------------------------------------------------------------
        // LOAD-USE Hazard Detection
        // When EX is doing a LOAD and the NEXT instruction reads that reg:
        // -----------------------------------------------------------------
        if (ex_mem_read &&
            (ex_rd_addr != 5'h0) &&
            ((ex_rd_addr == id_rs1_addr) || (ex_rd_addr == id_rs2_addr))) begin
            stall_if = 1'b1;    // Freeze PC and IF/ID
            stall_id = 1'b1;    // Freeze ID/EX
            flush_ex = 1'b1;    // Inject NOP into EX (bubble)
        end

        // -----------------------------------------------------------------
        // Branch / Jump Flush
        // Flush instructions fetched into IF and ID (2 bubbles)
        // Branch stall only triggers if branch actually taken
        // -----------------------------------------------------------------
        if (branch_taken || jump_taken) begin
            flush_if = 1'b1;
            flush_id = 1'b1;
        end

        // -----------------------------------------------------------------
        // Interrupt Flush — same as branch flush
        // -----------------------------------------------------------------
        if (irq_taken) begin
            flush_if = 1'b1;
            flush_id = 1'b1;
        end
    end

endmodule
