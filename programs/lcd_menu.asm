# =============================================================================
# Program     : lcd_menu.asm
# Description : LCD Menu System. Reads Up/Down buttons from GPIO and displays
#               interactive menu pages:
#                 1. RUN PROCESS
#                 2. SETTINGS
#                 3. DBU READINGS
# =============================================================================

.org 0x00001000

main:
    # 1. Base Address for GPIO (0xFFFF0000)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7

    # Configure Direction: Bottom 8 bits as Output (LEDs), rest input
    ADDI R2, R0, 0x00FF
    STORE R1, R2, 8      # DIR = 0xFF

    # 2. Base Address for LCD Driver (0xFFFF0900)
    ADDI R2, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R2, R2, R7
    ADDI R2, R2, 0x0900  # R2 = 0xFFFF0900

    # Initialize LCD
    ADDI R3, R0, 0x38     # 8-bit mode
    STORE R2, R3, 8
    CALL delay_short

    ADDI R3, R0, 0x0C     # Display ON, cursor OFF
    STORE R2, R3, 8
    CALL delay_short

    # Active page state: R10 (0 = Run, 1 = Settings, 2 = Debug)
    ADDI R10, R0, 0
    CALL print_page_0

menu_loop:
    # Read buttons from GPIO DATA_IN (offset 4)
    # SW0 (bit 0) = UP, SW1 (bit 1) = DOWN
    LOAD R4, R1, 4
    
    # Check UP button (mask 1)
    ADDI R5, R0, 1
    AND  R6, R4, R5
    BEQ  R6, R0, handle_up

    # Check DOWN button (mask 2)
    ADDI R5, R0, 2
    AND  R6, R4, R5
    BEQ  R6, R0, handle_down

    JMP  menu_loop

handle_up:
    # If page == 0, set to 2. Else decrement.
    CMP  R10, R0
    BEQ  R10, R0, set_page_2
    DEC  R10
    JMP  update_menu

set_page_2:
    ADDI R10, R0, 2
    JMP  update_menu

handle_down:
    # If page == 2, set to 0. Else increment.
    ADDI R5, R0, 2
    CMP  R10, R5
    BEQ  R10, R5, set_page_0
    INC  R10
    JMP  update_menu

set_page_0:
    ADDI R10, R0, 0

update_menu:
    # Clear display
    ADDI R3, R0, 0x01
    STORE R2, R3, 8
    CALL delay_long

    # Draw page
    CMP  R10, R0
    BEQ  R10, R0, do_page_0
    
    ADDI R5, R0, 1
    CMP  R10, R5
    BEQ  R10, R5, do_page_1

do_page_2:
    CALL print_page_2
    JMP  debounce

do_page_0:
    CALL print_page_0
    JMP  debounce

do_page_1:
    CALL print_page_1

debounce:
    # Delay for button release debounce (~200ms)
    CALL delay_long
    JMP  menu_loop


# --- Subroutines to print string patterns ---

print_page_0:
    # "1. RUN"
    ADDI R6, R0, 49      # '1'
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 46      # '.'
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 32      # ' '
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 82      # 'R'
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 85      # 'U'
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 78      # 'N'
    STORE R2, R6, 4
    RET

print_page_1:
    # "2. SETTINGS"
    ADDI R6, R0, 50      # '2'
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 46      # '.'
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 32      # ' '
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 83      # 'S'
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 69      # 'E'
    STORE R2, R6, 4
    RET

print_page_2:
    # "3. DEBUG"
    ADDI R6, R0, 51      # '3'
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 46      # '.'
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 32      # ' '
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 68      # 'D'
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 66      # 'B'
    STORE R2, R6, 4
    CALL delay_short
    ADDI R6, R0, 71      # 'G'
    STORE R2, R6, 4
    RET

# Delay subroutines
delay_long:
    ADDI R8, R0, 0xFFFF
    ADDI R7, R0, 7
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
