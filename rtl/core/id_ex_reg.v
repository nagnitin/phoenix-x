// =============================================================================
// Module      : id_ex_reg.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : ID/EX Pipeline Register — carries all decoded instruction
//               information from the Decode stage to the Execute stage.
// =============================================================================

`timescale 1ns/1ps

module id_ex_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,
    input  wire        stall,

    // Opcode pass-through
    input  wire [5:0]  id_opcode,

    // Control signals from ID stage
    input  wire [4:0]  id_alu_op,
    input  wire        id_alu_src,       // 0=rs2, 1=immediate
    input  wire        id_mem_read,
    input  wire        id_mem_write,
    input  wire        id_mem_byte,      // Byte-width access
    input  wire        id_reg_write,
    input  wire        id_branch,
    input  wire        id_jump,
    input  wire        id_alu_update_flags,
    input  wire        id_mem_to_reg,    // 0=ALU result, 1=mem data
    input  wire        id_is_call,
    input  wire        id_is_ret,
    input  wire        id_is_push,
    input  wire        id_is_pop,
    input  wire        id_halt,
    input  wire        id_is_io_in,
    input  wire        id_is_io_out,

    // Data path values
    input  wire [31:0] id_pc_plus4,
    input  wire [31:0] id_rs1_data,
    input  wire [31:0] id_rs2_data,
    input  wire [31:0] id_immediate,
    input  wire [4:0]  id_rd_addr,
    input  wire [4:0]  id_rs1_addr,
    input  wire [4:0]  id_rs2_addr,
    input  wire [25:0] id_jump_target,   // J-type target field

    // Outputs to EX stage (mirrors of all inputs with ex_ prefix)
    output reg  [5:0]  ex_opcode,
    output reg  [4:0]  ex_alu_op,
    output reg         ex_alu_src,
    output reg         ex_mem_read,
    output reg         ex_mem_write,
    output reg         ex_mem_byte,
    output reg         ex_reg_write,
    output reg         ex_branch,
    output reg         ex_jump,
    output reg         ex_alu_update_flags,
    output reg         ex_mem_to_reg,
    output reg         ex_is_call,
    output reg         ex_is_ret,
    output reg         ex_is_push,
    output reg         ex_is_pop,
    output reg         ex_halt,
    output reg         ex_is_io_in,
    output reg         ex_is_io_out,

    output reg  [31:0] ex_pc_plus4,
    output reg  [31:0] ex_rs1_data,
    output reg  [31:0] ex_rs2_data,
    output reg  [31:0] ex_immediate,
    output reg  [4:0]  ex_rd_addr,
    output reg  [4:0]  ex_rs1_addr,
    output reg  [4:0]  ex_rs2_addr,
    output reg  [25:0] ex_jump_target
);

    always @(posedge clk) begin
        if (!rst_n || flush) begin
            // Insert NOP — clear all control signals
            ex_opcode          <= 6'h0;
            ex_alu_op          <= 5'h0;
            ex_alu_src         <= 1'b0;
            ex_mem_read        <= 1'b0;
            ex_mem_write       <= 1'b0;
            ex_mem_byte        <= 1'b0;
            ex_reg_write       <= 1'b0;
            ex_branch          <= 1'b0;
            ex_jump            <= 1'b0;
            ex_alu_update_flags<= 1'b0;
            ex_mem_to_reg      <= 1'b0;
            ex_is_call         <= 1'b0;
            ex_is_ret          <= 1'b0;
            ex_is_push         <= 1'b0;
            ex_is_pop          <= 1'b0;
            ex_halt            <= 1'b0;
            ex_is_io_in        <= 1'b0;
            ex_is_io_out       <= 1'b0;
            ex_pc_plus4        <= 32'h0;
            ex_rs1_data        <= 32'h0;
            ex_rs2_data        <= 32'h0;
            ex_immediate       <= 32'h0;
            ex_rd_addr         <= 5'h0;
            ex_rs1_addr        <= 5'h0;
            ex_rs2_addr        <= 5'h0;
            ex_jump_target     <= 26'h0;
        end else if (!stall) begin
            ex_opcode          <= id_opcode;
            ex_alu_op          <= id_alu_op;
            ex_alu_src         <= id_alu_src;
            ex_mem_read        <= id_mem_read;
            ex_mem_write       <= id_mem_write;
            ex_mem_byte        <= id_mem_byte;
            ex_reg_write       <= id_reg_write;
            ex_branch          <= id_branch;
            ex_jump            <= id_jump;
            ex_alu_update_flags<= id_alu_update_flags;
            ex_mem_to_reg      <= id_mem_to_reg;
            ex_is_call         <= id_is_call;
            ex_is_ret          <= id_is_ret;
            ex_is_push         <= id_is_push;
            ex_is_pop          <= id_is_pop;
            ex_halt            <= id_halt;
            ex_is_io_in        <= id_is_io_in;
            ex_is_io_out       <= id_is_io_out;
            ex_pc_plus4        <= id_pc_plus4;
            ex_rs1_data        <= id_rs1_data;
            ex_rs2_data        <= id_rs2_data;
            ex_immediate       <= id_immediate;
            ex_rd_addr         <= id_rd_addr;
            ex_rs1_addr        <= id_rs1_addr;
            ex_rs2_addr        <= id_rs2_addr;
            ex_jump_target     <= id_jump_target;
        end
    end

endmodule
