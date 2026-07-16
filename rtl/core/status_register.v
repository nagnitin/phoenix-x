// =============================================================================
// Module      : status_register.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : 8-bit CPU Status Register (Processor Status Word).
//               Holds condition codes and mode bits updated by the ALU,
//               branch unit, and interrupt controller.
//
// Bit Assignment:
//   [7] S  — Supervisor mode (1=kernel, 0=user)
//   [6] T  — Timer interrupt pending
//   [5] H  — Half-carry (BCD operations)
//   [4] I  — Global interrupt enable
//   [3] V  — Signed overflow
//   [2] C  — Carry / Borrow
//   [1] N  — Negative (sign bit of result)
//   [0] Z  — Zero (result == 0)
//
// Sources that update flags:
//   alu_update   — ALU result flags (Z, N, C, V)
//   irq_update   — Interrupt controller clears/sets I flag
//   direct_write — IRET or software write (full register)
// =============================================================================

`timescale 1ns/1ps

module status_register (
    input  wire       clk,
    input  wire       rst_n,

    // ALU flag update interface
    input  wire       alu_update,    // 1 = capture ALU flags this cycle
    input  wire       alu_z,         // Zero flag from ALU
    input  wire       alu_n,         // Negative flag from ALU
    input  wire       alu_c,         // Carry flag from ALU
    input  wire       alu_v,         // Overflow flag from ALU

    // Interrupt controller interface
    input  wire       irq_disable_i, // Clear interrupt enable (entering ISR)
    input  wire       irq_enable_i,  // Set interrupt enable (IRET)
    input  wire       set_supervisor,// Enter supervisor mode
    input  wire       clr_supervisor,// Leave supervisor mode
    input  wire       set_timer_flag,// Timer interrupt fired
    input  wire       clr_timer_flag,// Timer flag acknowledged

    // Direct write (IRET restores saved SR)
    input  wire       direct_write,
    input  wire [7:0] direct_data,

    // Current status register value (read by CPU / pipeline)
    output reg  [7:0] status
);

    // -------------------------------------------------------------------------
    // Bit index aliases for readability
    // -------------------------------------------------------------------------
    localparam BIT_Z = 0;
    localparam BIT_N = 1;
    localparam BIT_C = 2;
    localparam BIT_V = 3;
    localparam BIT_I = 4;
    localparam BIT_H = 5;
    localparam BIT_T = 6;
    localparam BIT_S = 7;

    // -------------------------------------------------------------------------
    // Sequential update — priority (highest to lowest):
    //   1. Reset
    //   2. Direct write (IRET)
    //   3. ALU flag update
    //   4. Interrupt enable/disable
    //   5. Supervisor mode changes
    //   6. Timer flag
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            // After reset: interrupts enabled, user mode, all flags clear
            status <= 8'b0001_0000;   // I=1
        end else if (direct_write) begin
            // IRET restores the saved status register
            status <= direct_data;
        end else begin
            // ALU updates Z, N, C, V flags
            if (alu_update) begin
                status[BIT_Z] <= alu_z;
                status[BIT_N] <= alu_n;
                status[BIT_C] <= alu_c;
                status[BIT_V] <= alu_v;
            end
            // Interrupt enable / disable
            if (irq_disable_i)  status[BIT_I] <= 1'b0;
            if (irq_enable_i)   status[BIT_I] <= 1'b1;
            // Supervisor mode
            if (set_supervisor) status[BIT_S] <= 1'b1;
            if (clr_supervisor) status[BIT_S] <= 1'b0;
            // Timer flag
            if (set_timer_flag) status[BIT_T] <= 1'b1;
            if (clr_timer_flag) status[BIT_T] <= 1'b0;
        end
    end

endmodule
