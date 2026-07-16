# =============================================================================
# Program     : knight_rider.asm
# Description : Shifts a single LED light back and forth across pins 0-7 (LED bar)
#               creating the Knight Rider scanning effect.
# =============================================================================

.org 0x00001000        # Program Entry Point

main:
    # 1. Configure GPIO Direction (DIR at 0xFFFF0008)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7      # R1 = 0xFFFF0000
    ADDI R2, R0, 0x00FF  # R2 = 0x000000FF (pins 0-7 as output)
    STORE R1, R2, 8      # DIR = 0x000000FF

init_pattern:
    ADDI R2, R0, 1       # R2 = 1 (start at bit 0 / LED 0)

shift_left:
    STORE R1, R2, 0      # DATA_OUT = R2
    CALL delay
    
    ADDI R8, R0, 1       # Shift amount = 1
    LSL  R2, R2, R8      # Shift left by R8 (1)

    # Check if we reached pin 7 (value 128)
    ADDI R3, R0, 128
    BNE  R2, R3, shift_left

shift_right:
    STORE R1, R2, 0      # DATA_OUT = R2
    CALL delay

    ADDI R8, R0, 1
    LSR  R2, R2, R8      # Shift right by R8 (1)

    # Check if we reached pin 0 (value 1)
    ADDI R3, R0, 1
    BNE  R2, R3, shift_right

    # Repeat scan cycle
    JMP shift_left

# Delay subroutine
delay:
    ADDI R4, R0, 0xFFFF
    ADDI R8, R0, 7
    LSL  R4, R4, R8      # delay counter
delay_loop:
    DEC  R4
    BNE  R4, R0, delay_loop
    RET
