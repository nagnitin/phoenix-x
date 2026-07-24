// =============================================================================
// Module      : gpu_top
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T (Nexys A7-100T)
// Description : Tiny GPU Top-Level Module.
//               Integrates AXI-4 Lite Config Slave, Command Processor & FIFO,
//               Hardware Rasterizer, Dual-Port Frame Buffer, and VGA Controller.
//
// AXI SLAVE REGISTERS (base: 0x0020_0400):
//   0x00: CMD_FIFO_DATA (write commands here)
//   0x04: STATUS        [0]=BUSY, [1]=FIFO_FULL, [2]=FIFO_EMPTY
//   0x08: COLOR_REG     [15:0]=RGB565 Color
//   0x0C: DRAW_PIXEL    [31:16]=Y, [15:0]=X
// =============================================================================

`timescale 1ns/1ps
`include "../axi/axi_defines.vh"

module gpu_top #(
    parameter FB_WIDTH  = 160,
    parameter FB_HEIGHT = 120
) (
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // AXI-4 Lite Slave Port (for CPU commands & config)
    // -------------------------------------------------------------------------
    input  wire [31:0] s_aw_addr,
    input  wire        s_aw_valid,
    output reg         s_aw_ready,
    input  wire [31:0] s_w_data,
    input  wire [ 3:0] s_w_strb,
    input  wire        s_w_valid,
    output reg         s_w_ready,
    output reg  [ 1:0] s_b_resp,
    output reg         s_b_valid,
    input  wire        s_b_ready,
    input  wire [31:0] s_ar_addr,
    input  wire        s_ar_valid,
    output reg         s_ar_ready,
    output reg  [31:0] s_r_data,
    output reg  [ 1:0] s_r_resp,
    output reg         s_r_valid,
    input  wire        s_r_ready,

    // -------------------------------------------------------------------------
    // AXI-4 Lite Master Port (to flush frame buffer to Shared SRAM)
    // -------------------------------------------------------------------------
    output wire [31:0] m_aw_addr,
    output wire        m_aw_valid,
    input  wire        m_aw_ready,
    output wire [31:0] m_w_data,
    output wire [ 3:0] m_w_strb,
    output wire        m_w_valid,
    input  wire        m_w_ready,
    input  wire [ 1:0] m_b_resp,
    input  wire        m_b_valid,
    output wire        m_b_ready,

    // -------------------------------------------------------------------------
    // Physical VGA Output Pins
    // -------------------------------------------------------------------------
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,

    // Interrupt / Status
    output wire        gpu_busy,
    output wire        gpu_done_irq
);

    // -------------------------------------------------------------------------
    // Internal Wires
    // -------------------------------------------------------------------------
    reg  [31:0] cmd_word_in;
    reg         cmd_valid_in;
    wire        cmd_ready_out;

    wire [3:0]  prim_op;
    wire [15:0] prim_color;
    wire [15:0] prim_x0, prim_y0, prim_x1, prim_y1, prim_x2, prim_y2;
    wire        prim_valid, prim_ready;

    wire [15:0] pixel_x, pixel_y, pixel_color;
    wire        pixel_valid, pixel_ready;

    wire [15:0] vga_fb_x, vga_fb_y, vga_rgb565;
    wire        fifo_full, fifo_empty;

    // -------------------------------------------------------------------------
    // AXI Slave FSM
    // -------------------------------------------------------------------------
    localparam ST_IDLE  = 2'd0;
    localparam ST_WDATA = 2'd1;
    localparam ST_WRESP = 2'd2;
    localparam ST_RDATA = 2'd3;

    reg [1:0]  state;
    reg [31:0] aw_addr_r, ar_addr_r;

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
            cmd_word_in  <= 32'b0;
            cmd_valid_in <= 1'b0;
        end else begin
            s_aw_ready   <= 1'b0;
            s_w_ready    <= 1'b0;
            s_ar_ready   <= 1'b0;
            s_b_valid    <= 1'b0;
            s_r_valid    <= 1'b0;
            cmd_valid_in <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (s_aw_valid) begin
                        s_aw_ready <= 1'b1;
                        aw_addr_r  <= s_aw_addr;
                        state      <= ST_WDATA;
                    end else if (s_ar_valid) begin
                        s_ar_ready <= 1'b1;
                        ar_addr_r  <= s_ar_addr;
                        state      <= ST_RDATA;
                    end
                end

                ST_WDATA: begin
                    s_w_ready <= 1'b1;
                    if (s_w_valid) begin
                        s_w_ready <= 1'b0;
                        if (aw_addr_r[4:2] == 3'd0) begin
                            cmd_word_in  <= s_w_data;
                            cmd_valid_in <= 1'b1;
                        end
                        s_b_resp  <= `AXI_RESP_OKAY;
                        state     <= ST_WRESP;
                    end
                end

                ST_WRESP: begin
                    s_b_valid <= 1'b1;
                    if (s_b_valid && s_b_ready) begin
                        s_b_valid <= 1'b0;
                        state     <= ST_IDLE;
                    end
                end

                ST_RDATA: begin
                    case (ar_addr_r[4:2])
                        3'd1: s_r_data <= {29'b0, fifo_empty, fifo_full, gpu_busy};
                        default: s_r_data <= 32'h4750_0001;
                    endcase
                    s_r_resp  <= `AXI_RESP_OKAY;
                    s_r_valid <= 1'b1;
                    if (s_r_valid && s_r_ready) begin
                        s_r_valid <= 1'b0;
                        state     <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Instantiate GPU Sub-modules
    // -------------------------------------------------------------------------

    // 1. Command Processor & FIFO
    gpu_cmd_proc u_cmd_proc (
        .clk        (clk),
        .rst_n      (rst_n),
        .cmd_word   (cmd_word_in),
        .cmd_valid  (cmd_valid_in),
        .cmd_ready  (cmd_ready_out),
        .prim_op    (prim_op),
        .prim_color (prim_color),
        .prim_x0    (prim_x0), .prim_y0(prim_y0),
        .prim_x1    (prim_x1), .prim_y1(prim_y1),
        .prim_x2    (prim_x2), .prim_y2(prim_y2),
        .prim_valid (prim_valid),
        .prim_ready (prim_ready),
        .gpu_busy   (gpu_busy),
        .fifo_full  (fifo_full),
        .fifo_empty (fifo_empty)
    );

    // 2. Hardware 2D Rasterizer
    gpu_rasterizer #(
        .FB_WIDTH (FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT)
    ) u_rasterizer (
        .clk        (clk),
        .rst_n      (rst_n),
        .prim_op    (prim_op),
        .prim_color (prim_color),
        .prim_x0    (prim_x0), .prim_y0(prim_y0),
        .prim_x1    (prim_x1), .prim_y1(prim_y1),
        .prim_x2    (prim_x2), .prim_y2(prim_y2),
        .prim_valid (prim_valid),
        .prim_ready (prim_ready),
        .pixel_x    (pixel_x),
        .pixel_y    (pixel_y),
        .pixel_color(pixel_color),
        .pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready)
    );

    // 3. Dual-Port Frame Buffer Controller
    gpu_fb_ctrl #(
        .FB_WIDTH (FB_WIDTH),
        .FB_HEIGHT(FB_HEIGHT)
    ) u_fb_ctrl (
        .clk        (clk),
        .rst_n      (rst_n),
        .pixel_x    (pixel_x),
        .pixel_y    (pixel_y),
        .pixel_color(pixel_color),
        .pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),
        .vga_x      (vga_fb_x),
        .vga_y      (vga_fb_y),
        .vga_rgb565 (vga_rgb565),
        .m_aw_addr  (m_aw_addr),  .m_aw_valid(m_aw_valid), .m_aw_ready(m_aw_ready),
        .m_w_data   (m_w_data),   .m_w_strb  (m_w_strb),   .m_w_valid (m_w_valid),  .m_w_ready(m_w_ready),
        .m_b_resp   (m_b_resp),   .m_b_valid (m_b_valid),   .m_b_ready (m_b_ready)
    );

    // 4. VGA Output Controller (640×480 @ 60Hz timing generator)
    gpu_vga_ctrl u_vga_ctrl (
        .clk        (clk),
        .rst_n      (rst_n),
        .fb_x       (vga_fb_x),
        .fb_y       (vga_fb_y),
        .rgb565_in  (vga_rgb565),
        .vga_hsync  (vga_hsync),
        .vga_vsync  (vga_vsync),
        .vga_r      (vga_r),
        .vga_g      (vga_g),
        .vga_b      (vga_b)
    );

    assign gpu_done_irq = fifo_empty && !gpu_busy;

endmodule
