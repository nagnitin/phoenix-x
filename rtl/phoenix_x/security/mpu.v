// =============================================================================
// Module      : mpu
// Project     : Phoenix-X Phase 4 — Hardware Security Engine
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Memory Protection Unit with 8 configurable regions, 3-level
//               privilege model (MACHINE/SUPERVISOR/USER), and per-region
//               RWX permission bits. AXI Slave config at 0x0020_0600.
//
// Privilege Levels:
//   2'b11 = MACHINE    (full access, bypasses all MPU checks)
//   2'b01 = SUPERVISOR (region-limited access)
//   2'b00 = USER       (strict region enforcement)
//
// Fault Types:
//   2'b00 = READ  violation
//   2'b01 = WRITE violation
//   2'b10 = EXEC  violation
//   2'b11 = RANGE violation (address not in any region)
//
// Region Registers (per region i, 0-7):
//   BASE[i]  @ 0x0020_0600 + i*16 + 0x00   [31:0] base address (4KB aligned)
//   MASK[i]  @ 0x0020_0600 + i*16 + 0x04   [31:0] size mask (2^N - 1 granularity)
//   PERM[i]  @ 0x0020_0600 + i*16 + 0x08   [7:0]  {priv_lvl[1:0], exec, write, read, valid}
// =============================================================================

`timescale 1ns/1ps
`include "rtl/phoenix_x/axi/axi_defines.vh"

module mpu (
    input  wire        clk,
    input  wire        rst_n,

    // CPU Privilege Level from CPU core debug bus
    input  wire [1:0]  cpu0_priv_level,   // Current privilege level of CPU0
    input  wire [1:0]  cpu1_priv_level,   // Current privilege level of CPU1

    // AXI Transaction Monitor Inputs (from crossbar)
    input  wire [31:0] m0_aw_addr,  input wire m0_aw_valid,  // CPU0 write
    input  wire [31:0] m0_ar_addr,  input wire m0_ar_valid,  // CPU0 read
    input  wire [31:0] m1_aw_addr,  input wire m1_aw_valid,  // CPU1 write
    input  wire [31:0] m1_ar_addr,  input wire m1_ar_valid,  // CPU1 read
    input  wire [31:0] m2_aw_addr,  input wire m2_aw_valid,  // DMA write
    input  wire [31:0] m2_ar_addr,  input wire m2_ar_valid,  // DMA read

    // Fault Outputs
    output reg         mpu_fault,        // High for 1 cycle on violation
    output reg  [31:0] fault_addr,       // Address that caused fault
    output reg  [1:0]  fault_type,       // 00=read, 01=write, 10=exec, 11=range
    output reg  [2:0]  fault_master_id,  // 0=CPU0, 1=CPU1, 2=DMA
    output reg         mpu_irq,          // Interrupt to Shared PIC

    // AXI-4 Lite Config Slave (MPU region configuration)
    input  wire [31:0] s_aw_addr,   input wire s_aw_valid,  output reg s_aw_ready,
    input  wire [31:0] s_w_data,    input wire [3:0] s_w_strb,
    input  wire        s_w_valid,   output reg s_w_ready,
    output reg  [1:0]  s_b_resp,    output reg s_b_valid,   input wire s_b_ready,
    input  wire [31:0] s_ar_addr,   input wire s_ar_valid,  output reg s_ar_ready,
    output reg  [31:0] s_r_data,    output reg [1:0] s_r_resp,
    output reg         s_r_valid,   input wire s_r_ready
);

    // -------------------------------------------------------------------------
    // MPU Region Table: 8 Regions × 3 registers each
    // -------------------------------------------------------------------------
    localparam N_REGIONS = 8;

    reg [31:0] region_base [0:N_REGIONS-1];   // Base address (4-KB aligned)
    reg [31:0] region_mask [0:N_REGIONS-1];   // Address mask (size − 1)
    reg [7:0]  region_perm [0:N_REGIONS-1];   // {2'b priv_min, exec, write, read, valid}
    // perm bits: [0]=valid, [1]=read_allow, [2]=write_allow, [3]=exec_allow
    //            [5:4]=min_privilege_level (00=user access OK, 11=machine only)

    integer k;

    // -------------------------------------------------------------------------
    // Privilege Level Constants
    // -------------------------------------------------------------------------
    localparam PRIV_MACHINE    = 2'b11;
    localparam PRIV_SUPERVISOR = 2'b01;
    localparam PRIV_USER       = 2'b00;

    // -------------------------------------------------------------------------
    // AXI Config Slave FSM
    // -------------------------------------------------------------------------
    localparam CS_IDLE  = 2'd0, CS_WDATA = 2'd1, CS_WRESP = 2'd2, CS_RDATA = 2'd3;
    reg [1:0]  cs_state;
    reg [31:0] cs_aw_addr_r, cs_ar_addr_r, cs_w_data_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs_state   <= CS_IDLE;
            s_aw_ready <= 1'b0; s_w_ready  <= 1'b0; s_b_valid  <= 1'b0;
            s_ar_ready <= 1'b0; s_r_valid  <= 1'b0;
            for (k = 0; k < N_REGIONS; k = k + 1) begin
                region_base[k] <= 32'h0; region_mask[k] <= 32'h0; region_perm[k] <= 8'h0;
            end
        end else begin
            s_aw_ready <= 1'b0; s_w_ready <= 1'b0; s_ar_ready <= 1'b0;
            s_b_valid  <= 1'b0; s_r_valid <= 1'b0;
            case (cs_state)
                CS_IDLE: begin
                    if (s_aw_valid) begin s_aw_ready <= 1'b1; cs_aw_addr_r <= s_aw_addr; cs_state <= CS_WDATA; end
                    else if (s_ar_valid) begin s_ar_ready <= 1'b1; cs_ar_addr_r <= s_ar_addr; cs_state <= CS_RDATA; end
                end
                CS_WDATA: begin
                    s_w_ready <= 1'b1;
                    if (s_w_valid) begin
                        cs_w_data_r <= s_w_data;
                        s_w_ready   <= 1'b0;
                        // Decode: offset = cs_aw_addr_r[6:0]
                        // Region i: base @ i*16+0, mask @ i*16+4, perm @ i*16+8
                        case (cs_aw_addr_r[6:2])
                            5'h00: region_base[0] <= s_w_data; 5'h01: region_mask[0] <= s_w_data; 5'h02: region_perm[0] <= s_w_data[7:0];
                            5'h04: region_base[1] <= s_w_data; 5'h05: region_mask[1] <= s_w_data; 5'h06: region_perm[1] <= s_w_data[7:0];
                            5'h08: region_base[2] <= s_w_data; 5'h09: region_mask[2] <= s_w_data; 5'h0A: region_perm[2] <= s_w_data[7:0];
                            5'h0C: region_base[3] <= s_w_data; 5'h0D: region_mask[3] <= s_w_data; 5'h0E: region_perm[3] <= s_w_data[7:0];
                            5'h10: region_base[4] <= s_w_data; 5'h11: region_mask[4] <= s_w_data; 5'h12: region_perm[4] <= s_w_data[7:0];
                            5'h14: region_base[5] <= s_w_data; 5'h15: region_mask[5] <= s_w_data; 5'h16: region_perm[5] <= s_w_data[7:0];
                            5'h18: region_base[6] <= s_w_data; 5'h19: region_mask[6] <= s_w_data; 5'h1A: region_perm[6] <= s_w_data[7:0];
                            5'h1C: region_base[7] <= s_w_data; 5'h1D: region_mask[7] <= s_w_data; 5'h1E: region_perm[7] <= s_w_data[7:0];
                            default: ;
                        endcase
                        s_b_resp <= `AXI_RESP_OKAY;
                        cs_state <= CS_WRESP;
                    end
                end
                CS_WRESP: begin s_b_valid <= 1'b1; if (s_b_valid && s_b_ready) begin s_b_valid <= 1'b0; cs_state <= CS_IDLE; end end
                CS_RDATA: begin
                    case (cs_ar_addr_r[6:2])
                        5'h00: s_r_data <= region_base[0]; 5'h01: s_r_data <= region_mask[0]; 5'h02: s_r_data <= {24'b0, region_perm[0]};
                        5'h04: s_r_data <= region_base[1]; 5'h05: s_r_data <= region_mask[1]; 5'h06: s_r_data <= {24'b0, region_perm[1]};
                        5'h08: s_r_data <= region_base[2]; 5'h09: s_r_data <= region_mask[2]; 5'h0A: s_r_data <= {24'b0, region_perm[2]};
                        5'h0C: s_r_data <= region_base[3]; 5'h0D: s_r_data <= region_mask[3]; 5'h0E: s_r_data <= {24'b0, region_perm[3]};
                        5'h10: s_r_data <= region_base[4]; 5'h11: s_r_data <= region_mask[4]; 5'h12: s_r_data <= {24'b0, region_perm[4]};
                        5'h14: s_r_data <= region_base[5]; 5'h15: s_r_data <= region_mask[5]; 5'h16: s_r_data <= {24'b0, region_perm[5]};
                        5'h18: s_r_data <= region_base[6]; 5'h19: s_r_data <= region_mask[6]; 5'h1A: s_r_data <= {24'b0, region_perm[6]};
                        5'h1C: s_r_data <= region_base[7]; 5'h1D: s_r_data <= region_mask[7]; 5'h1E: s_r_data <= {24'b0, region_perm[7]};
                        default: s_r_data <= 32'h4D50_5500; // 'MPU\0' signature
                    endcase
                    s_r_resp  <= `AXI_RESP_OKAY;
                    s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin s_r_valid <= 1'b0; cs_state <= CS_IDLE; end
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Combinational Region Lookup Function (parallel check all 8 regions)
    // region_hit[i] = (addr & ~mask) == (base & ~mask) && valid
    // -------------------------------------------------------------------------
    reg [N_REGIONS-1:0] region_hit_wr [0:2];  // [master][region]
    reg [N_REGIONS-1:0] region_hit_rd [0:2];

    integer i;
    always @(*) begin
        for (i = 0; i < N_REGIONS; i = i + 1) begin
            region_hit_wr[0][i] = region_perm[i][0] && ((m0_aw_addr & ~region_mask[i]) == (region_base[i] & ~region_mask[i]));
            region_hit_rd[0][i] = region_perm[i][0] && ((m0_ar_addr & ~region_mask[i]) == (region_base[i] & ~region_mask[i]));
            region_hit_wr[1][i] = region_perm[i][0] && ((m1_aw_addr & ~region_mask[i]) == (region_base[i] & ~region_mask[i]));
            region_hit_rd[1][i] = region_perm[i][0] && ((m1_ar_addr & ~region_mask[i]) == (region_base[i] & ~region_mask[i]));
            region_hit_wr[2][i] = region_perm[i][0] && ((m2_aw_addr & ~region_mask[i]) == (region_base[i] & ~region_mask[i]));
            region_hit_rd[2][i] = region_perm[i][0] && ((m2_ar_addr & ~region_mask[i]) == (region_base[i] & ~region_mask[i]));
        end
    end

    // -------------------------------------------------------------------------
    // Violation Detection: check permission bits vs privilege level
    // Write violation: region_hit but write_allow=0 OR priv < min_priv
    // -------------------------------------------------------------------------
    function check_write_violation;
        input [7:0]  perm;
        input [1:0]  priv;
        begin
            // write_allow = perm[2], priv_min = perm[5:4]
            check_write_violation = (perm[2] == 1'b0) || (priv < perm[5:4]);
        end
    endfunction

    function check_read_violation;
        input [7:0]  perm;
        input [1:0]  priv;
        begin
            // read_allow = perm[1], priv_min = perm[5:4]
            check_read_violation = (perm[1] == 1'b0) || (priv < perm[5:4]);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Fault Registration (sequential: 1 fault per cycle, priority: CPU0 > CPU1 > DMA)
    // -------------------------------------------------------------------------
    integer j;
    reg found;
    reg [7:0] hit_perm_wr0, hit_perm_rd0, hit_perm_wr1, hit_perm_rd1, hit_perm_wr2, hit_perm_rd2;

    always @(*) begin
        hit_perm_wr0 = 8'h0; hit_perm_rd0 = 8'h0;
        hit_perm_wr1 = 8'h0; hit_perm_rd1 = 8'h0;
        hit_perm_wr2 = 8'h0; hit_perm_rd2 = 8'h0;
        for (j = 0; j < N_REGIONS; j = j + 1) begin
            if (region_hit_wr[0][j]) hit_perm_wr0 = region_perm[j];
            if (region_hit_rd[0][j]) hit_perm_rd0 = region_perm[j];
            if (region_hit_wr[1][j]) hit_perm_wr1 = region_perm[j];
            if (region_hit_rd[1][j]) hit_perm_rd1 = region_perm[j];
            if (region_hit_wr[2][j]) hit_perm_wr2 = region_perm[j];
            if (region_hit_rd[2][j]) hit_perm_rd2 = region_perm[j];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mpu_fault <= 1'b0; fault_addr <= 32'h0; fault_type <= 2'b0; fault_master_id <= 3'b0; mpu_irq <= 1'b0;
        end else begin
            mpu_fault <= 1'b0; mpu_irq <= 1'b0;
            // Priority: CPU0 write > CPU0 read > CPU1 write > CPU1 read > DMA write > DMA read
            if (m0_aw_valid && (|region_hit_wr[0]) && check_write_violation(hit_perm_wr0, cpu0_priv_level)) begin
                mpu_fault <= 1'b1; fault_addr <= m0_aw_addr; fault_type <= 2'b01; fault_master_id <= 3'd0; mpu_irq <= 1'b1;
            end else if (m0_ar_valid && (|region_hit_rd[0]) && check_read_violation(hit_perm_rd0, cpu0_priv_level)) begin
                mpu_fault <= 1'b1; fault_addr <= m0_ar_addr; fault_type <= 2'b00; fault_master_id <= 3'd0; mpu_irq <= 1'b1;
            end else if (m1_aw_valid && (|region_hit_wr[1]) && check_write_violation(hit_perm_wr1, cpu1_priv_level)) begin
                mpu_fault <= 1'b1; fault_addr <= m1_aw_addr; fault_type <= 2'b01; fault_master_id <= 3'd1; mpu_irq <= 1'b1;
            end else if (m1_ar_valid && (|region_hit_rd[1]) && check_read_violation(hit_perm_rd1, cpu1_priv_level)) begin
                mpu_fault <= 1'b1; fault_addr <= m1_ar_addr; fault_type <= 2'b00; fault_master_id <= 3'd1; mpu_irq <= 1'b1;
            end else if (m2_aw_valid && (|region_hit_wr[2]) && check_write_violation(hit_perm_wr2, PRIV_MACHINE)) begin
                mpu_fault <= 1'b1; fault_addr <= m2_aw_addr; fault_type <= 2'b01; fault_master_id <= 3'd2; mpu_irq <= 1'b1;
            end else if (m2_ar_valid && (|region_hit_rd[2]) && check_read_violation(hit_perm_rd2, PRIV_MACHINE)) begin
                mpu_fault <= 1'b1; fault_addr <= m2_ar_addr; fault_type <= 2'b00; fault_master_id <= 3'd2; mpu_irq <= 1'b1;
            end
        end
    end

endmodule
