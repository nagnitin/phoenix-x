# =============================================================================
# Program     : servo_control.asm
# Description : Servo Motor Position Control using PWM Channel 0.
#               Sets frequency to 50 Hz (period = 2,000,000 cycles at 100 MHz).
#               Reads Switch 0 and Switch 1 from GPIO (base 0xFFFF0000 DATA_IN)
#               and updates PWM Channel 0 Duty Cycle:
#                 - SW = 00 -> Center position (1.5 ms pulse = 150,000 cycles)
#                 - SW = 01 -> Minimum position (1.0 ms pulse = 100,000 cycles)
#                 - SW = 10 -> Maximum position (2.0 ms pulse = 200,000 cycles)
# =============================================================================

.org 0x00001000

main:
    # 1. Base Address for GPIO (0xFFFF0000)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7      # R1 = 0xFFFF0000

    # Configure GPIO Direction (DIR at offset 8)
    ADDI R2, R0, 0x0000  # Configure all pins as input
    STORE R1, R2, 8      # DIR = 0

    # 2. Base Address for PWM (0xFFFF0500)
    ADDI R3, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R3, R3, R7
    ADDI R3, R3, 0x0500  # R3 = 0xFFFF0500

    # 3. Set Period of PWM Channel 0 (offset 4)
    # Period = 2,000,000 cycles (50 Hz)
    ADDI R4, R0, 0x001E
    LSL  R4, R4, 16
    ADDI R4, R4, 0x8480  # R4 = 2,000,000
    STORE R3, R4, 4      # PWM_PERIOD_0 = 2,000,000

    # 4. Enable PWM Channel 0 (offset 0, Bit 0)
    ADDI R4, R0, 1
    STORE R3, R4, 0      # PWM_ENABLE = 1

read_switches:
    # 5. Read Switch values from GPIO DATA_IN (offset 4)
    LOAD R5, R1, 4       # Switches states in R5
    
    # Mask out only SW0 and SW1 (bits 0 and 1, mask = 3)
    ADDI R6, R0, 3
    AND  R5, R5, R6

    # 6. Compare switch inputs and select pulse width
    # Case SW = 1 (SW0 = 1, SW1 = 0) -> Min (100,000 cycles)
    ADDI R6, R0, 1
    CMP  R5, R6
    BEQ  R5, R6, set_min

    # Case SW = 2 (SW0 = 0, SW1 = 1) -> Max (200,000 cycles)
    ADDI R6, R0, 2
    CMP  R5, R6
    BEQ  R5, R6, set_max

set_center:
    # Default Case: Center (150,000 cycles)
    # 150,000 = 0x000249F0
    ADDI R8, R0, 2
    LSL  R8, R8, 16
    ADDI R8, R8, 0x49F0
    STORE R3, R8, 8      # PWM_DUTY_0 = 150,000
    JMP  wait_cycle

set_min:
    # Min position: 100,000 = 0x000186A0
    ADDI R8, R0, 1
    LSL  R8, R8, 16
    ADDI R8, R8, 0x86A0
    STORE R3, R8, 8      # PWM_DUTY_0 = 100,000
    JMP  wait_cycle

set_max:
    # Max position: 200,000 = 0x00030D40
    ADDI R8, R0, 3
    LSL  R8, R8, 16
    ADDI R8, R8, 0x0D40
    STORE R3, R8, 8      # PWM_DUTY_0 = 200,000

wait_cycle:
    # Small delay before reading switches again
    ADDI R10, R0, 0xFFFF
    ADDI R7, R0, 4
    LSL  R10, R10, R7
delay_loop:
    DEC  R10
    BNE  R10, R0, delay_loop
    JMP  read_switches
