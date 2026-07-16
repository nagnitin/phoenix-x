// =============================================================================
// Module      : mem_wb_reg.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : MEM/WB Pipeline Register — carries Memory Access stage results
//               to the Write-Back stage.
//
// Contents latched:
//   • Data from memory (for LOAD instructions)
//   • ALU result (for non-memory instructions)
//   • rd address
//   • Control: reg_write, mem_to_reg, is_call
//
// No flush/stall needed here — MEM/WB always propagates or writes back.
// =============================================================================

`timescale 1ns/1ps

module mem_wb_reg (
    input  wire        clk,
    input  wire        rst_n,

    // Control signals from MEM stage
    input  wire        mem_reg_write,
    input  wire        mem_mem_to_reg,  // 1=write mem_data, 0=write alu_result
    input  wire        mem_is_call,     // 1=write return address (pc_plus4)

    // Data from MEM stage
    input  wire [31:0] mem_read_data,   // Data from memory
    input  wire [31:0] mem_alu_result,  // ALU result pass-through
    input  wire [4:0]  mem_rd_addr,
    input  wire [31:0] mem_pc_plus4,    // Return address for CALL

    // Outputs to WB stage
    output reg         wb_reg_write,
    output reg         wb_mem_to_reg,
    output reg         wb_is_call,

    output reg  [31:0] wb_read_data,
    output reg  [31:0] wb_alu_result,
    output reg  [4:0]  wb_rd_addr,
    output reg  [31:0] wb_pc_plus4
);

    always @(posedge clk) begin
        if (!rst_n) begin
            wb_reg_write   <= 1'b0;
            wb_mem_to_reg  <= 1'b0;
            wb_is_call     <= 1'b0;
            wb_read_data   <= 32'h0;
            wb_alu_result  <= 32'h0;
            wb_rd_addr     <= 5'h0;
            wb_pc_plus4    <= 32'h0;
        end else begin
            wb_reg_write   <= mem_reg_write;
            wb_mem_to_reg  <= mem_mem_to_reg;
            wb_is_call     <= mem_is_call;
            wb_read_data   <= mem_read_data;
            wb_alu_result  <= mem_alu_result;
            wb_rd_addr     <= mem_rd_addr;
            wb_pc_plus4    <= mem_pc_plus4;
        end
    end

endmodule
