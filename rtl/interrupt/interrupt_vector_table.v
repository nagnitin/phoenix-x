// =============================================================================
// Module      : interrupt_vector_table.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Interrupt Vector Table (IVT) — maps 8 interrupt numbers to
//               their corresponding ISR (Interrupt Service Routine) addresses.
//
// The IVT is stored in Boot ROM space, starting at address 0x00000100.
// Each entry is 8 bytes (2 words): the first word contains the ISR address.
//
// Default ISR addresses:
//   IRQ 0 (NMI)      → 0x00001100
//   IRQ 1 (Timer)    → 0x00001120
//   IRQ 2 (UART RX)  → 0x00001140
//   IRQ 3 (UART TX)  → 0x00001160
//   IRQ 4 (SPI)      → 0x00001180
//   IRQ 5 (I2C)      → 0x000011A0
//   IRQ 6 (GPIO)     → 0x000011C0
//   IRQ 7 (Software) → 0x000011E0
//
// Software can reprogram IVT entries via memory-mapped writes to 0x00000100+.
// This module provides the hardware default table.
// =============================================================================

`timescale 1ns/1ps

module interrupt_vector_table (
    input  wire        clk,
    input  wire        rst_n,

    // IVT read port (from interrupt controller)
    input  wire [2:0]  irq_num,
    output reg  [31:0] isr_address,

    // IVT write port (from CPU via memory bus, allows runtime reprogramming)
    input  wire        we,
    input  wire [2:0]  wr_num,
    input  wire [31:0] wr_addr
);

    // -------------------------------------------------------------------------
    // IVT registers — 8 entries, one per IRQ
    // -------------------------------------------------------------------------
    reg [31:0] ivt [0:7];

    integer i;
    initial begin
        ivt[0] = 32'h0000_1100;   // NMI
        ivt[1] = 32'h0000_1120;   // Timer
        ivt[2] = 32'h0000_1140;   // UART RX
        ivt[3] = 32'h0000_1160;   // UART TX
        ivt[4] = 32'h0000_1180;   // SPI
        ivt[5] = 32'h0000_11A0;   // I2C
        ivt[6] = 32'h0000_11C0;   // GPIO
        ivt[7] = 32'h0000_11E0;   // Software INT
    end

    // -------------------------------------------------------------------------
    // Write port — software can reprogram vectors
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            ivt[0] <= 32'h0000_1100;
            ivt[1] <= 32'h0000_1120;
            ivt[2] <= 32'h0000_1140;
            ivt[3] <= 32'h0000_1160;
            ivt[4] <= 32'h0000_1180;
            ivt[5] <= 32'h0000_11A0;
            ivt[6] <= 32'h0000_11C0;
            ivt[7] <= 32'h0000_11E0;
        end else if (we) begin
            ivt[wr_num] <= wr_addr;
        end
    end

    // -------------------------------------------------------------------------
    // Combinational read — 1-cycle latency (registered at controller level)
    // -------------------------------------------------------------------------
    always @(*) begin
        isr_address = ivt[irq_num];
    end

endmodule
