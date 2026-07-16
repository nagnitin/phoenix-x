# =============================================================================
# Program     : rgb_led.asm
# Description : RGB LED brightness and color control.
#               Uses PWM Channel 2 (Red) and PWM Channel 3 (Green) to fade
#               different color levels, creating a color-wheel shifting effect.
# =============================================================================

.org 0x00001000

main:
    # 1. Base Address for PWM (0xFFFF0500)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7
    ADDI R1, R1, 0x0500  # R1 = 0xFFFF0500

    # 2. Set Period for PWM Channel 2 and 3 (1000 cycles)
    ADDI R2, R0, 1000
    STORE R1, R2, 20     # PWM_PERIOD_2 = 1000 (offset 20 = 5'h05 * 4)
    STORE R1, R2, 28     # PWM_PERIOD_3 = 1000 (offset 28 = 5'h07 * 4)

    # 3. Enable PWM Channel 2 & 3 (offset 0, write 0xC = 12 = 0b1100)
    ADDI R2, R0, 12
    STORE R1, R2, 0      # PWM_ENABLE = 12

    # R3 (Red duty) starts at 0, R4 (Green duty) starts at 1000
    ADDI R3, R0, 0
    ADDI R4, R0, 1000

fade_loop:
    # Write Red and Green duty registers (offsets 24 and 32)
    STORE R1, R3, 24     # PWM_DUTY_2 = R3
    STORE R1, R4, 32     # PWM_DUTY_3 = R4
    CALL delay

    # Increment Red, Decrement Green
    ADDI R5, R0, 10
    ADD  R3, R3, R5
    SUB  R4, R4, R5

    # Check bounds
    ADDI R5, R0, 1000
    CMP  R3, R5
    BNE  R3, R5, fade_loop

    # Swap directions (Red down, Green up)
fade_back_loop:
    STORE R1, R3, 24
    STORE R1, R4, 32
    CALL delay

    ADDI R5, R0, 10
    SUB  R3, R3, R5
    ADD  R4, R4, R5

    BNE  R3, R0, fade_back_loop

    JMP  fade_loop

# Soft delay subroutine
delay:
    ADDI R6, R0, 0xFFFF
    ADDI R7, R0, 2
    LSL  R6, R6, R7
delay_loop:
    DEC  R6
    BNE  R6, R0, delay_loop
    RET
