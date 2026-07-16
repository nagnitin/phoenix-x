# =============================================================================
# Program     : stack_demo.asm
# Description : Demonstrates functional hardware stack PUSH and POP operations.
#               Loads arbitrary registers, pushes them to RAM, pops them in
#               reverse order, and blinks pins 0-7 if the validation succeeds.
# =============================================================================

.org 0x00001000

main:
    # 1. Initialize data values
    ADDI R10, R0, 0x1111
    ADDI R11, R0, 0x2222
    ADDI R12, R0, 0x3333

    # 2. Push onto stack (SP auto-decrements by 4 each time)
    PUSH R10
    PUSH R11
    PUSH R12

    # 3. Clear source registers to verify pops
    ADDI R10, R0, 0
    ADDI R11, R0, 0
    ADDI R12, R0, 0

    # 4. Pop from stack in reverse order (SP auto-increments by 4 each time)
    POP R5        # R5 should get 0x3333
    POP R4        # R4 should get 0x2222
    POP R3        # R3 should get 0x1111

    # 5. Verify results
    ADDI R6, R0, 0x3333
    CMP  R5, R6
    BNE  R5, R6, error

    ADDI R6, R0, 0x2222
    CMP  R4, R6
    BNE  R4, R6, error

    ADDI R6, R0, 0x1111
    CMP  R3, R6
    BNE  R3, R6, error

success:
    # Set GPIO output (base 0xFFFF0000) to 0xAA (Success pattern)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7      # R1 = 0xFFFF0000
    ADDI R2, R0, 0x00FF  # Enable outputs
    STORE R1, R2, 8      # DIR = 0xFF
    ADDI R2, R0, 0x00AA  # Success pattern 10101010
    STORE R1, R2, 0      # DATA_OUT = 0xAA
    HALT

error:
    # Set GPIO output to 0xFF (Error pattern)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7      # R1 = 0xFFFF0000
    ADDI R2, R0, 0x00FF
    STORE R1, R2, 8      # DIR = 0xFF
    ADDI R2, R0, 0x00FF  # Error pattern 11111111
    STORE R1, R2, 0      # DATA_OUT = 0xFF
    HALT
