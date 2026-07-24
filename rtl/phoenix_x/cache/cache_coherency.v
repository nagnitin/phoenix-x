// =============================================================================
// Module      : cache_coherency
// Project     : Phoenix-X Heterogeneous SoC
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Snoop-based MESI Cache Coherency Controller.
//               Monitors ALL write transactions on the AXI bus and broadcasts
//               invalidation signals to L1 D-caches that may hold stale copies.
//
// MESI Protocol Summary:
//   MODIFIED  (M): Only this cache has the line; it is dirty.
//                  Must write-back to memory before anyone else can read it.
//   EXCLUSIVE (E): Only this cache has the line; it is clean.
//                  Can upgrade to M without bus traffic on a write hit.
//   SHARED    (S): Multiple caches have this line (all clean).
//                  Must invalidate others before writing (upgrade to M).
//   INVALID   (I): Line not present; any access is a miss.
//
// Snooping Protocol (Invalidation-Based):
//   1. CPU0 writes to address X:
//      → L1-D0 marks its line for X as MODIFIED
//      → This controller sees the AXI write (from the crossbar's snoop output)
//      → Sends snoop_inval[1] to L1-D1 for the line containing X
//      → L1-D1 transitions X to INVALID
//   2. CPU1 later reads X:
//      → L1-D1 miss → triggers fetch from L2 (or memory)
//      → Gets the modified data (because CPU0's write already propagated through WB)
//
// WHY INVALIDATION (not update)?
//   Update-based protocols broadcast the new data to all sharers on every write.
//   For typical multi-core workloads (producer-consumer, lock-protected data),
//   updates would waste bus bandwidth for data that may never be re-read by
//   the other core. Invalidation is the industry standard (ARM, x86) because
//   it avoids broadcast traffic for private writes.
//
// Connection:
//   The AXI crossbar has a `snoop_addr` and `snoop_wr_valid` output.
//   These feed directly into this controller.
//   The controller outputs `snoop_inval[1:0]` to each L1 D-cache.
//
// Note: This controller handles write-invalidation only.
//       The `snoop_hit` and `snoop_dirty` outputs of each L1 D-cache
//       are used in Phase 2 to implement write-back-before-invalidate
//       (for M→S or M→I transitions triggered by remote reads).
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module cache_coherency (
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Snoop Bus Input (from axi_crossbar snoop output)
    // -------------------------------------------------------------------------
    input  wire [31:0] snoop_addr,      // Address of the write transaction
    input  wire        snoop_wr_valid,  // 1-cycle pulse when write is committed

    // -------------------------------------------------------------------------
    // Mastership indicator: which core originated the write?
    // This prevents a core from invalidating its OWN cache.
    // Grant ID from the crossbar arbiter identifies the writing master.
    // -------------------------------------------------------------------------
    input  wire [1:0]  write_master_id, // 0=CPU0, 1=CPU1, 2=DMA

    // -------------------------------------------------------------------------
    // L1 D-Cache Snoop Interfaces (one pair per core)
    // -------------------------------------------------------------------------
    // To CPU0's L1 D-Cache
    output reg  [31:0] c0_snoop_addr,
    output reg         c0_snoop_inval,  // 1-cycle: invalidate this address in C0
    input  wire        c0_snoop_hit,    // C0 had this line
    input  wire        c0_snoop_dirty,  // C0's copy was dirty (may need WB)

    // To CPU1's L1 D-Cache
    output reg  [31:0] c1_snoop_addr,
    output reg         c1_snoop_inval,  // 1-cycle: invalidate this address in C1
    input  wire        c1_snoop_hit,    // C1 had this line
    input  wire        c1_snoop_dirty,  // C1's copy was dirty

    // -------------------------------------------------------------------------
    // To L1 I-Caches (instruction cache snooping — for self-modifying code)
    // Normally inactive; needed only if code is written to instruction memory.
    // -------------------------------------------------------------------------
    output reg  [31:0] i0_snoop_addr,
    output reg         i0_snoop_inval,  // Invalidate instruction line in Core 0
    output reg  [31:0] i1_snoop_addr,
    output reg         i1_snoop_inval,  // Invalidate instruction line in Core 1

    // -------------------------------------------------------------------------
    // Status / Debug
    // -------------------------------------------------------------------------
    output reg [31:0] coherency_event_count  // Total invalidation events (debug counter)
);

    // =========================================================================
    // Snoop Pipeline — registered 1 cycle for timing closure
    // The crossbar outputs snoop_wr_valid in the cycle of AW acceptance.
    // We pipeline it 1 cycle before acting to give snoop_addr time to stabilize.
    // =========================================================================
    reg [31:0] snoop_addr_r;
    reg        snoop_valid_r;
    reg [1:0]  write_master_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            snoop_addr_r    <= 32'b0;
            snoop_valid_r   <= 1'b0;
            write_master_r  <= 2'b0;
        end else begin
            snoop_addr_r   <= snoop_addr;
            snoop_valid_r  <= snoop_wr_valid;
            write_master_r <= write_master_id;
        end
    end

    // =========================================================================
    // Coherency Action Logic
    //
    // On each write transaction:
    //   - Determine which cores are NOT the writer (they may have stale copies)
    //   - Issue invalidation to all non-writer L1 D-caches
    //   - Issue invalidation to both I-caches (self-modifying code safety)
    //     only if the address is in instruction memory range
    // =========================================================================

    // Is the written address in instruction memory? (self-modifying code check)
    wire is_imem_addr = (snoop_addr_r >= 32'h0000_1000) && (snoop_addr_r <= 32'h0000_4FFF);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c0_snoop_addr      <= 32'b0;
            c0_snoop_inval     <= 1'b0;
            c1_snoop_addr      <= 32'b0;
            c1_snoop_inval     <= 1'b0;
            i0_snoop_addr      <= 32'b0;
            i0_snoop_inval     <= 1'b0;
            i1_snoop_addr      <= 32'b0;
            i1_snoop_inval     <= 1'b0;
            coherency_event_count <= 32'b0;
        end else begin
            // Default: de-assert all invalidation signals
            c0_snoop_inval <= 1'b0;
            c1_snoop_inval <= 1'b0;
            i0_snoop_inval <= 1'b0;
            i1_snoop_inval <= 1'b0;

            if (snoop_valid_r) begin
                // Increment debug event counter
                coherency_event_count <= coherency_event_count + 32'd1;

                // ---------------------------------------------------------------
                // D-Cache Invalidation:
                //   If CPU0 wrote (master=0): invalidate CPU1's D-cache
                //   If CPU1 wrote (master=1): invalidate CPU0's D-cache
                //   If DMA  wrote (master=2): invalidate BOTH D-caches
                //     (DMA writes are not associated with any core's cache)
                // ---------------------------------------------------------------
                case (write_master_r)
                    `MASTER_CPU0: begin
                        // CPU0 wrote → invalidate CPU1's D-cache
                        c1_snoop_addr  <= snoop_addr_r;
                        c1_snoop_inval <= 1'b1;
                    end
                    `MASTER_CPU1: begin
                        // CPU1 wrote → invalidate CPU0's D-cache
                        c0_snoop_addr  <= snoop_addr_r;
                        c0_snoop_inval <= 1'b1;
                    end
                    `MASTER_DMA: begin
                        // DMA wrote → invalidate BOTH D-caches
                        c0_snoop_addr  <= snoop_addr_r;
                        c0_snoop_inval <= 1'b1;
                        c1_snoop_addr  <= snoop_addr_r;
                        c1_snoop_inval <= 1'b1;
                    end
                    default: ;
                endcase

                // ---------------------------------------------------------------
                // I-Cache Invalidation (self-modifying code):
                //   Any write to instruction memory space must invalidate both
                //   I-caches, because a CPU may have cached the old instruction.
                //   This is rare but required for correctness.
                // ---------------------------------------------------------------
                if (is_imem_addr) begin
                    i0_snoop_addr  <= snoop_addr_r;
                    i0_snoop_inval <= 1'b1;
                    i1_snoop_addr  <= snoop_addr_r;
                    i1_snoop_inval <= 1'b1;
                end
            end
        end
    end

endmodule
