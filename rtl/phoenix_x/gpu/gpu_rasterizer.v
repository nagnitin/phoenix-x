// =============================================================================
// Module      : gpu_rasterizer
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Hardware 2D Primitive Rasterizer.
//               Executes pixel drawing, line drawing (Bresenham's algorithm),
//               filled rectangle scanning, 2D triangle edge-function rasterization,
//               and screen clearing.
//               Emits (X, Y, Color) pixel streams to Frame Buffer Controller.
// =============================================================================

`timescale 1ns/1ps

module gpu_rasterizer #(
    parameter FB_WIDTH  = 160,
    parameter FB_HEIGHT = 120
) (
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Primitive Command Input (from gpu_cmd_proc)
    // -------------------------------------------------------------------------
    input  wire [3:0]  prim_op,       // 2=PIXEL, 3=LINE, 4=RECT, 5=TRI, 15=CLEAR
    input  wire [15:0] prim_color,
    input  wire [15:0] prim_x0, prim_y0,
    input  wire [15:0] prim_x1, prim_y1,
    input  wire [15:0] prim_x2, prim_y2,
    input  wire        prim_valid,
    output wire        prim_ready,

    // -------------------------------------------------------------------------
    // Pixel Output Stream (to Frame Buffer Controller)
    // -------------------------------------------------------------------------
    output reg  [15:0] pixel_x,
    output reg  [15:0] pixel_y,
    output reg  [15:0] pixel_color,
    output reg         pixel_valid,
    input  wire        pixel_ready    // Frame Buffer ready for pixel
);

    // -------------------------------------------------------------------------
    // State Machine
    // -------------------------------------------------------------------------
    localparam RAST_IDLE  = 3'd0;
    localparam RAST_PIXEL = 3'd1;
    localparam RAST_LINE  = 3'd2;
    localparam RAST_RECT  = 3'd3;
    localparam RAST_TRI   = 3'd4;
    localparam RAST_CLEAR = 3'd5;

    reg [2:0] state;

    assign prim_ready = (state == RAST_IDLE);

    // -------------------------------------------------------------------------
    // Bresenham's Line Generator Registers
    // -------------------------------------------------------------------------
    reg signed [16:0] line_x, line_y;
    reg signed [16:0] line_x1, line_y1;
    reg signed [16:0] dx, dy;
    reg signed [16:0] sx, sy;
    reg signed [17:0] err, e2;

    // -------------------------------------------------------------------------
    // Rectangle & Screen Clear Scan Registers
    // -------------------------------------------------------------------------
    reg [15:0] scan_x, scan_y;
    reg [15:0] rect_min_x, rect_min_y, rect_max_x, rect_max_y;

    // -------------------------------------------------------------------------
    // Triangle Bounding Box & Edge Function Variables
    // -------------------------------------------------------------------------
    reg signed [16:0] tri_x0, tri_y0, tri_x1, tri_y1, tri_x2, tri_y2;
    reg signed [16:0] tri_min_x, tri_min_y, tri_max_x, tri_max_y;

    // Edge function helper: (px - ax)*(by - ay) - (py - ay)*(bx - ax)
    function signed [31:0] edge_func;
        input signed [16:0] px, py;
        input signed [16:0] ax, ay;
        input signed [16:0] bx, by;
        begin
            edge_func = (px - ax) * (by - ay) - (py - ay) * (bx - ax);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Helper Min/Max Functions
    // -------------------------------------------------------------------------
    function signed [16:0] min3;
        input signed [16:0] a, b, c;
        begin
            min3 = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
        end
    endfunction

    function signed [16:0] max3;
        input signed [16:0] a, b, c;
        begin
            max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Triangle Inside Check
    // -------------------------------------------------------------------------
    wire signed [31:0] w0 = edge_func(scan_x, scan_y, tri_x1, tri_y1, tri_x2, tri_y2);
    wire signed [31:0] w1 = edge_func(scan_x, scan_y, tri_x2, tri_y2, tri_x0, tri_y0);
    wire signed [31:0] w2 = edge_func(scan_x, scan_y, tri_x0, tri_y0, tri_x1, tri_y1);
    wire inside_tri = (w0 >= 0 && w1 >= 0 && w2 >= 0) || (w0 <= 0 && w1 <= 0 && w2 <= 0);

    // -------------------------------------------------------------------------
    // Main Rasterizer FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= RAST_IDLE;
            pixel_x     <= 16'd0;
            pixel_y     <= 16'd0;
            pixel_color <= 16'd0;
            pixel_valid <= 1'b0;
            line_x <= 0; line_y <= 0; line_x1 <= 0; line_y1 <= 0;
            dx <= 0; dy <= 0; sx <= 0; sy <= 0; err <= 0;
            scan_x <= 0; scan_y <= 0;
            rect_min_x <= 0; rect_min_y <= 0; rect_max_x <= 0; rect_max_y <= 0;
            tri_x0 <= 0; tri_y0 <= 0; tri_x1 <= 0; tri_y1 <= 0; tri_x2 <= 0; tri_y2 <= 0;
            tri_min_x <= 0; tri_min_y <= 0; tri_max_x <= 0; tri_max_y <= 0;
        end else begin
            if (pixel_valid && pixel_ready) begin
                pixel_valid <= 1'b0;
            end

            case (state)
                RAST_IDLE: begin
                    if (prim_valid && prim_ready) begin
                        pixel_color <= prim_color;
                        case (prim_op)
                            4'h2: begin // DRAW_PIXEL
                                pixel_x     <= prim_x0;
                                pixel_y     <= prim_y0;
                                pixel_valid <= 1'b1;
                                state       <= RAST_PIXEL;
                            end

                            4'h3: begin // DRAW_LINE
                                line_x  <= prim_x0;
                                line_y  <= prim_y0;
                                line_x1 <= prim_x1;
                                line_y1 <= prim_y1;
                                dx      <= (prim_x1 > prim_x0) ? (prim_x1 - prim_x0) : (prim_x0 - prim_x1);
                                dy      <= (prim_y1 > prim_y0) ? (prim_y1 - prim_y0) : (prim_y0 - prim_y1);
                                sx      <= (prim_x0 < prim_x1) ? 17'sd1 : -17'sd1;
                                sy      <= (prim_y0 < prim_y1) ? 17'sd1 : -17'sd1;
                                err     <= ((prim_x1 > prim_x0) ? (prim_x1 - prim_x0) : (prim_x0 - prim_x1)) - 
                                           ((prim_y1 > prim_y0) ? (prim_y1 - prim_y0) : (prim_y0 - prim_y1));
                                pixel_x     <= prim_x0;
                                pixel_y     <= prim_y0;
                                pixel_valid <= 1'b1;
                                state       <= RAST_LINE;
                            end

                            4'h4: begin // DRAW_RECT
                                rect_min_x <= (prim_x0 < prim_x1) ? prim_x0 : prim_x1;
                                rect_max_x <= (prim_x0 < prim_x1) ? prim_x1 : prim_x0;
                                rect_min_y <= (prim_y0 < prim_y1) ? prim_y0 : prim_y1;
                                rect_max_y <= (prim_y0 < prim_y1) ? prim_y1 : prim_y0;
                                scan_x     <= (prim_x0 < prim_x1) ? prim_x0 : prim_x1;
                                scan_y     <= (prim_y0 < prim_y1) ? prim_y0 : prim_y1;
                                pixel_x    <= (prim_x0 < prim_x1) ? prim_x0 : prim_x1;
                                pixel_y    <= (prim_y0 < prim_y1) ? prim_y0 : prim_y1;
                                pixel_valid<= 1'b1;
                                state      <= RAST_RECT;
                            end

                            4'h5: begin // DRAW_TRIANGLE
                                tri_x0 <= prim_x0; tri_y0 <= prim_y0;
                                tri_x1 <= prim_x1; tri_y1 <= prim_y1;
                                tri_x2 <= prim_x2; tri_y2 <= prim_y2;
                                tri_min_x <= min3(prim_x0, prim_x1, prim_x2);
                                tri_max_x <= max3(prim_x0, prim_x1, prim_x2);
                                tri_min_y <= min3(prim_y0, prim_y1, prim_y2);
                                tri_max_y <= max3(prim_y0, prim_y1, prim_y2);
                                scan_x    <= min3(prim_x0, prim_x1, prim_x2);
                                scan_y    <= min3(prim_y0, prim_y1, prim_y2);
                                state     <= RAST_TRI;
                            end

                            4'hF: begin // CLEAR_SCREEN
                                scan_x      <= 16'd0;
                                scan_y      <= 16'd0;
                                pixel_x     <= 16'd0;
                                pixel_y     <= 16'd0;
                                pixel_valid <= 1'b1;
                                state       <= RAST_CLEAR;
                            end

                            default: state <= RAST_IDLE;
                        endcase
                    end
                end

                RAST_PIXEL: begin
                    if (!pixel_valid || pixel_ready) begin
                        state <= RAST_IDLE;
                    end
                end

                RAST_LINE: begin
                    if (!pixel_valid || pixel_ready) begin
                        if (line_x == line_x1 && line_y == line_y1) begin
                            state <= RAST_IDLE;
                        end else begin
                            e2 = err << 1;
                            if (e2 > -dy) begin
                                err    <= err - dy;
                                line_x <= line_x + sx;
                            end
                            if (e2 < dx) begin
                                err    <= err + dx;
                                line_y <= line_y + sy;
                            end
                            pixel_x     <= (e2 > -dy) ? (line_x + sx) : line_x;
                            pixel_y     <= (e2 < dx)  ? (line_y + sy) : line_y;
                            pixel_valid <= 1'b1;
                        end
                    end
                end

                RAST_RECT: begin
                    if (!pixel_valid || pixel_ready) begin
                        if (scan_x < rect_max_x) begin
                            scan_x      <= scan_x + 16'd1;
                            pixel_x     <= scan_x + 16'd1;
                            pixel_y     <= scan_y;
                            pixel_valid <= 1'b1;
                        end else if (scan_y < rect_max_y) begin
                            scan_x      <= rect_min_x;
                            scan_y      <= scan_y + 16'd1;
                            pixel_x     <= rect_min_x;
                            pixel_y     <= scan_y + 16'd1;
                            pixel_valid <= 1'b1;
                        end else begin
                            state <= RAST_IDLE;
                        end
                    end
                end

                RAST_TRI: begin
                    if (!pixel_valid || pixel_ready) begin
                        if (inside_tri) begin
                            pixel_x     <= scan_x;
                            pixel_y     <= scan_y;
                            pixel_valid <= 1'b1;
                        end

                        if (scan_x < tri_max_x) begin
                            scan_x <= scan_x + 16'd1;
                        end else if (scan_y < tri_max_y) begin
                            scan_x <= tri_min_x;
                            scan_y <= scan_y + 16'd1;
                        end else begin
                            state  <= RAST_IDLE;
                        end
                    end
                end

                RAST_CLEAR: begin
                    if (!pixel_valid || pixel_ready) begin
                        if (scan_x < (FB_WIDTH - 1)) begin
                            scan_x      <= scan_x + 16'd1;
                            pixel_x     <= scan_x + 16'd1;
                            pixel_y     <= scan_y;
                            pixel_valid <= 1'b1;
                        end else if (scan_y < (FB_HEIGHT - 1)) begin
                            scan_x      <= 16'd0;
                            scan_y      <= scan_y + 16'd1;
                            pixel_x     <= 16'd0;
                            pixel_y     <= scan_y + 16'd1;
                            pixel_valid <= 1'b1;
                        end else begin
                            state <= RAST_IDLE;
                        end
                    end
                end

                default: state <= RAST_IDLE;
            endcase
        end
    end

endmodule
