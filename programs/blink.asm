# =============================================================================
# Program     : blink.asm
# Description : Configures GPIO pins 0-7 as outputs and blinks them in a loop
#               using a software delay.
# =============================================================================

.org 0x00001000        # Program Entry Point in Instruction ROM

main:
    # 1. Configure GPIO Direction (base address 0xFFFF0000)
    # DIR register offset is 0x08 -> Address is 0xFFFF0008
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7      # R1 = 0xFFFF0000
    ADDI R2, R0, 0x00FF  # R2 = 0x000000FF (pins 0-7 as output)
    STORE R1, R2, 8      # DIR = 0x000000FF

loop:
    # 2. Turn on LEDs (DATA_OUT offset is 0x00 -> Address 0xFFFF0000)
    ADDI R2, R0, 0x00FF  # R2 = 0x000000FF (Turn on pins 0-7)
    STORE R1, R2, 0      # DATA_OUT = 0xFF

    # 3. Delay
    CALL delay

    # 4. Turn off LEDs
    ADDI R2, R0, 0x0000  # R2 = 0x00000000 (Turn off all pins)
    STORE R1, R2, 0      # DATA_OUT = 0

    # 5. Delay
    CALL delay

    # Loop forever
    JMP loop

# Delay subroutine
delay:
    ADDI R3, R0, 0xFFFF
    ADDI R7, R0, 8
    LSL  R3, R3, R7      # Large delay counter
delay_loop:
    DEC  R3
    BNE  R3, R0, delay_loop
    RET
