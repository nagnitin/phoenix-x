// =============================================================================
// Module      : debug_unit.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Debug Unit (DBU) — provides tracing capabilities, cycle counters,
//               instruction counters, and interfaces to view CPU status.
//
// Memory-Mapped Registers (base 0xFFFF0800):
//   0x00: DBU_CTRL     [7:0]  RW  [0]=EN (Enable counters), [1]=HALT (Force CPU Halt), [2]=RESET (Reset counters)
//   0x04: CYCLE_L      [31:0] RO  Lower 32-bits of CPU cycle counter
//   0x08: CYCLE_H      [31:0] RO  Upper 32-bits of CPU cycle counter
//   0x0C: INSTR_L      [31:0] RO  Lower 32-bits of executed instruction counter
//   0x10: INSTR_H      [31:0] RO  Upper 32-bits of executed instruction counter
//   0x14: LAST_PC      [31:0] RO  PC of the last executed instruction (WB stage)
//   0x18: LAST_INSTR   [31:0] RO  Instruction word of the last executed instruction
//   0x1C: REG_VAL      [31:0] RO  Selected register value (via DBU_CTRL or host)
//   0x20: REG_SEL      [4:0]  RW  Select register (0-31) to view through REG_VAL
// =============================================================================

`timescale 1ns/1ps

module debug_unit (
    input  wire        clk,
    input  wire        rst_n,

    // Memory-mapped interface
    input  wire [3:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Interface to CPU Core pipelines
    input  wire [31:0] wb_pc,           // Current PC in Writeback stage
    input  wire [31:0] wb_instr,        // Current instruction in Writeback stage
    input  wire        wb_valid,        // 1 if instruction in WB stage is valid (not a bubble)
    input  wire [31:0] reg_file_val,    // Read back port connected to register file [reg_sel]
    output wire [4:0]  reg_file_sel,    // Request register index to RF

    // CPU control output
    output reg         dbu_halt         // Halt signal to CPU control logic
);

    // Registers
    reg        dbu_en;
    reg [63:0] cycle_count;
    reg [63:0] instr_count;
    reg [31:0] last_pc;
    reg [31:0] last_instr;
    reg [4:0]  reg_select;

    assign reg_file_sel = reg_select;

    // Cycle and instruction counter logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbu_en      <= 1'b1; // Default enabled after reset
            dbu_halt    <= 1'b0;
            cycle_count <= 64'd0;
            instr_count <= 64'd0;
            last_pc     <= 32'h0;
            last_instr  <= 32'h0;
            reg_select  <= 5'd0;
        end else begin
            // Register writes
            if (reg_we) begin
                case (reg_addr)
                    4'h0: begin // DBU_CTRL
                        dbu_en   <= reg_wdata[0];
                        dbu_halt <= reg_wdata[1];
                        if (reg_wdata[2]) begin // RESET counters
                            cycle_count <= 64'd0;
                            instr_count <= 64'd0;
                        end
                    end
                    4'h8: reg_select <= reg_wdata[4:0]; // REG_SEL
                    default: ;
                endcase
            end

            // Performance counters
            if (dbu_en && !dbu_halt) begin
                cycle_count <= cycle_count + 1;
                if (wb_valid) begin
                    instr_count <= instr_count + 1;
                    last_pc     <= wb_pc;
                    last_instr  <= wb_instr;
                end
            end
        end
    end

    // Register reads
    always @(*) begin
        case (reg_addr)
            4'h0: reg_rdata = {29'h0, 1'b0, dbu_halt, dbu_en};
            4'h1: reg_rdata = cycle_count[31:0];
            4'h2: reg_rdata = cycle_count[63:32];
            4'h3: reg_rdata = instr_count[31:0];
            4'h4: reg_rdata = instr_count[63:32];
            4'h5: reg_rdata = last_pc;
            4'h6: reg_rdata = last_instr;
            4'h7: reg_rdata = reg_file_val; // Value of selected register
            4'h8: reg_rdata = {27'h0, reg_select};
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
