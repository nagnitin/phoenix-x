// =============================================================================
// Module      : watchdog_timer.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Programmable Watchdog Timer (WDT). Prevents lockups by
//               generating a system reset unless periodically fed (cleared)
//               by software.
//
// Memory-Mapped Registers (base 0xFFFF0700):
//   0x00: WDT_CTRL  [7:0]  RW  [0]=EN (Enable), [1]=IRQ_EN (Generate interrupt before reset)
//                              [7:2]=Reserved
//   0x04: WDT_LOAD  [31:0] RW  Watchdog timeout value in clock cycles
//   0x08: WDT_FEED  [31:0] WO  Write 0xAAAA5555 to kick/feed the dog
//   0x0C: WDT_STAT  [7:0]  RO  [0]=WD_RESET_OCCURRED (Sticky bit, cleared by writing 1)
//
// If IRQ_EN is set, the WDT generates an interrupt when the count reaches
// half of the timeout value, giving the system a chance to log debug info
// before reset. If count reaches WDT_LOAD, the system reset (wdt_reset_out) is asserted.
// =============================================================================

`timescale 1ns/1ps

module watchdog_timer (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [1:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Outputs
    output reg         wdt_irq,        // Pre-reset warning interrupt
    output reg         wdt_reset_out   // Watchdog system reset (active high)
);

    // WDT Registers
    reg        wdt_en;
    reg        wdt_irq_en;
    reg [31:0] wdt_load;
    reg        wdt_status_sticky;

    // Internal WDT counter
    reg [31:0] wdt_count;

    // Reset logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wdt_en            <= 1'b0;
            wdt_irq_en        <= 1'b0;
            wdt_load          <= 32'hFFFF_FFFF; // Max load value
            wdt_status_sticky <= 1'b0;
            wdt_count         <= 32'h0;
            wdt_irq           <= 1'b0;
            wdt_reset_out     <= 1'b0;
        end else begin
            wdt_irq       <= 1'b0;
            wdt_reset_out <= 1'b0;

            // Handle register writes
            if (reg_we) begin
                case (reg_addr)
                    2'b00: begin // WDT_CTRL
                        wdt_en     <= reg_wdata[0];
                        wdt_irq_en <= reg_wdata[1];
                    end
                    2'b01: begin // WDT_LOAD
                        wdt_load  <= reg_wdata;
                        wdt_count <= 32'h0; // Reset counter on load write
                    end
                    2'b10: begin // WDT_FEED
                        if (reg_wdata == 32'hAAAA_5555) begin
                            wdt_count <= 32'h0; // Feed the dog
                        end
                    end
                    2'b11: begin // WDT_STAT
                        if (reg_wdata[0]) begin
                            wdt_status_sticky <= 1'b0; // Clear sticky bit
                        end
                    end
                endcase
            end

            // Main WDT counter logic
            if (wdt_en) begin
                if (wdt_count >= wdt_load) begin
                    wdt_reset_out     <= 1'b1;         // Reset the system
                    wdt_status_sticky <= 1'b1;         // Set sticky bit
                    wdt_count         <= 32'h0;        // Reset count
                end else begin
                    wdt_count <= wdt_count + 1;

                    // Generate early warning interrupt at 50% timeout if enabled
                    if (wdt_irq_en && (wdt_count == (wdt_load >> 1))) begin
                        wdt_irq <= 1'b1;
                    end
                end
            end else begin
                wdt_count <= 32'h0;
            end
        end
    end

    // Register reads
    always @(*) begin
        case (reg_addr)
            2'b00:   reg_rdata = {30'h0, wdt_irq_en, wdt_en};
            2'b01:   reg_rdata = wdt_load;
            2'b10:   reg_rdata = wdt_count;
            2'b11:   reg_rdata = {31'h0, wdt_status_sticky};
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
