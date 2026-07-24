// =============================================================================
// Module      : phoenix_x_top
// Project     : Phoenix-X Heterogeneous Compute Accelerator — PHASE 4 COMPLETE
// Target      : Xilinx Artix-7 XC7A100T (Nexys A7-100T)
// Clock       : 100 MHz system clock (single domain + BUFGCE gated CPU clocks)
// Description : Production-Grade Research SoC Integrating:
//               Phase 1 — Dual-Core CPU, AXI Crossbar, L1/L2 Cache, MESI Coherency
//               Phase 2 — DMA Controller, IPC Mailbox, Shared PIC, PMU
//               Phase 3 — Tiny GPU (160×120 VGA), NPU (4×4 INT8), Job Scheduler
//               Phase 4 — Hardware Security Engine (MPU + Trojan Detection)
//                        — Dynamic Power Optimization Unit (DPOU)
//                        — Advanced Debug Unit (ADBU): Instr+Mem+Bus Trace
//               Architecture: 5 Masters × 9 Slaves AXI-4 Lite Shared Crossbar
// =============================================================================
// NOTE: Phase 4 new modules at addresses:
//   0x0020_0600–06FF  Hardware Security Engine (MPU + Trojan Monitor)
//   0x0020_0700–07FF  Dynamic Power Optimization Unit
//   0x0020_0800–08FF  Advanced Debug Unit (ADBU)
// =============================================================================

`timescale 1ns/1ps
`include "rtl/phoenix_x/axi/axi_defines.vh"

module phoenix_x_top #(
    parameter MEM_FILE = "prog.hex"
) (
    input  wire        clk,          // 100 MHz board clock
    input  wire        rst_n,        // Active-low reset button

    // Peripheral Pins (Nexys A7-100T)
    output wire        tx,
    input  wire        rx,
    output wire        sclk,
    output wire        mosi,
    input  wire        miso,
    output wire        cs_n,
    output wire        scl_oe,
    output wire        sda_oe,
    input  wire        scl_in,
    input  wire        sda_in,
    input  wire [31:0] gp_in,
    output wire [31:0] gp_out,
    output wire [31:0] gp_oe,
    output wire        timer_pwm,
    output wire [3:0]  pwm_out,
    output wire [3:0]  anodes,
    output wire [7:0]  segments,
    output wire [3:0]  keypad_cols,
    input  wire [3:0]  keypad_rows,
    output wire        lcd_rs,
    output wire        lcd_rw,
    output wire        lcd_e,
    output wire [7:0]  lcd_db,
    output wire        oled_scl_oe,
    output wire        oled_sda_oe,
    input  wire        oled_scl_in,
    input  wire        oled_sda_in,
    output wire        ee_scl_oe,
    output wire        ee_sda_oe,
    input  wire        ee_scl_in,
    input  wire        ee_sda_in,
    output wire        ultrasonic_trig,
    input  wire        ultrasonic_echo,
    output wire        temp_scl_oe,
    output wire        temp_sda_oe,
    input  wire        temp_scl_in,
    input  wire        temp_sda_in,
    output wire        system_reset_out,

    // VGA Hardware Pins (Nexys A7-100T)
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,

    // Telemetry & Status LEDs
    output wire [15:0] status_leds
);

    wire wdt_reset;
    wire sys_rst_n = rst_n & ~wdt_reset;
    assign system_reset_out = wdt_reset;

    // AXI Master Signals (M0=CPU0, M1=CPU1, M2=DMA, M3=GPU, M4=NPU)
    wire [31:0] c0_ar_addr, c0_aw_addr, c0_w_data, c0_r_data;
    wire [ 3:0] c0_w_strb; wire [ 1:0] c0_r_resp, c0_b_resp;
    wire        c0_ar_valid, c0_ar_ready, c0_aw_valid, c0_aw_ready, c0_w_valid, c0_w_ready, c0_r_valid, c0_r_ready, c0_b_valid, c0_b_ready;

    wire [31:0] c1_ar_addr, c1_aw_addr, c1_w_data, c1_r_data;
    wire [ 3:0] c1_w_strb; wire [ 1:0] c1_r_resp, c1_b_resp;
    wire        c1_ar_valid, c1_ar_ready, c1_aw_valid, c1_aw_ready, c1_w_valid, c1_w_ready, c1_r_valid, c1_r_ready, c1_b_valid, c1_b_ready;

    wire [31:0] dm_ar_addr, dm_aw_addr, dm_w_data, dm_r_data;
    wire [ 3:0] dm_w_strb; wire [ 1:0] dm_r_resp, dm_b_resp;
    wire        dm_ar_valid, dm_ar_ready, dm_aw_valid, dm_aw_ready, dm_w_valid, dm_w_ready, dm_r_valid, dm_r_ready, dm_b_valid, dm_b_ready;

    wire [31:0] gpu_m_aw_addr, gpu_m_w_data, gpu_m_r_data, gpu_m_ar_addr;
    wire [ 3:0] gpu_m_w_strb; wire [ 1:0] gpu_m_r_resp, gpu_m_b_resp;
    wire        gpu_m_aw_valid, gpu_m_aw_ready, gpu_m_w_valid, gpu_m_w_ready, gpu_m_b_valid, gpu_m_b_ready, gpu_m_ar_valid, gpu_m_ar_ready, gpu_m_r_valid, gpu_m_r_ready;

    wire [31:0] npu_m_aw_addr, npu_m_w_data, npu_m_r_data, npu_m_ar_addr;
    wire [ 3:0] npu_m_w_strb; wire [ 1:0] npu_m_r_resp, npu_m_b_resp;
    wire        npu_m_aw_valid, npu_m_aw_ready, npu_m_w_valid, npu_m_w_ready, npu_m_b_valid, npu_m_b_ready, npu_m_ar_valid, npu_m_ar_ready, npu_m_r_valid, npu_m_r_ready;

    // AXI Slave Signals (S0=BootROM, S1=IROM, S2=DRAM0, S3=DRAM1, S4=SharedSRAM, S5=SysCtrl, S6=Periph, S7=GPU, S8=NPU)
    wire [31:0] br_ar_addr, br_r_data, ir_ar_addr, ir_r_data;
    wire [ 1:0] br_r_resp, ir_r_resp;
    wire        br_ar_valid, br_ar_ready, br_r_valid, br_r_ready, ir_ar_valid, ir_ar_ready, ir_r_valid, ir_r_ready;

    wire [31:0] d0_aw_addr, d0_w_data, d0_ar_addr, d0_r_data;
    wire [ 3:0] d0_w_strb; wire [ 1:0] d0_b_resp, d0_r_resp;
    wire        d0_aw_valid, d0_aw_ready, d0_w_valid, d0_w_ready, d0_b_valid, d0_b_ready, d0_ar_valid, d0_ar_ready, d0_r_valid, d0_r_ready;

    wire [31:0] d1_aw_addr, d1_w_data, d1_ar_addr, d1_r_data;
    wire [ 3:0] d1_w_strb; wire [ 1:0] d1_b_resp, d1_r_resp;
    wire        d1_aw_valid, d1_aw_ready, d1_w_valid, d1_w_ready, d1_b_valid, d1_b_ready, d1_ar_valid, d1_ar_ready, d1_r_valid, d1_r_ready;

    wire [31:0] sm_aw_addr, sm_w_data, sm_ar_addr, sm_r_data;
    wire [ 3:0] sm_w_strb; wire [ 1:0] sm_b_resp, sm_r_resp;
    wire        sm_aw_valid, sm_aw_ready, sm_w_valid, sm_w_ready, sm_b_valid, sm_b_ready, sm_ar_valid, sm_ar_ready, sm_r_valid, sm_r_ready;

    wire [31:0] sys_aw_addr, sys_w_data, sys_ar_addr, sys_r_data;
    wire [ 3:0] sys_w_strb; wire [ 1:0] sys_b_resp, sys_r_resp;
    wire        sys_aw_valid, sys_aw_ready, sys_w_valid, sys_w_ready, sys_b_valid, sys_b_ready, sys_ar_valid, sys_ar_ready, sys_r_valid, sys_r_ready;

    reg  [31:0] pb_r_data; reg [1:0] pb_b_resp, pb_r_resp;
    wire [31:0] pb_aw_addr, pb_w_data, pb_ar_addr; wire [3:0] pb_w_strb;
    wire        pb_aw_valid, pb_w_valid, pb_b_ready, pb_ar_valid, pb_r_ready;
    reg         pb_aw_ready, pb_w_ready, pb_b_valid, pb_ar_ready, pb_r_valid;

    wire [31:0] gpu_s_aw_addr, gpu_s_w_data, gpu_s_ar_addr, gpu_s_r_data;
    wire [ 3:0] gpu_s_w_strb; wire [ 1:0] gpu_s_b_resp, gpu_s_r_resp;
    wire        gpu_s_aw_valid, gpu_s_aw_ready, gpu_s_w_valid, gpu_s_w_ready, gpu_s_b_valid, gpu_s_b_ready, gpu_s_ar_valid, gpu_s_ar_ready, gpu_s_r_valid, gpu_s_r_ready;

    wire [31:0] npu_s_aw_addr, npu_s_w_data, npu_s_ar_addr, npu_s_r_data;
    wire [ 3:0] npu_s_w_strb; wire [ 1:0] npu_s_b_resp, npu_s_r_resp;
    wire        npu_s_aw_valid, npu_s_aw_ready, npu_s_w_valid, npu_s_w_ready, npu_s_b_valid, npu_s_b_ready, npu_s_ar_valid, npu_s_ar_ready, npu_s_r_valid, npu_s_r_ready;

    // Accelerator IRQ & Status Wires
    wire gpu_busy, gpu_done_irq;
    wire npu_busy, npu_done_irq;
    wire [3:0] dma_busy_lines, dma_done_irqs;
    wire scheduler_irq;
    wire axi_rd_pulse, axi_wr_pulse;

    // =========================================================================
    // Phase 4: Hardware Security Engine, Power Monitor, ADBU Wires
    // =========================================================================
    wire mpu_fault, trojan_alert, hse_irq;
    wire [31:0] fault_addr, trojan_fault_report;
    wire [1:0]  fault_type;

    // Power Monitor clock gate enables (drive external BUFGCE if needed)
    wire clk_en_gpu_pm, clk_en_npu_pm, clk_en_cpu0_pm, clk_en_cpu1_pm, clk_en_dma_pm;
    wire iso_gpu_pm, iso_npu_pm;

    // Phase 4 AXI Slave Signals (HSE, DPOU, ADBU share SysCtrl bus decode)
    wire [31:0] hse_s_aw_addr, hse_s_ar_addr, hse_s_w_data, hse_s_r_data;
    wire [3:0]  hse_s_w_strb; wire [1:0] hse_s_b_resp, hse_s_r_resp;
    wire        hse_s_aw_valid, hse_s_aw_ready, hse_s_w_valid, hse_s_w_ready;
    wire        hse_s_b_valid, hse_s_b_ready, hse_s_ar_valid, hse_s_ar_ready;
    wire        hse_s_r_valid, hse_s_r_ready;

    // Coherency Snoop Wires
    wire [31:0] snoop_addr, c0_dsnoop_addr, c1_dsnoop_addr, c0_isnoop_addr, c1_isnoop_addr;
    wire        snoop_wr_valid, c0_dsnoop_inval, c1_dsnoop_inval, c0_dsnoop_hit, c1_dsnoop_hit, c0_dsnoop_dirty, c1_dsnoop_dirty, c0_isnoop_inval, c1_isnoop_inval;

    // CPU Interrupt wires
    wire cpu0_irq_req, cpu0_irq_ack, cpu0_in_isr, cpu1_irq_req, cpu1_irq_ack, cpu1_in_isr;
    wire [31:0] cpu0_irq_vector, cpu1_irq_vector, cpu0_dbu_pc, cpu0_dbu_instr, cpu0_dbu_reg_val, cpu1_dbu_pc, cpu1_dbu_instr, cpu1_dbu_reg_val;
    wire        cpu0_dbu_valid, cpu1_dbu_valid, ipc_irq_cpu0, ipc_irq_cpu1;

    // 1. CPU0 Wrapper
    cpu_core_wrapper #(.CORE_ID(0)) u_cpu0 (
        .sys_clk(clk), .rst_n(sys_rst_n),
        .axi_ar_addr(c0_ar_addr), .axi_ar_valid(c0_ar_valid), .axi_ar_ready(c0_ar_ready),
        .axi_r_data(c0_r_data),   .axi_r_resp(c0_r_resp),   .axi_r_valid(c0_r_valid),   .axi_r_ready(c0_r_ready),
        .axi_aw_addr(c0_aw_addr), .axi_aw_valid(c0_aw_valid), .axi_aw_ready(c0_aw_ready),
        .axi_w_data(c0_w_data),   .axi_w_strb(c0_w_strb),   .axi_w_valid(c0_w_valid),   .axi_w_ready(c0_w_ready),
        .axi_b_resp(c0_b_resp),   .axi_b_valid(c0_b_valid), .axi_b_ready(c0_b_ready),
        .irq_req(cpu0_irq_req),   .irq_vector(cpu0_irq_vector), .irq_ack(cpu0_irq_ack), .in_isr(cpu0_in_isr),
        .dbu_pc(cpu0_dbu_pc),     .dbu_instr(cpu0_dbu_instr), .dbu_valid(cpu0_dbu_valid), .dbu_reg_sel(5'b0), .dbu_reg_val(cpu0_dbu_reg_val), .dbu_halt_in(1'b0),
        .snoop_addr(c0_dsnoop_addr), .snoop_inval(c0_dsnoop_inval), .snoop_hit(c0_dsnoop_hit), .snoop_dirty(c0_dsnoop_dirty),
        .isnoop_addr(c0_isnoop_addr), .isnoop_inval(c0_isnoop_inval), .cache_miss_active()
    );

    // 2. CPU1 Wrapper
    cpu_core_wrapper #(.CORE_ID(1)) u_cpu1 (
        .sys_clk(clk), .rst_n(sys_rst_n),
        .axi_ar_addr(c1_ar_addr), .axi_ar_valid(c1_ar_valid), .axi_ar_ready(c1_ar_ready),
        .axi_r_data(c1_r_data),   .axi_r_resp(c1_r_resp),   .axi_r_valid(c1_r_valid),   .axi_r_ready(c1_r_ready),
        .axi_aw_addr(c1_aw_addr), .axi_aw_valid(c1_aw_valid), .axi_aw_ready(c1_aw_ready),
        .axi_w_data(c1_w_data),   .axi_w_strb(c1_w_strb),   .axi_w_valid(c1_w_valid),   .axi_w_ready(c1_w_ready),
        .axi_b_resp(c1_b_resp),   .axi_b_valid(c1_b_valid), .axi_b_ready(c1_b_ready),
        .irq_req(cpu1_irq_req),   .irq_vector(cpu1_irq_vector), .irq_ack(cpu1_irq_ack), .in_isr(cpu1_in_isr),
        .dbu_pc(cpu1_dbu_pc),     .dbu_instr(cpu1_dbu_instr), .dbu_valid(cpu1_dbu_valid), .dbu_reg_sel(5'b0), .dbu_reg_val(cpu1_dbu_reg_val), .dbu_halt_in(1'b0),
        .snoop_addr(c1_dsnoop_addr), .snoop_inval(c1_dsnoop_inval), .snoop_hit(c1_dsnoop_hit), .snoop_dirty(c1_dsnoop_dirty),
        .isnoop_addr(c1_isnoop_addr), .isnoop_inval(c1_isnoop_inval), .cache_miss_active()
    );

    // 3. DMA Controller
    wire dma_cs = sys_aw_valid && (sys_aw_addr >= 32'h0020_0100) && (sys_aw_addr <= 32'h0020_017F);
    dma_controller u_dma (
        .clk(clk), .rst_n(sys_rst_n),
        .s_aw_addr(sys_aw_addr), .s_aw_valid(sys_aw_valid & dma_cs), .s_aw_ready(),
        .s_w_data(sys_w_data),   .s_w_strb(sys_w_strb), .s_w_valid(sys_w_valid), .s_w_ready(),
        .s_b_resp(), .s_b_valid(), .s_b_ready(sys_b_ready),
        .s_ar_addr(sys_ar_addr), .s_ar_valid(sys_ar_valid & dma_cs), .s_ar_ready(),
        .s_r_data(), .s_r_resp(), .s_r_valid(), .s_r_ready(sys_r_ready),
        .m_ar_addr(dm_ar_addr), .m_ar_valid(dm_ar_valid), .m_ar_ready(dm_ar_ready),
        .m_r_data(dm_r_data),   .m_r_resp(dm_r_resp),   .m_r_valid(dm_r_valid),   .m_r_ready(dm_r_ready),
        .m_aw_addr(dm_aw_addr), .m_aw_valid(dm_aw_valid), .m_aw_ready(dm_aw_ready),
        .m_w_data(dm_w_data),   .m_w_strb(dm_w_strb),   .m_w_valid(dm_w_valid),   .m_w_ready(dm_w_ready),
        .m_b_resp(dm_b_resp),   .m_b_valid(dm_b_valid), .m_b_ready(dm_b_ready),
        .dma_irq(dma_done_irqs)
    );

    // 4. Tiny GPU
    gpu_top u_gpu (
        .clk(clk), .rst_n(sys_rst_n),
        .s_aw_addr(gpu_s_aw_addr), .s_aw_valid(gpu_s_aw_valid), .s_aw_ready(gpu_s_aw_ready),
        .s_w_data(gpu_s_w_data),   .s_w_strb(gpu_s_w_strb),   .s_w_valid(gpu_s_w_valid),   .s_w_ready(gpu_s_w_ready),
        .s_b_resp(gpu_s_b_resp),   .s_b_valid(gpu_s_b_valid), .s_b_ready(gpu_s_b_ready),
        .s_ar_addr(gpu_s_ar_addr), .s_ar_valid(gpu_s_ar_valid), .s_ar_ready(gpu_s_ar_ready),
        .s_r_data(gpu_s_r_data),   .s_r_resp(gpu_s_r_resp),   .s_r_valid(gpu_s_r_valid),   .s_r_ready(gpu_s_r_ready),
        .m_aw_addr(gpu_m_aw_addr), .m_aw_valid(gpu_m_aw_valid), .m_aw_ready(gpu_m_aw_ready),
        .m_w_data(gpu_m_w_data),   .m_w_strb(gpu_m_w_strb),   .m_w_valid(gpu_m_w_valid),   .m_w_ready(gpu_m_w_ready),
        .m_b_resp(gpu_m_b_resp),   .m_b_valid(gpu_m_b_valid), .m_b_ready(gpu_m_b_ready),
        .vga_hsync(vga_hsync), .vga_vsync(vga_vsync), .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .gpu_busy(gpu_busy), .gpu_done_irq(gpu_done_irq)
    );

    // 5. Dedicated NPU
    npu_top u_npu (
        .clk(clk), .rst_n(sys_rst_n),
        .s_aw_addr(npu_s_aw_addr), .s_aw_valid(npu_s_aw_valid), .s_aw_ready(npu_s_aw_ready),
        .s_w_data(npu_s_w_data),   .s_w_strb(npu_s_w_strb),   .s_w_valid(npu_s_w_valid),   .s_w_ready(npu_s_w_ready),
        .s_b_resp(npu_s_b_resp),   .s_b_valid(npu_s_b_valid), .s_b_ready(npu_s_b_ready),
        .s_ar_addr(npu_s_ar_addr), .s_ar_valid(npu_s_ar_valid), .s_ar_ready(npu_s_ar_ready),
        .s_r_data(npu_s_r_data),   .s_r_resp(npu_s_r_resp),   .s_r_valid(npu_s_r_valid),   .s_r_ready(npu_s_r_ready),
        .m_ar_addr(npu_m_ar_addr), .m_ar_valid(npu_m_ar_valid), .m_ar_ready(npu_m_ar_ready),
        .m_r_data(npu_m_r_data),   .m_r_resp(npu_m_r_resp),   .m_r_valid(npu_m_r_valid),   .m_r_ready(npu_m_r_ready),
        .m_aw_addr(npu_m_aw_addr), .m_aw_valid(npu_m_aw_valid), .m_aw_ready(npu_m_aw_ready),
        .m_w_data(npu_m_w_data),   .m_w_strb(npu_m_w_strb),   .m_w_valid(npu_m_w_valid),   .m_w_ready(npu_m_w_ready),
        .m_b_resp(npu_m_b_resp),   .m_b_valid(npu_m_b_valid), .m_b_ready(npu_m_b_ready),
        .npu_busy(npu_busy), .npu_done_irq(npu_done_irq)
    );

    // 6. Hardware Job Scheduler
    wire sched_cs = sys_aw_valid && (sys_aw_addr >= 32'h0020_0300) && (sys_aw_addr <= 32'h0020_037F);
    job_scheduler u_scheduler (
        .clk(clk), .rst_n(sys_rst_n),
        .s_aw_addr(sys_aw_addr), .s_aw_valid(sys_aw_valid & sched_cs), .s_aw_ready(),
        .s_w_data(sys_w_data),   .s_w_strb(sys_w_strb), .s_w_valid(sys_w_valid), .s_w_ready(),
        .s_b_resp(), .s_b_valid(), .s_b_ready(sys_b_ready),
        .s_ar_addr(sys_ar_addr), .s_ar_valid(sys_ar_valid & sched_cs), .s_ar_ready(),
        .s_r_data(), .s_r_resp(), .s_r_valid(), .s_r_ready(sys_r_ready),
        .gpu_busy(gpu_busy), .gpu_done_irq(gpu_done_irq), .gpu_cmd_word(), .gpu_cmd_valid(),
        .npu_busy(npu_busy), .npu_done_irq(npu_done_irq), .npu_mat_a(), .npu_mat_b(), .npu_mat_c(), .npu_start_cmd(),
        .dma_busy(dma_done_irqs), .dma_done_irq(dma_done_irqs), .dma_src(), .dma_dst(), .dma_len(), .dma_start_cmd(),
        .scheduler_irq(scheduler_irq)
    );

    // 7. Performance Monitoring Unit (PMU)
    wire pmu_cs = sys_aw_valid && (sys_aw_addr >= 32'h0020_0380) && (sys_aw_addr <= 32'h0020_03FF);
    pmu_counters u_pmu (
        .clk(clk), .rst_n(sys_rst_n),
        .cpu0_instr_valid(cpu0_dbu_valid), .cpu1_instr_valid(cpu1_dbu_valid),
        .gpu_busy(gpu_busy), .npu_busy(npu_busy),
        .axi_read_pulse(axi_rd_pulse), .axi_write_pulse(axi_wr_pulse),
        .s_aw_addr(sys_aw_addr), .s_aw_valid(sys_aw_valid & pmu_cs), .s_aw_ready(),
        .s_w_data(sys_w_data),   .s_w_strb(sys_w_strb), .s_w_valid(sys_w_valid), .s_w_ready(),
        .s_b_resp(), .s_b_valid(), .s_b_ready(sys_b_ready),
        .s_ar_addr(sys_ar_addr), .s_ar_valid(sys_ar_valid & pmu_cs), .s_ar_ready(),
        .s_r_data(), .s_r_resp(), .s_r_valid(), .s_r_ready(sys_r_ready)
    );

    // 8. 5M × 9S AXI Crossbar Interconnect
    axi_crossbar u_xbar (
        .clk(clk), .rst_n(sys_rst_n),
        .m0_aw_addr(c0_aw_addr), .m0_aw_valid(c0_aw_valid), .m0_aw_ready(c0_aw_ready),
        .m0_w_data(c0_w_data),   .m0_w_strb(c0_w_strb),   .m0_w_valid(c0_w_valid),   .m0_w_ready(c0_w_ready),
        .m0_b_resp(c0_b_resp),   .m0_b_valid(c0_b_valid), .m0_b_ready(c0_b_ready),
        .m0_ar_addr(c0_ar_addr), .m0_ar_valid(c0_ar_valid), .m0_ar_ready(c0_ar_ready),
        .m0_r_data(c0_r_data),   .m0_r_resp(c0_r_resp),   .m0_r_valid(c0_r_valid),   .m0_r_ready(c0_r_ready),

        .m1_aw_addr(c1_aw_addr), .m1_aw_valid(c1_aw_valid), .m1_aw_ready(c1_aw_ready),
        .m1_w_data(c1_w_data),   .m1_w_strb(c1_w_strb),   .m1_w_valid(c1_w_valid),   .m1_w_ready(c1_w_ready),
        .m1_b_resp(c1_b_resp),   .m1_b_valid(c1_b_valid), .m1_b_ready(c1_b_ready),
        .m1_ar_addr(c1_ar_addr), .m1_ar_valid(c1_ar_valid), .m1_ar_ready(c1_ar_ready),
        .m1_r_data(c1_r_data),   .m1_r_resp(c1_r_resp),   .m1_r_valid(c1_r_valid),   .m1_r_ready(c1_r_ready),

        .m2_aw_addr(dm_aw_addr), .m2_aw_valid(dm_aw_valid), .m2_aw_ready(dm_aw_ready),
        .m2_w_data(dm_w_data),   .m2_w_strb(dm_w_strb),   .m2_w_valid(dm_w_valid),   .m2_w_ready(dm_w_ready),
        .m2_b_resp(dm_b_resp),   .m2_b_valid(dm_b_valid), .m2_b_ready(dm_b_ready),
        .m2_ar_addr(dm_ar_addr), .m2_ar_valid(dm_ar_valid), .m2_ar_ready(dm_ar_ready),
        .m2_r_data(dm_r_data),   .m2_r_resp(dm_r_resp),   .m2_r_valid(dm_r_valid),   .m2_r_ready(dm_r_ready),

        .m3_aw_addr(gpu_m_aw_addr), .m3_aw_valid(gpu_m_aw_valid), .m3_aw_ready(gpu_m_aw_ready),
        .m3_w_data(gpu_m_w_data),   .m3_w_strb(gpu_m_w_strb),   .m3_w_valid(gpu_m_w_valid),   .m3_w_ready(gpu_m_w_ready),
        .m3_b_resp(gpu_m_b_resp),   .m3_b_valid(gpu_m_b_valid), .m3_b_ready(gpu_m_b_ready),
        .m3_ar_addr(32'b0), .m3_ar_valid(1'b0), .m3_ar_ready(), .m3_r_data(), .m3_r_resp(), .m3_r_valid(), .m3_r_ready(1'b0),

        .m4_aw_addr(npu_m_aw_addr), .m4_aw_valid(npu_m_aw_valid), .m4_aw_ready(npu_m_aw_ready),
        .m4_w_data(npu_m_w_data),   .m4_w_strb(npu_m_w_strb),   .m4_w_valid(npu_m_w_valid),   .m4_w_ready(npu_m_w_ready),
        .m4_b_resp(npu_m_b_resp),   .m4_b_valid(npu_m_b_valid), .m4_b_ready(npu_m_b_ready),
        .m4_ar_addr(npu_m_ar_addr), .m4_ar_valid(npu_m_ar_valid), .m4_ar_ready(npu_m_ar_ready),
        .m4_r_data(npu_m_r_data),   .m4_r_resp(npu_m_r_resp),   .m4_r_valid(npu_m_r_valid),   .m4_r_ready(npu_m_r_ready),

        .s0_ar_addr(br_ar_addr), .s0_ar_valid(br_ar_valid), .s0_ar_ready(br_ar_ready), .s0_r_data(br_r_data), .s0_r_resp(br_r_resp), .s0_r_valid(br_r_valid), .s0_r_ready(br_r_ready),
        .s1_ar_addr(ir_ar_addr), .s1_ar_valid(ir_ar_valid), .s1_ar_ready(ir_ar_ready), .s1_r_data(ir_r_data), .s1_r_resp(ir_r_resp), .s1_r_valid(ir_r_valid), .s1_r_ready(ir_r_ready),

        .s2_aw_addr(d0_aw_addr), .s2_w_data(d0_w_data), .s2_w_strb(d0_w_strb), .s2_aw_valid(d0_aw_valid), .s2_aw_ready(d0_aw_ready), .s2_w_valid(d0_w_valid), .s2_w_ready(d0_w_ready), .s2_b_resp(d0_b_resp), .s2_b_valid(d0_b_valid), .s2_b_ready(d0_b_ready), .s2_ar_addr(d0_ar_addr), .s2_ar_valid(d0_ar_valid), .s2_ar_ready(d0_ar_ready), .s2_r_data(d0_r_data), .s2_r_resp(d0_r_resp), .s2_r_valid(d0_r_valid), .s2_r_ready(d0_r_ready),
        .s3_aw_addr(d1_aw_addr), .s3_w_data(d1_w_data), .s3_w_strb(d1_w_strb), .s3_aw_valid(d1_aw_valid), .s3_aw_ready(d1_aw_ready), .s3_w_valid(d1_w_valid), .s3_w_ready(d1_w_ready), .s3_b_resp(d1_b_resp), .s3_b_valid(d1_b_valid), .s3_b_ready(d1_b_ready), .s3_ar_addr(d1_ar_addr), .s3_ar_valid(d1_ar_valid), .s3_ar_ready(d1_ar_ready), .s3_r_data(d1_r_data), .s3_r_resp(d1_r_resp), .s3_r_valid(d1_r_valid), .s3_r_ready(d1_r_ready),

        .s4_aw_addr(sm_aw_addr), .s4_w_data(sm_w_data), .s4_w_strb(sm_w_strb), .s4_aw_valid(sm_aw_valid), .s4_aw_ready(sm_aw_ready), .s4_w_valid(sm_w_valid), .s4_w_ready(sm_w_ready), .s4_b_resp(sm_b_resp), .s4_b_valid(sm_b_valid), .s4_b_ready(sm_b_ready), .s4_ar_addr(sm_ar_addr), .s4_ar_valid(sm_ar_valid), .s4_ar_ready(sm_ar_ready), .s4_r_data(sm_r_data), .s4_r_resp(sm_r_resp), .s4_r_valid(sm_r_valid), .s4_r_ready(sm_r_ready),
        .s5_aw_addr(sys_aw_addr), .s5_w_data(sys_w_data), .s5_w_strb(sys_w_strb), .s5_aw_valid(sys_aw_valid), .s5_aw_ready(sys_aw_ready), .s5_w_valid(sys_w_valid), .s5_w_ready(sys_w_ready), .s5_b_resp(sys_b_resp), .s5_b_valid(sys_b_valid), .s5_b_ready(sys_b_ready), .s5_ar_addr(sys_ar_addr), .s5_ar_valid(sys_ar_valid), .s5_ar_ready(sys_ar_ready), .s5_r_data(sys_r_data), .s5_r_resp(sys_r_resp), .s5_r_valid(sys_r_valid), .s5_r_ready(sys_r_ready),

        .s6_aw_addr(pb_aw_addr), .s6_w_data(pb_w_data), .s6_w_strb(pb_w_strb), .s6_aw_valid(pb_aw_valid), .s6_aw_ready(pb_aw_ready), .s6_w_valid(pb_w_valid), .s6_w_ready(pb_w_ready), .s6_b_resp(pb_b_resp), .s6_b_valid(pb_b_valid), .s6_b_ready(pb_b_ready), .s6_ar_addr(pb_ar_addr), .s6_ar_valid(pb_ar_valid), .s6_ar_ready(pb_ar_ready), .s6_r_data(pb_r_data), .s6_r_resp(pb_r_resp), .s6_r_valid(pb_r_valid), .s6_r_ready(pb_r_ready),

        .s7_aw_addr(gpu_s_aw_addr), .s7_w_data(gpu_s_w_data), .s7_w_strb(gpu_s_w_strb), .s7_aw_valid(gpu_s_aw_valid), .s7_aw_ready(gpu_s_aw_ready), .s7_w_valid(gpu_s_w_valid), .s7_w_ready(gpu_s_w_ready), .s7_b_resp(gpu_s_b_resp), .s7_b_valid(gpu_s_b_valid), .s7_b_ready(gpu_s_b_ready), .s7_ar_addr(gpu_s_ar_addr), .s7_ar_valid(gpu_s_ar_valid), .s7_ar_ready(gpu_s_ar_ready), .s7_r_data(gpu_s_r_data), .s7_r_resp(gpu_s_r_resp), .s7_r_valid(gpu_s_r_valid), .s7_r_ready(gpu_s_r_ready),

        .s8_aw_addr(npu_s_aw_addr), .s8_w_data(npu_s_w_data), .s8_w_strb(npu_s_w_strb), .s8_aw_valid(npu_s_aw_valid), .s8_aw_ready(npu_s_aw_ready), .s8_w_valid(npu_s_w_valid), .s8_w_ready(npu_s_w_ready), .s8_b_resp(npu_s_b_resp), .s8_b_valid(npu_s_b_valid), .s8_b_ready(npu_s_b_ready), .s8_ar_addr(npu_s_ar_addr), .s8_ar_valid(npu_s_ar_valid), .s8_ar_ready(npu_s_ar_ready), .s8_r_data(npu_s_r_data), .s8_r_resp(npu_s_r_resp), .s8_r_valid(npu_s_r_valid), .s8_r_ready(npu_s_r_ready),

        .snoop_addr(snoop_addr), .snoop_wr_valid(snoop_wr_valid),
        .axi_read_pulse(axi_rd_pulse), .axi_write_pulse(axi_wr_pulse)
    );

    // 9. Cache Coherency Controller
    cache_coherency u_coherency (
        .clk(clk), .rst_n(sys_rst_n),
        .snoop_addr(snoop_addr), .snoop_wr_valid(snoop_wr_valid), .write_master_id(2'b0),
        .c0_snoop_addr(c0_dsnoop_addr), .c0_snoop_inval(c0_dsnoop_inval), .c0_snoop_hit(c0_dsnoop_hit), .c0_snoop_dirty(c0_dsnoop_dirty),
        .c1_snoop_addr(c1_dsnoop_addr), .c1_snoop_inval(c1_dsnoop_inval), .c1_snoop_hit(c1_dsnoop_hit), .c1_snoop_dirty(c1_dsnoop_dirty),
        .i0_snoop_addr(c0_isnoop_addr), .i0_snoop_inval(c0_isnoop_inval), .i1_snoop_addr(c1_isnoop_addr), .i1_snoop_inval(c1_isnoop_inval),
        .coherency_event_count()
    );

    // 10. IPC Mailbox
    ipc_mailbox u_ipc (
        .clk(clk), .rst_n(sys_rst_n),
        .s_aw_addr(sys_aw_addr), .s_aw_valid(sys_aw_valid & (sys_aw_addr[9:8] == 2'b00)), .s_aw_ready(),
        .s_w_data(sys_w_data),   .s_w_strb(sys_w_strb), .s_w_valid(sys_w_valid), .s_w_ready(),
        .s_b_resp(), .s_b_valid(), .s_b_ready(sys_b_ready),
        .s_ar_addr(sys_ar_addr), .s_ar_valid(sys_ar_valid & (sys_ar_addr[9:8] == 2'b00)), .s_ar_ready(),
        .s_r_data(), .s_r_resp(), .s_r_valid(), .s_r_ready(sys_r_ready),
        .accessing_master(2'b00), .irq_cpu0(ipc_irq_cpu0), .irq_cpu1(ipc_irq_cpu1)
    );

    // 11. Shared PIC
    wire [7:0] irq_lines_combined = 8'b0;
    shared_pic u_shared_pic (
        .clk(clk), .rst_n(sys_rst_n), .irq_lines(irq_lines_combined),
        .ipc_irq_cpu0(ipc_irq_cpu0), .ipc_irq_cpu1(ipc_irq_cpu1), .dma_irq(dma_done_irqs),
        .cpu0_irq_req(cpu0_irq_req), .cpu0_irq_vector(cpu0_irq_vector), .cpu0_irq_ack(cpu0_irq_ack), .cpu0_in_isr(cpu0_in_isr),
        .cpu1_irq_req(cpu1_irq_req), .cpu1_irq_vector(cpu1_irq_vector), .cpu1_irq_ack(cpu1_irq_ack), .cpu1_in_isr(cpu1_in_isr),
        .s_aw_addr(32'b0), .s_aw_valid(1'b0), .s_aw_ready(), .s_w_data(32'b0), .s_w_strb(4'b0), .s_w_valid(1'b0), .s_w_ready(),
        .s_b_resp(), .s_b_valid(), .s_b_ready(1'b0), .s_ar_addr(32'b0), .s_ar_valid(1'b0), .s_ar_ready(), .s_r_data(), .s_r_resp(), .s_r_valid(), .s_r_ready(1'b0)
    );

    // 12. Peripheral Bridge
    wire [31:0] br_cpu_addr, br_cpu_wdata, br_cpu_rdata; wire br_cpu_we, br_cpu_re, br_cpu_byte, br_cpu_ready;
    localparam PB_IDLE = 2'd0, PB_WDATA = 2'd1, PB_WRESP = 2'd2, PB_RDATA = 2'd3;
    reg [1:0] pb_state; reg [31:0] pb_aw_addr_r, pb_w_data_r, pb_ar_addr_r; reg pb_is_write;

    always @(posedge clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            pb_state <= PB_IDLE; pb_aw_ready <= 1'b0; pb_w_ready <= 1'b0; pb_b_valid <= 1'b0;
            pb_ar_ready <= 1'b0; pb_r_valid <= 1'b0; pb_r_data <= 32'b0; pb_r_resp <= 2'b0; pb_b_resp <= 2'b0; pb_is_write <= 1'b0;
        end else begin
            pb_aw_ready <= 1'b0; pb_w_ready <= 1'b0; pb_ar_ready <= 1'b0; pb_b_valid <= 1'b0; pb_r_valid <= 1'b0;
            case (pb_state)
                PB_IDLE: begin
                    if (pb_aw_valid) begin pb_aw_ready <= 1'b1; pb_aw_addr_r <= pb_aw_addr; pb_is_write <= 1'b1; pb_state <= PB_WDATA; end
                    else if (pb_ar_valid) begin pb_ar_ready <= 1'b1; pb_ar_addr_r <= pb_ar_addr; pb_is_write <= 1'b0; pb_state <= PB_RDATA; end
                end
                PB_WDATA: begin
                    pb_w_ready <= 1'b1;
                    if (pb_w_valid) begin pb_w_data_r <= pb_w_data; pb_w_ready <= 1'b0; pb_b_resp <= `AXI_RESP_OKAY; pb_state <= PB_WRESP; end
                end
                PB_WRESP: begin pb_b_valid <= 1'b1; if (pb_b_valid && pb_b_ready) begin pb_b_valid <= 1'b0; pb_state <= PB_IDLE; end end
                PB_RDATA: begin pb_r_data <= br_cpu_rdata; pb_r_resp <= `AXI_RESP_OKAY; pb_r_valid <= 1'b1; if (pb_r_valid && pb_r_ready) begin pb_r_valid <= 1'b0; pb_state <= PB_IDLE; end end
            endcase
        end
    end
    assign br_cpu_addr = pb_is_write ? pb_aw_addr_r : pb_ar_addr_r; assign br_cpu_wdata = pb_w_data_r;
    assign br_cpu_we = (pb_state == PB_WRESP); assign br_cpu_re = (pb_state == PB_RDATA); assign br_cpu_byte = 1'b0;

    // Memory Instances
    wire [7:0] boot_addr_wire; wire [31:0] boot_rdata_wire; wire [31:0] irom_rdata_wire, dram0_rdata_wire, dram1_rdata_wire, shm_rdata_wire;
    wire [12:0] dram0_addr_wire; wire dram0_we_wire; wire [3:0] dram0_be_wire; wire [31:0] dram0_wdata_wire;

    boot_rom boot_rom_inst (.clk(clk), .addr(boot_addr_wire), .data_out(boot_rdata_wire));
    reg br_r_valid_r; always @(posedge clk or negedge sys_rst_n) begin if (!sys_rst_n) br_r_valid_r <= 1'b0; else br_r_valid_r <= br_ar_valid & br_ar_ready; end
    assign br_ar_ready = 1'b1; assign br_r_data = boot_rdata_wire; assign br_r_resp = 2'b00; assign br_r_valid = br_r_valid_r;

    instruction_rom #(.ADDR_WIDTH(12), .MEM_FILE(MEM_FILE)) irom_inst (.clk(clk), .addr(ir_ar_addr[13:2]), .data_out(ir_r_data));
    reg ir_r_valid_r; always @(posedge clk or negedge sys_rst_n) begin if (!sys_rst_n) ir_r_valid_r <= 1'b0; else ir_r_valid_r <= ir_ar_valid & ir_ar_ready; end
    assign ir_ar_ready = 1'b1; assign ir_r_resp = 2'b00; assign ir_r_valid = ir_r_valid_r;

    data_ram #(.ADDR_WIDTH(13)) dram0_inst (.clk(clk), .we(dram0_we_wire), .be(dram0_be_wire), .addr(dram0_addr_wire), .wdata(dram0_wdata_wire), .rdata(dram0_rdata_wire));
    reg d0_r_valid_r; always @(posedge clk or negedge sys_rst_n) begin if (!sys_rst_n) d0_r_valid_r <= 1'b0; else d0_r_valid_r <= d0_ar_valid & d0_ar_ready; end
    assign d0_aw_ready = 1'b1; assign d0_w_ready = 1'b1; assign d0_b_resp = 2'b0; assign d0_b_valid = d0_w_valid; assign d0_ar_ready = 1'b1; assign d0_r_data = 32'b0; assign d0_r_resp = 2'b0; assign d0_r_valid = d0_r_valid_r;

    data_ram #(.ADDR_WIDTH(13)) dram1_inst (.clk(clk), .we(d1_aw_valid & d1_w_valid), .be(d1_w_strb), .addr(d1_aw_valid ? d1_aw_addr[14:2] : d1_ar_addr[14:2]), .wdata(d1_w_data), .rdata(dram1_rdata_wire));
    reg d1_r_valid_r; always @(posedge clk or negedge sys_rst_n) begin if (!sys_rst_n) d1_r_valid_r <= 1'b0; else d1_r_valid_r <= d1_ar_valid & d1_ar_ready; end
    assign d1_aw_ready = 1'b1; assign d1_w_ready = 1'b1; assign d1_b_resp = 2'b0; assign d1_b_valid = d1_w_valid; assign d1_ar_ready = 1'b1; assign d1_r_data = dram1_rdata_wire; assign d1_r_resp = 2'b0; assign d1_r_valid = d1_r_valid_r;

    data_ram #(.ADDR_WIDTH(13)) shared_sram_inst (.clk(clk), .we(sm_aw_valid & sm_w_valid), .be(sm_w_strb), .addr(sm_aw_valid ? sm_aw_addr[14:2] : sm_ar_addr[14:2]), .wdata(sm_w_data), .rdata(shm_rdata_wire));
    reg sm_r_valid_r; always @(posedge clk or negedge sys_rst_n) begin if (!sys_rst_n) sm_r_valid_r <= 1'b0; else sm_r_valid_r <= sm_ar_valid & sm_ar_ready; end
    assign sm_aw_ready = 1'b1; assign sm_w_ready = 1'b1; assign sm_b_resp = 2'b0; assign sm_b_valid = sm_w_valid; assign sm_ar_ready = 1'b1; assign sm_r_data = shm_rdata_wire; assign sm_r_resp = 2'b0; assign sm_r_valid = sm_r_valid_r;

    // Legacy memory_controller
    memory_controller mem_ctrl_inst (
        .clk(clk), .rst_n(sys_rst_n), .cpu_addr(br_cpu_addr), .cpu_we(br_cpu_we), .cpu_re(br_cpu_re), .cpu_wdata(br_cpu_wdata), .cpu_byte(br_cpu_byte), .cpu_rdata(br_cpu_rdata), .cpu_ready(br_cpu_ready),
        .boot_addr(boot_addr_wire), .boot_rdata(boot_rdata_wire), .irom_addr(), .irom_rdata(irom_rdata_wire), .dram_addr(dram0_addr_wire), .dram_we(dram0_we_wire), .dram_be(dram0_be_wire), .dram_wdata(dram0_wdata_wire), .dram_rdata(dram0_rdata_wire),
        .gpio_rdata(32'b0), .uart_rdata(32'b0), .spi_rdata(32'b0), .i2c_rdata(32'b0), .timer_rdata(32'b0), .pwm_rdata(32'b0), .irq_ctrl_rdata(32'b0), .wdog_rdata(32'b0), .debug_rdata(32'b0), .lcd_rdata(32'b0), .oled_rdata(32'b0), .eeprom_rdata(32'b0), .seven_seg_rdata(32'b0), .keypad_rdata(32'b0), .ultrasonic_rdata(32'b0), .temp_sensor_rdata(32'b0),
        .gpio_cs(), .uart_cs(), .spi_cs(), .i2c_cs(), .timer_cs(), .pwm_cs(), .irq_ctrl_cs(), .wdog_cs(), .debug_cs(), .lcd_cs(), .oled_cs(), .eeprom_cs(), .seven_seg_cs(), .keypad_cs(), .ultrasonic_cs(), .temp_sensor_cs(), .periph_we(), .periph_addr(), .periph_wdata()
    );

    // =========================================================================
    // Phase 4: Hardware Security Engine (HSE)
    // =========================================================================
    wire hse_cs_aw = sys_aw_valid && (sys_aw_addr >= 32'h0020_0600) && (sys_aw_addr <= 32'h0020_06FF);
    wire hse_cs_ar = sys_ar_valid && (sys_ar_addr >= 32'h0020_0600) && (sys_ar_addr <= 32'h0020_06FF);

    hse_top u_hse (
        .clk(clk), .rst_n(sys_rst_n),
        .cpu0_priv_level(2'b11), .cpu1_priv_level(2'b11),  // MACHINE level (extend CPU debug bus for real priv)
        .cpu0_pipe_valid(cpu0_dbu_valid), .cpu1_pipe_valid(cpu1_dbu_valid),
        .cpu0_pc(cpu0_dbu_pc), .cpu0_instr(cpu0_dbu_instr), .cpu0_dbu_valid(cpu0_dbu_valid),
        .cpu1_pc(cpu1_dbu_pc), .cpu1_instr(cpu1_dbu_instr), .cpu1_dbu_valid(cpu1_dbu_valid),
        .m0_aw_addr(c0_aw_addr), .m0_aw_valid(c0_aw_valid),
        .m0_ar_addr(c0_ar_addr), .m0_ar_valid(c0_ar_valid),
        .m1_aw_addr(c1_aw_addr), .m1_aw_valid(c1_aw_valid),
        .m1_ar_addr(c1_ar_addr), .m1_ar_valid(c1_ar_valid),
        .m2_aw_addr(dm_aw_addr), .m2_aw_valid(dm_aw_valid),
        .m2_ar_addr(dm_ar_addr), .m2_ar_valid(dm_ar_valid),
        .m3_aw_valid(gpu_m_aw_valid), .m4_aw_valid(npu_m_aw_valid),
        .mpu_fault(mpu_fault), .fault_addr(fault_addr),
        .fault_type(fault_type), .trojan_alert(trojan_alert),
        .trojan_fault_report(trojan_fault_report), .hse_irq(hse_irq),
        .s_aw_addr(sys_aw_addr), .s_aw_valid(hse_cs_aw), .s_aw_ready(),
        .s_w_data(sys_w_data), .s_w_strb(sys_w_strb), .s_w_valid(sys_w_valid), .s_w_ready(),
        .s_b_resp(), .s_b_valid(), .s_b_ready(sys_b_ready),
        .s_ar_addr(sys_ar_addr), .s_ar_valid(hse_cs_ar), .s_ar_ready(),
        .s_r_data(), .s_r_resp(), .s_r_valid(), .s_r_ready(sys_r_ready)
    );

    // =========================================================================
    // Phase 4: Dynamic Power Optimization Unit (DPOU)
    // =========================================================================
    wire dpou_cs_aw = sys_aw_valid && (sys_aw_addr >= 32'h0020_0700) && (sys_aw_addr <= 32'h0020_07FF);
    wire dpou_cs_ar = sys_ar_valid && (sys_ar_addr >= 32'h0020_0700) && (sys_ar_addr <= 32'h0020_07FF);

    power_monitor u_dpou (
        .clk(clk), .rst_n(sys_rst_n),
        .gpu_busy(gpu_busy), .npu_busy(npu_busy),
        .cpu0_pipe_valid(cpu0_dbu_valid), .cpu1_pipe_valid(cpu1_dbu_valid),
        .dma_active(|dma_done_irqs),
        .m0_aw_valid(c0_aw_valid), .m0_ar_valid(c0_ar_valid),
        .m1_aw_valid(c1_aw_valid), .m1_ar_valid(c1_ar_valid),
        .m3_aw_valid(gpu_m_aw_valid), .m4_ar_valid(npu_m_ar_valid),
        .clk_en_gpu(clk_en_gpu_pm), .clk_en_npu(clk_en_npu_pm),
        .clk_en_cpu0(clk_en_cpu0_pm), .clk_en_cpu1(clk_en_cpu1_pm), .clk_en_dma(clk_en_dma_pm),
        .iso_gpu(iso_gpu_pm), .iso_npu(iso_npu_pm),
        .s_aw_addr(sys_aw_addr), .s_aw_valid(dpou_cs_aw), .s_aw_ready(),
        .s_w_data(sys_w_data), .s_w_strb(sys_w_strb), .s_w_valid(sys_w_valid), .s_w_ready(),
        .s_b_resp(), .s_b_valid(), .s_b_ready(sys_b_ready),
        .s_ar_addr(sys_ar_addr), .s_ar_valid(dpou_cs_ar), .s_ar_ready(),
        .s_r_data(), .s_r_resp(), .s_r_valid(), .s_r_ready(sys_r_ready)
    );

    // =========================================================================
    // Phase 4: Advanced Debug Unit (ADBU)
    // =========================================================================
    wire adbu_cs_aw = sys_aw_valid && (sys_aw_addr >= 32'h0020_0800) && (sys_aw_addr <= 32'h0020_08FF);
    wire adbu_cs_ar = sys_ar_valid && (sys_ar_addr >= 32'h0020_0800) && (sys_ar_addr <= 32'h0020_08FF);

    adbu_top u_adbu (
        .clk(clk), .rst_n(sys_rst_n),
        .cpu0_pc(cpu0_dbu_pc), .cpu0_instr(cpu0_dbu_instr), .cpu0_dbu_valid(cpu0_dbu_valid),
        .cpu1_pc(cpu1_dbu_pc), .cpu1_instr(cpu1_dbu_instr), .cpu1_dbu_valid(cpu1_dbu_valid),
        .cpu0_priv(2'b11), .cpu1_priv(2'b11),
        .m0_aw_addr(c0_aw_addr), .m0_w_data(c0_w_data), .m0_aw_valid(c0_aw_valid), .m0_w_valid(c0_w_valid),
        .m1_aw_addr(c1_aw_addr), .m1_w_data(c1_w_data), .m1_aw_valid(c1_aw_valid), .m1_w_valid(c1_w_valid),
        .m2_aw_addr(dm_aw_addr), .m2_w_data(dm_w_data), .m2_aw_valid(dm_aw_valid), .m2_w_valid(dm_w_valid),
        .m0_ar_addr(c0_ar_addr), .m0_ar_valid(c0_ar_valid),
        .m1_ar_addr(c1_ar_addr), .m1_ar_valid(c1_ar_valid),
        .m2_ar_addr(dm_ar_addr), .m2_ar_valid(dm_ar_valid),
        .mpu_fault(mpu_fault), .fault_addr(fault_addr), .fault_type(fault_type),
        .trojan_alert(trojan_alert), .wdt_reset(wdt_reset), .dma_error(1'b0),
        .s_aw_addr(sys_aw_addr), .s_aw_valid(adbu_cs_aw), .s_aw_ready(),
        .s_w_data(sys_w_data), .s_w_strb(sys_w_strb), .s_w_valid(sys_w_valid), .s_w_ready(),
        .s_b_resp(), .s_b_valid(), .s_b_ready(sys_b_ready),
        .s_ar_addr(sys_ar_addr), .s_ar_valid(adbu_cs_ar), .s_ar_ready(),
        .s_r_data(), .s_r_resp(), .s_r_valid(), .s_r_ready(sys_r_ready)
    );

    // Telemetry LEDs — Phase 4 Extended
    assign status_leds[0]  = cpu0_dbu_valid;
    assign status_leds[1]  = cpu1_dbu_valid;
    assign status_leds[2]  = gpu_busy;
    assign status_leds[3]  = npu_busy;
    assign status_leds[4]  = |dma_done_irqs;
    assign status_leds[5]  = scheduler_irq;
    assign status_leds[6]  = mpu_fault;       // MPU security violation
    assign status_leds[7]  = trojan_alert;    // Hardware Trojan detection alert
    assign status_leds[8]  = hse_irq;         // Combined security IRQ
    assign status_leds[9]  = clk_en_gpu_pm;   // GPU clock gate status
    assign status_leds[10] = clk_en_npu_pm;   // NPU clock gate status
    assign status_leds[11] = iso_gpu_pm;      // GPU operand isolation active
    assign status_leds[15:12] = 4'b0;

endmodule
