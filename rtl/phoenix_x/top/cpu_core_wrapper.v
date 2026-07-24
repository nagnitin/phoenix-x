// =============================================================================
// Module      : cpu_core_wrapper
// Project     : Phoenix-X Heterogeneous SoC
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Wrapper that integrates the existing cpu_core (UNMODIFIED) with:
//               1. BUFGCE clock gating: CPU clock is frozen during cache misses
//               2. L1 Instruction Cache (l1_icache)
//               3. L1 Data Cache (l1_dcache)
//               4. AXI-4 Lite master port (combined cache fill interface to L2)
//
// WHY CLOCK GATING (not clock enable)?
//   The existing cpu_core.v has no external stall input. Adding one would
//   require modifying every pipeline register (400+ lines). Instead, we use
//   BUFGCE to gate the clock TO the cpu_core. When the clock is frozen:
//   - All pipeline registers inside cpu_core hold their state
//   - All output signals (dmem_addr, imem_addr, dmem_we, etc.) remain stable
//   - The cache controller (on ungated sys_clk) uses these stable signals
//     to fetch the missing cache line
//   - When the miss is resolved, BUFGCE re-enables the clock
//   - cpu_core resumes from exactly where it paused
//
// BUFGCE Primitive (Artix-7 / Vivado):
//   BUFGCE #(.CE_TYPE("SYNC")) u_bufgce (
//     .I(sys_clk),    // Input: always-running 100 MHz clock
//     .CE(clk_en),    // Clock Enable: 1 = pass through, 0 = freeze at 0
//     .O(cpu_clk)     // Output: gated clock to cpu_core
//   );
//   CE_TYPE="SYNC" ensures gating happens only on a clock LOW phase,
//   preventing glitches on the output clock.
//
// Clock Enable Timing:
//   miss = (icache_miss | dcache_miss)
//   clk_en is registered on negedge of sys_clk (synchronized to clock LOW phase)
//   This ensures CE is stable before BUFGCE evaluates it on the next LOW phase.
//
// Dual-Port L2 Interface:
//   Both I-cache and D-cache may need to fill simultaneously (rare but possible
//   on context switch). This wrapper arbitrates between them: D-cache fill
//   takes priority over I-cache fill (data accesses are on the critical path).
//
// Parameters:
//   CORE_ID [0:1] — which cpu_core this is (0=CPU0, 1=CPU1)
//                    Used to partition private DRAM banks in address requests
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module cpu_core_wrapper #(
    parameter CORE_ID = 0   // 0 = CPU0, 1 = CPU1
) (
    input  wire        sys_clk,   // Always-running 100 MHz system clock
    input  wire        rst_n,

    // =========================================================================
    // AXI-4 Lite Master Port (to L2 cache / crossbar)
    // =========================================================================
    // Read Address Channel (cache line fills: I-cache or D-cache)
    output wire [31:0] axi_ar_addr,
    output wire        axi_ar_valid,
    input  wire        axi_ar_ready,
    // Read Data Channel
    input  wire [31:0] axi_r_data,
    input  wire [ 1:0] axi_r_resp,
    input  wire        axi_r_valid,
    output wire        axi_r_ready,
    // Write Address Channel (D-cache dirty eviction)
    output wire [31:0] axi_aw_addr,
    output wire        axi_aw_valid,
    input  wire        axi_aw_ready,
    // Write Data Channel
    output wire [31:0] axi_w_data,
    output wire [ 3:0] axi_w_strb,
    output wire        axi_w_valid,
    input  wire        axi_w_ready,
    // Write Response Channel
    input  wire [ 1:0] axi_b_resp,
    input  wire        axi_b_valid,
    output wire        axi_b_ready,

    // =========================================================================
    // Interrupt Interface (to/from Shared PIC)
    // =========================================================================
    input  wire        irq_req,
    input  wire [31:0] irq_vector,
    output wire        irq_ack,
    output wire        in_isr,

    // =========================================================================
    // Debug Interface (to debug unit in top-level)
    // =========================================================================
    output wire [31:0] dbu_pc,
    output wire [31:0] dbu_instr,
    output wire        dbu_valid,
    input  wire [ 4:0] dbu_reg_sel,
    output wire [31:0] dbu_reg_val,
    input  wire        dbu_halt_in,

    // =========================================================================
    // Cache Snoop Interface (from cache_coherency controller)
    // =========================================================================
    // D-cache snoop
    input  wire [31:0] snoop_addr,
    input  wire        snoop_inval,
    output wire        snoop_hit,
    output wire        snoop_dirty,
    // I-cache snoop
    input  wire [31:0] isnoop_addr,
    input  wire        isnoop_inval,

    // =========================================================================
    // Status
    // =========================================================================
    output wire        cache_miss_active  // 1 = CPU is stalled on cache miss
);

    // =========================================================================
    // BUFGCE — Gated CPU Clock
    // Synthesizes to BUFGCE primitive on Artix-7 (Vivado UNISIM library)
    // =========================================================================
    wire icache_miss, dcache_miss;
    wire any_miss = icache_miss | dcache_miss;

    // Register clk_en on negedge to ensure CE is stable before clock LOW phase
    reg clk_en_r;
    always @(negedge sys_clk or negedge rst_n) begin
        if (!rst_n) clk_en_r <= 1'b1;  // Enable clock during reset so core flops initialize cleanly
        else        clk_en_r <= ~any_miss;  // Enable clock only when no miss
    end

    wire cpu_clk;  // Gated clock to cpu_core

`ifdef SIMULATION
    // Behavioral clock gating for simulation / Icarus Verilog
    assign cpu_clk = sys_clk & clk_en_r;
`else
    // Xilinx BUFGCE — synthesizable clock gating primitive for Vivado
    BUFGCE #(
        .CE_TYPE       ("SYNC"),   // Gate only on clock LOW (glitch-free)
        .IS_CE_INVERTED(1'b0),
        .IS_I_INVERTED (1'b0)
    ) u_cpu_clk_gate (
        .I  (sys_clk),   // Input clock (always running)
        .CE (clk_en_r),  // Clock enable: 1=pass, 0=hold LOW
        .O  (cpu_clk)    // Gated clock to cpu_core
    );
`endif

    assign cache_miss_active = any_miss;

    // =========================================================================
    // CPU Core Internal Wires
    // =========================================================================
    wire [31:0] imem_addr;    // Instruction fetch address (PC output)
    wire [31:0] imem_rdata;   // Instruction to CPU (from I-cache)
    wire [31:0] dmem_addr;    // Data memory address
    wire [31:0] dmem_wdata;   // Data write data
    wire        dmem_we;      // Data write enable
    wire        dmem_re;      // Data read enable
    wire        dmem_byte;    // Byte access flag
    wire [31:0] dmem_rdata;   // Data read data (from D-cache)

    // Convert dmem_byte to byte-enable vector for d-cache
    wire [ 3:0] dmem_be = dmem_byte ?
                          (4'h1 << dmem_addr[1:0]) :  // Byte access: single byte
                          4'hF;                        // Word access: all bytes

    // =========================================================================
    // Instantiate cpu_core (UNMODIFIED ORIGINAL MODULE)
    // =========================================================================
    cpu_core u_cpu_core (
        .clk          (cpu_clk),      // Gated clock — freezes during miss
        .rst_n        (rst_n),
        // Instruction memory (connected to L1 I-cache)
        .imem_addr    (imem_addr),
        .imem_rdata   (imem_rdata),
        // Data memory (connected to L1 D-cache)
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_we      (dmem_we),
        .dmem_re      (dmem_re),
        .dmem_byte    (dmem_byte),
        .dmem_rdata   (dmem_rdata),
        // Interrupt
        .irq_req      (irq_req),
        .irq_vector   (irq_vector),
        .irq_ack      (irq_ack),
        .in_isr       (in_isr),
        // Debug
        .dbu_pc       (dbu_pc),
        .dbu_instr    (dbu_instr),
        .dbu_valid    (dbu_valid),
        .dbu_reg_sel  (dbu_reg_sel),
        .dbu_reg_val  (dbu_reg_val),
        .dbu_halt_in  (dbu_halt_in)
    );

    // =========================================================================
    // L1 Instruction Cache
    // =========================================================================
    // I-cache AXI wires (toward L2 / crossbar)
    wire [31:0] ic_ar_addr;
    wire        ic_ar_valid;
    wire        ic_ar_ready_in;
    wire [31:0] ic_r_data;
    wire [ 1:0] ic_r_resp;
    wire        ic_r_valid_in;
    wire        ic_r_ready;

    l1_icache u_icache (
        .sys_clk    (sys_clk),
        .cpu_clk    (cpu_clk),
        .rst_n      (rst_n),
        // CPU interface
        .cpu_addr   (imem_addr),
        .cpu_rdata  (imem_rdata),
        .miss       (icache_miss),
        // AXI master (toward L2)
        .axi_ar_addr  (ic_ar_addr),
        .axi_ar_valid (ic_ar_valid),
        .axi_ar_ready (ic_ar_ready_in),
        .axi_r_data   (ic_r_data),
        .axi_r_resp   (ic_r_resp),
        .axi_r_valid  (ic_r_valid_in),
        .axi_r_ready  (ic_r_ready),
        // Snoop
        .snoop_addr   (isnoop_addr),
        .snoop_inval  (isnoop_inval)
    );

    // =========================================================================
    // L1 Data Cache
    // =========================================================================
    // D-cache AXI wires
    wire [31:0] dc_ar_addr, dc_aw_addr, dc_w_data;
    wire [ 3:0] dc_w_strb;
    wire        dc_ar_valid, dc_ar_ready_in;
    wire [31:0] dc_r_data;
    wire [ 1:0] dc_r_resp;
    wire        dc_r_valid_in, dc_r_ready;
    wire        dc_aw_valid, dc_aw_ready_in;
    wire        dc_w_valid, dc_w_ready_in;
    wire [ 1:0] dc_b_resp;
    wire        dc_b_valid_in, dc_b_ready;

    l1_dcache u_dcache (
        .sys_clk    (sys_clk),
        .cpu_clk    (cpu_clk),
        .rst_n      (rst_n),
        .core_id    (CORE_ID[0]),
        // CPU interface
        .cpu_addr   (dmem_addr),
        .cpu_wdata  (dmem_wdata),
        .cpu_we     (dmem_we),
        .cpu_re     (dmem_re),
        .cpu_be     (dmem_be),
        .cpu_rdata  (dmem_rdata),
        .miss       (dcache_miss),
        // AXI read (fill)
        .axi_ar_addr  (dc_ar_addr),
        .axi_ar_valid (dc_ar_valid),
        .axi_ar_ready (dc_ar_ready_in),
        .axi_r_data   (dc_r_data),
        .axi_r_resp   (dc_r_resp),
        .axi_r_valid  (dc_r_valid_in),
        .axi_r_ready  (dc_r_ready),
        // AXI write (dirty eviction)
        .axi_aw_addr  (dc_aw_addr),
        .axi_aw_valid (dc_aw_valid),
        .axi_aw_ready (dc_aw_ready_in),
        .axi_w_data   (dc_w_data),
        .axi_w_strb   (dc_w_strb),
        .axi_w_valid  (dc_w_valid),
        .axi_w_ready  (dc_w_ready_in),
        .axi_b_resp   (dc_b_resp),
        .axi_b_valid  (dc_b_valid_in),
        .axi_b_ready  (dc_b_ready),
        // Snoop
        .snoop_addr   (snoop_addr),
        .snoop_inval  (snoop_inval),
        .snoop_hit    (snoop_hit),
        .snoop_dirty  (snoop_dirty)
    );

    // =========================================================================
    // AXI Master Mux: D-cache has priority over I-cache
    // D-cache is on the data critical path; I-cache fill can wait.
    // When D-cache is filling (dc_ar_valid or dc_aw_valid), I-cache is stalled.
    // =========================================================================
    wire dc_active = dc_ar_valid | dc_aw_valid | dc_w_valid;
    wire ic_active = ic_ar_valid & ~dc_active;

    // Read address channel: D-cache first, then I-cache
    assign axi_ar_addr  = dc_active ? dc_ar_addr  : ic_ar_addr;
    assign axi_ar_valid = dc_active ? dc_ar_valid : ic_ar_valid;

    // Route ar_ready back to the right cache
    assign dc_ar_ready_in = dc_active ? axi_ar_ready : 1'b0;
    assign ic_ar_ready_in = ic_active ? axi_ar_ready : 1'b0;

    // Read data channel: route to whichever cache is active
    assign dc_r_data    = dc_active ? axi_r_data  : 32'b0;
    assign dc_r_resp    = dc_active ? axi_r_resp  : 2'b0;
    assign dc_r_valid_in = dc_active ? axi_r_valid : 1'b0;
    assign ic_r_data    = ic_active ? axi_r_data  : 32'b0;
    assign ic_r_resp    = ic_active ? axi_r_resp  : 2'b0;
    assign ic_r_valid_in = ic_active ? axi_r_valid : 1'b0;
    assign axi_r_ready  = dc_active ? dc_r_ready  : ic_r_ready;

    // Write channels: only D-cache uses write (dirty eviction)
    assign axi_aw_addr  = dc_aw_addr;
    assign axi_aw_valid = dc_aw_valid;
    assign dc_aw_ready_in = axi_aw_ready;
    assign axi_w_data   = dc_w_data;
    assign axi_w_strb   = dc_w_strb;
    assign axi_w_valid  = dc_w_valid;
    assign dc_w_ready_in = axi_w_ready;
    assign dc_b_resp    = axi_b_resp;
    assign dc_b_valid_in = axi_b_valid;
    assign axi_b_ready  = dc_b_ready;

endmodule
