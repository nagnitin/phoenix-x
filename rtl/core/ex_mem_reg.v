// =============================================================================
// Module      : ex_mem_reg.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : EX/MEM Pipeline Register — carries Execute stage results to
//               the Memory Access stage.
//
// Contents latched:
//   • ALU result (effective address for LOAD/STORE, or data result)
//   • rs2_data (data to be written to memory for STORE)
//   • Updated status flags
//   • Control signals for MEM and WB stages
//   • rd address for eventual write-back
//   • PC+4 for CALL (link register value)
//
// flush=1 → NOP bubble (interrupt taken)
// =============================================================================

`timescale 1ns/1ps

module ex_mem_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,

    // Control signals from EX stage
    input  wire        ex_mem_read,
    input  wire        ex_mem_write,
    input  wire        ex_mem_byte,
    input  wire        ex_reg_write,
    input  wire        ex_mem_to_reg,
    input  wire        ex_is_call,
    input  wire        ex_halt,
    input  wire        ex_is_io_in,
    input  wire        ex_is_io_out,

    // Data from EX stage
    input  wire [31:0] ex_alu_result,
    input  wire [31:0] ex_rs2_data,     // Store data
    input  wire [4:0]  ex_rd_addr,
    input  wire [31:0] ex_pc_plus4,
    input  wire [31:0] ex_io_addr,      // Peripheral address for IN/OUT
    input  wire [7:0]  ex_flags,        // Updated status flags

    // Outputs to MEM stage
    output reg         mem_mem_read,
    output reg         mem_mem_write,
    output reg         mem_mem_byte,
    output reg         mem_reg_write,
    output reg         mem_mem_to_reg,
    output reg         mem_is_call,
    output reg         mem_halt,
    output reg         mem_is_io_in,
    output reg         mem_is_io_out,

    output reg  [31:0] mem_alu_result,
    output reg  [31:0] mem_rs2_data,
    output reg  [4:0]  mem_rd_addr,
    output reg  [31:0] mem_pc_plus4,
    output reg  [31:0] mem_io_addr,
    output reg  [7:0]  mem_flags
);

    always @(posedge clk) begin
        if (!rst_n || flush) begin
            mem_mem_read   <= 1'b0;
            mem_mem_write  <= 1'b0;
            mem_mem_byte   <= 1'b0;
            mem_reg_write  <= 1'b0;
            mem_mem_to_reg <= 1'b0;
            mem_is_call    <= 1'b0;
            mem_halt       <= 1'b0;
            mem_is_io_in   <= 1'b0;
            mem_is_io_out  <= 1'b0;
            mem_alu_result <= 32'h0;
            mem_rs2_data   <= 32'h0;
            mem_rd_addr    <= 5'h0;
            mem_pc_plus4   <= 32'h0;
            mem_io_addr    <= 32'h0;
            mem_flags      <= 8'h0;
        end else begin
            mem_mem_read   <= ex_mem_read;
            mem_mem_write  <= ex_mem_write;
            mem_mem_byte   <= ex_mem_byte;
            mem_reg_write  <= ex_reg_write;
            mem_mem_to_reg <= ex_mem_to_reg;
            mem_is_call    <= ex_is_call;
            mem_halt       <= ex_halt;
            mem_is_io_in   <= ex_is_io_in;
            mem_is_io_out  <= ex_is_io_out;
            mem_alu_result <= ex_alu_result;
            mem_rs2_data   <= ex_rs2_data;
            mem_rd_addr    <= ex_rd_addr;
            mem_pc_plus4   <= ex_pc_plus4;
            mem_io_addr    <= ex_io_addr;
            mem_flags      <= ex_flags;
        end
    end

endmodule
