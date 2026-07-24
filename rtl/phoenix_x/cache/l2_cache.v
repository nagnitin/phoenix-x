// =============================================================================
// Module      : l2_cache
// Project     : Phoenix-X Heterogeneous SoC
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : 32KB 4-Way Set-Associative Shared L2 Cache.
//               Sits between both L1 caches and main DRAM on the AXI bus.
//               Acts as AXI SLAVE toward L1 caches (receives fill requests)
//               and AXI MASTER toward DRAM (issues main-memory accesses).
//
// Specification:
//   Capacity    : 32768 bytes
//   Associativity: 4-way set-associative
//   Sets        : 128
//   Ways        : 4 (way 0–3)
//   Line size   : 64 bytes (16 × 32-bit words)
//   Tag width   : 19 bits  (addr[31:13])
//   Index width :  7 bits  (addr[12:6])
//   Word offset :  4 bits  (addr[5:2])
//   Write policy: Write-back
//   Replacement : Tree-based Pseudo-LRU (3 bits per set for 4 ways)
//
// WHY 4-WAY SET-ASSOCIATIVE?
//   L2 caches serve as victims for L1 misses. With 4-way SA, the probability
//   that an L1 evicted line can be re-found in L2 is dramatically higher than
//   with direct-mapped or 2-way. 4-way is the standard (Intel Sandy Bridge L2,
//   ARM Cortex-A55 L2) for this capacity range. The pseudo-LRU replacement
//   approximates true LRU at a fraction of the hardware cost.
//
// WHY LARGER LINE SIZE (64 bytes) FOR L2?
//   L2 prefetches spatial locality: when L1 misses on word X, L2 fetches the
//   full 64-byte block. This fills L1's 32-byte line AND pre-populates the
//   neighboring 32-byte line into L2. The result is 2× reduction in DRAM
//   accesses for sequential workloads (arrays, DMA buffers, code segments).
//
// Pseudo-LRU Tree (3 bits per set for 4 ways):
//   Bit layout:  [2] [1] [0]
//   Tree:
//         [2]
//        /    \
//      [1]    [0]
//     /   \  /   \
//    W0   W1 W2   W3
//   bit=0 → point LEFT (lower-numbered way)
//   bit=1 → point RIGHT (higher-numbered way)
//   Evict: follow pointers to a leaf
//   Update: on access to Wn, flip bits on the path FROM root TO Wn
//
// AXI Interface Summary:
//   Slave port  (s_*): Receives L1 cache-fill requests (AXI-4 Lite master → L2)
//   Master port (m_*): Issues DRAM fill requests on L2 miss (L2 → DRAM)
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module l2_cache (
    input  wire        clk,
    input  wire        rst_n,

    // =========================================================================
    // AXI-4 Lite Slave Port (from L1 cache fill requests)
    // =========================================================================
    // Write Address Channel (L1 write-back dirty line to L2)
    input  wire [31:0] s_aw_addr,
    input  wire        s_aw_valid,
    output reg         s_aw_ready,
    // Write Data Channel
    input  wire [31:0] s_w_data,
    input  wire [ 3:0] s_w_strb,
    input  wire        s_w_valid,
    output reg         s_w_ready,
    // Write Response Channel
    output reg  [ 1:0] s_b_resp,
    output reg         s_b_valid,
    input  wire        s_b_ready,
    // Read Address Channel (L1 fill request)
    input  wire [31:0] s_ar_addr,
    input  wire        s_ar_valid,
    output reg         s_ar_ready,
    // Read Data Channel (L2 → L1)
    output reg  [31:0] s_r_data,
    output reg  [ 1:0] s_r_resp,
    output reg         s_r_valid,
    input  wire        s_r_ready,

    // =========================================================================
    // AXI-4 Lite Master Port (to DRAM for L2 miss fill)
    // =========================================================================
    // Read Address Channel
    output reg  [31:0] m_ar_addr,
    output reg         m_ar_valid,
    input  wire        m_ar_ready,
    // Read Data Channel
    input  wire [31:0] m_r_data,
    input  wire [ 1:0] m_r_resp,
    input  wire        m_r_valid,
    output reg         m_r_ready,
    // Write Address Channel (L2 dirty eviction to DRAM)
    output reg  [31:0] m_aw_addr,
    output reg         m_aw_valid,
    input  wire        m_aw_ready,
    // Write Data Channel
    output reg  [31:0] m_w_data,
    output reg  [ 3:0] m_w_strb,
    output reg         m_w_valid,
    input  wire        m_w_ready,
    // Write Response Channel
    input  wire [ 1:0] m_b_resp,
    input  wire        m_b_valid,
    output reg         m_b_ready
);

    // =========================================================================
    // Cache Storage Arrays (Vivado will infer RAMB36E1 for data arrays)
    // =========================================================================

    // Tag arrays (128 sets × 4 ways, each 22 bits):
    //   [21]   = valid
    //   [20]   = dirty
    //   [19:0] ... wait, tag is 19 bits: addr[31:13]
    //   [21] = valid, [20] = dirty, [19:1] = tag bits [18:0], [0] unused → rethink:
    //   [21] = valid, [20] = dirty, [19:0] = tag[18:0] padded to 20 bits
    // Simpler: {valid(1), dirty(1), tag(19)} = 21 bits
    reg [20:0] tag_w0 [0:127];  // {valid[20], dirty[19], tag[18:0]}
    reg [20:0] tag_w1 [0:127];
    reg [20:0] tag_w2 [0:127];
    reg [20:0] tag_w3 [0:127];

    // Pseudo-LRU bits (3 bits per set)
    reg [ 2:0] lru_bits [0:127];

    // Data arrays: 128 sets × 4 ways × 16 words = 8192 words × 32 bits
    // Vivado will infer 4 RAMB36E1 (one per way, 2048 words each)
    reg [31:0] data_w0 [0:2047];  // 128 sets × 16 words
    reg [31:0] data_w1 [0:2047];
    reg [31:0] data_w2 [0:2047];
    reg [31:0] data_w3 [0:2047];

    // =========================================================================
    // Address Field Extraction (from slave port)
    // =========================================================================
    wire [18:0] ar_tag   = s_ar_addr[31:13];
    wire [ 6:0] ar_index = s_ar_addr[12:6];
    wire [ 3:0] ar_word  = s_ar_addr[5:2];

    wire [18:0] aw_tag   = s_aw_addr[31:13];
    wire [ 6:0] aw_index = s_aw_addr[12:6];
    wire [ 3:0] aw_word  = s_aw_addr[5:2];

    // =========================================================================
    // Tag Lookup (combinational on slave request)
    // =========================================================================
    wire tag_hit_w0 = tag_w0[ar_index][20] & (tag_w0[ar_index][18:0] == ar_tag);
    wire tag_hit_w1 = tag_w1[ar_index][20] & (tag_w1[ar_index][18:0] == ar_tag);
    wire tag_hit_w2 = tag_w2[ar_index][20] & (tag_w2[ar_index][18:0] == ar_tag);
    wire tag_hit_w3 = tag_w3[ar_index][20] & (tag_w3[ar_index][18:0] == ar_tag);
    wire l2_hit = tag_hit_w0 | tag_hit_w1 | tag_hit_w2 | tag_hit_w3;

    // Which way hit?
    wire [1:0] hit_way = tag_hit_w0 ? 2'd0 :
                         tag_hit_w1 ? 2'd1 :
                         tag_hit_w2 ? 2'd2 : 2'd3;

    // =========================================================================
    // Pseudo-LRU Eviction Way Selection
    // Tree: [2]=root, [1]=left subtree, [0]=right subtree
    //   Evict way 0 if lru[2]=0 & lru[1]=0
    //   Evict way 1 if lru[2]=0 & lru[1]=1
    //   Evict way 2 if lru[2]=1 & lru[0]=0
    //   Evict way 3 if lru[2]=1 & lru[0]=1
    // =========================================================================
    wire [2:0] lru = lru_bits[ar_index];
    wire [1:0] evict_way = (!lru[2] && !lru[1]) ? 2'd0 :
                           (!lru[2] &&  lru[1])  ? 2'd1 :
                           ( lru[2] && !lru[0])  ? 2'd2 : 2'd3;

    // Is evicted way dirty?
    wire evict_dirty = (evict_way == 2'd0) ? tag_w0[ar_index][19] :
                       (evict_way == 2'd1) ? tag_w1[ar_index][19] :
                       (evict_way == 2'd2) ? tag_w2[ar_index][19] : tag_w3[ar_index][19];

    // Evicted line's address tag (for write-back address)
    wire [18:0] evict_tag = (evict_way == 2'd0) ? tag_w0[ar_index][18:0] :
                             (evict_way == 2'd1) ? tag_w1[ar_index][18:0] :
                             (evict_way == 2'd2) ? tag_w2[ar_index][18:0] : tag_w3[ar_index][18:0];

    wire [31:0] evict_base_addr = {evict_tag, ar_index, 6'b0};

    // =========================================================================
    // Main FSM — processes both read (L1 fill) and write (L1 write-back) requests
    // =========================================================================
    localparam ST_IDLE       = 4'd0;
    localparam ST_RD_HIT     = 4'd1;  // L2 read hit: serve data word by word
    localparam ST_WB_EVICT   = 4'd2;  // Write-back dirty evicted line to DRAM
    localparam ST_WB_ADDR    = 4'd3;
    localparam ST_WB_DATA    = 4'd4;
    localparam ST_WB_RESP    = 4'd5;
    localparam ST_FILL_ADDR  = 4'd6;  // Fetch line from DRAM
    localparam ST_FILL_DATA  = 4'd7;
    localparam ST_RD_SERVE   = 4'd8;  // Serve the freshly loaded line to L1
    localparam ST_WR_ACCEPT  = 4'd9;  // Accept write-back from L1 (dirty → L2)
    localparam ST_WR_DONE    = 4'd10;

    reg [3:0] state;
    reg [3:0] fill_word;   // Word counter for 16-word L2 line
    reg [31:0] req_addr;   // Latched request address
    reg [31:0] req_base;   // Line-aligned request base
    reg [6:0]  req_idx;
    reg [18:0] req_tag;
    reg [1:0]  req_way;    // Target way for fill
    reg        req_is_wr;  // 1 = write-back request from L1

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            s_aw_ready   <= 1'b0;
            s_w_ready    <= 1'b0;
            s_b_valid    <= 1'b0;
            s_b_resp     <= `AXI_RESP_OKAY;
            s_ar_ready   <= 1'b0;
            s_r_valid    <= 1'b0;
            s_r_data     <= 32'b0;
            s_r_resp     <= `AXI_RESP_OKAY;
            m_ar_valid   <= 1'b0;
            m_ar_addr    <= 32'b0;
            m_r_ready    <= 1'b0;
            m_aw_valid   <= 1'b0;
            m_aw_addr    <= 32'b0;
            m_w_valid    <= 1'b0;
            m_w_data     <= 32'b0;
            m_w_strb     <= 4'hF;
            m_b_ready    <= 1'b0;
            fill_word    <= 4'd0;
        end else begin
            // Default: de-assert handshake signals
            s_b_valid  <= 1'b0;
            s_r_valid  <= 1'b0;
            s_ar_ready <= 1'b0;
            s_aw_ready <= 1'b0;
            s_w_ready  <= 1'b0;

            case (state)

                ST_IDLE: begin
                    fill_word <= 4'd0;
                    // Priority: accept AW (write-back from L1) or AR (fill req)
                    if (s_aw_valid) begin
                        // L1 is writing a dirty line back to L2
                        s_aw_ready <= 1'b1;
                        req_addr   <= s_aw_addr;
                        req_base   <= {s_aw_addr[31:6], 6'b0};
                        req_idx    <= s_aw_addr[12:6];
                        req_tag    <= s_aw_addr[31:13];
                        req_is_wr  <= 1'b1;
                        state      <= ST_WR_ACCEPT;
                    end else if (s_ar_valid) begin
                        // L1 requests a cache line fill
                        s_ar_ready <= 1'b1;
                        req_addr   <= s_ar_addr;
                        req_base   <= {s_ar_addr[31:6], 6'b0};
                        req_idx    <= s_ar_addr[12:6];
                        req_tag    <= s_ar_addr[31:13];
                        req_is_wr  <= 1'b0;
                        if (l2_hit) begin
                            req_way  <= hit_way;
                            state    <= ST_RD_HIT;
                        end else begin
                            // L2 miss — must evict if dirty, then fill from DRAM
                            req_way  <= evict_way;
                            if (evict_dirty && tag_w0[ar_index][20]) // if evicted line valid & dirty
                                state <= ST_WB_ADDR;
                            else
                                state <= ST_FILL_ADDR;
                        end
                    end
                end

                // --- Read Hit Path ---
                ST_RD_HIT: begin
                    // Serve 1 word to L1 per AXI read transaction (16 words total)
                    case (req_way)
                        2'd0: s_r_data <= data_w0[{req_idx, fill_word}];
                        2'd1: s_r_data <= data_w1[{req_idx, fill_word}];
                        2'd2: s_r_data <= data_w2[{req_idx, fill_word}];
                        2'd3: s_r_data <= data_w3[{req_idx, fill_word}];
                    endcase
                    s_r_resp  <= `AXI_RESP_OKAY;
                    s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin
                        if (fill_word == 4'd15) begin
                            // All 16 words served
                            update_lru(req_idx, req_way);
                            state <= ST_IDLE;
                        end else begin
                            fill_word <= fill_word + 4'd1;
                        end
                    end
                end

                // --- Dirty Eviction Write-Back Path ---
                ST_WB_ADDR: begin
                    m_aw_addr  <= evict_base_addr + {28'b0, fill_word, 2'b00};
                    m_aw_valid <= 1'b1;
                    if (m_aw_valid && m_aw_ready) begin
                        m_aw_valid <= 1'b0;
                        state      <= ST_WB_DATA;
                    end
                end

                ST_WB_DATA: begin
                    case (evict_way)
                        2'd0: m_w_data <= data_w0[{req_idx, fill_word}];
                        2'd1: m_w_data <= data_w1[{req_idx, fill_word}];
                        2'd2: m_w_data <= data_w2[{req_idx, fill_word}];
                        2'd3: m_w_data <= data_w3[{req_idx, fill_word}];
                    endcase
                    m_w_strb  <= 4'hF;
                    m_w_valid <= 1'b1;
                    if (m_w_valid && m_w_ready) begin
                        m_w_valid <= 1'b0;
                        state     <= ST_WB_RESP;
                    end
                end

                ST_WB_RESP: begin
                    m_b_ready <= 1'b1;
                    if (m_b_valid && m_b_ready) begin
                        m_b_ready <= 1'b0;
                        if (fill_word == 4'd15) begin
                            // Eviction complete — clear dirty bit in tag
                            case (evict_way)
                                2'd0: tag_w0[req_idx][19] <= 1'b0;
                                2'd1: tag_w1[req_idx][19] <= 1'b0;
                                2'd2: tag_w2[req_idx][19] <= 1'b0;
                                2'd3: tag_w3[req_idx][19] <= 1'b0;
                            endcase
                            fill_word <= 4'd0;
                            state     <= ST_FILL_ADDR;
                        end else begin
                            fill_word <= fill_word + 4'd1;
                            state     <= ST_WB_ADDR;
                        end
                    end
                end

                // --- DRAM Fill Path ---
                ST_FILL_ADDR: begin
                    m_ar_addr  <= req_base + {28'b0, fill_word, 2'b00};
                    m_ar_valid <= 1'b1;
                    m_r_ready  <= 1'b0;
                    if (m_ar_valid && m_ar_ready) begin
                        m_ar_valid <= 1'b0;
                        m_r_ready  <= 1'b1;
                        state      <= ST_FILL_DATA;
                    end
                end

                ST_FILL_DATA: begin
                    if (m_r_valid && m_r_ready) begin
                        m_r_ready <= 1'b0;
                        case (req_way)
                            2'd0: data_w0[{req_idx, fill_word}] <= m_r_data;
                            2'd1: data_w1[{req_idx, fill_word}] <= m_r_data;
                            2'd2: data_w2[{req_idx, fill_word}] <= m_r_data;
                            2'd3: data_w3[{req_idx, fill_word}] <= m_r_data;
                        endcase
                        if (fill_word == 4'd15) begin
                            // Full 64-byte line loaded — update tag
                            case (req_way)
                                2'd0: tag_w0[req_idx] <= {1'b1, 1'b0, req_tag};  // valid=1, dirty=0
                                2'd1: tag_w1[req_idx] <= {1'b1, 1'b0, req_tag};
                                2'd2: tag_w2[req_idx] <= {1'b1, 1'b0, req_tag};
                                2'd3: tag_w3[req_idx] <= {1'b1, 1'b0, req_tag};
                            endcase
                            update_lru(req_idx, req_way);
                            fill_word <= 4'd0;
                            state     <= ST_RD_SERVE;
                        end else begin
                            fill_word <= fill_word + 4'd1;
                            state     <= ST_FILL_ADDR;
                        end
                    end
                end

                ST_RD_SERVE: begin
                    // Re-serve from the freshly filled line to the pending L1 request
                    case (req_way)
                        2'd0: s_r_data <= data_w0[{req_idx, fill_word}];
                        2'd1: s_r_data <= data_w1[{req_idx, fill_word}];
                        2'd2: s_r_data <= data_w2[{req_idx, fill_word}];
                        2'd3: s_r_data <= data_w3[{req_idx, fill_word}];
                    endcase
                    s_r_resp  <= `AXI_RESP_OKAY;
                    s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin
                        if (fill_word == 4'd15) begin
                            state <= ST_IDLE;
                        end else begin
                            fill_word <= fill_word + 4'd1;
                        end
                    end
                end

                // --- L1 Write-Back Accept Path ---
                ST_WR_ACCEPT: begin
                    s_w_ready <= 1'b1;
                    if (s_w_valid && s_w_ready) begin
                        // Write incoming dirty word into L2
                        // Find or allocate a way for this write-back
                        case (evict_way)
                            2'd0: data_w0[{req_idx, fill_word}] <= s_w_data;
                            2'd1: data_w1[{req_idx, fill_word}] <= s_w_data;
                            2'd2: data_w2[{req_idx, fill_word}] <= s_w_data;
                            2'd3: data_w3[{req_idx, fill_word}] <= s_w_data;
                        endcase
                        s_w_ready <= 1'b0;
                        if (fill_word == 4'd15) begin
                            // Entire line written; mark L2 line as valid + dirty
                            case (evict_way)
                                2'd0: tag_w0[req_idx] <= {1'b1, 1'b1, req_tag};
                                2'd1: tag_w1[req_idx] <= {1'b1, 1'b1, req_tag};
                                2'd2: tag_w2[req_idx] <= {1'b1, 1'b1, req_tag};
                                2'd3: tag_w3[req_idx] <= {1'b1, 1'b1, req_tag};
                            endcase
                            s_b_resp  <= `AXI_RESP_OKAY;
                            s_b_valid <= 1'b1;
                            state     <= ST_WR_DONE;
                        end else begin
                            fill_word <= fill_word + 4'd1;
                        end
                    end
                end

                ST_WR_DONE: begin
                    if (s_b_valid && s_b_ready) begin
                        s_b_valid <= 1'b0;
                        state     <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Pseudo-LRU Update Task
    // On access to way W, update lru_bits[idx] to point AWAY from W.
    // =========================================================================
    task update_lru;
        input [6:0] idx;
        input [1:0] way;
        begin
            case (way)
                2'd0: begin lru_bits[idx][2] <= 1'b1; lru_bits[idx][1] <= 1'b1; end // W0 used → L=right,right
                2'd1: begin lru_bits[idx][2] <= 1'b1; lru_bits[idx][1] <= 1'b0; end
                2'd2: begin lru_bits[idx][2] <= 1'b0; lru_bits[idx][0] <= 1'b1; end
                2'd3: begin lru_bits[idx][2] <= 1'b0; lru_bits[idx][0] <= 1'b0; end
            endcase
        end
    endtask

    // =========================================================================
    // Initialization
    // =========================================================================
    integer ii;
    initial begin
        for (ii = 0; ii < 128; ii = ii + 1) begin
            tag_w0[ii]  = 21'b0;
            tag_w1[ii]  = 21'b0;
            tag_w2[ii]  = 21'b0;
            tag_w3[ii]  = 21'b0;
            lru_bits[ii] = 3'b0;
        end
        for (ii = 0; ii < 2048; ii = ii + 1) begin
            data_w0[ii] = 32'b0;
            data_w1[ii] = 32'b0;
            data_w2[ii] = 32'b0;
            data_w3[ii] = 32'b0;
        end
        state      = ST_IDLE;
        m_ar_valid = 1'b0;
        m_aw_valid = 1'b0;
        m_w_valid  = 1'b0;
        m_b_ready  = 1'b0;
        m_r_ready  = 1'b0;
    end

endmodule
