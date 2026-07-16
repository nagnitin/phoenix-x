# =============================================================================
# Program     : traffic_light.asm
# Description : Implements a simple traffic light controller.
#               Sequences three LEDs (Red = Pin 0, Yellow = Pin 1, Green = Pin 2)
#               on the GPIO interface with custom delays.
# =============================================================================

.org 0x00001000

main:
    # 1. Configure GPIO Direction (DIR at 0xFFFF0008)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7      # R1 = 0xFFFF0000
    ADDI R2, R0, 0x0007  # Pins 0, 1, 2 as outputs
    STORE R1, R2, 8      # DIR = 7

sequence_loop:
    # State 1: Red Light (Pin 0 high = 0x01)
    ADDI R2, R0, 0x0001
    STORE R1, R2, 0      # DATA_OUT = 1
    CALL delay_long

    # State 2: Yellow Light (Pin 1 high = 0x02)
    ADDI R2, R0, 0x0002
    STORE R1, R2, 0      # DATA_OUT = 2
    CALL delay_short

    # State 3: Green Light (Pin 2 high = 0x04)
    ADDI R2, R0, 0x0004
    STORE R1, R2, 0      # DATA_OUT = 4
    CALL delay_long

    # Repeat forever
    JMP sequence_loop

# Subroutines
delay_long:
    ADDI R3, R0, 0xFFFF
    ADDI R7, R0, 8
    LSL  R3, R3, R7
delay_l_loop:
    DEC  R3
    BNE  R3, R0, delay_l_loop
    RET

delay_short:
    ADDI R3, R0, 0xFFFF
    ADDI R7, R0, 6
    LSL  R3, R3, R7
delay_s_loop:
    DEC  R3
    BNE  R3, R0, delay_s_loop
    RET
