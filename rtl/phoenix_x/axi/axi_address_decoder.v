// =============================================================================
// Module      : axi_address_decoder
// Project     : Phoenix-X Heterogeneous SoC
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Combinational address decoder for the AXI-4 Lite shared bus.
//               Maps a 32-bit byte address to a 3-bit slave select signal.
//               Decodes both read (AR channel) and write (AW channel) addresses.
//
// Phoenix-X Memory Map:
//   0x0000_0000 – 0x0000_0FFF   SLAVE_BOOTROM  (4 KB)
//   0x0000_1000 – 0x0000_4FFF   SLAVE_IROM     (16 KB)
//   0x0001_0000 – 0x0001_7FFF   SLAVE_DRAM0    (32 KB)
//   0x0002_0000 – 0x0002_7FFF   SLAVE_DRAM1    (32 KB)
//   0x0003_0000 – 0x0003_7FFF   SLAVE_SHARED   (32 KB shared SRAM)
//   0x0020_0000 – 0x0020_02FF   SLAVE_IPC      (IPC mailbox + DMA cfg + SPIC)
//   0xFFFF_0000 – 0xFFFF_FFFF   SLAVE_PERIPH   (all legacy peripherals)
//   all others                  SLAVE_NONE     (decode error → DECERR)
//
// WHY COMBINATIONAL?
//   The AXI spec requires that ARREADY/AWREADY be asserted in the same
//   cycle (or the cycle after) that ARVALID/AWVALID is asserted. A
//   combinational decoder adds zero latency to the address phase, allowing
//   single-cycle address acceptance. Any sequential logic here would add
//   pipeline stages and hurt Fmax without benefit.
//
// Outputs:
//   slave_sel[2:0]  — Selected slave ID (see SLAVE_* defines in axi_defines.vh)
//   decode_err      — 1 if no slave maps to the given address
// =============================================================================

`timescale 1ns/1ps
`include "axi_defines.vh"

module axi_address_decoder (
    // Address to decode (comes from winning master's AW/AR channel)
    input  wire [31:0] addr,

    // Decode outputs
    output reg  [3:0]  slave_sel,   // Which slave owns this address (4-bit)
    output wire        decode_err   // 1 = address is unmapped
);

    // -------------------------------------------------------------------------
    // Combinational decode: priority-ordered if-else ensures exactly one
    // slave is selected per address. Ranges are non-overlapping.
    // -------------------------------------------------------------------------
    always @(*) begin
        if (addr <= 32'h0000_0FFF)
            slave_sel = `SLAVE_BOOTROM;                     // 0x0000_0000..0FFF

        else if (addr >= 32'h0000_1000 && addr <= 32'h0000_4FFF)
            slave_sel = `SLAVE_IROM;                        // 0x0000_1000..4FFF

        else if (addr >= 32'h0001_0000 && addr <= 32'h0001_7FFF)
            slave_sel = `SLAVE_DRAM0;                       // 0x0001_0000..7FFF

        else if (addr >= 32'h0002_0000 && addr <= 32'h0002_7FFF)
            slave_sel = `SLAVE_DRAM1;                       // 0x0002_0000..7FFF

        else if (addr >= 32'h0003_0000 && addr <= 32'h0004_FFFF)
            slave_sel = `SLAVE_SHARED;                      // 0x0003_0000..4FFF (Shared SRAM + Frame Buffer)

        else if (addr >= 32'h0020_0000 && addr <= 32'h0020_03FF)
            slave_sel = `SLAVE_SYSCTRL;                     // 0x0020_0000..03FF (IPC + Scheduler + PMU + PIC)

        else if (addr >= 32'h0020_0400 && addr <= 32'h0020_04FF)
            slave_sel = `SLAVE_GPU;                         // 0x0020_0400..04FF (Tiny GPU Config)

        else if (addr >= 32'h0020_0500 && addr <= 32'h0020_05FF)
            slave_sel = `SLAVE_NPU;                         // 0x0020_0500..05FF (NPU Config)

        else if (addr >= 32'hFFFF_0000)
            slave_sel = `SLAVE_PERIPH;                      // 0xFFFF_0000..FFFF (Legacy Peripherals)

        else
            slave_sel = `SLAVE_NONE;                        // Unmapped
    end

    // Decode error when no slave is selected
    assign decode_err = (slave_sel == `SLAVE_NONE);

endmodule
