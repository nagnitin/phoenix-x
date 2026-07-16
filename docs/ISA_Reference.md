# Custom 32-Bit Microcontroller Instruction Set Architecture (ISA) Reference

This document describes the instruction formats, register conventions, status flag bit assignments, and full instructions supported by the custom Harvard-architecture CPU.

---

## 1. Register Set

The processor contains 32 general-purpose 32-bit registers (`R0` to `R31`):

| Name | Alias | Description / Register Convention |
|------|-------|----------------------------------|
| `R0` | `ZERO`| Hardwired to zero. Writes are ignored. |
| `R1`-`R28`| -  | General-purpose temporary and saved registers. |
| `R29`| `SP`  | Stack Pointer. Pointing to current top of memory stack in RAM. |
| `R30`| `LR`  | Link Register. Holds return address for `CALL` instructions. |
| `R31`| `PC`  | Reserved/Zero (Internally PC is a separate hardware register). |

---

## 2. Processor Status Word (Status Register Flags)

The CPU status register (`SR`) is an 8-bit register containing the following flags:

| Bit | Name | Description |
|-----|------|-------------|
| 7   | `S`  | Supervisor mode (1=kernel, 0=user) |
| 6   | `T`  | Timer flag (Interrupt pending) |
| 5   | `H`  | Half-carry |
| 4   | `I`  | Global Interrupt Enable (1=enabled, 0=masked) |
| 3   | `V`  | Signed Overflow flag |
| 2   | `C`  | Carry / Borrow flag |
| 1   | `N`  | Negative flag |
| 0   | `Z`  | Zero flag |

---

## 3. Instruction Formats

Every instruction is fixed-width 32-bit:

### R-Type (Register)
Used for arithmetic, logic, shifts, comparison and system operations using registers.
`[31:26] opcode | [25:21] rd | [20:16] rs1 | [15:11] rs2 | [10:0] func`

### I-Type (Immediate)
Used for arithmetic immediates, loads, stores, branch offsets, and peripheral input/outputs.
`[31:26] opcode | [25:21] rd | [20:16] rs1 | [15:0] imm16`

### J-Type (Jump)
Used for unconditional jumps and subroutines.
`[31:26] opcode | [25:0] target26`

---

## 4. Complete Instruction Reference Table

| Mnemonic | Opcode (Hex) | Format | Syntax | Description |
|----------|--------------|--------|--------|-------------|
| `NOP`    | `0x00`       | R      | `NOP`  | No Operation |
| `ADD`    | `0x01`       | R      | `ADD rd, rs1, rs2` | `rd = rs1 + rs2` |
| `ADDI`   | `0x02`       | I      | `ADDI rd, rs1, imm` | `rd = rs1 + sign_ext(imm)` |
| `SUB`    | `0x03`       | R      | `SUB rd, rs1, rs2` | `rd = rs1 - rs2` |
| `MUL`    | `0x04`       | R      | `MUL rd, rs1, rs2` | `rd = rs1 * rs2` (lower 32 bits) |
| `DIV`    | `0x05`       | R      | `DIV rd, rs1, rs2` | `rd = rs1 / rs2` |
| `INC`    | `0x06`       | R      | `INC rd` | `rd = rd + 1` |
| `DEC`    | `0x07`       | R      | `DEC rd` | `rd = rd - 1` |
| `AND`    | `0x08`       | R      | `AND rd, rs1, rs2` | `rd = rs1 & rs2` |
| `OR`     | `0x09`       | R      | `OR rd, rs1, rs2` | `rd = rs1 \| rs2` |
| `XOR`    | `0x0A`       | R      | `XOR rd, rs1, rs2` | `rd = rs1 ^ rs2` |
| `NOT`    | `0x0B`       | R      | `NOT rd, rs1` | `rd = ~rs1` |
| `NAND`   | `0x0C`       | R      | `NAND rd, rs1, rs2` | `rd = ~(rs1 & rs2)` |
| `NOR`    | `0x0D`       | R      | `NOR rd, rs1, rs2` | `rd = ~(rs1 \| rs2)` |
| `LSL`    | `0x0E`       | R      | `LSL rd, rs1, rs2` | `rd = rs1 << rs2` (logical shift left) |
| `LSR`    | `0x0F`       | R      | `LSR rd, rs1, rs2` | `rd = rs1 >> rs2` (logical shift right) |
| `ASR`    | `0x10`       | R      | `ASR rd, rs1, rs2` | `rd = rs1 >>> rs2` (arithmetic shift right) |
| `ROL`    | `0x11`       | R      | `ROL rd, rs1, rs2` | `rd = rotate_left(rs1, rs2)` |
| `ROR`    | `0x12`       | R      | `ROR rd, rs1, rs2` | `rd = rotate_right(rs1, rs2)` |
| `CMP`    | `0x13`       | R      | `CMP rs1, rs2` | Evaluates `rs1 - rs2`, updates Z, N, C, V |
| `SLT`    | `0x14`       | R      | `SLT rd, rs1, rs2` | `rd = (rs1 < rs2) ? 1 : 0` (signed) |
| `LOAD`   | `0x15`       | I      | `LOAD rd, rs1, offset` | `rd = Mem32[rs1 + offset]` |
| `STORE`  | `0x16`       | I      | `STORE rs1, rs2, offset` | `Mem32[rs1 + offset] = rs2` |
| `LOADB`  | `0x17`       | I      | `LOADB rd, rs1, offset` | `rd = zero_ext(Mem8[rs1 + offset])` |
| `STOREB` | `0x18`       | I      | `STOREB rs1, rs2, offset` | `Mem8[rs1 + offset] = rs2[7:0]` |
| `JMP`    | `0x19`       | J      | `JMP target` | `PC = target26 << 2` |
| `CALL`   | `0x1A`       | J      | `CALL target` | `LR = PC + 4; PC = target26 << 2` |
| `RET`    | `0x1B`       | R      | `RET [rs1]` | `PC = rs1` (defaults to LR/R30 if omitted) |
| `BEQ`    | `0x1C`       | I      | `BEQ rs1, rs2, label` | `if (rs1 == rs2) PC = PC + 4 + (offset << 2)` |
| `BNE`    | `0x1D`       | I      | `BNE rs1, rs2, label` | `if (rs1 != rs2) PC = PC + 4 + (offset << 2)` |
| `BLT`    | `0x1E`       | I      | `BLT rs1, rs2, label` | `if (rs1 < rs2) PC = PC + 4 + (offset << 2)` (signed) |
| `BGT`    | `0x1F`       | I      | `BGT rs1, rs2, label` | `if (rs1 > rs2) PC = PC + 4 + (offset << 2)` (signed) |
| `PUSH`   | `0x20`       | R      | `PUSH rs2` | `Mem32[SP-4] = rs2; SP = SP - 4` |
| `POP`    | `0x21`       | R      | `POP rd` | `rd = Mem32[SP]; SP = SP + 4` |
| `IN`     | `0x22`       | I      | `IN rd, port_offset` | `rd = Peripheral[port_offset]` |
| `OUT`    | `0x23`       | I      | `OUT rs1, port_offset` | `Peripheral[port_offset] = rs1` |
| `INT`    | `0x24`       | I      | `INT num` | Trigger software interrupt vector `num` |
| `IRET`   | `0x25`       | R      | `IRET` | Return from Interrupt (restores PC and SR) |
| `HALT`   | `0x3F`       | R      | `HALT` | Stop execution (freeze pipeline) |
