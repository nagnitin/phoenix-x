// =============================================================================
// Module      : memory_controller.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : Memory Controller and Address Decoder — routes all CPU memory
//               accesses to the correct target based on the address space map.
// =============================================================================

`timescale 1ns/1ps

module memory_controller (
    input  wire        clk,
    input  wire        rst_n,

    // CPU interface
    input  wire [31:0] cpu_addr,        // Byte address from CPU
    input  wire        cpu_we,          // CPU write enable
    input  wire        cpu_re,          // CPU read enable
    input  wire [31:0] cpu_wdata,       // CPU write data
    input  wire        cpu_byte,        // 1 = byte access, 0 = word access
    output reg  [31:0] cpu_rdata,       // CPU read data (muxed)
    output reg         cpu_ready,       // Ready signal (always 1 here)

    // Boot ROM interface
    output wire [7:0]  boot_addr,
    input  wire [31:0] boot_rdata,

    // Instruction ROM interface (for data reads from program space)
    output wire [11:0] irom_addr,
    input  wire [31:0] irom_rdata,

    // Data RAM interface
    output wire [12:0] dram_addr,
    output wire        dram_we,
    output wire [3:0]  dram_be,
    output wire [31:0] dram_wdata,
    input  wire [31:0] dram_rdata,

    // Peripheral read data buses
    input  wire [31:0] gpio_rdata,
    input  wire [31:0] uart_rdata,
    input  wire [31:0] spi_rdata,
    input  wire [31:0] i2c_rdata,
    input  wire [31:0] timer_rdata,
    input  wire [31:0] pwm_rdata,
    input  wire [31:0] irq_ctrl_rdata,
    input  wire [31:0] wdog_rdata,
    input  wire [31:0] debug_rdata,
    input  wire [31:0] lcd_rdata,
    input  wire [31:0] oled_rdata,
    input  wire [31:0] eeprom_rdata,
    input  wire [31:0] seven_seg_rdata,
    input  wire [31:0] keypad_rdata,
    input  wire [31:0] ultrasonic_rdata,
    input  wire [31:0] temp_sensor_rdata,

    // Peripheral chip selects and write strobes
    output reg         gpio_cs,
    output reg         uart_cs,
    output reg         spi_cs,
    output reg         i2c_cs,
    output reg         timer_cs,
    output reg         pwm_cs,
    output reg         irq_ctrl_cs,
    output reg         wdog_cs,
    output reg         debug_cs,
    output reg         lcd_cs,
    output reg         oled_cs,
    output reg         eeprom_cs,
    output reg         seven_seg_cs,
    output reg         keypad_cs,
    output reg         ultrasonic_cs,
    output reg         temp_sensor_cs,
    output reg         periph_we,
    output wire [7:0]  periph_addr,    // Lower 8 bits of address within peripheral
    output wire [31:0] periph_wdata    // Write data to peripheral
);

    // -------------------------------------------------------------------------
    // Address region detection
    // -------------------------------------------------------------------------
    wire in_boot    = (cpu_addr[31:10] == 22'h0);                   // 0x000–0x3FF
    wire in_irom    = (cpu_addr[31:14] == 18'h0) &&
                      (cpu_addr[13:12] != 2'b00) &&
                      (cpu_addr >= 32'h0000_1000) &&
                      (cpu_addr <= 32'h0000_4FFF);
    wire in_dram    = (cpu_addr >= 32'h0001_0000) &&
                      (cpu_addr <= 32'h0001_7FFF);
    wire in_periph  = (cpu_addr[31:16] == 16'hFFFF);

    // Peripheral sub-region (bits 11:8 select the peripheral block of 256 bytes)
    wire [3:0] periph_sel = cpu_addr[11:8];

    // -------------------------------------------------------------------------
    // Address extractions for each memory target
    // -------------------------------------------------------------------------
    assign boot_addr   = cpu_addr[9:2];        // Word address in Boot ROM
    assign irom_addr   = cpu_addr[13:2];       // Word address in IROM
    assign dram_addr   = cpu_addr[14:2];       // Word address in DRAM
    assign periph_addr = cpu_addr[7:0];        // Byte offset within peripheral
    assign periph_wdata = cpu_wdata;

    // -------------------------------------------------------------------------
    // Byte enable generation for Data RAM
    // -------------------------------------------------------------------------
    wire [1:0] byte_offset = cpu_addr[1:0];
    assign dram_we    = cpu_we && in_dram;
    assign dram_be    = cpu_byte ? (4'h1 << byte_offset) : 4'hF;
    assign dram_wdata = cpu_byte ?
                        (cpu_wdata[7:0] << (byte_offset * 8)) :
                         cpu_wdata;

    // -------------------------------------------------------------------------
    // Peripheral chip-select decode
    // -------------------------------------------------------------------------
    always @(*) begin
        gpio_cs        = 1'b0;
        uart_cs        = 1'b0;
        spi_cs         = 1'b0;
        i2c_cs         = 1'b0;
        timer_cs       = 1'b0;
        pwm_cs         = 1'b0;
        irq_ctrl_cs    = 1'b0;
        wdog_cs        = 1'b0;
        debug_cs       = 1'b0;
        lcd_cs         = 1'b0;
        oled_cs        = 1'b0;
        eeprom_cs      = 1'b0;
        seven_seg_cs   = 1'b0;
        keypad_cs      = 1'b0;
        ultrasonic_cs  = 1'b0;
        temp_sensor_cs = 1'b0;
        periph_we      = 1'b0;

        if (in_periph) begin
            periph_we = cpu_we;
            case (periph_sel)
                4'h0: gpio_cs        = 1'b1;
                4'h1: uart_cs        = 1'b1;
                4'h2: spi_cs         = 1'b1;
                4'h3: i2c_cs         = 1'b1;
                4'h4: timer_cs       = 1'b1;
                4'h5: pwm_cs         = 1'b1;
                4'h6: irq_ctrl_cs    = 1'b1;
                4'h7: wdog_cs        = 1'b1;
                4'h8: debug_cs       = 1'b1;
                4'h9: lcd_cs         = 1'b1;
                4'hA: oled_cs        = 1'b1;
                4'hB: eeprom_cs      = 1'b1;
                4'hC: seven_seg_cs   = 1'b1;
                4'hD: keypad_cs      = 1'b1;
                4'hE: ultrasonic_cs  = 1'b1;
                4'hF: temp_sensor_cs = 1'b1;
                default: ;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Read data multiplexer
    // -------------------------------------------------------------------------
    always @(*) begin
        cpu_rdata = 32'h0;
        cpu_ready = 1'b1;

        if (in_boot)   cpu_rdata = boot_rdata;
        else if (in_irom) cpu_rdata = irom_rdata;
        else if (in_dram) begin
            // Handle byte extraction on reads
            if (cpu_byte) begin
                case (byte_offset)
                    2'b00: cpu_rdata = {24'h0, dram_rdata[ 7: 0]};
                    2'b01: cpu_rdata = {24'h0, dram_rdata[15: 8]};
                    2'b10: cpu_rdata = {24'h0, dram_rdata[23:16]};
                    2'b11: cpu_rdata = {24'h0, dram_rdata[31:24]};
                endcase
            end else begin
                cpu_rdata = dram_rdata;
            end
        end else if (in_periph) begin
            case (periph_sel)
                4'h0: cpu_rdata = gpio_rdata;
                4'h1: cpu_rdata = uart_rdata;
                4'h2: cpu_rdata = spi_rdata;
                4'h3: cpu_rdata = i2c_rdata;
                4'h4: cpu_rdata = timer_rdata;
                4'h5: cpu_rdata = pwm_rdata;
                4'h6: cpu_rdata = irq_ctrl_rdata;
                4'h7: cpu_rdata = wdog_rdata;
                4'h8: cpu_rdata = debug_rdata;
                4'h9: cpu_rdata = lcd_rdata;
                4'hA: cpu_rdata = oled_rdata;
                4'hB: cpu_rdata = eeprom_rdata;
                4'hC: cpu_rdata = seven_seg_rdata;
                4'hD: cpu_rdata = keypad_rdata;
                4'hE: cpu_rdata = ultrasonic_rdata;
                4'hF: cpu_rdata = temp_sensor_rdata;
                default: cpu_rdata = 32'hDEAD_BEEF;
            endcase
        end
    end

endmodule
