// =============================================================================
# Program     : ultrasonic_sensor.asm
# Description : Measures distance using the HC-SR04 Ultrasonic Sensor driver
#               and displays the distance in binary on the 8 onboard LEDs.
# =============================================================================

.org 0x00001000

main:
    # 1. Base Address for GPIO (0xFFFF0000)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7
    
    # Configure GPIO Direction (DIR at offset 8)
    ADDI R2, R0, 0x00FF  # Pins 0-7 as output
    STORE R1, R2, 8      # DIR = 255

    # 2. Base Address for Ultrasonic Driver (0xFFFF0E00)
    ADDI R3, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R3, R3, R7
    ADDI R3, R3, 0x0E00  # R3 = 0xFFFF0E00

measure_loop:
    # 3. Trigger measurement (Write 1 to US_CTRL offset 0)
    ADDI R4, R0, 1
    STORE R3, R4, 0

wait_busy:
    # 4. Wait for busy flag to clear (Bit 7 of US_CTRL offset 0)
    LOAD R4, R3, 0
    ADDI R5, R0, 128     # Mask for bit 7 (value 128)
    AND  R4, R4, R5
    BNE  R4, R0, wait_busy # Keep polling if busy

    # 5. Read distance value in cm (US_DIST offset 4)
    LOAD R4, R3, 4       # Distance value is in R4

    # 6. Display distance on GPIO LEDs (offset 0)
    STORE R1, R4, 0

    # Delay before next measure (~100 ms)
    CALL delay_long

    JMP  measure_loop

# Delay subroutine
delay_long:
    ADDI R6, R0, 0xFFFF
    ADDI R7, R0, 6
    LSL  R6, R6, R7
delay_loop:
    DEC  R6
    BNE  R6, R0, delay_loop
    RET
