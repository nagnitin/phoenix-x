# =============================================================================
# File        : timing.xdc
# Project     : 32-Bit Custom FPGA Microcontroller
# Description : Xilinx Timing Constraints File (XDC) for Basys 3 board
# =============================================================================

# Define main clock constraint (100 MHz clock from physical oscillator)
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# Setup input and output delay constraints for general analysis (estimation)
set_input_delay -clock sys_clk_pin -max 3.000 [get_ports {gp_in[*] rx miso sda_in scl_in keypad_rows[*]}]
set_input_delay -clock sys_clk_pin -min 1.000 [get_ports {gp_in[*] rx miso sda_in scl_in keypad_rows[*]}]

set_output_delay -clock sys_clk_pin -max 3.000 [get_ports {gp_out[*] tx mosi sclk cs_n sda_oe scl_oe segments[*] anodes[*]}]
set_output_delay -clock sys_clk_pin -min 1.000 [get_ports {gp_out[*] tx mosi sclk cs_n sda_oe scl_oe segments[*] anodes[*]}]
