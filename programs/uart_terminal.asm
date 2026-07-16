# =============================================================================
# Program     : uart_terminal.asm
# Description : Polling-based UART Echo Terminal.
#               Prints a welcome message ("HI\n") on startup, then polls the UART
#               status flags in a loop. When a character is received, it echoes
#               it back to the terminal.
# =============================================================================

.org 0x00001000

main:
    # 1. Base Address for UART (0xFFFF0100)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7
    ADDI R1, R1, 0x0100  # R1 = 0xFFFF0100

    # 2. Print Welcome Message "HI\n" (H = 72, I = 73, \n = 10)
    ADDI R2, R0, 72
    CALL uart_write
    
    ADDI R2, R0, 73
    CALL uart_write

    ADDI R2, R0, 10
    CALL uart_write

echo_loop:
    # 3. Read Status Register (offset 0x08 = 8)
    LOAD R3, R1, 8
    
    # Check bit 2 (RX_EMPTY). If RX_EMPTY is 0, we have data!
    # Status bits: [2]=RX_EMPTY. We mask with 4.
    ADDI R4, R0, 4
    AND  R3, R3, R4
    BNE  R3, R0, echo_loop # If RX_EMPTY != 0, keep polling

    # 4. Read data from RX_DATA (offset 0x04 = 4)
    LOAD R2, R1, 4         # Character is in R2
    
    # 5. Echo character back to TX_DATA (offset 0x00 = 0)
    CALL uart_write

    JMP  echo_loop

# Subroutine to write character in R2 to UART
uart_write:
    # Read status register, check if TX FIFO is full (bit 1). If full, wait.
    # Status bits: [1]=TX_FULL. We mask with 2.
    LOAD R5, R1, 8
    ADDI R6, R0, 2
    AND  R5, R5, R6
    BNE  R5, R0, uart_write # If TX_FULL != 0, wait

    # Write char to TX_DATA
    STORE R1, R2, 0
    RET
