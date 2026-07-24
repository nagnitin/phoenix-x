// =============================================================================
// Module      : l1_icache
// Project     : Phoenix-X Heterogeneous SoC
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : 4KB Direct-Mapped L1 Instruction Cache.
//               One instance per CPU core (cpu_core_wrapper instantiates 2).
//
// Specification:
//   Capacity    : 4096 bytes
//   Associativity: Direct-mapped (1 way)
//   Line size   : 32 bytes (8 × 32-bit words)
//   Lines total : 128
//   Tag width   : 20 bits  (addr[31:12])
//   Index width :  7 bits  (addr[11:5])
//   Word offset :  3 bits  (addr[4:2])
//   Write policy: Read-only (instruction fetch never writes to I-cache)
//
// WHY DIRECT-MAPPED?
//   Instruction streams are sequential with highly predictable access patterns.
//   Direct-mapped caches have zero tag comparison overhead (1 tag per set),
//   giving the shortest critical path for hit detection. The conflict miss rate
//   (the main drawback of direct-mapped) is low for typical instruction workloads.
//   2-way set-associativity is not justified for instruction caches at this size.
//
// TIMING MODEL (1-cycle hit path matches existing cpu_core memory timing):
//   T=0 (posedge cpu_clk): cpu_core presents new imem_addr
//   T=0→T=1: BRAM read completes (registered output, 1-cycle latency)
//   T=1 (posedge cpu_clk): Tag comparison result available
//     HIT:  imem_rdata is valid → cpu_core proceeds normally
//     MISS: assert `miss` → BUFGCE in cpu_core_wrapper freezes cpu_clk
//           Fill FSM runs on sys_clk (ungated), fetches 8 words via AXI
//           After fill: de-assert `miss` → cpu_clk resumes → hit on next cycle
//
// Memory Layout:
//   Data BRAM: 1024 words × 32 bits (Vivado infers RAMB36E1)
//     Address: {index[6:0], word_offset[2:0]} = 10 bits
//   Tag  RAM : 128 entries × 21 bits (tag[19:0] + valid[0])
//     Synthesized as LUTRAM (small enough, faster than BRAM)
//
// AXI Master Interface (for cache line fills):
//   AXI-4 Lite, single-word transfers.
//   To fill a 32-byte (8-word) line, 8 sequential AXI read transactions
//   are issued to consecutive addresses.
//   (AXI-4 Full burst would be ideal; Phase 2 upgrade.)
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module l1_icache (
    // -------------------------------------------------------------------------
    // Clock Ports:
    //   sys_clk  — always-running 100 MHz system clock (for FSM and AXI)
    //   cpu_clk  — gated clock from BUFGCE (frozen during miss)
    // -------------------------------------------------------------------------
    input  wire        sys_clk,
    input  wire        cpu_clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // CPU Interface (synchronous to cpu_clk)
    // -------------------------------------------------------------------------
    input  wire [31:0] cpu_addr,     // Instruction fetch address (from PC)
    output reg  [31:0] cpu_rdata,    // Instruction word to cpu_core
    output wire        miss,         // 1 = miss detected; cpu_clk frozen

    // -------------------------------------------------------------------------
    // AXI-4 Lite Master Port (synchronous to sys_clk) — for cache line fills
    // -------------------------------------------------------------------------
    // Read Address Channel
    output reg  [31:0] axi_ar_addr,
    output reg         axi_ar_valid,
    input  wire        axi_ar_ready,
    // Read Data Channel
    input  wire [31:0] axi_r_data,
    input  wire [ 1:0] axi_r_resp,
    input  wire        axi_r_valid,
    output reg         axi_r_ready,
    // (No write channels — instruction cache is read-only)

    // -------------------------------------------------------------------------
    // Snoop Invalidation Interface (from cache_coherency controller)
    // When coherency controller detects a remote write to an address in this
    // cache, it sends an invalidation pulse.
    // -------------------------------------------------------------------------
    input  wire [31:0] snoop_addr,
    input  wire        snoop_inval   // 1-cycle pulse: invalidate line containing snoop_addr
);

    // =========================================================================
    // Cache Storage Arrays
    // =========================================================================

    // Tag RAM (128 entries, 21 bits each: valid[20] + tag[19:0])
    // Synchronous write, synchronous read → Vivado infers Block RAM or LUTRAM
    // We use LUTRAM here (sync write, async read) for 1-cycle tag check
    reg [20:0] tag_ram [0:127];   // [20]=valid, [19:0]=tag bits

    // Data RAM (1024 words × 32 bits → Vivado infers RAMB36E1 block RAM)
    // Synchronous write, synchronous read (1-cycle latency)
    reg [31:0] data_ram [0:1023];

    // =========================================================================
    // Address Field Extraction
    // =========================================================================
    wire [19:0] cpu_tag    = cpu_addr[31:12];  // 20-bit tag
    wire [ 6:0] cpu_index  = cpu_addr[11:5];   // 7-bit line index (0–127)
    wire [ 2:0] cpu_word   = cpu_addr[4:2];    // 3-bit word offset within line

    // Full address of the cache line base (byte-aligned, lower 5 bits zeroed)
    wire [31:0] line_base_addr = {cpu_addr[31:5], 5'b0};

    // =========================================================================
    // Registered Address Pipeline (for BRAM output timing alignment)
    // cpu_addr registered 1 cycle → tag_ram reads on reg'd index → compare
    // =========================================================================
    reg [31:0] cpu_addr_r;   // Registered address (one cpu_clk cycle after cpu_addr)
    always @(posedge cpu_clk or negedge rst_n) begin
        if (!rst_n) cpu_addr_r <= 32'b0;
        else        cpu_addr_r <= cpu_addr;
    end

    wire [19:0] tag_r   = cpu_addr_r[31:12];
    wire [ 6:0] idx_r   = cpu_addr_r[11:5];
    wire [ 2:0] word_r  = cpu_addr_r[4:2];

    // =========================================================================
    // Tag RAM Read (combinational / synchronous-write)
    // =========================================================================
    wire [20:0] tag_entry   = tag_ram[idx_r];      // Async read on registered index
    wire        cached_valid = tag_entry[20];
    wire [19:0] cached_tag  = tag_entry[19:0];
    wire        tag_hit     = cached_valid & (cached_tag == tag_r);

    // =========================================================================
    // Data RAM Read (synchronous, 1-cycle latency)
    // =========================================================================
    reg [31:0] data_ram_out;
    always @(posedge cpu_clk) begin
        data_ram_out <= data_ram[{idx_r, word_r}];
    end

    // =========================================================================
    // Miss Detection FSM
    // FSM runs on sys_clk (ungated) so it can operate when cpu_clk is frozen.
    // States: IDLE → FETCH (8 AXI reads) → FILL → DONE
    // =========================================================================
    localparam ST_IDLE  = 2'd0;  // Hit or waiting for new request
    localparam ST_FETCH = 2'd1;  // Issuing AXI read for one word of the miss line
    localparam ST_FILL  = 2'd2;  // Receiving and writing fetched word to data_ram
    localparam ST_DONE  = 2'd3;  // Line filled; de-assert miss for 1 cycle

    reg  [1:0] state;
    reg        miss_r;     // Registered miss (drives BUFGCE CE)
    reg  [2:0] fill_word;  // Which word in the line is being fetched (0–7)
    reg [31:0] fetch_base; // Base address of miss line (latched from cpu_addr_r)

    // miss output — high as long as the FSM is in FETCH or FILL state
    assign miss = miss_r;

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            miss_r     <= 1'b0;
            fill_word  <= 3'd0;
            fetch_base <= 32'b0;
            axi_ar_valid <= 1'b0;
            axi_ar_addr  <= 32'b0;
            axi_r_ready  <= 1'b0;
        end else begin
            case (state)

                ST_IDLE: begin
                    axi_ar_valid <= 1'b0;
                    axi_r_ready  <= 1'b0;
                    if (!tag_hit && cached_valid !== 1'bx) begin
                        // Miss detected: latch the miss address and start fill
                        miss_r     <= 1'b1;
                        fetch_base <= {cpu_addr_r[31:5], 5'b0}; // line-aligned
                        fill_word  <= 3'd0;
                        state      <= ST_FETCH;
                    end
                    // else: HIT — data_ram_out is the instruction; stay IDLE
                end

                ST_FETCH: begin
                    // Issue AXI read for word fill_word of the miss line
                    axi_ar_addr  <= fetch_base + {29'b0, fill_word, 2'b00};
                    axi_ar_valid <= 1'b1;
                    axi_r_ready  <= 1'b0;
                    if (axi_ar_valid && axi_ar_ready) begin
                        // Address accepted by slave — wait for data
                        axi_ar_valid <= 1'b0;
                        axi_r_ready  <= 1'b1;
                        state        <= ST_FILL;
                    end
                end

                ST_FILL: begin
                    if (axi_r_valid && axi_r_ready) begin
                        // Write fetched word into data RAM
                        data_ram[{fetch_base[11:5], fill_word}] <= axi_r_data;

                        if (fill_word == 3'd7) begin
                            // All 8 words filled — update tag RAM and release miss
                            tag_ram[fetch_base[11:5]] <= {1'b1, fetch_base[31:12]};
                            miss_r    <= 1'b0;
                            axi_r_ready <= 1'b0;
                            state     <= ST_DONE;
                        end else begin
                            // Fetch next word
                            fill_word    <= fill_word + 3'd1;
                            axi_r_ready  <= 1'b0;
                            state        <= ST_FETCH;
                        end
                    end
                end

                ST_DONE: begin
                    // One cycle delay: let cpu_clk resume before going back to IDLE
                    // The next cpu_clk posedge will see a tag hit
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // =========================================================================
    // CPU Read Data Output (registered on cpu_clk to match 1-cycle memory model)
    // =========================================================================
    always @(posedge cpu_clk) begin
        if (!rst_n)
            cpu_rdata <= 32'b0;
        else if (tag_hit)
            cpu_rdata <= data_ram_out;
        // On miss, cpu_rdata is stale but cpu_clk is frozen so cpu_core doesn't see it
    end

    // =========================================================================
    // Snoop Invalidation (from cache coherency controller)
    // When another core writes an address that maps to a line in this cache,
    // the coherency controller sends a 1-cycle snoop_inval pulse.
    // We invalidate by clearing the valid bit in tag_ram.
    // =========================================================================
    wire [ 6:0] snoop_idx = snoop_addr[11:5];

    always @(posedge sys_clk) begin
        if (snoop_inval) begin
            // Clear valid bit of the snooped cache line
            tag_ram[snoop_idx][20] <= 1'b0;
        end
    end

    // =========================================================================
    // Initialization (for simulation — pre-invalidate all lines)
    // =========================================================================
    integer ii;
    initial begin
        for (ii = 0; ii < 128; ii = ii + 1)
            tag_ram[ii] = 21'b0;   // valid=0, tag=0
        for (ii = 0; ii < 1024; ii = ii + 1)
            data_ram[ii] = 32'b0;
        state        = ST_IDLE;
        miss_r       = 1'b0;
        axi_ar_valid = 1'b0;
        axi_r_ready  = 1'b0;
    end

endmodule
