# =============================================================================
# Program     : timer_irq.asm
# Description : Demonstrates hardware timer interrupts. Configures the 32-bit
#               timer to overflow and generate interrupts. The ISR increments
#               a counter and toggles the LEDs on GPIO.
# =============================================================================

.org 0x00001000        # Main program entry

main:
    # 1. Configure GPIO Direction (DIR at 0xFFFF0008)
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7      # R1 = 0xFFFF0000
    ADDI R2, R0, 0x00FF  # Pins 0-7 as output
    STORE R1, R2, 8      # DIR = 0xFF

    # 2. Configure Timer (base address 0xFFFF0400)
    # Timer Period register at offset 0x04 -> 0xFFFF0404
    # Timer Control register at offset 0x00 -> 0xFFFF0400
    ADDI R3, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R3, R3, R7
    ADDI R3, R3, 0x0400  # R3 = 0xFFFF0400
    
    ADDI R4, R0, 0x03E8  # Period = 1000 cycles
    STORE R3, R4, 4      # TIMER_PERIOD = 1000

    ADDI R4, R0, 0x0013  # EN=1, AUTO_RELOAD=1, IRQ_EN=1 (0b10011 = 0x13)
    STORE R3, R4, 0      # TIMER_CTRL = 0x13

    # R5 is the main thread loop counter
    ADDI R5, R0, 0

main_loop:
    INC  R5              # Just increment counter in background
    JMP  main_loop


# =============================================================================
# Timer ISR (Vector 1: located at 0x00001120 per IVT default)
# =============================================================================
.org 0x00001120

timer_isr:
    # Save active register R2, R4 to stack
    PUSH R2
    PUSH R4

    # 1. Toggle GPIO outputs to show ISR execution
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7      # R1 = 0xFFFF0000
    LOAD R2, R1, 0       # Read current DATA_OUT
    XOR  R2, R2, R1      # Toggle bottom bits
    ADDI R4, R0, 0x00FF
    AND  R2, R2, R4      # Keep only bottom 8 bits
    STORE R1, R2, 0      # Write updated value

    # 2. Acknowledge interrupt in PIC (base 0xFFFF0600)
    # IRQ_ACK register is at offset 0x0C -> 0xFFFF060C
    # Write 1 to bit 1 to clear Timer interrupt pending bit
    ADDI R1, R0, 0xFFFF
    ADDI R7, R0, 16
    LSL  R1, R1, R7
    ADDI R1, R1, 0x0600  # R1 = 0xFFFF0600
    ADDI R4, R0, 0x0002  # Bit 1 = Timer
    STORE R1, R4, 12     # PIC_IRQ_ACK = 2

    # Restore registers from stack
    POP  R4
    POP  R2

    # Return from interrupt (restores PC and flags status register)
    IRET
