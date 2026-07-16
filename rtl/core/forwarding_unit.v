// =============================================================================
// Module      : forwarding_unit.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Data Forwarding Unit — resolves RAW (Read-After-Write) hazards
//               without stalling by forwarding result values from later pipeline
//               stages back to the EX stage operand inputs.
//
// Two forwarding paths are implemented:
//   EX→EX  : EX/MEM.ALUresult → EX stage operand
//             (instruction 1 result forwarded to instruction 2 in EX)
//   MEM→EX : MEM/WB result    → EX stage operand
//             (instruction 1 result forwarded to instruction 3 in EX)
//
// Forwarding Mux Encoding:
//   forward_a/b = 2'b00 → Use register file data (no hazard)
//   forward_a/b = 2'b01 → Forward from MEM/WB write-back data
//   forward_a/b = 2'b10 → Forward from EX/MEM ALU result
//
// Notes:
//   • R0 is hardwired zero — forwarding to/from R0 is suppressed.
//   • EX→EX forwarding has higher priority than MEM→EX.
// =============================================================================

`timescale 1ns/1ps

module forwarding_unit (
    // EX stage source register addresses
    input  wire [4:0]  ex_rs1_addr,
    input  wire [4:0]  ex_rs2_addr,

    // EX/MEM stage write-back info
    input  wire        exmem_reg_write,
    input  wire [4:0]  exmem_rd_addr,

    // MEM/WB stage write-back info
    input  wire        memwb_reg_write,
    input  wire [4:0]  memwb_rd_addr,

    // Forwarding mux select outputs
    output reg  [1:0]  forward_a,     // Mux select for operand A (rs1)
    output reg  [1:0]  forward_b      // Mux select for operand B (rs2)
);

    // -------------------------------------------------------------------------
    // Forward A (rs1) determination
    // -------------------------------------------------------------------------
    always @(*) begin
        // Default: use register file value
        forward_a = 2'b00;

        // EX→EX hazard: EX/MEM destination matches EX source rs1
        if (exmem_reg_write &&
            (exmem_rd_addr != 5'h0) &&
            (exmem_rd_addr == ex_rs1_addr)) begin
            forward_a = 2'b10;   // Forward from EX/MEM ALU result

        // MEM→EX hazard: MEM/WB destination matches EX source rs1
        end else if (memwb_reg_write &&
                     (memwb_rd_addr != 5'h0) &&
                     (memwb_rd_addr == ex_rs1_addr)) begin
            forward_a = 2'b01;   // Forward from MEM/WB result
        end
    end

    // -------------------------------------------------------------------------
    // Forward B (rs2) determination
    // -------------------------------------------------------------------------
    always @(*) begin
        forward_b = 2'b00;

        if (exmem_reg_write &&
            (exmem_rd_addr != 5'h0) &&
            (exmem_rd_addr == ex_rs2_addr)) begin
            forward_b = 2'b10;

        end else if (memwb_reg_write &&
                     (memwb_rd_addr != 5'h0) &&
                     (memwb_rd_addr == ex_rs2_addr)) begin
            forward_b = 2'b01;
        end
    end

endmodule
