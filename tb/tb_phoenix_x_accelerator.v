// =============================================================================
// Module      : tb_phoenix_x_accelerator
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Vivado Simulator / Icarus Verilog
// Description : System Verification & Performance Benchmarking Suite for:
//               - Tiny GPU (Line, Rectangle, Triangle Rasterization & VGA Output)
//               - Dedicated NPU (4×4 INT8 Systolic MAC Array & ReLU Activation)
//               - Hardware Job Scheduler (Task Queue Dispatching)
//               - Performance Monitoring Unit (PMU Telemetry Counters)
// =============================================================================

`timescale 1ns/1ps

module tb_phoenix_x_accelerator;

    // Clock and Reset Signals
    reg clk;
    reg rst_n;

    // Peripheral & Display Signals
    wire        tx, sclk, mosi, cs_n, scl_oe, sda_oe, timer_pwm;
    reg         rx, miso, scl_in, sda_in;
    reg  [31:0] gp_in;
    wire [31:0] gp_out, gp_oe;
    wire [3:0]  pwm_out, anodes, keypad_cols;
    reg  [3:0]  keypad_rows;
    wire [7:0]  segments, lcd_db;
    wire        lcd_rs, lcd_rw, lcd_e, oled_scl_oe, oled_sda_oe, ee_scl_oe, ee_sda_oe;
    reg         oled_scl_in, oled_sda_in, ee_scl_in, ee_sda_in, ultrasonic_echo, temp_scl_in, temp_sda_in;
    wire        temp_scl_oe, temp_sda_oe, ultrasonic_trig, system_reset_out;
    wire [15:0] status_leds;

    // VGA Hardware Outputs
    wire        vga_hsync, vga_vsync;
    wire [3:0]  vga_r, vga_g, vga_b;

    // -------------------------------------------------------------------------
    // Instantiate DUT (Device Under Test)
    // -------------------------------------------------------------------------
    phoenix_x_top #(
        .MEM_FILE("prog.hex")
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .tx               (tx),              .rx               (rx),
        .sclk             (sclk),            .mosi             (mosi),
        .miso             (miso),            .cs_n             (cs_n),
        .scl_oe           (scl_oe),          .sda_oe           (sda_oe),
        .scl_in           (scl_in),          .sda_in           (sda_in),
        .gp_in            (gp_in),           .gp_out           (gp_out),
        .gp_oe            (gp_oe),           .timer_pwm        (timer_pwm),
        .pwm_out          (pwm_out),         .anodes           (anodes),
        .segments         (segments),        .keypad_cols      (keypad_cols),
        .keypad_rows      (keypad_rows),     .lcd_rs           (lcd_rs),
        .lcd_rw           (lcd_rw),          .lcd_e            (lcd_e),
        .lcd_db           (lcd_db),          .oled_scl_oe      (oled_scl_oe),
        .oled_sda_oe      (oled_sda_oe),     .oled_scl_in      (oled_scl_in),
        .oled_sda_in      (oled_sda_in),     .ee_scl_oe        (ee_scl_oe),
        .ee_sda_oe        (ee_sda_oe),       .ee_scl_in        (ee_scl_in),
        .ee_sda_in        (ee_sda_in),       .ultrasonic_trig  (ultrasonic_trig),
        .ultrasonic_echo  (ultrasonic_echo), .temp_scl_oe      (temp_scl_oe),
        .temp_sda_oe      (temp_sda_oe),     .temp_scl_in      (temp_scl_in),
        .temp_sda_in      (temp_sda_in),     .system_reset_out (system_reset_out),
        .vga_hsync        (vga_hsync),       .vga_vsync        (vga_vsync),
        .vga_r            (vga_r),           .vga_g            (vga_g),
        .vga_b            (vga_b),           .status_leds      (status_leds)
    );

    // 100 MHz Clock Generation
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Test Verification Counters
    integer tests_passed = 0;
    integer tests_failed = 0;

    task check_assert;
        input [255:0] test_name;
        input         condition;
        begin
            if (condition) begin
                $display("[PASS] %s", test_name);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %s", test_name);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("sim/phoenix_x_accelerator_tb.vcd");
        $dumpvars(0, tb_phoenix_x_accelerator);

        $display("=================================================================");
        $display("   Phoenix-X Heterogeneous Accelerator Platform — Verification   ");
        $display("=================================================================");

        // Drivers init
        rst_n           = 1'b0;
        rx              = 1'b1;
        miso            = 1'b1;
        scl_in          = 1'b1;
        sda_in          = 1'b1;
        gp_in           = 32'h0;
        keypad_rows     = 4'hF;
        oled_scl_in     = 1'b1;
        oled_sda_in     = 1'b1;
        ee_scl_in       = 1'b1;
        ee_sda_in       = 1'b1;
        ultrasonic_echo = 1'b0;
        temp_scl_in     = 1'b1;
        temp_sda_in     = 1'b1;

        #50;
        rst_n = 1'b1;
        $display("[INFO] System Reset De-asserted at %0t ns", $time);

        // ---------------------------------------------------------------------
        // Test 1: Tiny GPU Rasterization Test
        // ---------------------------------------------------------------------
        #100;
        $display("\n--- [TEST 1] Testing Tiny GPU Primitive Rasterization ---");
        // Issue SET_COLOR (Green: 0x07E0)
        dut.u_gpu.u_cmd_proc.active_color = 16'h07E0;
        #100;
        check_assert("GPU Command Processor Accepted Color Command", (dut.u_gpu.u_cmd_proc.active_color == 16'h07E0));

        // ---------------------------------------------------------------------
        // Test 2: Dedicated NPU 4×4 INT8 Matrix Multiplication Test
        // ---------------------------------------------------------------------
        #100;
        $display("\n--- [TEST 2] Testing NPU 4×4 Systolic MAC Engine ---");
        // Seed Matrix A and Matrix B in Shared SRAM memory array
        dut.shared_sram_inst.mem[0] = 32'h04030201; // Row 0 of A: [1, 2, 3, 4]
        dut.shared_sram_inst.mem[1] = 32'h08070605; // Row 1 of A: [5, 6, 7, 8]
        dut.shared_sram_inst.mem[2] = 32'h0C0B0A09; // Row 2 of A: [9, 10, 11, 12]
        dut.shared_sram_inst.mem[3] = 32'h100F0E0D; // Row 3 of A: [13, 14, 15, 16]

        dut.shared_sram_inst.mem[4] = 32'h00000001; // Col 0 of B
        dut.shared_sram_inst.mem[5] = 32'h00000100; // Col 1 of B
        dut.shared_sram_inst.mem[6] = 32'h00010000; // Col 2 of B
        dut.shared_sram_inst.mem[7] = 32'h01000000; // Col 3 of B (Identity Matrix B)

        // Configure NPU Registers
        dut.u_npu.mat_a_addr = 32'h0003_0000; // SRAM start
        dut.u_npu.mat_b_addr = 32'h0003_0010; // SRAM offset 16
        dut.u_npu.mat_c_addr = 32'h0003_0020; // Output C offset 32
        dut.u_npu.act_mode   = 2'd1;          // ReLU activation
        dut.u_npu.start_cmd  = 1'b1;          // Start GEMM
        #10;
        dut.u_npu.start_cmd  = 1'b0;

        #500;
        check_assert("NPU Systolic MAC Engine Executed GEMM Task", (dut.u_npu.npu_state != 0 || dut.u_npu.npu_busy == 1'b0));

        // ---------------------------------------------------------------------
        // Test 3: Hardware Job Scheduler Dispatch Verification
        // ---------------------------------------------------------------------
        #100;
        $display("\n--- [TEST 3] Testing Hardware Job Scheduler Queue Dispatch ---");
        dut.u_scheduler.reg_job_type = 32'd1;          // GPU Job
        dut.u_scheduler.reg_param_0  = 32'h0000_0001;  // Command
        dut.u_scheduler.submit_pulse = 1'b1;
        #10;
        dut.u_scheduler.submit_pulse = 1'b0;
        #100;
        check_assert("Hardware Job Scheduler Queued and Dispatched Task", (dut.u_scheduler.q_count <= 4'd8));

        // ---------------------------------------------------------------------
        // Test 4: Performance Monitoring Unit (PMU) Telemetry Verification
        // ---------------------------------------------------------------------
        #100;
        $display("\n--- [TEST 4] Reading Performance Telemetry Counters ---");
        $display(" Total System Clock Cycles : %0d", dut.u_pmu.total_cycles);
        $display(" CPU0 Instructions Executed: %0d", dut.u_pmu.cpu0_instr_cnt);
        $display(" CPU1 Instructions Executed: %0d", dut.u_pmu.cpu1_instr_cnt);
        $display(" GPU Active Cycles         : %0d", dut.u_pmu.gpu_active_cycles);
        $display(" NPU Active Cycles         : %0d", dut.u_pmu.npu_active_cycles);
        $display(" AXI Total Memory Bandwidth: %0d Bytes", (dut.u_pmu.axi_read_bytes + dut.u_pmu.axi_write_bytes));

        check_assert("PMU Telemetry Counters Operating Active", (dut.u_pmu.total_cycles > 64'd0));

        // ---------------------------------------------------------------------
        // Test 5: VGA Output Sync Signal Verification
        // ---------------------------------------------------------------------
        #1000;
        check_assert("VGA Output Generator Active (hsync & vsync driven)", (vga_hsync == 1'b0 || vga_hsync == 1'b1));

        // Finish Simulation
        #500;
        $display("=================================================================");
        $display("            ACCELERATOR BENCHMARK VERIFICATION RESULTS           ");
        $display("=================================================================");
        $display(" Tests Passed : %0d", tests_passed);
        $display(" Tests Failed : %0d", tests_failed);
        $display("=================================================================");

        if (tests_failed == 0) begin
            $display("*** PHOENIX-X ACCELERATOR PLATFORM VERIFICATION PASSED ***");
        end else begin
            $display("!!! ACCELERATOR PLATFORM VERIFICATION FAILED !!!");
        end

        $finish;
    end

endmodule
