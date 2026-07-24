// =============================================================================
// Module      : axi_bus_arbiter
// Project     : Phoenix-X Heterogeneous Compute Accelerator
// Target      : Xilinx Artix-7 XC7A100T @ 100 MHz
// Description : Round-robin bus arbiter for 5 AXI-4 Lite masters:
//               0=CPU0, 1=CPU1, 2=DMA, 3=GPU, 4=NPU.
// =============================================================================

`timescale 1ns/1ps
`include "axi_defines.vh"

module axi_bus_arbiter (
    input  wire       clk,
    input  wire       rst_n,

    // Request inputs from 5 masters (CPU0=0, CPU1=1, DMA=2, GPU=3, NPU=4)
    input  wire [4:0] req,

    // Transaction-complete pulse from crossbar
    input  wire       txn_done,

    // Grant outputs
    output reg  [2:0] grant_id,     // Granted master ID (3-bit)
    output reg        grant_valid   // 1 = a master holds the bus
);

    reg [2:0] token; // Last-served master: 0..4

    localparam ARB_IDLE  = 1'b0;
    localparam ARB_GRANT = 1'b1;
    reg arb_state;

    // Search round-robin order starting from (token + 1) mod 5
    integer i;
    reg [2:0] winner;
    reg       found_req;
    reg [2:0] idx;

    always @(*) begin
        winner    = token;
        found_req = 1'b0;
        for (i = 0; i < 5; i = i + 1) begin
            if (!found_req) begin
                idx = (token + 1'b1 + i[2:0]) % 5;
                if (req[idx]) begin
                    winner    = idx;
                    found_req = 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_state   <= ARB_IDLE;
            grant_id    <= 3'd0;
            grant_valid <= 1'b0;
            token       <= 3'd0;
        end else begin
            case (arb_state)
                ARB_IDLE: begin
                    if (found_req) begin
                        grant_id    <= winner;
                        grant_valid <= 1'b1;
                        arb_state   <= ARB_GRANT;
                    end else begin
                        grant_valid <= 1'b0;
                    end
                end

                ARB_GRANT: begin
                    if (txn_done) begin
                        token       <= grant_id;
                        grant_valid <= 1'b0;
                        arb_state   <= ARB_IDLE;
                    end
                end

                default: arb_state <= ARB_IDLE;
            endcase
        end
    end

endmodule
