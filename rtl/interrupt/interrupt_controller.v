// =============================================================================
// Module      : interrupt_controller.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Priority Interrupt Controller (PIC) — manages 8 interrupt
//               sources with fixed priority (0 = highest, 7 = lowest).
//
// Interrupt Sources (irq_lines[7:0]):
//   0: NMI      — Non-maskable (always accepted)
//   1: Timer    — Timer overflow / match
//   2: UART RX  — UART receive data ready
//   3: UART TX  — UART transmit complete
//   4: SPI      — SPI transfer complete
//   5: I2C      — I2C transaction complete
//   6: GPIO     — GPIO edge detect
//   7: Software — INT instruction
//
// Registers (memory-mapped at 0xFFFF0600):
//   Offset 0x00: IRQ_STATUS  [7:0]  — Raw interrupt status (RO)
//   Offset 0x04: IRQ_ENABLE  [7:0]  — Interrupt enable mask (RW)
//   Offset 0x08: IRQ_PENDING [7:0]  — Pending & enabled (RO)
//   Offset 0x0C: IRQ_ACK     [7:0]  — Write 1 to clear pending (WO)
//   Offset 0x10: IRQ_ACTIVE  [2:0]  — Currently serviced IRQ number (RO)
//
// Operation:
//   • irq_out pulses for one cycle when an interrupt is accepted.
//   • irq_num indicates the highest-priority pending interrupt.
//   • irq_vector is looked up from the interrupt vector table.
//   • The CPU must write to IRQ_ACK to clear the request after IRET.
// =============================================================================

`timescale 1ns/1ps

module interrupt_controller (
    input  wire        clk,
    input  wire        rst_n,

    // Interrupt request lines (active high, level sensitive)
    input  wire [7:0]  irq_lines,

    // CPU status — global interrupt enable flag
    input  wire        irq_enable_flag,     // CPU I flag

    // CPU is currently in ISR (prevents nesting unless NMI)
    input  wire        in_isr,

    // Memory-mapped register interface
    input  wire [3:0]  reg_addr,            // Register offset / 4
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Outputs to CPU
    output reg         irq_out,             // Interrupt request to CPU
    output reg  [2:0]  irq_num,            // IRQ number (0-7)
    output wire [31:0] irq_vector           // ISR address from IVT
);

    // -------------------------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------------------------
    reg [7:0] irq_enable;       // IRQ enable mask
    reg [7:0] irq_pending;      // Software-clearable pending bits

    // -------------------------------------------------------------------------
    // Interrupt Vector Table (IVT) — fixed addresses
    // Vector[n] = 0x00000100 + n*8 (within Boot ROM space)
    // -------------------------------------------------------------------------
    function [31:0] get_vector;
        input [2:0] num;
        begin
            get_vector = 32'h0000_0100 + {26'h0, num, 3'h0}; // num * 8
        end
    endfunction

    assign irq_vector = get_vector(irq_num);

    // -------------------------------------------------------------------------
    // Priority encoder — find lowest-numbered set bit
    // -------------------------------------------------------------------------
    wire [7:0] masked = irq_lines & irq_enable;

    // -------------------------------------------------------------------------
    // Sequential logic
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            irq_enable  <= 8'hFF;   // All enabled after reset
            irq_pending <= 8'h0;
            irq_out     <= 1'b0;
            irq_num     <= 3'h0;
        end else begin
            // Latch pending edges
            irq_pending <= irq_pending | irq_lines;

            // Register write handling
            if (reg_we) begin
                case (reg_addr)
                    4'h1: irq_enable  <= reg_wdata[7:0];       // IRQ_ENABLE write
                    4'h3: irq_pending <= irq_pending & ~reg_wdata[7:0]; // IRQ_ACK
                    default: ;
                endcase
            end

            // Default: no interrupt this cycle
            irq_out <= 1'b0;

            // Priority resolution — accept highest priority (lowest index)
            if (irq_enable_flag && !in_isr) begin
                if      (masked[0]) begin irq_out <= 1'b1; irq_num <= 3'd0; irq_pending[0] <= 1'b0; end
                else if (masked[1]) begin irq_out <= 1'b1; irq_num <= 3'd1; irq_pending[1] <= 1'b0; end
                else if (masked[2]) begin irq_out <= 1'b1; irq_num <= 3'd2; irq_pending[2] <= 1'b0; end
                else if (masked[3]) begin irq_out <= 1'b1; irq_num <= 3'd3; irq_pending[3] <= 1'b0; end
                else if (masked[4]) begin irq_out <= 1'b1; irq_num <= 3'd4; irq_pending[4] <= 1'b0; end
                else if (masked[5]) begin irq_out <= 1'b1; irq_num <= 3'd5; irq_pending[5] <= 1'b0; end
                else if (masked[6]) begin irq_out <= 1'b1; irq_num <= 3'd6; irq_pending[6] <= 1'b0; end
                else if (masked[7]) begin irq_out <= 1'b1; irq_num <= 3'd7; irq_pending[7] <= 1'b0; end
            end
            // NMI (irq_lines[0]) is never masked — override if CPU in ISR
            if (irq_lines[0] && in_isr) begin
                irq_out <= 1'b1;
                irq_num <= 3'd0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Register read
    // -------------------------------------------------------------------------
    always @(*) begin
        case (reg_addr)
            4'h0: reg_rdata = {24'h0, irq_lines};
            4'h1: reg_rdata = {24'h0, irq_enable};
            4'h2: reg_rdata = {24'h0, irq_pending & irq_enable};
            4'h4: reg_rdata = {29'h0, irq_num};
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
