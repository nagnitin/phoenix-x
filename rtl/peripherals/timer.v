// =============================================================================
// Module      : timer.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Multi-mode 32-bit programmable timer with:
//               • Periodic interrupt timer (auto-reload)
//               • One-shot timer (fires once)
//               • Delay generator (blocking in software via polling)
//               • PWM output with configurable period and duty cycle
//               • Free-running counter for cycle-accurate timing
//
// Memory-Mapped Registers (base 0xFFFF0400):
//   0x00: CTRL    [7:0]  RW  [0]=EN, [1]=AUTO_RELOAD, [2]=PWM_EN
//                            [3]=ONE_SHOT, [4]=IRQ_EN
//   0x04: PERIOD  [31:0] RW  Timer period (counts until interrupt)
//   0x08: COMPARE [31:0] RW  PWM compare value (duty cycle)
//   0x0C: COUNT   [31:0] RO  Current counter value
//   0x10: STATUS  [7:0]  RO  [0]=OVERFLOW, [1]=RUNNING
//   0x14: PRESCALE[15:0] RW  Prescaler (divides system clock before timer)
// =============================================================================

`timescale 1ns/1ps

module timer (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [2:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Timer output
    output reg         pwm_out,    // PWM signal
    output reg         irq         // Timer interrupt
);

    // -------------------------------------------------------------------------
    // Configuration registers
    // -------------------------------------------------------------------------
    reg        en;
    reg        auto_reload;
    reg        pwm_en;
    reg        one_shot;
    reg        irq_en;
    reg [31:0] period;
    reg [31:0] compare;
    reg [15:0] prescale;

    // -------------------------------------------------------------------------
    // Internal counters
    // -------------------------------------------------------------------------
    reg [31:0] count;
    reg [15:0] pre_cnt;
    reg        tick;
    reg        overflow;
    reg        running;

    // -------------------------------------------------------------------------
    // Prescaler
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n || !en) begin
            pre_cnt <= 0;
            tick    <= 1'b0;
        end else begin
            tick <= 1'b0;
            if (pre_cnt >= prescale) begin
                pre_cnt <= 0;
                tick    <= 1'b1;
            end else begin
                pre_cnt <= pre_cnt + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Main counter
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            count    <= 32'h0;
            overflow <= 1'b0;
            running  <= 1'b0;
            irq      <= 1'b0;
            pwm_out  <= 1'b0;
        end else begin
            irq      <= 1'b0;
            overflow <= 1'b0;

            if (en && tick) begin
                running <= 1'b1;

                if (count >= period) begin
                    // Timer expired
                    overflow <= 1'b1;
                    if (irq_en) irq <= 1'b1;

                    if (auto_reload && !one_shot) begin
                        count <= 32'h0;   // Auto-reload: restart
                    end else begin
                        count   <= 32'h0;
                        running <= 1'b0;
                        // One-shot or no reload: stop
                        // (will not restart until re-enabled)
                    end
                end else begin
                    count <= count + 1;
                end

                // PWM output: high when count < compare
                if (pwm_en) begin
                    pwm_out <= (count < compare);
                end
            end else if (!en) begin
                running <= 1'b0;
                count   <= 32'h0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Register write
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            en         <= 1'b0;
            auto_reload<= 1'b1;
            pwm_en     <= 1'b0;
            one_shot   <= 1'b0;
            irq_en     <= 1'b1;
            period     <= 32'h0009_C3FF;  // Default ~10ms at 100MHz / 1 prescale
            compare    <= 32'h0004_E200;  // 50% duty cycle
            prescale   <= 16'd0;
        end else if (reg_we) begin
            case (reg_addr)
                3'h0: begin
                    en         <= reg_wdata[0];
                    auto_reload<= reg_wdata[1];
                    pwm_en     <= reg_wdata[2];
                    one_shot   <= reg_wdata[3];
                    irq_en     <= reg_wdata[4];
                end
                3'h1: period   <= reg_wdata;
                3'h2: compare  <= reg_wdata;
                3'h5: prescale <= reg_wdata[15:0];
                default: ;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Register read
    // -------------------------------------------------------------------------
    always @(*) begin
        case (reg_addr)
            3'h0: reg_rdata = {27'h0, irq_en, one_shot, pwm_en, auto_reload, en};
            3'h1: reg_rdata = period;
            3'h2: reg_rdata = compare;
            3'h3: reg_rdata = count;
            3'h4: reg_rdata = {30'h0, running, overflow};
            3'h5: reg_rdata = {16'h0, prescale};
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
