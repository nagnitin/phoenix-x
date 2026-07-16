# =============================================================================
# Program     : temp_display.asm
# Description : Reads temperature from the LM75 I2C sensor, converts the Celsius
#               value to decimal digits, and prints "T = XX C" on the 16x2 LCD.
# =============================================================================

.org 0x00001000

main:
    # 1. Base Address for LCD Driver (0xFFFF0900)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7
    ADDI R1, R1, 0x0900  # R1 = 0xFFFF0900

    # 2. Base Address for Temp Sensor (0xFFFF0950)
    ADDI R2, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R2, R2, R7
    ADDI R2, R2, 0x0950  # R2 = 0xFFFF0950

    # Initialize LCD: Function set, Clear Display, Display ON
    # Write Command (offset 8)
    ADDI R3, R0, 0x38     # 8-bit, 2-line mode
    STORE R1, R3, 8
    CALL delay_short

    ADDI R3, R0, 0x0E     # Display ON, cursor ON
    STORE R1, R3, 8
    CALL delay_short

    ADDI R3, R0, 0x01     # Clear display
    STORE R1, R3, 8
    CALL delay_long

read_temp_loop:
    # 3. Trigger measurement (Write 1 to TEMP_CTRL offset 0)
    ADDI R3, R0, 1
    STORE R2, R3, 0

wait_temp_busy:
    # 4. Wait for busy flag to clear (Bit 7 of TEMP_CTRL offset 0)
    LOAD R3, R2, 0
    ADDI R4, R0, 128
    AND  R3, R3, R4
    BNE  R3, R0, wait_temp_busy

    # 5. Read Temperature Value (TEMP_VAL offset 4)
    LOAD R5, R2, 4       # Celsius value is in R5 (e.g. 27)

    # 6. Reset LCD Cursor to Home (0x02)
    ADDI R3, R0, 0x02
    STORE R1, R3, 8
    CALL delay_short

    # 7. Print "T = "
    ADDI R6, R0, 84      # 'T'
    STORE R1, R6, 4      # Write LCD_DATA (offset 4)
    CALL delay_short

    ADDI R6, R0, 32      # ' '
    STORE R1, R6, 4
    CALL delay_short

    ADDI R6, R0, 61      # '='
    STORE R1, R6, 4
    CALL delay_short

    ADDI R6, R0, 32      # ' '
    STORE R1, R6, 4
    CALL delay_short

    # 8. Decode and Print Digits (R5 / 10 and R5 % 10)
    # R10 = tens, R11 = ones
    ADDI R12, R0, 10
    DIV  R10, R5, R12    # R10 = R5 / 10 (tens)
    MUL  R3, R10, R12
    SUB  R11, R5, R3     # R11 = R5 - (tens * 10) (ones)

    # Convert to ASCII and Print Tens
    ADDI R6, R10, 48     # R6 = tens + '0'
    STORE R1, R6, 4
    CALL delay_short

    # Convert to ASCII and Print Ones
    ADDI R6, R11, 48     # R6 = ones + '0'
    STORE R1, R6, 4
    CALL delay_short

    # Print " C"
    ADDI R6, R0, 32      # ' '
    STORE R1, R6, 4
    CALL delay_short

    ADDI R6, R0, 67      # 'C'
    STORE R1, R6, 4
    CALL delay_short

    # Delay ~1s before next query
    CALL delay_long
    JMP  read_temp_loop

# Subroutines
delay_long:
    ADDI R8, R0, 0xFFFF
    ADDI R7, R0, 8
    LSL  R8, R8, R7
d_l_loop:
    DEC  R8
    BNE  R8, R0, d_l_loop
    RET

delay_short:
    ADDI R8, R0, 0x0FFF
d_s_loop:
    DEC  R8
    BNE  R8, R0, d_s_loop
    RET
