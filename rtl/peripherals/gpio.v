// =============================================================================
// Module      : gpio.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : General Purpose I/O — 32 bidirectional pins configurable as
//               inputs or outputs. Supports interrupt-on-change with selectable
//               edge detection (rising, falling, or both).
//
// Memory-Mapped Registers (base 0xFFFF0000):
//   0x00: DATA_OUT  [31:0] RW  Output register
//   0x04: DATA_IN   [31:0] RO  Input register (sampled pin values)
//   0x08: DIR       [31:0] RW  Direction: 1=output, 0=input
//   0x0C: IRQ_MASK  [31:0] RW  Interrupt enable per pin
//   0x10: IRQ_EDGE  [31:0] RW  Edge select: 1=rising, 0=falling
//   0x14: IRQ_BOTH  [31:0] RW  Both edges: 1=both, 0=use IRQ_EDGE
//   0x18: IRQ_STAT  [31:0] RO  Interrupt status (write 1 to clear)
//   0x1C: IRQ_CLR   [31:0] WO  Clear interrupt flags
// =============================================================================

`timescale 1ns/1ps

module gpio (
    input  wire        clk,
    input  wire        rst_n,

    // Physical I/O pins
    input  wire [31:0] pin_in,     // Sampled input values
    output wire [31:0] pin_out,    // Output drive values
    output wire [31:0] pin_oe,     // Output enables (1=drive)

    // Register interface
    input  wire [2:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Interrupt output
    output reg         irq
);

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    reg [31:0] data_out;
    reg [31:0] dir_reg;        // 1=output, 0=input
    reg [31:0] irq_mask;
    reg [31:0] irq_edge;       // 1=rising, 0=falling
    reg [31:0] irq_both;       // 1=both edges
    reg [31:0] irq_status;

    // Double-register inputs for metastability prevention
    reg [31:0] pin_sync0, pin_sync1;

    // Previous value for edge detection
    reg [31:0] pin_prev;

    assign pin_out = data_out;
    assign pin_oe  = dir_reg;

    // -------------------------------------------------------------------------
    // Input synchronization (2-FF)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            pin_sync0 <= 32'h0;
            pin_sync1 <= 32'h0;
            pin_prev  <= 32'h0;
        end else begin
            pin_sync0 <= pin_in;
            pin_sync1 <= pin_sync0;
            pin_prev  <= pin_sync1;
        end
    end

    // -------------------------------------------------------------------------
    // Edge detection and interrupt generation
    // -------------------------------------------------------------------------
    wire [31:0] rising  = ~pin_prev & pin_sync1;  // 0→1 transition
    wire [31:0] falling =  pin_prev & ~pin_sync1; // 1→0 transition

    always @(posedge clk) begin
        if (!rst_n) begin
            irq_status <= 32'h0;
            irq        <= 1'b0;
        end else begin
            // Set interrupt flags on detected edges
            irq_status <= irq_status |
                          (irq_mask & (
                              (irq_both & (rising | falling)) |
                              (~irq_both & irq_edge  & rising ) |
                              (~irq_both & ~irq_edge & falling)
                          ));

            // Clear flags on write
            if (reg_we && reg_addr == 3'h7) begin
                irq_status <= irq_status & ~reg_wdata;
            end

            // IRQ output: any unmasked interrupt pending
            irq <= |(irq_status & irq_mask);
        end
    end

    // -------------------------------------------------------------------------
    // Register write
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            data_out <= 32'h0;
            dir_reg  <= 32'h0;
            irq_mask <= 32'h0;
            irq_edge <= 32'hFFFF_FFFF;
            irq_both <= 32'h0;
        end else if (reg_we) begin
            case (reg_addr)
                3'h0: data_out <= reg_wdata;
                3'h2: dir_reg  <= reg_wdata;
                3'h3: irq_mask <= reg_wdata;
                3'h4: irq_edge <= reg_wdata;
                3'h5: irq_both <= reg_wdata;
                default: ;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Register read
    // -------------------------------------------------------------------------
    always @(*) begin
        case (reg_addr)
            3'h0: reg_rdata = data_out;
            3'h1: reg_rdata = pin_sync1;   // Current input values
            3'h2: reg_rdata = dir_reg;
            3'h3: reg_rdata = irq_mask;
            3'h4: reg_rdata = irq_edge;
            3'h5: reg_rdata = irq_both;
            3'h6: reg_rdata = irq_status;
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
