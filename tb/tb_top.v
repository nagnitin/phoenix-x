// =============================================================================
// Testbench   : tb_top.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : System-Level Testbench for the entire microcontroller.
//               Instantiates the top module, runs the compiled hex file,
//               dumps waves, and monitors execution.
// =============================================================================

`timescale 1ns/1ps

module tb_top;

    // Clock and reset
    reg         clk;
    reg         rst_n;

    // UART pins
    wire        tx;
    reg         rx;

    // SPI pins
    wire        sclk;
    wire        mosi;
    reg         miso;
    wire        cs_n;

    // I2C pins
    wire        scl_oe;
    wire        sda_oe;
    wire        scl_in;
    wire        sda_in;

    // GPIO pins
    reg  [31:0] gp_in;
    wire [31:0] gp_out;
    wire [31:0] gp_oe;

    // Timer/PWM
    wire        timer_pwm;
    wire [3:0]  pwm_out;

    // Seven-Segment
    wire [3:0]  anodes;
    wire [7:0]  segments;

    // Keypad Matrix
    wire [3:0]  keypad_cols;
    reg  [3:0]  keypad_rows;

    // LCD character display
    wire        lcd_rs;
    wire        lcd_rw;
    wire        lcd_e;
    wire [7:0]  lcd_db;

    // OLED display I2C bus
    wire        oled_scl_oe;
    wire        oled_sda_oe;
    wire        oled_scl_in;
    wire        oled_sda_in;

    // EEPROM I2C bus
    wire        ee_scl_oe;
    wire        ee_sda_oe;
    wire        ee_scl_in;
    wire        ee_sda_in;

    // Status
    wire        system_reset_out;

    // Pullups for I2C busses (simulating open-drain lines)
    assign scl_in = scl_oe ? 1'b0 : 1'b1;
    assign sda_in = sda_oe ? 1'b0 : 1'b1;

    assign oled_scl_in = oled_scl_oe ? 1'b0 : 1'b1;
    assign oled_sda_in = oled_sda_oe ? 1'b0 : 1'b1;

    assign ee_scl_in = ee_scl_oe ? 1'b0 : 1'b1;
    assign ee_sda_in = ee_sda_oe ? 1'b0 : 1'b1;

    // Instantiate Top-Level System Under Test
    top #(
        .MEM_FILE ("c:/Users/nitin/OneDrive/Desktop/32_Bit/prog_temp.hex")
    ) uut (
        .clk              (clk),
        .rst_n            (rst_n),
        .tx               (tx),
        .rx               (rx),
        .sclk             (sclk),
        .mosi             (mosi),
        .miso             (miso),
        .cs_n             (cs_n),
        .scl_oe           (scl_oe),
        .sda_oe           (sda_oe),
        .scl_in           (scl_in),
        .sda_in           (sda_in),
        .gp_in            (gp_in),
        .gp_out           (gp_out),
        .gp_oe            (gp_oe),
        .timer_pwm        (timer_pwm),
        .pwm_out          (pwm_out),
        .anodes           (anodes),
        .segments         (segments),
        .keypad_cols      (keypad_cols),
        .keypad_rows      (keypad_rows),
        .lcd_rs           (lcd_rs),
        .lcd_rw           (lcd_rw),
        .lcd_e            (lcd_e),
        .lcd_db           (lcd_db),
        .oled_scl_oe      (oled_scl_oe),
        .oled_sda_oe      (oled_sda_oe),
        .oled_scl_in      (oled_scl_in),
        .oled_sda_in      (oled_sda_in),
        .ee_scl_oe        (ee_scl_oe),
        .ee_sda_oe        (ee_sda_oe),
        .ee_scl_in        (ee_scl_in),
        .ee_sda_in        (ee_sda_in),
        .system_reset_out (system_reset_out)
    );

    // Clock Generator (100 MHz -> 10ns period)
    always #5 clk = ~clk;

    // Simulation sequence
    initial begin
        // Setup wave dumps
        $dumpfile("sim/waves.vcd");
        $dumpvars(0, tb_top);

        // Initialize signals
        clk         = 1'b0;
        rst_n       = 1'b0;
        rx          = 1'b1;
        miso        = 1'b0;
        gp_in       = 32'h0;
        keypad_rows = 4'hF; // Active low (default released)

        $display("[TB] Starting Microcontroller Simulation...");
        #40;
        rst_n = 1'b1; // Release reset
        $display("[TB] Reset released. CPU executing boot sequence...");

        // Run simulation for a maximum number of cycles
        // Halt will terminate simulation if executed in test code
        #100000;
        
        $display("[TB] Simulation timed out. Displaying final registers...");
        // Print general registers for debugging
        $display("R0=%X R1=%X R2=%X R3=%X", uut.cpu_core_inst.reg_file_inst.regs[0], uut.cpu_core_inst.reg_file_inst.regs[1], uut.cpu_core_inst.reg_file_inst.regs[2], uut.cpu_core_inst.reg_file_inst.regs[3]);
        $display("R4=%X R5=%X R10=%X R11=%X R12=%X", uut.cpu_core_inst.reg_file_inst.regs[4], uut.cpu_core_inst.reg_file_inst.regs[5], uut.cpu_core_inst.reg_file_inst.regs[10], uut.cpu_core_inst.reg_file_inst.regs[11], uut.cpu_core_inst.reg_file_inst.regs[12]);
        $display("R29(SP)=%X R30(LR)=%X PC=%X SR=%X", uut.cpu_core_inst.reg_file_inst.regs[29], uut.cpu_core_inst.reg_file_inst.regs[30], uut.cpu_core_inst.pc_out, uut.cpu_core_inst.status_out);
        $finish;
    end

    // Monitor halts or success states
    always @(posedge clk) begin
        if (uut.cpu_core_inst.ex_halt) begin
            $display("[TB] HALT instruction executed at PC=0x%08X.", uut.cpu_core_inst.pc_out);
            $display("[TB] Registers dump:");
            $display("R0=%X R1=%X R2=%X R3=%X", uut.cpu_core_inst.reg_file_inst.regs[0], uut.cpu_core_inst.reg_file_inst.regs[1], uut.cpu_core_inst.reg_file_inst.regs[2], uut.cpu_core_inst.reg_file_inst.regs[3]);
            $display("R4=%X R5=%X R10=%X R11=%X R12=%X", uut.cpu_core_inst.reg_file_inst.regs[4], uut.cpu_core_inst.reg_file_inst.regs[5], uut.cpu_core_inst.reg_file_inst.regs[10], uut.cpu_core_inst.reg_file_inst.regs[11], uut.cpu_core_inst.reg_file_inst.regs[12]);
            $display("R29(SP)=%X R30(LR)=%X PC=%X SR=%X GPIO_OUT=%X", uut.cpu_core_inst.reg_file_inst.regs[29], uut.cpu_core_inst.reg_file_inst.regs[30], uut.cpu_core_inst.pc_out, uut.cpu_core_inst.status_out, gp_out);
            $finish;
        end
    end

endmodule
