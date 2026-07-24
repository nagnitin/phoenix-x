// =============================================================================
// Module      : gpu_vga_ctrl
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T (Nexys A7-100T)
// Description : Standard VGA Timing Generator (640 × 480 @ 60 Hz).
//               Generates hsync, vsync, and 4-bit Red/Green/Blue DAC signals.
//               Upscales 160 × 120 internal frame buffer by 4×4 nearest-neighbor.
//
// VGA 640×480 @ 60Hz Timing (25 MHz Pixel Clock):
//   Horizontal: Visible=640, FrontPorch=16, SyncPulse=96, BackPorch=48 (Total=800)
//   Vertical  : Visible=480, FrontPorch=10, SyncPulse=2,  BackPorch=33 (Total=525)
// =============================================================================

`timescale 1ns/1ps

module gpu_vga_ctrl (
    input  wire        clk,            // 100 MHz system clock
    input  wire        rst_n,

    // Interface to Frame Buffer Controller
    output wire [15:0] fb_x,           // 0..159 (vga_x / 4)
    output wire [15:0] fb_y,           // 0..119 (vga_y / 4)
    input  wire [15:0] rgb565_in,      // RGB565 pixel from frame buffer

    // VGA Hardware Outputs (connect directly to Nexys A7 VGA pins)
    output reg         vga_hsync,
    output reg         vga_vsync,
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b
);

    // -------------------------------------------------------------------------
    // 25 MHz Pixel Clock Generator (100 MHz / 4)
    // -------------------------------------------------------------------------
    reg [1:0] clk_div;
    wire pclk = (clk_div == 2'b00);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) clk_div <= 2'b00;
        else        clk_div <= clk_div + 2'b01;
    end

    // -------------------------------------------------------------------------
    // Timing Parameters (640 × 480 @ 60Hz)
    // -------------------------------------------------------------------------
    localparam H_VISIBLE = 640;
    localparam H_FP      = 16;
    localparam H_SYNC    = 96;
    localparam H_BP      = 48;
    localparam H_TOTAL   = 800;

    localparam V_VISIBLE = 480;
    localparam V_FP      = 10;
    localparam V_SYNC    = 2;
    localparam V_BP      = 33;
    localparam V_TOTAL   = 525;

    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    // Counters
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else if (pclk) begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 10'd0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= 10'd0;
                else
                    v_cnt <= v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    // Sync Signal Generation (Active Low)
    wire h_sync_active = (h_cnt >= (H_VISIBLE + H_FP)) && (h_cnt < (H_VISIBLE + H_FP + H_SYNC));
    wire v_sync_active = (v_cnt >= (V_VISIBLE + V_FP)) && (v_cnt < (V_VISIBLE + V_FP + V_SYNC));
    wire active_video  = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);

    // Frame Buffer 4×4 Down-scaling for 160×120 buffer readout
    assign fb_x = h_cnt[9:2];  // divide by 4 (0..159)
    assign fb_y = v_cnt[9:2];  // divide by 4 (0..119)

    // Output Registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vga_hsync <= 1'b1;
            vga_vsync <= 1'b1;
            vga_r     <= 4'b0;
            vga_g     <= 4'b0;
            vga_b     <= 4'b0;
        end else if (pclk) begin
            vga_hsync <= ~h_sync_active;
            vga_vsync <= ~v_sync_active;

            if (active_video) begin
                // Convert RGB565 -> RGB444 for VGA DAC pins
                vga_r <= rgb565_in[15:12];
                vga_g <= rgb565_in[10:7];
                vga_b <= rgb565_in[4:1];
            end else begin
                vga_r <= 4'b0;
                vga_g <= 4'b0;
                vga_b <= 4'b0;
            end
        end
    end

endmodule
