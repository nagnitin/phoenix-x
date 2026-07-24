#!/usr/bin/env python3
# =============================================================================
# Script      : assembler.py
# Project     : 32-Bit Custom FPGA Microcontroller Toolchain
# Description : Custom assembler translating assembly programs (.asm) into
#               machine code (.hex) compatible with Verilog $readmemh.
# =============================================================================

import sys
import os
import re

# Opcode Mapping (6-bit opcodes)
OPCODES = {
    "NOP":     0x00,
    "ADD":     0x01,
    "ADDI":    0x02,
    "SUB":     0x03,
    "MUL":     0x04,
    "DIV":     0x05,
    "INC":     0x06,
    "DEC":     0x07,
    "AND":     0x08,
    "OR":      0x09,
    "XOR":     0x0A,
    "NOT":     0x0B,
    "NAND":    0x0C,
    "NOR":     0x0D,
    "LSL":     0x0E,
    "LSR":     0x0F,
    "ASR":     0x10,
    "ROL":     0x11,
    "ROR":     0x12,
    "CMP":     0x13,
    "SLT":     0x14,
    "LOAD":    0x15,
    "STORE":   0x16,
    "LOADB":   0x17,
    "STOREB":  0x18,
    "JMP":     0x19,
    "CALL":    0x1A,
    "RET":     0x1B,
    "BEQ":     0x1C,
    "BNE":     0x1D,
    "BLT":     0x1E,
    "BGT":     0x1F,
    "PUSH":    0x20,
    "POP":     0x21,
    "IN":      0x22,
    "OUT":     0x23,
    "INT":     0x24,
    "IRET":    0x25,
    "HALT":    0x3F,
}

# Register Mapping (R0-R31, SP=R29, LR=R30)
REG_MAP = {f"R{i}": i for i in range(32)}
REG_MAP["SP"] = 29
REG_MAP["LR"] = 30

def parse_reg(reg_str):
    reg_str = reg_str.strip().upper()
    if reg_str in REG_MAP:
        return REG_MAP[reg_str]
    raise ValueError(f"Invalid register: {reg_str}")

def parse_imm(imm_str):
    imm_str = imm_str.strip()
    try:
        if imm_str.lower().startswith("0x"):
            return int(imm_str, 16)
        if imm_str.lower().startswith("0b"):
            return int(imm_str, 2)
        return int(imm_str, 10)
    except ValueError:
        raise ValueError(f"Invalid immediate value: {imm_str}")

def assemble_line(opcode, args, pc, labels):
    opcode = opcode.upper()
    if opcode not in OPCODES:
        raise ValueError(f"Unknown instruction: {opcode}")

    op = OPCODES[opcode]

    # R-Type: [31:26]=opcode, [25:21]=rd, [20:16]=rs1, [15:11]=rs2, [10:0]=func
    # I-Type: [31:26]=opcode, [25:21]=rd, [20:16]=rs1, [15:0]=imm16
    # J-Type: [31:26]=opcode, [25:0]=target26

    # 1. NOP / HALT / IRET
    if opcode in ["NOP", "HALT", "IRET"]:
        return (op << 26)

    # 2. RET
    if opcode == "RET":
        rs1 = 30 # Default return to LR/R30
        if len(args) > 0:
            rs1 = parse_reg(args[0])
        return (op << 26) | (rs1 << 16)

    # 3. INC / DEC / NOT
    if opcode in ["INC", "DEC", "NOT"]:
        rd = parse_reg(args[0])
        rs1 = rd
        if len(args) > 1:
            rs1 = parse_reg(args[1])
        return (op << 26) | (rd << 21) | (rs1 << 16)

    # 4. R-Type arithmetic/logic: ADD, SUB, MUL, DIV, AND, OR, XOR, NAND, NOR, LSL, LSR, ASR, ROL, ROR, SLT
    if opcode in ["ADD", "SUB", "MUL", "DIV", "AND", "OR", "XOR", "NAND", "NOR", "LSL", "LSR", "ASR", "ROL", "ROR", "SLT"]:
        rd = parse_reg(args[0])
        rs1 = parse_reg(args[1])
        rs2 = parse_reg(args[2])
        return (op << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11)

    # 5. CMP
    if opcode == "CMP":
        rs1 = parse_reg(args[0])
        rs2 = parse_reg(args[1])
        return (op << 26) | (rs1 << 16) | (rs2 << 11)

    # 6. ADDI, LOAD, LOADB
    if opcode in ["ADDI", "LOAD", "LOADB"]:
        rd = parse_reg(args[0])
        rs1 = parse_reg(args[1])
        imm_val = 0
        if len(args) > 2:
            imm_str = args[2]
            if imm_str in labels:
                imm_val = labels[imm_str]
            else:
                imm_val = parse_imm(imm_str)
        # Ensure 16-bit immediate range
        imm16 = imm_val & 0xFFFF
        return (op << 26) | (rd << 21) | (rs1 << 16) | imm16

    # 7. STORE, STOREB
    if opcode in ["STORE", "STOREB"]:
        rs1 = parse_reg(args[0]) # Base
        rs2 = parse_reg(args[1]) # Data source
        imm_val = parse_imm(args[2]) & 0xFFFF
        return (op << 26) | (rs1 << 16) | (rs2 << 11) | imm_val

    # 8. PUSH
    if opcode == "PUSH":
        rs2 = parse_reg(args[0]) # data to push
        rs1 = 29 # SP
        # PUSH decrements SP by 4 (forced to 4 in hardware, immediate not needed in instruction bits 15:0)
        return (op << 26) | (rs1 << 16) | (rs2 << 11)

    # 9. POP
    if opcode == "POP":
        rd = parse_reg(args[0]) # data to pop into
        rs1 = 29 # SP
        # POP loads from SP then increments SP by 4. So offset is 0.
        return (op << 26) | (rd << 21) | (rs1 << 16) | 0x0000

    # 10. Branches: BEQ, BNE, BLT, BGT
    if opcode in ["BEQ", "BNE", "BLT", "BGT"]:
        rs1 = parse_reg(args[0])
        rs2 = parse_reg(args[1])
        target_str = args[2]
        offset = 0
        if target_str in labels:
            # PC-relative calculation: (LabelAddr - (PC + 4)) / 4
            offset = (labels[target_str] - (pc + 4)) // 4
        else:
            offset = parse_imm(target_str)
        imm16 = offset & 0xFFFF
        # For branches, encode rs2 in rd (bits 25:21), rs1 in rs1 (bits 20:16), offset in imm16 (bits 15:0)
        return (op << 26) | (rs2 << 21) | (rs1 << 16) | imm16

    # 11. IN / OUT
    if opcode == "IN":
        rd = parse_reg(args[0])
        imm_val = parse_imm(args[1]) & 0xFFFF
        return (op << 26) | (rd << 21) | imm_val
    if opcode == "OUT":
        rs1 = parse_reg(args[0])
        imm_val = parse_imm(args[1]) & 0xFFFF
        return (op << 26) | (rs1 << 16) | imm_val

    # 12. JMP / CALL / INT
    if opcode in ["JMP", "CALL"]:
        target_str = args[0]
        target_addr = 0
        if target_str in labels:
            target_addr = labels[target_str]
        else:
            target_addr = parse_imm(target_str)
        # J-Type targets are absolute word addresses: target_addr / 4
        target26 = (target_addr // 4) & 0x3FFFFFF
        return (op << 26) | target26

    if opcode == "INT":
        imm_val = parse_imm(args[0]) & 0x3FFFFFF
        return (op << 26) | imm_val

    raise ValueError(f"Unhandled instruction format: {opcode}")

def assemble(input_file, output_file):
    labels = {}
    lines = []
    
    # Read and clean file
    with open(input_file, "r") as f:
        raw_lines = f.readlines()

    # Pass 1: Parse labels and count instructions
    pc = 0x00001000 # Program entry address in Instruction ROM
    cleaned_lines = []
    
    for line in raw_lines:
        # Strip comments
        line = re.sub(r"[;#].*$", "", line).strip()
        if not line:
            continue
        
        # Check for directive
        if line.startswith(".org"):
            parts = line.split()
            pc = parse_imm(parts[1])
            continue

        # Check for label
        match = re.match(r"^([a-zA-Z_][a-zA-Z0-9_]*):(.*)$", line)
        if match:
            label_name = match.group(1)
            labels[label_name] = pc
            line = match.group(2).strip()
            if not line:
                continue

        cleaned_lines.append((pc, line))
        pc += 4

    # Pass 2: Generate machine code
    machine_codes = [0] * 4096
    for pc, line in cleaned_lines:
        # Parse mnemonic and arguments
        parts = re.split(r"[\s,]+", line)
        opcode = parts[0]
        args = [p for p in parts[1:] if p]

        try:
            code = assemble_line(opcode, args, pc, labels)
            index = (pc - 0x1000) // 4
            if 0 <= index < 4096:
                machine_codes[index] = code
            else:
                print(f"Error: Address 0x{pc:08X} is out of instruction ROM bounds (0x1000 - 0x4FFF)", file=sys.stderr)
                sys.exit(1)
        except Exception as e:
            print(f"Error at address 0x{pc:08X}: '{line}' -> {e}", file=sys.stderr)
            sys.exit(1)

    # Write Verilog hex initialization file (4096 words to match instruction ROM size)
    with open(output_file, "w") as f:
        for code in machine_codes:
            f.write(f"{code:08X}\n")

    print(f"Assembly completed successfully. Output written to '{output_file}'.")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python assembler.py <input.asm> <output.hex>")
        sys.exit(1)
    assemble(sys.argv[1], sys.argv[2])
