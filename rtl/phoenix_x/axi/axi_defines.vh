// =============================================================================
// File        : axi_defines.vh
// Project     : Phoenix-X Heterogeneous SoC
// Target      : Xilinx Artix-7 XC7A100T (Nexys A7-100T)
// Clock       : 100 MHz single domain
// Description : Central header — AXI-4 Lite parameters, memory address map,
//               cache geometry constants, and MESI state encoding.
//               Include this file in EVERY Phoenix-X RTL module.
//
// WHY AXI-4 Lite (not AXI-4 Full)?
//   AXI-4 Lite has no burst transactions, no ID fields, and no QoS channels.
//   This drastically reduces the interconnect area while still providing the
//   valid/ready handshake and separate read/write channel model of AXI-4 Full.
//   For a 100 MHz dual-core SoC on Artix-7, bandwidth is not the bottleneck —
//   latency predictability is. AXI-4 Lite's simplicity maximises Fmax.
// =============================================================================

`ifndef AXI_DEFINES_VH
`define AXI_DEFINES_VH

// ---------------------------------------------------------------------------
// AXI-4 Lite Bus Width Parameters
// ---------------------------------------------------------------------------
`define AXI_AW          32    // Address bus width (32-bit physical address space)
`define AXI_DW          32    // Data bus width (32-bit, matches CPU word size)
`define AXI_SW           4    // Write strobe width = AXI_DW/8 (byte enables)

// ---------------------------------------------------------------------------
// AXI-4 Lite Response Codes (BRESP / RRESP fields)
// ---------------------------------------------------------------------------
`define AXI_RESP_OKAY    2'b00   // Normal success
`define AXI_RESP_EXOKAY  2'b01   // Exclusive access OK (not used in Phase 1)
`define AXI_RESP_SLVERR  2'b10   // Slave error (e.g., write to read-only ROM)
`define AXI_RESP_DECERR  2'b11   // Decode error (unmapped address)

// ---------------------------------------------------------------------------
// Master IDs (3-bit, up to 8 masters)
// ---------------------------------------------------------------------------
`define MASTER_CPU0      3'd0    // CPU Core 0 AXI bridge
`define MASTER_CPU1      3'd1    // CPU Core 1 AXI bridge
`define MASTER_DMA       3'd2    // DMA Controller
`define MASTER_GPU       3'd3    // Tiny GPU Frame Buffer Write Master
`define MASTER_NPU       3'd4    // NPU Weight & Feature Streamer Master

// ---------------------------------------------------------------------------
// Slave IDs (4-bit, up to 16 slaves)
// ---------------------------------------------------------------------------
`define SLAVE_BOOTROM    4'd0    // Boot ROM       0x0000_0000 – 0x0000_0FFF (4KB)
`define SLAVE_IROM       4'd1    // Instruction ROM 0x0000_1000 – 0x0000_4FFF (16KB)
`define SLAVE_DRAM0      4'd2    // CPU0 Private RAM 0x0001_0000 – 0x0001_7FFF (32KB)
`define SLAVE_DRAM1      4'd3    // CPU1 Private RAM 0x0002_0000 – 0x0002_7FFF (32KB)
`define SLAVE_SHARED     4'd4    // Shared SRAM    0x0003_0000 – 0x0003_7FFF (32KB)
`define SLAVE_SYSCTRL    4'd5    // IPC + Scheduler + PMU + Shared PIC (0x0020_0000..03FF)
`define SLAVE_PERIPH     4'd6    // Legacy periph  0xFFFF_0000 – 0xFFFF_FFFF
`define SLAVE_GPU        4'd7    // Tiny GPU Config 0x0020_0400 – 0x0020_04FF
`define SLAVE_NPU        4'd8    // NPU Config      0x0020_0500 – 0x0020_05FF
`define SLAVE_NONE       4'd9    // No match → DECERR

// ---------------------------------------------------------------------------
// Phoenix-X Memory Address Map
// ---------------------------------------------------------------------------
//  0x0000_0000 – 0x0000_0FFF   Boot ROM        (4 KB)   Read-only
//  0x0000_1000 – 0x0000_4FFF   Instruction ROM (16 KB)  Read-only, both cores
//  0x0001_0000 – 0x0001_7FFF   DRAM Bank 0     (32 KB)  CPU0 private data
//  0x0002_0000 – 0x0002_7FFF   DRAM Bank 1     (32 KB)  CPU1 private data
//  0x0003_0000 – 0x0003_7FFF   Shared SRAM     (32 KB)  Both cores + DMA
//  0x0020_0000 – 0x0020_00FF   IPC Mailbox     (256 B)  Inter-processor comms
//  0x0020_0100 – 0x0020_01FF   DMA Controller  (256 B)  DMA config registers
//  0x0020_0200 – 0x0020_02FF   Shared PIC      (256 B)  IRQ routing
//  0xFFFF_0000 – 0xFFFF_FFFF   Peripherals     (64 KB)  All legacy peripherals

// ---------------------------------------------------------------------------
// L1 Instruction Cache — Direct-Mapped, 4KB, 32-byte Lines
// ---------------------------------------------------------------------------
// Total lines     : 4096 / 32 = 128
// Address layout  : [31:12]=tag(20b) | [11:5]=index(7b) | [4:2]=word(3b) | [1:0]=byte
`define L1I_TOTAL_LINES  128
`define L1I_LINE_WORDS     8    // 32-byte line = 8 × 32-bit words
`define L1I_INDEX_W        7    // log2(128) = 7
`define L1I_OFFSET_W       5    // log2(32)  = 5 (byte offset within line)
`define L1I_WORD_SEL_W     3    // log2(8)   = 3 (word select within line)
`define L1I_TAG_W         20    // 32 - 7 - 5 = 20
`define L1I_TAG_MSB       31
`define L1I_TAG_LSB       12
`define L1I_INDEX_MSB     11
`define L1I_INDEX_LSB      5
`define L1I_WORD_MSB       4
`define L1I_WORD_LSB       2

// ---------------------------------------------------------------------------
// L1 Data Cache — 2-Way Set-Associative, 4KB, 32-byte Lines
// ---------------------------------------------------------------------------
// Total lines     : 4096 / 32 = 128 → 64 sets × 2 ways
// Address layout  : [31:11]=tag(21b) | [10:5]=index(6b) | [4:2]=word(3b) | [1:0]=byte
`define L1D_TOTAL_SETS    64
`define L1D_WAYS           2
`define L1D_LINE_WORDS     8    // 32-byte line = 8 × 32-bit words
`define L1D_INDEX_W        6    // log2(64) = 6
`define L1D_OFFSET_W       5    // log2(32) = 5
`define L1D_WORD_SEL_W     3    // log2(8)  = 3
`define L1D_TAG_W         21    // 32 - 6 - 5 = 21
`define L1D_TAG_MSB       31
`define L1D_TAG_LSB       11
`define L1D_INDEX_MSB     10
`define L1D_INDEX_LSB      5
`define L1D_WORD_MSB       4
`define L1D_WORD_LSB       2

// ---------------------------------------------------------------------------
// L2 Cache — 4-Way Set-Associative, 32KB, 64-byte Lines (shared)
// ---------------------------------------------------------------------------
// Total lines     : 32768 / 64 = 512 → 128 sets × 4 ways
// Address layout  : [31:13]=tag(19b) | [12:6]=index(7b) | [5:2]=word(4b) | [1:0]=byte
`define L2_TOTAL_SETS    128
`define L2_WAYS            4
`define L2_LINE_WORDS     16    // 64-byte line = 16 × 32-bit words
`define L2_INDEX_W         7    // log2(128) = 7
`define L2_OFFSET_W        6    // log2(64)  = 6
`define L2_WORD_SEL_W      4    // log2(16)  = 4
`define L2_TAG_W          19    // 32 - 7 - 6 = 19
`define L2_TAG_MSB        31
`define L2_TAG_LSB        13
`define L2_INDEX_MSB      12
`define L2_INDEX_LSB       6
`define L2_WORD_MSB        5
`define L2_WORD_LSB        2

// ---------------------------------------------------------------------------
// MESI Cache Coherency State Encoding (2 bits per cache line)
// WHY MESI?
//   With 2 shared-memory cores, stale cache values cause incorrect computation.
//   MESI uses the bus as a snoop medium: every write is visible to all caches.
//   It is the industry standard (Intel P6, ARM Cortex-A), implementable in RTL
//   with a simple snoop FSM per L1 D-cache.
// ---------------------------------------------------------------------------
`define MESI_INVALID     2'b00   // Line not present → any access triggers miss
`define MESI_SHARED      2'b01   // Clean copy; another core may also have it
`define MESI_EXCLUSIVE   2'b10   // Clean copy; this core is the sole owner
`define MESI_MODIFIED    2'b11   // Dirty copy; must write-back before eviction

// ---------------------------------------------------------------------------
// Artix-7 XC7A100T Resource Budget (for reference in comments)
// ---------------------------------------------------------------------------
// LUTs              : 63,400
// FFs               : 126,800
// BRAM (36Kb each) :     135   (total 4,860 Kb)
// DSP48E1           :     240
//
// Cache BRAM budget:
//   L1 I-Cache ×2  : 2×(1 BRAM 36Kb = 4KB data)  = 2 BRAMs
//   L1 D-Cache ×2  : 2×(2 BRAM for 2-way)          = 4 BRAMs
//   L2 Cache       : 4×(2 BRAMs per way, 32KB/4)   = 8 BRAMs
//   Shared SRAM     : 32KB                          = 8 BRAMs
//   TOTAL cache+sram: 22 BRAMs (16% of 135 BRAMs)

`endif // AXI_DEFINES_VH
