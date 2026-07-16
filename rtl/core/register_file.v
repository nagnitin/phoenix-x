// =============================================================================
// Module      : register_file.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : 32 × 32-bit general-purpose register file.
//               • Register R0 is permanently zero (writes are ignored).
//               • R29 = Stack Pointer (SP), R30 = Link Register (LR),
//                 R31 = reserved / zero.
//               • Two independent asynchronous read ports (rs1, rs2).
//               • One synchronous write port (rd) on rising clock edge.
//               • Supports automatic SP (R29) updates on PUSH/POP in WB stage.
// =============================================================================

`timescale 1ns/1ps

module register_file (
    input  wire        clk,
    input  wire        rst_n,
    // Write port
    input  wire        we,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    // Read ports
    input  wire [4:0]  rs1_addr,
    output wire [31:0] rs1_data,
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs2_data,

    // Hardware stack pointer auto-update interface (from WB stage)
    input  wire        wb_is_push,
    input  wire        wb_is_pop
);

    // Register Array
    reg [31:0] regs [0:31];

    integer i;

    // Synchronous write / SP auto-update
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                if (i == 29)
                    regs[i] <= 32'h0001_7FFC; // Default SP pointing to top of RAM
                else
                    regs[i] <= 32'h0;
            end
        end else begin
            // Normal register write
            if (we && (rd_addr != 5'h00)) begin
                regs[rd_addr] <= rd_data;
            end

            // Stack Pointer hardware updates
            if (wb_is_push) begin
                regs[29] <= regs[29] - 32'd4;
            end else if (wb_is_pop) begin
                regs[29] <= regs[29] + 32'd4;
            end
        end
    end

    // Asynchronous read
    assign rs1_data = (rs1_addr == 5'h00) ? 32'h0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'h00) ? 32'h0 : regs[rs2_addr];

endmodule
