# =============================================================================
# Program     : dc_motor_pwm.asm
# Description : DC Motor Speed Control using PWM Channel 1.
#               Sets a fixed frequency of 20 kHz (period = 5000 cycles) and
#               gradually ramps the duty cycle up from 0% to 100% and back down
#               to control motor acceleration and deceleration.
# =============================================================================

.org 0x00001000

main:
    # 1. Base Address for PWM (0xFFFF0500)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7
    ADDI R1, R1, 0x0500  # R1 = 0xFFFF0500

    # 2. Set Period of PWM Channel 1 (offset 0x0C = 12)
    # Period = 5000 cycles (20 kHz at 100 MHz)
    ADDI R2, R0, 5000
    STORE R1, R2, 12     # PWM_PERIOD_1 = 5000

    # 3. Enable PWM Channel 1 (offset 0x00, Bit 1)
    ADDI R2, R0, 0x0002  # Enable bit 1
    STORE R1, R2, 0      # PWM_ENABLE = 2

    # R3 is active duty cycle (starts at 0)
    ADDI R3, R0, 0

ramp_up:
    # Write duty cycle to channel 1 duty register (offset 0x10 = 16)
    STORE R1, R3, 16     # PWM_DUTY_1 = R3
    CALL delay

    # Increment duty cycle by 100
    ADDI R4, R0, 100
    ADD  R3, R3, R4
    
    # Check if we reached 5000 (100% duty)
    ADDI R4, R0, 5000
    CMP  R3, R4
    BNE  R3, R4, ramp_up

ramp_down:
    # Write duty cycle
    STORE R1, R3, 16
    CALL delay

    # Decrement duty cycle by 100
    ADDI R4, R0, 100
    SUB  R3, R3, R4

    # Check if we reached 0
    BNE  R3, R0, ramp_down

    # Loop forever
    JMP ramp_up

# Small delay to visual ramp speed changes
delay:
    ADDI R5, R0, 0xFFFF
    ADDI R7, R0, 3
    LSL  R5, R5, R7
delay_loop:
    DEC  R5
    BNE  R5, R0, delay_loop
    RET
