// =============================================================================
// Module      : gpu_cmd_proc
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Tiny GPU Command Processor & Decoded Command FIFO.
//               Accepts 32-bit graphics command words from CPU via register/FIFO.
//               Decodes primitives (PIXEL, LINE, RECTANGLE, TRIANGLE, SET_COLOR)
//               and feeds parameters to the Hardware Rasterizer.
//
// Command Set:
//   Opcode 0x01: SET_COLOR    -> Param 0: {16'b0, RGB565_color}
//   Opcode 0x02: DRAW_PIXEL   -> Param 0: {16'b0, X0}, Param 1: {16'b0, Y0}
//   Opcode 0x03: DRAW_LINE    -> Param 0: {16'b0, X0}, Param 1: {16'b0, Y0}, Param 2: {16'b0, X1}, Param 3: {16'b0, Y1}
//   Opcode 0x04: DRAW_RECT    -> Param 0: {16'b0, X0}, Param 1: {16'b0, Y0}, Param 2: {16'b0, X1}, Param 3: {16'b0, Y1}
//   Opcode 0x05: DRAW_TRIANGLE-> Param 0: {16'b0, X0}, Param 1: {16'b0, Y0}, Param 2: {16'b0, X1}, Param 3: {16'b0, Y1}, Param 4: {16'b0, X2}, Param 5: {16'b0, Y2}
//   Opcode 0x0F: CLEAR_SCREEN -> Param 0: {16'b0, RGB565_color}
// =============================================================================

`timescale 1ns/1ps

module gpu_cmd_proc (
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Interface from AXI Slave (CPU writes command words here)
    // -------------------------------------------------------------------------
    input  wire [31:0] cmd_word,
    input  wire        cmd_valid,
    output wire        cmd_ready,

    // -------------------------------------------------------------------------
    // Decoded Primitive Output to Rasterizer
    // -------------------------------------------------------------------------
    output reg  [3:0]  prim_op,       // 0=IDLE, 1=COLOR, 2=PIXEL, 3=LINE, 4=RECT, 5=TRI, 15=CLEAR
    output reg  [15:0] prim_color,
    output reg  [15:0] prim_x0, prim_y0,
    output reg  [15:0] prim_x1, prim_y1,
    output reg  [15:0] prim_x2, prim_y2,
    output reg         prim_valid,
    input  wire        prim_ready,    // Rasterizer ready to accept new primitive

    // Status
    output wire        gpu_busy,
    output wire        fifo_full,
    output wire        fifo_empty
);

    // -------------------------------------------------------------------------
    // Command FIFO (16 entries × 32 bits)
    // -------------------------------------------------------------------------
    reg [31:0] fifo_mem [0:15];
    reg [3:0]  wr_ptr, rd_ptr;
    reg [4:0]  fifo_count;

    assign fifo_full  = (fifo_count == 5'd16);
    assign fifo_empty = (fifo_count == 5'd0);
    assign cmd_ready  = !fifo_full;

    // FIFO Push logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= 4'd0;
            fifo_count <= 5'd0;
        end else if (cmd_valid && cmd_ready) begin
            fifo_mem[wr_ptr] <= cmd_word;
            wr_ptr           <= wr_ptr + 4'd1;
            fifo_count       <= fifo_count + 5'd1;
        end else if (fifo_pop && !cmd_valid) begin
            fifo_count       <= fifo_count - 5'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Command Parser FSM
    // -------------------------------------------------------------------------
    localparam ST_IDLE    = 3'd0;
    localparam ST_OPCODE  = 3'd1;
    localparam ST_PARAM   = 3'd2;
    localparam ST_DISPATCH= 3'd3;

    reg [2:0]  state;
    reg [3:0]  cur_opcode;
    reg [2:0]  param_idx;
    reg [2:0]  param_needed;
    reg        fifo_pop;

    reg [15:0] active_color;
    reg [15:0] p_x0, p_y0, p_x1, p_y1, p_x2, p_y2;

    assign gpu_busy = (state != ST_IDLE) || !fifo_empty || prim_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            cur_opcode   <= 4'd0;
            param_idx    <= 3'd0;
            param_needed <= 3'd0;
            fifo_pop     <= 1'b0;
            rd_ptr       <= 4'd0;
            prim_op      <= 4'd0;
            prim_color   <= 16'hFFFF; // Default white
            prim_x0 <= 0; prim_y0 <= 0;
            prim_x1 <= 0; prim_y1 <= 0;
            prim_x2 <= 0; prim_y2 <= 0;
            prim_valid   <= 1'b0;
            active_color <= 16'hFFFF;
        end else begin
            fifo_pop <= 1'b0;

            // Clear dispatched valid flag when accepted by rasterizer
            if (prim_valid && prim_ready) begin
                prim_valid <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    if (!fifo_empty && !prim_valid) begin
                        state <= ST_OPCODE;
                    end
                end

                ST_OPCODE: begin
                    if (!fifo_empty) begin
                        cur_opcode <= fifo_mem[rd_ptr][3:0];
                        rd_ptr     <= rd_ptr + 4'd1;
                        fifo_pop   <= 1'b1;
                        param_idx  <= 3'd0;

                        case (fifo_mem[rd_ptr][3:0])
                            4'h1: param_needed <= 3'd1; // COLOR
                            4'h2: param_needed <= 3'd2; // PIXEL (X,Y)
                            4'h3: param_needed <= 3'd4; // LINE (X0,Y0,X1,Y1)
                            4'h4: param_needed <= 3'd4; // RECT (X0,Y0,X1,Y1)
                            4'h5: param_needed <= 3'd6; // TRIANGLE (X0,Y0,X1,Y1,X2,Y2)
                            4'hF: param_needed <= 3'd1; // CLEAR
                            default: param_needed <= 3'd0;
                        endcase
                        state <= ST_PARAM;
                    end
                end

                ST_PARAM: begin
                    if (param_idx == param_needed) begin
                        state <= ST_DISPATCH;
                    end else if (!fifo_empty) begin
                        // Latch parameters in order
                        case (param_idx)
                            3'd0: if (cur_opcode == 4'h1 || cur_opcode == 4'hF) active_color <= fifo_mem[rd_ptr][15:0]; else p_x0 <= fifo_mem[rd_ptr][15:0];
                            3'd1: p_y0 <= fifo_mem[rd_ptr][15:0];
                            3'd2: p_x1 <= fifo_mem[rd_ptr][15:0];
                            3'd3: p_y1 <= fifo_mem[rd_ptr][15:0];
                            3'd4: p_x2 <= fifo_mem[rd_ptr][15:0];
                            3'd5: p_y2 <= fifo_mem[rd_ptr][15:0];
                        endcase
                        param_idx <= param_idx + 3'd1;
                        rd_ptr    <= rd_ptr + 4'd1;
                        fifo_pop  <= 1'b1;
                    end
                end

                ST_DISPATCH: begin
                    prim_op    <= cur_opcode;
                    prim_color <= active_color;
                    prim_x0    <= p_x0; prim_y0 <= p_y0;
                    prim_x1    <= p_x1; prim_y1 <= p_y1;
                    prim_x2    <= p_x2; prim_y2 <= p_y2;
                    prim_valid <= 1'b1;
                    state      <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
