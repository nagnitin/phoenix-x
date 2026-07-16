# Custom 32-Bit Microcontroller Memory Map Reference

The microcontroller implements a single unified address space for data reads and writes (Harvard architecture handles instructions separately, but instruction memory can also be read by the memory controller for constant lookups).

---

## 1. Unified Address Space Allocation

| Byte Address Range | Size | Target Device | Width | Description / Access Permissions |
|--------------------|------|---------------|-------|----------------------------------|
| `0x00000000 - 0x000003FF` | 1 KB | Boot ROM | 32-bit | Read-Only. Contains hardware boot sequence. |
| `0x00001000 - 0x00004FFF` | 16 KB | Instruction ROM | 32-bit | Read-Only. User program code memory. |
| `0x00010000 - 0x00017FFF` | 32 KB | Data RAM | 32-bit | Read/Write (Word & Byte). Stack and variable heap. |
| `0xFFFF0000 - 0xFFFF0DFF` | ~3.5 KB | Peripherals (MMIO) | 32-bit | Read/Write. Device status and configuration registers. |

---

## 2. Memory-Mapped I/O (MMIO) Peripheral Register Map

All peripheral registers are memory-mapped under the `0xFFFF0000` segment. Each peripheral block occupies 256 bytes.

### 2.1 GPIO Registers (Base `0xFFFF0000`)
- `0xFFFF0000`: `DATA_OUT` (RW) — Outputs driven to pin (32 bits)
- `0xFFFF0004`: `DATA_IN` (RO) — Inputs read from pin (32 bits)
- `0xFFFF0008`: `DIR` (RW) — Pin directions: 1=Output, 0=Input (32 bits)
- `0xFFFF000C`: `IRQ_MASK` (RW) — Pin interrupt mask (32 bits)
- `0xFFFF0010`: `IRQ_EDGE` (RW) — Edge select: 1=Rising, 0=Falling (32 bits)
- `0xFFFF0014`: `IRQ_BOTH` (RW) — Both edge interrupt triggers: 1=Both, 0=Use Edge (32 bits)
- `0xFFFF0018`: `IRQ_STAT` (RO) — Pin interrupt status flag
- `0xFFFF001C`: `IRQ_CLR` (WO) — Write 1s to clear pin interrupt flags

### 2.2 UART Registers (Base `0xFFFF0100`)
- `0xFFFF0100`: `TX_DATA` (WO) — Write byte to transmit FIFO
- `0xFFFF0104`: `RX_DATA` (RO) — Read byte from receive FIFO
- `0xFFFF0108`: `STATUS` (RO) — Bits: [0]=TX_Empty, [1]=TX_Full, [2]=RX_Empty, [3]=RX_Full, [4]=Overrun
- `0xFFFF010C`: `CTRL` (RW) — Bits: [0]=TX_Int_Enable, [1]=RX_Int_Enable

### 2.3 SPI Master Registers (Base `0xFFFF0200`)
- `0xFFFF0200`: `CTRL` (RW) — Bits: [1:0]=Mode, [2]=Start, [3]=Busy (RO), [4]=Auto_CS
- `0xFFFF0204`: `DIVIDER` (RW) — SCLK clock divider factor (16 bits)
- `0xFFFF0208`: `TX_DATA` (WO) — Byte to transmit
- `0xFFFF020C`: `RX_DATA` (RO) — Received byte
- `0xFFFF0210`: `STATUS` (RO) — Bits: [0]=Done, [1]=Busy

### 2.4 I2C Master Registers (Base `0xFFFF0300`)
- `0xFFFF0300`: `CTRL` (RW) — Bits: [0]=Start, [1]=Stop, [2]=RW, [3]=ACK_En
- `0xFFFF0304`: `ADDR` (RW) — 7-bit slave address
- `0xFFFF0308`: `TX_DATA` (WO) — Byte to transmit
- `0xFFFF030C`: `RX_DATA` (RO) — Received byte
- `0xFFFF0310`: `DIVIDER` (RW) — I2C clock speed divider (16 bits)
- `0xFFFF0314`: `STATUS` (RO) — Bits: [0]=Done, [1]=Busy, [2]=ACK, [3]=NACK, [4]=Arb_Lost

### 2.5 Timer Registers (Base `0xFFFF0400`)
- `0xFFFF0400`: `CTRL` (RW) — Bits: [0]=Enable, [1]=Auto_Reload, [2]=PWM_En, [3]=One_Shot, [4]=Int_Enable
- `0xFFFF0404`: `PERIOD` (RW) — Timer overflow match value (32 bits)
- `0xFFFF0408`: `COMPARE` (RW) — Timer PWM compare width (32 bits)
- `0xFFFF040C`: `COUNT` (RO) — Current counter value (32 bits)
- `0xFFFF0410`: `STATUS` (RO) — Bits: [0]=Overflow, [1]=Running
- `0xFFFF0414`: `PRESCALE` (RW) — Clock prescale divider factor (16 bits)

### 2.6 PWM Controller Registers (Base `0xFFFF0500`)
- `0xFFFF0500`: `ENABLE` (RW) — Bits: [3:0]=Enable channels 0-3
- `0xFFFF0504` to `0xFFFF0524` (RW) — Period and Duty width registers per channel

### 2.7 PIC Interrupt Controller Registers (Base `0xFFFF0600`)
- `0xFFFF0600`: `STATUS` (RO) — Bits [7:0] raw hardware interrupt lines status
- `0xFFFF0604`: `ENABLE` (RW) — Bits [7:0] interrupt line mask enable
- `0xFFFF0608`: `PENDING` (RO) — Bits [7:0] active pending interrupts
- `0xFFFF060C`: `ACK` (WO) — Write 1s to clear pending interrupt flags

### 2.8 Watchdog & CRC Registers (Base `0xFFFF0700`)
- `0xFFFF0700`: `WDT_CTRL` (RW) — Bits: [0]=Enable, [1]=Early_Int_Enable
- `0xFFFF0704`: `WDT_LOAD` (RW) — WDT timeout period (32 bits)
- `0xFFFF0708`: `WDT_FEED` (WO) — Write `0xAAAA5555` to reload counter
- `0xFFFF070C`: `WDT_STAT` (RW) — Sticky watchdog reset occurred flag
- `0xFFFF0740`: `CRC_CTRL` (RW) — Bits: [0]=Enable, [1]=Mode (0=16-bit, 1=32-bit), [2]=Reset accumulator
- `0xFFFF0744`: `CRC_DATA` (WO) — Write data word to calculate CRC checksum
- `0xFFFF0748`: `CRC_RESULT` (RO) — Checksum result accumulator output (32 bits)

### 2.9 Debug Unit Registers (Base `0xFFFF0800`)
- `0xFFFF0800`: `CTRL` (RW) — Bits: [0]=Enable counters, [1]=Force cpu halt, [2]=Reset counters
- `0xFFFF0804`: `CYCLE_L` (RO) — Cycles count lower word
- `0xFFFF0808`: `CYCLE_H` (RO) — Cycles count upper word
- `0xFFFF080C`: `INSTR_L` (RO) — Executed instructions count lower word
- `0xFFFF0810`: `INSTR_H` (RO) — Executed instructions count upper word
- `0xFFFF0814`: `LAST_PC` (RO) — PC of the last executed instruction (WB stage)
- `0xFFFF0818`: `LAST_INSTR` (RO) — Instruction word of last executed instruction
- `0xFFFF081C`: `REG_VAL` (RO) — Value of selected register
- `0xFFFF0820`: `REG_SEL` (RW) — Select R0-R31 to read via `REG_VAL`

### 2.10 LCD character display (Base `0xFFFF0900`)
- `0xFFFF0900`: `LCD_CTRL` (RW) — Bits: [0]=Enable, [1]=RS, [2]=RW, [7]=Busy
- `0xFFFF0904`: `LCD_DATA` (WO) — Character byte to display RAM
- `0xFFFF0908`: `LCD_CMD` (WO) — Instruction byte to controller

### 2.11 OLED display (Base `0xFFFF0A00`)
- `0xFFFF0A00`: `OLED_CTRL` (RW) — Bits: [0]=Trigger init, [1]=Trigger clear, [7]=Busy
- `0xFFFF0A04`: `OLED_DATA` (WO) — Pixel data byte to GDDRAM
- `0xFFFF0A08`: `OLED_CMD` (WO) — Command byte to display controller

### 2.12 EEPROM (Base `0xFFFF0B00`)
- `0xFFFF0B00`: `EE_CTRL` (RW) — Bits: [0]=Read start, [1]=Write start, [7]=Busy
- `0xFFFF0B04`: `EE_ADDR_H` (RW) — High byte of 16-bit EEPROM cell address
- `0xFFFF0B08`: `EE_ADDR_L` (RW) — Low byte of 16-bit EEPROM cell address
- `0xFFFF0B0C`: `EE_DATA` (RW) — Byte data payload read/write

### 2.13 Seven-Segment (Base `0xFFFF0C00`)
- `0xFFFF0C00`: `SEG_DATA` (RW) — Packed 4 hex characters to show on segments
- `0xFFFF0C04`: `SEG_CTRL` (RW) — Bits: [3:0]=Digit enable mask, [7]=Common anode select
- `0xFFFF0C08`: `SEG_DP` (RW) — Decimal point configuration per digit

### 2.14 Keypad Matrix (Base `0xFFFF0D00`)
- `0xFFFF0D00`: `KEY_DATA` (RO) — Decoded index of pressed key (0-15)
- `0xFFFF0D04`: `KEY_STAT` (RO) — Bits: [0]=Key held down, [1]=New key pressed
- `0xFFFF0D08`: `KEY_CTRL` (RW) — Bits: [0]=Interrupt enable on keypress
