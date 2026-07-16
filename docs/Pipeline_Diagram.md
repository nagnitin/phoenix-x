# Custom 32-Bit Pipelined CPU Hazard and Forwarding Specification

This document details the pipeline design, hazard detection logic, and forwarding paths implemented in the CPU core.

---

## 1. 5-Stage Pipeline Stages

The processor splits instruction execution across 5 stages, separated by edge-triggered registers:

```
[Instruction Fetch (IF)] -> (IF/ID Reg) -> [Decode / RegRead (ID)] -> (ID/EX Reg) -> [Execute / Branch (EX)] -> (EX/MEM Reg) -> [Memory Access (MEM)] -> (MEM/WB Reg) -> [Write-Back (WB)]
```

1. **Instruction Fetch (IF)**:
   - Program counter (`PC`) drives the instruction ROM address bus.
   - Fetched instruction word is latched into the Instruction Register.
2. **Instruction Decode (ID)**:
   - Instruction is split into opcode, source registers (`rs1`, `rs2`), destination register (`rd`), and immediate fields.
   - Registers are read asynchronously from the Register File.
   - Main control signals are generated combinationally.
3. **Execute (EX)**:
   - Operations are executed in the ALU (Arithmetic/Logic, Shifts, Multiplications).
   - Branch target evaluation is resolved in the Branch Unit.
   - Forwarding multiplexers select the latest values for register operands.
4. **Memory Access (MEM)**:
   - Data RAM is read or written for `LOAD` / `STORE` instructions.
   - Stack updates are sequenced for `PUSH` / `POP`.
   - Peripherals are written/read for memory-mapped I/O.
5. **Write-Back (WB)**:
   - Selects whether the ALU result, memory data, or return link PC is written back to the Register File destination register.

---

## 2. RAW (Read-After-Write) Data Hazards and Forwarding

A RAW hazard occurs when an instruction in the EX stage depends on the output register of a preceding instruction that has not yet written back its results to the Register File.

### Forwarding Path Matrix
Rather than stalling, the **Data Forwarding Unit** bypasses the register file and feeds the calculated results directly back to the ALU input multiplexers in the EX stage:

| Preceding Instruction Stage | Dependent Instruction Stage | Hazard Type | Resolution | Mux Code |
|-----------------------------|----------------------------|-------------|------------|----------|
| **EX/MEM** (in MEM stage)   | **ID/EX** (in EX stage)    | EX-to-EX    | Forward ALU result from MEM stage | `2'b10`  |
| **MEM/WB** (in WB stage)    | **ID/EX** (in EX stage)    | MEM-to-EX   | Forward Write-back data from WB stage | `2'b01`  |

*Note: Forwarding is disabled for reads from R0 since R0 is hardwired to zero.*

---

## 3. Structural Load-Use Hazard Stalls

A Load-Use hazard occurs when a `LOAD` instruction is immediately followed by an instruction that reads the loaded register. Because the loaded data does not leave the Data RAM until the end of the MEM stage, forwarding cannot resolve this hazard.

### Stall Condition
When a load-use hazard is detected:
- The `hazard_detection_unit` asserts `stall_if` and `stall_id` to freeze the `PC` and `IF/ID` pipeline registers.
- The unit asserts `flush_ex` to inject a **NOP** (bubble) into the `ID/EX` register.
- This creates a 1-cycle delay, pushing the dependent instruction back. In the next cycle, the hazard becomes a MEM-to-EX hazard, which is resolved via standard forwarding.

---

## 4. Control Hazards (Branch / Jump Flushes)

Control hazards occur when a branch or jump instruction redirects the program execution flow. By the time the branch decision is made in the EX stage, the two subsequent instructions have already been fetched into the IF and ID stages.

### Flush Condition
If a branch is taken or a jump is executed:
- The branch unit calculates the target address and updates the `PC`.
- The `hazard_detection_unit` asserts `flush_if` and `flush_id` to clear the instructions in the IF and ID pipeline registers (converting them to **NOPs**).
- This flushes the pipeline of incorrect instructions, incurring a 2-cycle control penalty.
