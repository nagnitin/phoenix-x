// =============================================================================
// Module      : top.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Top-Level Module. Connects the CPU core, memory controller,
//               Boot ROM, Instruction ROM, Data RAM, Priority Interrupt
//               Controller, and all 16 peripheral & external driver blocks.
// =============================================================================

`timescale 1ns/1ps

module top #(
    parameter MEM_FILE = "prog.hex"
) (
    input  wire        clk,
    input  wire        rst_n,

    // Physical Peripherals Pins
    // UART
    output wire        tx,
    input  wire        rx,

    // SPI
    output wire        sclk,
    output wire        mosi,
    input  wire        miso,
    output wire        cs_n,

    // I2C Master
    output wire        scl_oe,
    output wire        sda_oe,
    input  wire        scl_in,
    input  wire        sda_in,

    // GPIO
    input  wire [31:0] gp_in,
    output wire [31:0] gp_out,
    output wire [31:0] gp_oe,

    // Timer/PWM Outputs
    output wire        timer_pwm,
    output wire [3:0]  pwm_out,

    // Seven-Segment
    output wire [3:0]  anodes,
    output wire [7:0]  segments,

    // Keypad Matrix
    output wire [3:0]  keypad_cols,
    input  wire [3:0]  keypad_rows,

    // LCD character display (HD44780 8-bit mode)
    output wire        lcd_rs,
    output wire        lcd_rw,
    output wire        lcd_e,
    output wire [7:0]  lcd_db,

    // OLED display I2C bus
    output wire        oled_scl_oe,
    output wire        oled_sda_oe,
    input  wire        oled_scl_in,
    input  wire        oled_sda_in,

    // EEPROM I2C bus
    output wire        ee_scl_oe,
    output wire        ee_sda_oe,
    input  wire        ee_scl_in,
    input  wire        ee_sda_in,

    // Ultrasonic Sensor
    output wire        ultrasonic_trig,
    input  wire        ultrasonic_echo,

    // Temperature Sensor I2C bus
    output wire        temp_scl_oe,
    output wire        temp_sda_oe,
    input  wire        temp_scl_in,
    input  wire        temp_sda_in,

    // System Status
    output wire        system_reset_out
);

    // -------------------------------------------------------------------------
    // Interconnect signals
    // -------------------------------------------------------------------------
    
    // CPU Core <-> Memory Controller
    wire [31:0] cpu_addr;
    wire [31:0] cpu_wdata;
    wire [31:0] cpu_rdata;
    wire        cpu_we;
    wire        cpu_re;
    wire        cpu_byte;
    wire        cpu_ready;

    // CPU Core Instruction Fetch Path (Harvard Direct)
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

    // Boot ROM <-> Memory Controller
    wire [7:0]  boot_addr;
    wire [31:0] boot_rdata;
    wire [7:0]  boot_rom_addr;
    assign boot_rom_addr = (imem_addr < 32'h0000_1000) ? imem_addr[9:2] : boot_addr;

    // Instruction ROM <-> Memory Controller
    wire [11:0] irom_addr;
    wire [31:0] irom_rdata;
    assign irom_addr = (imem_addr - 32'h0000_1000) >> 2;
    assign imem_rdata = (imem_addr < 32'h0000_1000) ? boot_rdata : irom_rdata;

    // Data RAM <-> Memory Controller
    wire [12:0] dram_addr;
    wire        dram_we;
    wire [3:0]  dram_be;
    wire [31:0] dram_wdata;
    wire [31:0] dram_rdata;

    // Peripheral buses from Memory Controller
    wire        gpio_cs;
    wire        uart_cs;
    wire        spi_cs;
    wire        i2c_cs;
    wire        timer_cs;
    wire        pwm_cs;
    wire        irq_ctrl_cs;
    wire        wdog_cs;
    wire        debug_cs;
    wire        lcd_cs;
    wire        oled_cs;
    wire        eeprom_cs;
    wire        seven_seg_cs;
    wire        keypad_cs;
    wire        ultrasonic_cs;
    wire        temp_sensor_cs;
    wire        periph_we;
    wire [7:0]  periph_addr;
    wire [31:0] periph_wdata;

    // Peripheral read buses
    wire [31:0] gpio_rdata;
    wire [31:0] uart_rdata;
    wire [31:0] spi_rdata;
    wire [31:0] i2c_rdata;
    wire [31:0] timer_rdata;
    wire [31:0] pwm_rdata;
    wire [31:0] irq_ctrl_rdata;
    wire [31:0] wdog_rdata;
    wire [31:0] wdt_rdata;
    wire [31:0] crc_rdata;
    assign wdog_rdata = (periph_addr[7:6] == 2'b01) ? crc_rdata : wdt_rdata;
    wire [31:0] debug_rdata;
    wire [31:0] lcd_rdata;
    wire [31:0] oled_rdata;
    wire [31:0] eeprom_rdata;
    wire [31:0] seven_seg_rdata;
    wire [31:0] keypad_rdata;
    wire [31:0] ultrasonic_rdata;
    wire [31:0] temp_sensor_rdata;

    // Interrupt requests to PIC
    wire [7:0]  irq_lines;
    wire        cpu_irq_req;
    wire [31:0] cpu_irq_vector;
    wire        cpu_irq_ack;
    wire        cpu_in_isr;
    wire        cpu_irq_enable;

    // Watchdog
    wire        wdt_irq;
    wire        wdt_reset;
    assign system_reset_out = wdt_reset;

    // Debug <-> CPU hooks
    wire [31:0] dbu_pc;
    wire [31:0] dbu_instr;
    wire        dbu_valid;
    wire [4:0]  dbu_reg_sel;
    wire [31:0] dbu_reg_val;
    wire        dbu_halt;

    // Individual interrupts
    wire        timer_irq;
    wire        uart_irq_rx;
    wire        uart_irq_tx;
    wire        spi_irq;
    wire        i2c_irq;
    wire        gpio_irq;
    wire        keypad_irq;
    wire        crc_busy;

    // Map interrupt request lines to priority slots (0=NMI, 7=low)
    assign irq_lines[0] = wdt_irq;       // Watchdog pre-warning (NMI)
    assign irq_lines[1] = timer_irq;     // Timer interrupt
    assign irq_lines[2] = uart_irq_rx;   // UART RX
    assign irq_lines[3] = uart_irq_tx;   // UART TX
    assign irq_lines[4] = spi_irq;       // SPI Master
    assign irq_lines[5] = i2c_irq;       // I2C Master
    assign irq_lines[6] = gpio_irq;      // GPIO Input Change
    assign irq_lines[7] = keypad_irq;    // Keypad press detected

    // -------------------------------------------------------------------------
    // Sub-Module Instantiations
    // -------------------------------------------------------------------------

    // 1. CPU Core
    cpu_core cpu_core_inst (
        .clk            (clk),
        .rst_n          (rst_n & ~wdt_reset),
        .imem_addr      (imem_addr),
        .imem_rdata     (imem_rdata),
        .dmem_addr      (cpu_addr),
        .dmem_wdata     (cpu_wdata),
        .dmem_we        (cpu_we),
        .dmem_re        (cpu_re),
        .dmem_byte      (cpu_byte),
        .dmem_rdata     (cpu_rdata),
        .irq_req        (cpu_irq_req),
        .irq_vector     (cpu_irq_vector),
        .irq_ack        (cpu_irq_ack),
        .in_isr         (cpu_in_isr),
        .dbu_pc         (dbu_pc),
        .dbu_instr      (dbu_instr),
        .dbu_valid      (dbu_valid),
        .dbu_reg_sel    (dbu_reg_sel),
        .dbu_reg_val    (dbu_reg_val),
        .dbu_halt_in    (dbu_halt)
    );

    // 2. Address Decoder / Memory Controller
    memory_controller mem_ctrl_inst (
        .clk             (clk),
        .rst_n           (rst_n & ~wdt_reset),
        .cpu_addr        (cpu_addr),
        .cpu_we          (cpu_we),
        .cpu_re          (cpu_re),
        .cpu_wdata       (cpu_wdata),
        .cpu_byte        (cpu_byte),
        .cpu_rdata       (cpu_rdata),
        .cpu_ready       (cpu_ready),
        .boot_addr       (boot_addr),
        .boot_rdata      (boot_rdata),
        .irom_addr       (),
        .irom_rdata      (irom_rdata),
        .dram_addr       (dram_addr),
        .dram_we         (dram_we),
        .dram_be         (dram_be),
        .dram_wdata      (dram_wdata),
        .dram_rdata      (dram_rdata),
        .gpio_rdata      (gpio_rdata),
        .uart_rdata      (uart_rdata),
        .spi_rdata       (spi_rdata),
        .i2c_rdata       (i2c_rdata),
        .timer_rdata     (timer_rdata),
        .pwm_rdata       (pwm_rdata),
        .irq_ctrl_rdata  (irq_ctrl_rdata),
        .wdog_rdata      (wdog_rdata),
        .debug_rdata     (debug_rdata),
        .lcd_rdata       (lcd_rdata),
        .oled_rdata      (oled_rdata),
        .eeprom_rdata    (eeprom_rdata),
        .seven_seg_rdata (seven_seg_rdata),
        .keypad_rdata    (keypad_rdata),
        .ultrasonic_rdata(ultrasonic_rdata),
        .temp_sensor_rdata(temp_sensor_rdata),
        .gpio_cs         (gpio_cs),
        .uart_cs         (uart_cs),
        .spi_cs          (spi_cs),
        .i2c_cs          (i2c_cs),
        .timer_cs        (timer_cs),
        .pwm_cs          (pwm_cs),
        .irq_ctrl_cs     (irq_ctrl_cs),
        .wdog_cs         (wdog_cs),
        .debug_cs        (debug_cs),
        .lcd_cs          (lcd_cs),
        .oled_cs         (oled_cs),
        .eeprom_cs       (eeprom_cs),
        .seven_seg_cs    (seven_seg_cs),
        .keypad_cs       (keypad_cs),
        .ultrasonic_cs   (ultrasonic_cs),
        .temp_sensor_cs  (temp_sensor_cs),
        .periph_we       (periph_we),
        .periph_addr     (periph_addr),
        .periph_wdata    (periph_wdata)
    );

    // 3. Boot ROM (1 KB)
    boot_rom boot_rom_inst (
        .clk      (clk),
        .addr     (boot_rom_addr),
        .data_out (boot_rdata)
    );

    // 4. Instruction ROM (16 KB)
    instruction_rom #(
        .ADDR_WIDTH (12),
        .MEM_FILE   (MEM_FILE)
    ) irom_inst (
        .clk      (clk),
        .addr     (irom_addr),
        .data_out (irom_rdata)
    );

    // 5. Data RAM (32 KB)
    data_ram #(
        .ADDR_WIDTH (13)
    ) dram_inst (
        .clk   (clk),
        .we    (dram_we),
        .be    (dram_be),
        .addr  (dram_addr),
        .wdata (dram_wdata),
        .rdata (dram_rdata)
    );

    // 6. Interrupt Controller
    interrupt_controller pic_inst (
        .clk             (clk),
        .rst_n           (rst_n & ~wdt_reset),
        .irq_lines       (irq_lines),
        .irq_enable_flag (1'b1), // Active high enable
        .in_isr          (cpu_in_isr),
        .reg_addr        (periph_addr[5:2]),
        .reg_we          (periph_we & irq_ctrl_cs),
        .reg_wdata       (periph_wdata),
        .reg_rdata       (irq_ctrl_rdata),
        .irq_out         (cpu_irq_req),
        .irq_num         (),
        .irq_vector      (cpu_irq_vector)
    );

    // 7. GPIO
    gpio gpio_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .pin_in    (gp_in),
        .pin_out   (gp_out),
        .pin_oe    (gp_oe),
        .reg_addr  (periph_addr[4:2]),
        .reg_we    (periph_we & gpio_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (gpio_rdata),
        .irq       (gpio_irq)
    );

    // 8. UART
    uart #(
        .BAUD_DIV (868)
    ) uart_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .tx        (tx),
        .rx        (rx),
        .reg_addr  (periph_addr[3:2]),
        .reg_we    (periph_we & uart_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (uart_rdata),
        .irq_tx    (uart_irq_tx),
        .irq_rx    (uart_irq_rx)
    );

    // 9. SPI Master
    spi_master spi_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .sclk      (sclk),
        .mosi      (mosi),
        .miso      (miso),
        .cs_n      (cs_n),
        .reg_addr  (periph_addr[4:2]),
        .reg_we    (periph_we & spi_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (spi_rdata),
        .irq       (spi_irq)
    );

    // 10. I2C Master
    i2c_master i2c_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .scl_oe    (scl_oe),
        .sda_oe    (sda_oe),
        .scl_in    (scl_in),
        .sda_in    (sda_in),
        .reg_addr  (periph_addr[4:2]),
        .reg_we    (periph_we & i2c_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (i2c_rdata),
        .irq       (i2c_irq)
    );

    // 11. Timer
    timer timer_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .reg_addr  (periph_addr[4:2]),
        .reg_we    (periph_we & timer_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (timer_rdata),
        .pwm_out   (timer_pwm),
        .irq       (timer_irq)
    );

    // 12. PWM Controller
    pwm pwm_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .reg_addr  (periph_addr[6:2]),
        .reg_we    (periph_we & pwm_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (pwm_rdata),
        .pwm_out   (pwm_out)
    );

    // 13. Watchdog Timer
    watchdog_timer wdt_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .reg_addr      (periph_addr[3:2]),
        .reg_we        (periph_we & wdog_cs),
        .reg_wdata     (periph_wdata),
        .reg_rdata     (wdt_rdata),
        .wdt_irq       (wdt_irq),
        .wdt_reset_out (wdt_reset)
    );

    // 14. CRC Engine
    crc_engine crc_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .reg_addr  (periph_addr[3:2]),
        .reg_we    (periph_we & (periph_addr[7:6] == 2'b01) & wdog_cs), // mapped in shared space
        .reg_wdata (periph_wdata),
        .reg_rdata (crc_rdata),
        .busy      (crc_busy)
    );

    // 15. Debug Unit
    debug_unit dbu_inst (
        .clk          (clk),
        .rst_n        (rst_n & ~wdt_reset),
        .reg_addr     (periph_addr[5:2]),
        .reg_we       (periph_we & debug_cs),
        .reg_wdata    (periph_wdata),
        .reg_rdata    (debug_rdata),
        .wb_pc        (dbu_pc),
        .wb_instr     (dbu_instr),
        .wb_valid     (dbu_valid),
        .reg_file_val (dbu_reg_val),
        .reg_file_sel (dbu_reg_sel),
        .dbu_halt     (dbu_halt)
    );

    // 16. LCD Driver (16x2)
    lcd_driver lcd_drv_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .reg_addr  (periph_addr[3:2]),
        .reg_we    (periph_we & lcd_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (lcd_rdata),
        .lcd_rs    (lcd_rs),
        .lcd_rw    (lcd_rw),
        .lcd_e     (lcd_e),
        .lcd_db    (lcd_db)
    );

    // 17. OLED Driver (SSD1306)
    oled_driver oled_drv_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .reg_addr  (periph_addr[3:2]),
        .reg_we    (periph_we & oled_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (oled_rdata),
        .scl_oe    (oled_scl_oe),
        .sda_oe    (oled_sda_oe),
        .scl_in    (oled_scl_in),
        .sda_in    (oled_sda_in)
    );

    // 18. EEPROM Driver (AT24C32)
    eeprom_driver ee_drv_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .reg_addr  (periph_addr[3:2]),
        .reg_we    (periph_we & eeprom_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (eeprom_rdata),
        .scl_oe    (ee_scl_oe),
        .sda_oe    (ee_sda_oe),
        .scl_in    (ee_scl_in),
        .sda_in    (ee_sda_in)
    );

    // 19. Seven-Segment Multiplexer Driver
    seven_seg_driver seg_drv_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .reg_addr  (periph_addr[3:2]),
        .reg_we    (periph_we & seven_seg_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (seven_seg_rdata),
        .anodes    (anodes),
        .segments  (segments)
    );

    // 20. Keypad Scanner Driver (4x4 Matrix)
    keypad_driver keypad_drv_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .reg_addr  (periph_addr[3:2]),
        .reg_we    (periph_we & keypad_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (keypad_rdata),
        .cols      (keypad_cols),
        .rows      (keypad_rows),
        .irq       (keypad_irq)
    );

    // 21. Ultrasonic Sensor Driver
    ultrasonic_driver us_drv_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .reg_addr  (periph_addr[3:2]),
        .reg_we    (periph_we & ultrasonic_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (ultrasonic_rdata),
        .trigger   (ultrasonic_trig),
        .echo      (ultrasonic_echo)
    );

    // 22. Temperature Sensor Driver
    temp_sensor_driver temp_drv_inst (
        .clk       (clk),
        .rst_n     (rst_n & ~wdt_reset),
        .reg_addr  (periph_addr[3:2]),
        .reg_we    (periph_we & temp_sensor_cs),
        .reg_wdata (periph_wdata),
        .reg_rdata (temp_sensor_rdata),
        .scl_oe    (temp_scl_oe),
        .sda_oe    (temp_sda_oe),
        .scl_in    (temp_scl_in),
        .sda_in    (temp_sda_in)
    );

endmodule
