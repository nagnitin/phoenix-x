# 32-Bit Pipelined FPGA Microcontroller System-on-Chip (SoC)

A complete, professional-grade 32-bit pipelined Harvard-architecture microcontroller System-on-Chip (SoC) designed entirely from scratch in synthesizable Verilog HDL. This SoC contains a custom 5-stage pipelined CPU core, data forwarding, hazard detection, prioritized interrupts, a rich set of memory-mapped communication peripherals (UART, SPI, I2C, Timers, PWM), security modules, and custom drivers for external physical hardware interfaces.

No pre-existing third-party IP cores (such as ARM, RISC-V, or MIPS) are used. Every hardware module, constraint file, assembler toolchain component, and program has been custom-developed.

---

## 1. System Specifications & Features

### CPU Architecture
*   **Word Width**: 32-bit registers, data path, and instructions.
*   **Harvard Design**: Separate instruction and data address/data spaces allow simultaneous instruction fetch and memory access.
*   **Pipeline Stages**: 5-stage structure:
    1.  `IF` (Instruction Fetch): Loads instructions from instruction memory using the Program Counter.
    2.  `ID` (Instruction Decode): Parses opcodes, control logic, and reads operands from register files.
    3.  `EX` (Execute): Runs arithmetic, logic, shifts, and comparisons in the ALU, and resolves branches.
    4.  `MEM` (Memory Access): Accesses Data RAM, Boot ROM, or memory-mapped I/O peripherals.
    5.  `WB` (Write-Back): Commits results to the general-purpose Register File.
*   **Register File**: 32 general-purpose 32-bit registers. `R0` is hardwired to zero. `R29` serves as the Stack Pointer (`SP`), and `R30` serves as the Link Register (`LR`).
*   **Status register (`SR`)**: 8-bit flags register containing Zero (`Z`), Negative (`N`), Carry (`C`), Overflow (`V`), Interrupt Enable (`I`), Timer Interrupt (`T`), and Supervisor Mode (`S`) flags.

### Pipeline Control & Hazards
*   **Data Forwarding Unit**: Resolves Read-After-Write (RAW) data hazards combinationally by routing values from the `MEM` (EX/MEM latch) and `WB` (MEM/WB latch) stages back to the ALU inputs, avoiding stalls.
*   **Hazard Detection Unit**:
    *   Inserts 1-cycle stalls (NOP bubbles) for Load-Use hazards.
    *   Executes 2-cycle flushes (NOP clearing) on taken branch/jump instructions.
    *   Executes flushes on interrupt entries.
*   **Exception Return**: Dedicated Exception Program Counter (`EPC`) and Exception Status Register (`ESR`) registers allow fast interrupt entry and return (`IRET`) without memory stack overhead.

### Integrated Peripherals (Memory-Mapped I/O)
*   **UART**: Full-duplex transmitter/receiver with configurable baud rate and 8-byte TX/RX FIFO buffers.
*   **SPI Master**: Supports SPI modes 0-3, configurable clock dividers, and automatic chip select (`CS`) assertions.
*   **I2C Master**: Full state-machine engine supporting standard (100 kHz) and fast (400 kHz) modes.
*   **Programmable Timer**: 32-bit periodic, one-shot, or PWM timer with a 16-bit clock prescaler.
*   **PWM Generator**: 4 independent PWM channels with configurable periods and duty cycles for DC motors, servos, or RGB LEDs.
*   **Priority Interrupt Controller**: Handles 8 prioritize hardware and software interrupts, with vector redirects mapped via a reprogrammable Interrupt Vector Table (IVT).
*   **Watchdog Timer**: Programmable timeout window with system reset assertions and pre-warning interrupts.
*   **CRC Engine**: Hardware Cyclic Redundancy Check calculator supporting both CRC-16-CCITT and CRC-32 polynomials.
*   **Debug Unit (DBU)**: Performance monitoring counters (cycle/instruction counts), last executed PC/instruction trace buffers, and a host inspection register interface.

### Integrated Drivers for External Hardware
*   **OLED Driver**: SSD1306 128x64 display driver running on an automated, internal I2C micro-state machine.
*   **LCD Driver**: 16x2 HD44780 controller driver executing commands and data over an 8-bit parallel bus.
*   **EEPROM Driver**: AT24C series driver executing random 16-bit address reads and byte writes.
*   **7-Segment Driver**: Multiplexed 4-digit common anode/cathode display driver with automatic hex-to-segment decoding.
*   **Keypad Driver**: 4x4 matrix keypad scanner with synchronization, debouncing, and interrupt triggers on keypress.
*   **Ultrasonic Driver**: HC-SR04 distance metric driver triggering and measuring echo pulse widths to supply centimeter (cm) values.
*   **Temperature Sensor Driver**: LM75 temperature sensor driver periodically reading temperatures via I2C.

---

## 2. Directory Structure

```
32_Bit/
├── rtl/                        # Synthesizable Hardware Source Code
│   ├── core/                   # CPU Pipeline, registers, ALU, decode, and debug
│   │   ├── alu.v
│   │   ├── register_file.v
│   │   ├── status_register.v
│   │   ├── program_counter.v
│   │   ├── instruction_register.v
│   │   ├── if_id_reg.v
│   │   ├── id_ex_reg.v
│   │   ├── ex_mem_reg.v
│   │   ├── mem_wb_reg.v
│   │   ├── forwarding_unit.v
│   │   ├── hazard_detection_unit.v
│   │   ├── control_unit.v
│   │   ├── branch_unit.v
│   │   ├── cpu_core.v
│   │   └── debug_unit.v
│   ├── memory/                 # Memory Controller and Memory Blocks
│   │   ├── memory_controller.v
│   │   ├── boot_rom.v
│   │   ├── instruction_rom.v
│   │   └── data_ram.v
│   ├── peripherals/            # Core SoC Peripherals
│   │   ├── clock_divider.v
│   │   ├── uart.v
│   │   ├── spi_master.v
│   │   ├── i2c_master.v
│   │   ├── gpio.v
│   │   ├── timer.v
│   │   └── pwm.v
│   ├── interrupt/              # Interrupt Controller and IVT
│   │   ├── interrupt_controller.v
│   │   └── interrupt_vector_table.v
│   ├── security/               # Security and CRC Engines
│   │   ├── watchdog_timer.v
│   │   └── crc_engine.v
│   ├── drivers/                # External Hardware Interface Drivers
│   │   ├── lcd_driver.v
│   │   ├── oled_driver.v
│   │   ├── eeprom_driver.v
│   │   ├── seven_seg_driver.v
│   │   ├── keypad_driver.v
│   │   ├── ultrasonic_driver.v
│   │   └── temp_sensor_driver.v
│   └── top/                    # Top Level System-on-Chip wrapper
│       └── top.v
├── tb/                         # Testbenches
│   └── tb_top.v                # SoC integration testbench
├── constraints/                # FPGA Vivado constraints
│   ├── pinout.xdc              # Pin constraints
│   └── timing.xdc              # Timing constraints
├── assembler/                  # Compiler Toolchain
│   └── assembler.py            # 2-pass Python assembler
├── programs/                   # Assembly Demonstration Programs
│   ├── blink.asm
│   ├── knight_rider.asm
│   ├── stack_demo.asm
│   ├── func_call.asm
│   ├── timer_irq.asm
│   ├── traffic_light.asm
│   ├── dc_motor_pwm.asm
│   ├── uart_terminal.asm
│   ├── ultrasonic_sensor.asm
│   └── temp_display.asm
├── docs/                       # Technical Specifications
│   ├── ISA_Reference.md
│   ├── Architecture_Diagram.md
│   ├── Memory_Map.md
│   └── Pipeline_Diagram.md
└── README.md
```

---

## 3. Custom ISA Instruction Format

All instructions are fixed 32-bit width:

```
R-Type Format:
  [31:26] Opcode (6 bits)
  [25:21] Destination Register rd (5 bits)
  [20:16] Source Register rs1 (5 bits)
  [15:11] Source Register rs2 (5 bits)
  [10:0]  Function Selector func (11 bits)

I-Type Format:
  [31:26] Opcode (6 bits)
  [25:21] Destination Register rd (5 bits)
  [20:16] Source Register rs1 (5 bits)
  [15:0]  Immediate Value imm16 (16 bits)

J-Type Format:
  [31:26] Opcode (6 bits)
  [25:0]  Target Address target26 (26 bits)
```

Refer to the [ISA_Reference.md](file:///c:/Users/nitin/OneDrive/Desktop/32_Bit/docs/ISA_Reference.md) for individual mnemonics and opcodes.

---

## 4. Software Setup & Verification Guide

You can run, program, and simulate this entire project on your computer without physical hardware by using open-source Verilog simulation tools.

### 4.1 Prerequisites (Windows Installation)
1.  **Python 3**: Used for running the assembler toolchain.
2.  **Icarus Verilog & GTKWave**:
    *   Download the unified installer from [http://bleyer.org/icarus/](http://bleyer.org/icarus/) (Select the latest x64 version).
    *   Run the installation wizard and **check the box "Add executable folders to the user PATH"**.

### 4.2 Assembly and Compilation Steps
Open a Command Prompt or PowerShell in the project root directory (`32_Bit`) and execute the following:

1.  **Compile Assembly Code**:
    Translate any of the demo programs into a hexadecimal memory file:
    ```bash
    python assembler/assembler.py programs/stack_demo.asm prog.hex
    ```
    This creates `prog.hex`, which contains 32-bit hex values read by the Instruction ROM.

2.  **Compile Verilog Source Files**:
    Compile the synthesizable source files and system testbench using `iverilog`:
    ```bash
    iverilog -o sim_top.out tb/tb_top.v rtl/top/top.v rtl/core/*.v rtl/memory/*.v rtl/peripherals/*.v rtl/interrupt/*.v rtl/security/*.v rtl/drivers/*.v
    ```

3.  **Run Simulation**:
    Execute the simulator using `vvp`. This runs the code on the simulated CPU and dumps signal transitions into `sim/waves.vcd`:
    ```bash
    vvp sim_top.out
    ```

4.  **View Waveforms**:
    Open the signal traces in GTKWave:
    ```bash
    gtkwave sim/waves.vcd
    ```
    Within GTKWave, navigate to `tb_top -> uut -> cpu_core_inst` to add signals like `clk`, `pc_out`, `imem_rdata`, and `regs` to watch register states change and instructions decode in real time!

---

## 5. FPGA Synthesis & Deployment Guide

This project is fully synthesizable and can be deployed on a Xilinx Artix-7 FPGA (such as the Basys 3 board) using Vivado.

1.  **Create a New Project**:
    *   Open Vivado and create a new project. Select the Artix-7 part `xc7a35tcpg236-1` (the Basys 3 target device).
2.  **Import RTL Source Files**:
    *   Add all files from the `rtl/` subfolders as design sources. Set `rtl/top/top.v` as the top-level module.
3.  **Import Constraints**:
    *   Add the XDC files `constraints/pinout.xdc` and `constraints/timing.xdc` as constraints sources.
4.  **ROM Initialization**:
    *   Compile your selected assembly program using `assembler.py` and copy the generated `prog.hex` file into your Vivado project's workspace directory. The synthesized design will automatically preload this file into block memory.
5.  **Generate Bitstream**:
    *   Click **Run Synthesis** followed by **Run Implementation**.
    *   Click **Generate Bitstream** to create the target `.bit` programming file.
6.  **Program FPGA Board**:
    *   Connect the Basys 3 board, open the **Hardware Manager** in Vivado, and program the device.
    *   The 16 onboard switches serve as inputs (`gp_in[15:0]`), the 16 LEDs serve as outputs (`gp_out[15:0]`), and the 4-digit seven-segment display will display values mapped by your programs.
