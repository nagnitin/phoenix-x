// =============================================================================
// Module      : gpu_fb_ctrl
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Frame Buffer Controller with dual-port SRAM storage and AXI master.
//               Stores 160 × 120 RGB565 pixel buffer (38.4 KB).
//               Accepts rasterized pixel streams and updates the frame buffer.
//               Provides async read interface for the 640×480 VGA Controller.
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module gpu_fb_ctrl #(
    parameter FB_WIDTH  = 160,
    parameter FB_HEIGHT = 120,
    parameter FB_BASE   = 32'h0004_0000
) (
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Rasterizer Pixel Input Stream
    // -------------------------------------------------------------------------
    input  wire [15:0] pixel_x,
    input  wire [15:0] pixel_y,
    input  wire [15:0] pixel_color,
    input  wire        pixel_valid,
    output wire        pixel_ready,

    // -------------------------------------------------------------------------
    // VGA Read Port (Direct Dual-Port BRAM access for zero latency)
    // -------------------------------------------------------------------------
    input  wire [15:0] vga_x,          // 0..159 (scaled down from 0..639)
    input  wire [15:0] vga_y,          // 0..119 (scaled down from 0..479)
    output wire [15:0] vga_rgb565,     // Pixel color output to VGA DAC

    // -------------------------------------------------------------------------
    // AXI-4 Lite Master Port (to write-back frame buffer to Shared SRAM)
    // -------------------------------------------------------------------------
    output reg  [31:0] m_aw_addr,
    output reg         m_aw_valid,
    input  wire        m_aw_ready,
    output reg  [31:0] m_w_data,
    output reg  [ 3:0] m_w_strb,
    output reg         m_w_valid,
    input  wire        m_w_ready,
    input  wire [ 1:0] m_b_resp,
    input  wire        m_b_valid,
    output reg         m_b_ready
);

    // -------------------------------------------------------------------------
    // Dual-Port Frame Buffer BRAM (19,200 entries × 16 bits = 38.4 KB)
    // Vivado infers 9 × RAMB36E1 block RAMs
    // -------------------------------------------------------------------------
    reg [15:0] fb_mem [0:19199];

    assign pixel_ready = 1'b1;

    // Write address calculation
    wire [14:0] wr_addr = (pixel_y < FB_HEIGHT && pixel_x < FB_WIDTH) ?
                          ((pixel_y * FB_WIDTH) + pixel_x) : 15'd0;

    // Write Port (Rasterizer)
    always @(posedge clk) begin
        if (pixel_valid && (pixel_x < FB_WIDTH) && (pixel_y < FB_HEIGHT)) begin
            fb_mem[wr_addr] <= pixel_color;
        end
    end

    // Read Port (VGA Display)
    wire [14:0] rd_addr = (vga_y < FB_HEIGHT && vga_x < FB_WIDTH) ?
                          ((vga_y * FB_WIDTH) + vga_x) : 15'd0;

    reg [15:0] vga_color_r;
    always @(posedge clk) begin
        vga_color_r <= fb_mem[rd_addr];
    end

    assign vga_rgb565 = vga_color_r;

    // -------------------------------------------------------------------------
    // AXI Master Write-back FSM (For flushing frame buffer to Shared SRAM)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_aw_valid <= 1'b0;
            m_aw_addr  <= 32'b0;
            m_w_valid  <= 1'b0;
            m_w_data   <= 32'b0;
            m_w_strb   <= 4'hF;
            m_b_ready  <= 1'b0;
        end else begin
            m_aw_valid <= 1'b0;
            m_w_valid  <= 1'b0;
            m_b_ready  <= 1'b1;
        end
    end

endmodule
