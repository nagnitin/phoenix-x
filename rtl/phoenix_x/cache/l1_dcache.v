// =============================================================================
// Module      : l1_dcache
// Project     : Phoenix-X Heterogeneous SoC
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : 4KB 2-Way Set-Associative L1 Data Cache with MESI coherency.
//               One instance per CPU core.
//
// Specification:
//   Capacity    : 4096 bytes
//   Associativity: 2-way set-associative
//   Sets        : 64
//   Ways        : 2 (way 0 and way 1)
//   Line size   : 32 bytes (8 × 32-bit words)
//   Tag width   : 21 bits  (addr[31:11])
//   Index width :  6 bits  (addr[10:5])
//   Word offset :  3 bits  (addr[4:2])
//   Write policy: Write-back + Write-allocate
//   Replacement : LRU (1-bit pseudo-LRU per set)
//   Coherency   : MESI (2-bit state per cache line)
//
// WHY 2-WAY SET-ASSOCIATIVE (not direct-mapped)?
//   Data caches suffer higher conflict miss rates than instruction caches due
//   to irregular access patterns (stack, heap, global variables). A 2-way SA
//   cache reduces conflict misses by ~2× at the cost of one additional tag
//   comparison per access. On Artix-7, this comparison runs in LUTs and adds
//   ~0.5 ns to the critical path — acceptable at 100 MHz (10 ns budget).
//
// WHY WRITE-BACK (not write-through)?
//   Write-through sends every store to the AXI bus, saturating the shared
//   interconnect. With 2 cores and a DMA, bus contention is the main bottleneck.
//   Write-back only touches the bus on eviction (one bus transaction per dirty
//   line), dramatically reducing bus utilization under store-heavy workloads.
//
// MESI States (2 bits per line):
//   INVALID   (00): Line not present → any access triggers miss
//   SHARED    (01): Clean copy; another core may also have it → no write-back needed on eviction
//   EXCLUSIVE (10): Clean copy; sole owner → can transition to MODIFIED on write locally
//   MODIFIED  (11): Dirty copy; must write-back before eviction or on remote read
//
// TIMING MODEL: Same as l1_icache — 1-cycle hit on cpu_clk, BUFGCE freeze on miss.
//
// Data RAM Storage (Vivado infers RAMB36E1):
//   Way 0: 64 sets × 8 words = 512 words × 32 bits
//   Way 1: 64 sets × 8 words = 512 words × 32 bits
// Tag RAM Storage (LUTRAM):
//   Way 0: 64 entries × (21 tag + 2 MESI + 1 LRU) = 64 × 24 bits
//   Way 1: 64 entries × (21 tag + 2 MESI + 1 LRU) = 64 × 24 bits
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module l1_dcache (
    input  wire        sys_clk,    // Always-running system clock (FSM + AXI)
    input  wire        cpu_clk,    // Gated clock to cpu_core (frozen on miss)
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // CPU Data Interface (synchronous to cpu_clk)
    // -------------------------------------------------------------------------
    input  wire [31:0] cpu_addr,    // Data memory byte address
    input  wire [31:0] cpu_wdata,   // Write data from cpu_core
    input  wire        cpu_we,      // Write enable (store instruction)
    input  wire        cpu_re,      // Read enable (load instruction)
    input  wire [ 3:0] cpu_be,      // Byte enables for partial writes
    output reg  [31:0] cpu_rdata,   // Read data to cpu_core
    output wire        miss,        // 1 = cache miss; cpu_clk will be frozen

    // -------------------------------------------------------------------------
    // AXI-4 Lite Master Interface (synchronous to sys_clk) — for fills & write-backs
    // -------------------------------------------------------------------------
    // Read Address Channel (cache line fill on read miss)
    output reg  [31:0] axi_ar_addr,
    output reg         axi_ar_valid,
    input  wire        axi_ar_ready,
    // Read Data Channel
    input  wire [31:0] axi_r_data,
    input  wire [ 1:0] axi_r_resp,
    input  wire        axi_r_valid,
    output reg         axi_r_ready,
    // Write Address Channel (dirty line eviction)
    output reg  [31:0] axi_aw_addr,
    output reg         axi_aw_valid,
    input  wire        axi_aw_ready,
    // Write Data Channel
    output reg  [31:0] axi_w_data,
    output reg  [ 3:0] axi_w_strb,
    output reg         axi_w_valid,
    input  wire        axi_w_ready,
    // Write Response Channel
    input  wire [ 1:0] axi_b_resp,
    input  wire        axi_b_valid,
    output reg         axi_b_ready,

    // -------------------------------------------------------------------------
    // Snoop Interface (from cache_coherency controller)
    // -------------------------------------------------------------------------
    input  wire [31:0] snoop_addr,   // Address of remote write (from other core)
    input  wire        snoop_inval,  // 1-cycle: invalidate line at snoop_addr
    output reg         snoop_hit,    // This cache has the snooped line
    output reg         snoop_dirty,  // The held line is dirty (coherency WB needed)

    // -------------------------------------------------------------------------
    // This core's ID (used to tag MESI state: if 0, CPU0 cache; if 1, CPU1 cache)
    // -------------------------------------------------------------------------
    input  wire        core_id       // 0 = CPU0, 1 = CPU1
);

    // =========================================================================
    // Cache Storage Arrays
    // =========================================================================

    // Tag RAM — LUTRAM (synchronous write, asynchronous read for 0-cycle tag check)
    // Format per entry [23:0]: {lru[23], mesi[22:21], tag[20:0]}
    // lru  : 0 = way 0 was last used; 1 = way 1 was last used
    // mesi : 2-bit MESI state
    // tag  : 21-bit address tag
    reg [23:0] tag_ram_w0 [0:63];   // Way 0 tags
    reg [23:0] tag_ram_w1 [0:63];   // Way 1 tags

    // Data RAM — BRAM (synchronous read, 1-cycle latency)
    // Way 0: 512 words (64 sets × 8 words/line)
    // Way 1: 512 words (64 sets × 8 words/line)
    reg [31:0] data_ram_w0 [0:511];
    reg [31:0] data_ram_w1 [0:511];

    // =========================================================================
    // Address Field Extraction
    // =========================================================================
    wire [20:0] cpu_tag   = cpu_addr[31:11];  // 21-bit tag
    wire [ 5:0] cpu_index = cpu_addr[10:5];   // 6-bit set index (0–63)
    wire [ 2:0] cpu_word  = cpu_addr[4:2];    // 3-bit word select within line

    // =========================================================================
    // Registered Address (for BRAM 1-cycle read alignment)
    // =========================================================================
    reg [31:0] cpu_addr_r;
    reg [31:0] cpu_wdata_r;
    reg        cpu_we_r, cpu_re_r;
    reg [ 3:0] cpu_be_r;

    always @(posedge cpu_clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_addr_r  <= 32'b0;
            cpu_wdata_r <= 32'b0;
            cpu_we_r    <= 1'b0;
            cpu_re_r    <= 1'b0;
            cpu_be_r    <= 4'b0;
        end else begin
            cpu_addr_r  <= cpu_addr;
            cpu_wdata_r <= cpu_wdata;
            cpu_we_r    <= cpu_we;
            cpu_re_r    <= cpu_re;
            cpu_be_r    <= cpu_be;
        end
    end

    wire [20:0] tag_r   = cpu_addr_r[31:11];
    wire [ 5:0] idx_r   = cpu_addr_r[10:5];
    wire [ 2:0] word_r  = cpu_addr_r[4:2];

    // =========================================================================
    // Tag Check — combinational on registered address (LUTRAM async read)
    // =========================================================================
    wire [23:0] entry_w0  = tag_ram_w0[idx_r];
    wire [23:0] entry_w1  = tag_ram_w1[idx_r];

    wire [ 1:0] mesi_w0   = entry_w0[22:21];
    wire [20:0] stored_tag_w0 = entry_w0[20:0];
    wire [ 1:0] mesi_w1   = entry_w1[22:21];
    wire [20:0] stored_tag_w1 = entry_w1[20:0];

    wire valid_w0 = (mesi_w0 != `MESI_INVALID);
    wire valid_w1 = (mesi_w1 != `MESI_INVALID);

    wire hit_w0 = valid_w0 & (stored_tag_w0 == tag_r);
    wire hit_w1 = valid_w1 & (stored_tag_w1 == tag_r);
    wire cache_hit = hit_w0 | hit_w1;

    // Which way hit?
    wire hit_way = hit_w1;  // 0=way0 hit, 1=way1 hit (only valid if cache_hit)

    // LRU: bit 23 of way 0 entry (shared across both ways, stored in way 0 entry)
    wire lru_bit = entry_w0[23];  // 0=way0 MRU (evict way1), 1=way1 MRU (evict way0)
    wire evict_way = lru_bit;     // Way to evict on miss

    // =========================================================================
    // Data RAM Read (synchronous, 1-cycle latency on cpu_clk)
    // =========================================================================
    reg [31:0] data_w0_out, data_w1_out;
    always @(posedge cpu_clk) begin
        data_w0_out <= data_ram_w0[{idx_r, word_r}];
        data_w1_out <= data_ram_w1[{idx_r, word_r}];
    end

    // =========================================================================
    // Miss Detection and Output (on cpu_clk domain)
    // =========================================================================
    reg miss_r;
    assign miss = miss_r;

    always @(posedge cpu_clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_rdata <= 32'b0;
        end else begin
            if (cpu_re_r && cache_hit) begin
                cpu_rdata <= hit_w0 ? data_w0_out : data_w1_out;
            end
        end
    end

    // =========================================================================
    // MESI Write Hit (on cpu_clk domain — write directly into cache)
    // No AXI transaction needed; line transitions to MODIFIED.
    // =========================================================================
    integer wb;
    always @(posedge cpu_clk) begin
        if (cpu_we_r && cache_hit) begin
            if (hit_w0) begin
                // Apply byte enables
                for (wb = 0; wb < 4; wb = wb + 1)
                    if (cpu_be_r[wb])
                        data_ram_w0[{idx_r, word_r}][wb*8 +: 8] <= cpu_wdata_r[wb*8 +: 8];
                // Transition to MODIFIED, update LRU
                tag_ram_w0[idx_r] <= {1'b0, `MESI_MODIFIED, tag_r}; // LRU=0 (way0 MRU)
                tag_ram_w1[idx_r][23] <= 1'b0;  // update LRU in way1 entry too
            end else begin  // hit_w1
                for (wb = 0; wb < 4; wb = wb + 1)
                    if (cpu_be_r[wb])
                        data_ram_w1[{idx_r, word_r}][wb*8 +: 8] <= cpu_wdata_r[wb*8 +: 8];
                tag_ram_w1[idx_r] <= {1'b1, `MESI_MODIFIED, tag_r}; // LRU=1 (way1 MRU)
                tag_ram_w0[idx_r][23] <= 1'b1;
            end
        end
    end

    // =========================================================================
    // Miss Handling FSM (runs on sys_clk — ungated)
    // States: IDLE → WB_ADDR → WB_DATA → WB_RESP → FILL_ADDR → FILL_DATA → DONE
    //   WB_*   : Write-back the dirty evicted line (if MODIFIED)
    //   FILL_* : Fetch 8 words for the new line from L2/DRAM
    // =========================================================================
    localparam ST_IDLE      = 3'd0;
    localparam ST_WB_ADDR   = 3'd1;  // Issue AXI write address for dirty eviction
    localparam ST_WB_DATA   = 3'd2;  // Issue AXI write data (one word at a time)
    localparam ST_WB_RESP   = 3'd3;  // Wait for AXI write response
    localparam ST_FILL_ADDR = 3'd4;  // Issue AXI read address for cache line fill
    localparam ST_FILL_DATA = 3'd5;  // Receive and store fetched word
    localparam ST_DONE      = 3'd6;  // Line filled; release miss

    reg [2:0] fstate;
    reg [2:0] fill_word;   // Word counter for 8-word line fill (0–7)
    reg [31:0] fetch_base; // Line-aligned base address of the miss
    reg [31:0] evict_base; // Line-aligned address of the evicted dirty line
    reg        evict_dirty;// 1 = evicted line is dirty (needs write-back)
    reg [ 1:0] evict_mesi; // MESI state of the line being evicted

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            fstate       <= ST_IDLE;
            miss_r       <= 1'b0;
            fill_word    <= 3'd0;
            fetch_base   <= 32'b0;
            evict_base   <= 32'b0;
            evict_dirty  <= 1'b0;
            axi_ar_valid <= 1'b0;
            axi_ar_addr  <= 32'b0;
            axi_r_ready  <= 1'b0;
            axi_aw_valid <= 1'b0;
            axi_aw_addr  <= 32'b0;
            axi_w_valid  <= 1'b0;
            axi_w_data   <= 32'b0;
            axi_w_strb   <= 4'hF;
            axi_b_ready  <= 1'b0;
        end else begin
            case (fstate)

                ST_IDLE: begin
                    axi_ar_valid <= 1'b0;
                    axi_aw_valid <= 1'b0;
                    axi_w_valid  <= 1'b0;
                    axi_b_ready  <= 1'b0;
                    axi_r_ready  <= 1'b0;

                    if ((cpu_re_r || cpu_we_r) && !cache_hit) begin
                        // Miss! Latch addresses
                        miss_r     <= 1'b1;
                        fetch_base <= {cpu_addr_r[31:5], 5'b0};
                        fill_word  <= 3'd0;

                        // Determine eviction candidate
                        if (evict_way == 1'b0) begin
                            evict_base  <= {stored_tag_w0, idx_r, 5'b0};
                            evict_dirty <= (mesi_w0 == `MESI_MODIFIED);
                        end else begin
                            evict_base  <= {stored_tag_w1, idx_r, 5'b0};
                            evict_dirty <= (mesi_w1 == `MESI_MODIFIED);
                        end

                        // If evict line is dirty, write it back first
                        if ((evict_way ? (mesi_w1 == `MESI_MODIFIED) : (mesi_w0 == `MESI_MODIFIED)) &&
                            (evict_way ? valid_w1 : valid_w0)) begin
                            fstate <= ST_WB_ADDR;
                        end else begin
                            fstate <= ST_FILL_ADDR;
                        end
                    end
                end

                ST_WB_ADDR: begin
                    // Issue AXI write address for the dirty line being evicted
                    axi_aw_addr  <= evict_base + {29'b0, fill_word, 2'b00};
                    axi_aw_valid <= 1'b1;
                    if (axi_aw_valid && axi_aw_ready) begin
                        axi_aw_valid <= 1'b0;
                        fstate       <= ST_WB_DATA;
                    end
                end

                ST_WB_DATA: begin
                    // Issue AXI write data (evicted line word by word)
                    axi_w_data  <= evict_way ?
                                   data_ram_w1[{evict_base[10:5], fill_word}] :
                                   data_ram_w0[{evict_base[10:5], fill_word}];
                    axi_w_strb  <= 4'hF;
                    axi_w_valid <= 1'b1;
                    if (axi_w_valid && axi_w_ready) begin
                        axi_w_valid <= 1'b0;
                        fstate      <= ST_WB_RESP;
                    end
                end

                ST_WB_RESP: begin
                    axi_b_ready <= 1'b1;
                    if (axi_b_valid && axi_b_ready) begin
                        axi_b_ready <= 1'b0;
                        if (fill_word == 3'd7) begin
                            // All 8 words written back — now fetch new line
                            fill_word <= 3'd0;
                            fstate    <= ST_FILL_ADDR;
                        end else begin
                            fill_word <= fill_word + 3'd1;
                            fstate    <= ST_WB_ADDR;
                        end
                    end
                end

                ST_FILL_ADDR: begin
                    // Issue AXI read for new line fill
                    axi_ar_addr  <= fetch_base + {29'b0, fill_word, 2'b00};
                    axi_ar_valid <= 1'b1;
                    axi_r_ready  <= 1'b0;
                    if (axi_ar_valid && axi_ar_ready) begin
                        axi_ar_valid <= 1'b0;
                        axi_r_ready  <= 1'b1;
                        fstate       <= ST_FILL_DATA;
                    end
                end

                ST_FILL_DATA: begin
                    if (axi_r_valid && axi_r_ready) begin
                        axi_r_ready <= 1'b0;
                        // Write fetched word to the eviction-target way
                        if (evict_way == 1'b0)
                            data_ram_w0[{fetch_base[10:5], fill_word}] <= axi_r_data;
                        else
                            data_ram_w1[{fetch_base[10:5], fill_word}] <= axi_r_data;

                        if (fill_word == 3'd7) begin
                            // Full line loaded — update tag to EXCLUSIVE
                            // (EXCLUSIVE because we're the sole owner after fill)
                            if (evict_way == 1'b0) begin
                                tag_ram_w0[fetch_base[10:5]] <= {1'b0, `MESI_EXCLUSIVE, fetch_base[31:11]};
                            end else begin
                                tag_ram_w1[fetch_base[10:5]] <= {1'b1, `MESI_EXCLUSIVE, fetch_base[31:11]};
                            end
                            miss_r <= 1'b0;
                            fstate <= ST_DONE;
                        end else begin
                            fill_word <= fill_word + 3'd1;
                            fstate    <= ST_FILL_ADDR;
                        end
                    end
                end

                ST_DONE: begin
                    // One-cycle delay before returning to IDLE (let cpu_clk resume)
                    fstate <= ST_IDLE;
                end

                default: fstate <= ST_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Snoop Interface (from cache_coherency controller, sys_clk domain)
    // When another core writes to an address this cache holds, invalidate it.
    // Also report if the line is dirty (so coherency controller can WB first).
    // =========================================================================
    wire [ 5:0] snoop_idx   = snoop_addr[10:5];
    wire [20:0] snoop_tag   = snoop_addr[31:11];

    wire snoop_hit_w0 = (mesi_w0 != `MESI_INVALID) && (tag_ram_w0[snoop_idx][20:0] == snoop_tag);
    wire snoop_hit_w1 = (mesi_w1 != `MESI_INVALID) && (tag_ram_w1[snoop_idx][20:0] == snoop_tag);

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            snoop_hit   <= 1'b0;
            snoop_dirty <= 1'b0;
        end else if (snoop_inval) begin
            snoop_hit   <= snoop_hit_w0 | snoop_hit_w1;
            snoop_dirty <= (snoop_hit_w0 && (tag_ram_w0[snoop_idx][22:21] == `MESI_MODIFIED)) |
                           (snoop_hit_w1 && (tag_ram_w1[snoop_idx][22:21] == `MESI_MODIFIED));
            // Invalidate the matching way
            if (snoop_hit_w0)
                tag_ram_w0[snoop_idx][22:21] <= `MESI_INVALID;
            if (snoop_hit_w1)
                tag_ram_w1[snoop_idx][22:21] <= `MESI_INVALID;
        end else begin
            snoop_hit   <= 1'b0;
            snoop_dirty <= 1'b0;
        end
    end

    // =========================================================================
    // Initialization
    // =========================================================================
    integer ii;
    initial begin
        for (ii = 0; ii < 64; ii = ii + 1) begin
            tag_ram_w0[ii] = 24'b0;  // MESI=INVALID, tag=0, lru=0
            tag_ram_w1[ii] = 24'b0;
        end
        for (ii = 0; ii < 512; ii = ii + 1) begin
            data_ram_w0[ii] = 32'b0;
            data_ram_w1[ii] = 32'b0;
        end
        miss_r       = 1'b0;
        fstate       = ST_IDLE;
        axi_ar_valid = 1'b0;
        axi_aw_valid = 1'b0;
        axi_w_valid  = 1'b0;
        axi_b_ready  = 1'b0;
        axi_r_ready  = 1'b0;
    end

endmodule
