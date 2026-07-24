# =============================================================================
# Program     : func_call.asm
# Description : Demonstrates nested subroutine calls (CALL and RET) by
#               iteratively calculating the 7th Fibonacci number (F(7) = 13).
#               Validates the result and displays success/error code on GPIO.
# =============================================================================

.org 0x00001000

main:
    # 1. Initialize input: compute Fibonacci for N = 7
    ADDI R10, R0, 7

    # 2. Call Fibonacci function
    CALL fibonacci

    # 3. Verify that Fib(7) == 13 (0xD)
    ADDI R11, R0, 13
    CMP  R10, R11
    BNE  R10, R11, error

success:
    # Success pattern: 0x55 on GPIO pins 0-7
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7      # R1 = 0xFFFF0000
    ADDI R2, R0, 0x00FF
    STORE R1, R2, 8      # DIR = 0xFF
    ADDI R2, R0, 0x0055  # 01010101
    STORE R1, R2, 0      # DATA_OUT = 0x55
    HALT

error:
    # Error pattern: 0xEE on GPIO pins 0-7
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7
    ADDI R2, R0, 0x00FF
    STORE R1, R2, 8
    ADDI R2, R0, 0x00EE  # 11101110
    STORE R1, R2, 0      # DATA_OUT = 0xEE
    HALT

# Fibonacci Subroutine
# Input:  R10 = N
# Output: R10 = Fib(N)
fibonacci:
    # Handle base cases: Fib(0) = 0, Fib(1) = 1
    CMP  R10, R0
    BEQ  R10, R0, fib_zero
    ADDI R12, R0, 1
    CMP  R10, R12
    BEQ  R10, R12, fib_one

    # Iterate to compute Fib(N)
    # R2 = F(n-1) = 1, R3 = F(n-2) = 0, R4 = temp, R5 = counter
    ADDI R2, R0, 1
    ADDI R3, R0, 1
    ADDI R5, R0, 2       # Start counting at index 2

fib_loop:
    ADD  R4, R2, R3      # temp = F(n-1) + F(n-2)
    ADD  R3, R0, R2      # F(n-2) = F(n-1)
    ADD  R2, R0, R4      # F(n-1) = temp

    CMP  R5, R10
    BEQ  R5, R10, fib_done
    INC  R5
    JMP  fib_loop

fib_zero:
    ADD  R10, R0, R0
    RET

fib_one:
    ADDI R10, R0, 1
    RET

fib_done:
    ADD  R10, R0, R2     # Return value is F(n) in R10
    RET
