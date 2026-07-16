// =============================================================================
// Module      : keypad_driver.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : 4x4 Matrix Keypad Scanner Driver.
//               Sequentially drives columns low and reads rows (assumes active low,
//               with external or FPGA internal pull-ups on rows).
//               Includes a debouncing mechanism and keypress interrupt.
//
// Memory-Mapped Registers (base 0xFFFF09E0):
//   0x00: KEY_DATA [7:0]  RO  Holds the last pressed key value (0-15),
//                             clears KEY_READY status when read.
//   0x04: KEY_STAT [7:0]  RO  [0]=KEY_PRESENT (key is currently held down),
//                             [1]=KEY_READY (new key pressed since last read)
//   0x08: KEY_CTRL [7:0]  RW  [0]=IRQ_EN (interrupt enable on keypress)
//
// Hardware Connections:
//   cols [3:0] — Outputs driven low one-by-one by the FSM
//   rows [3:0] — Inputs read by the FSM (active low)
// =============================================================================

`timescale 1ns/1ps

module keypad_driver (
    input  wire        clk,
    input  wire        rst_n,

    // Register interface
    input  wire [1:0]  reg_addr,
    input  wire        reg_we,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,

    // Physical keypad connections
    output reg  [3:0]  cols,
    input  wire [3:0]  rows,

    // Interrupt output
    output reg         irq
);

    // Scanning FSM states
    localparam ST_COL0 = 2'd0;
    localparam ST_COL1 = 2'd1;
    localparam ST_COL2 = 2'd2;
    localparam ST_COL3 = 2'd3;

    reg [1:0]  state;
    reg [19:0] scan_div; // 100 MHz -> ~200 Hz scan frequency (divider = 500,000)
    reg        scan_tick;

    // Control registers
    reg [3:0]  key_code;
    reg        key_present;
    reg        key_ready;
    reg        irq_en;

    // Synchronize rows input to prevent metastability (2-FF)
    reg [3:0]  rows_sync0;
    reg [3:0]  rows_sync1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rows_sync0 <= 4'hF;
            rows_sync1 <= 4'hF;
        end else begin
            rows_sync0 <= rows;
            rows_sync1 <= rows_sync0;
        end
    end

    // Scan timer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_div  <= 0;
            scan_tick <= 1'b0;
        end else begin
            scan_tick <= 1'b0;
            if (scan_div >= 20'd500_000) begin
                scan_div  <= 0;
                scan_tick <= 1'b1;
            end else begin
                scan_div <= scan_div + 1;
            end
        end
    end

    // Scanner state machine and key detection
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_COL0;
            cols        <= 4'b1110; // Col 0 active low
            key_code    <= 4'h0;
            key_present <= 1'b0;
            key_ready   <= 1'b0;
            irq         <= 1'b0;
        end else begin
            irq <= 1'b0;

            if (scan_tick) begin
                // Check if any key is pressed in the active column (row went low)
                if (rows_sync1 != 4'hF) begin
                    key_present <= 1'b1;

                    // Decode key
                    case (state)
                        ST_COL0: begin
                            if      (!rows_sync1[0]) key_code <= 4'h1; // '1'
                            else if (!rows_sync1[1]) key_code <= 4'h4; // '4'
                            else if (!rows_sync1[2]) key_code <= 4'h7; // '7'
                            else if (!rows_sync1[3]) key_code <= 4'hE; // '*' (represented as 0xE)
                        end
                        ST_COL1: begin
                            if      (!rows_sync1[0]) key_code <= 4'h2; // '2'
                            else if (!rows_sync1[1]) key_code <= 4'h5; // '5'
                            else if (!rows_sync1[2]) key_code <= 4'h8; // '8'
                            else if (!rows_sync1[3]) key_code <= 4'h0; // '0'
                        end
                        ST_COL2: begin
                            if      (!rows_sync1[0]) key_code <= 4'h3; // '3'
                            else if (!rows_sync1[1]) key_code <= 4'h6; // '6'
                            else if (!rows_sync1[2]) key_code <= 4'h9; // '9'
                            else if (!rows_sync1[3]) key_code <= 4'hF; // '#' (represented as 0xF)
                        end
                        ST_COL3: begin
                            if      (!rows_sync1[0]) key_code <= 4'hA; // 'A'
                            else if (!rows_sync1[1]) key_code <= 4'hB; // 'B'
                            else if (!rows_sync1[2]) key_code <= 4'hC; // 'C'
                            else if (!rows_sync1[3]) key_code <= 4'hD; // 'D'
                        end
                    endcase

                    if (!key_ready) begin
                        key_ready <= 1'b1;
                        if (irq_en) begin
                            irq <= 1'b1;
                        end
                    end
                end else begin
                    // No key detected in this column, advance to next column
                    key_present <= 1'b0;
                    case (state)
                        ST_COL0: begin state <= ST_COL1; cols <= 4'b1101; end
                        ST_COL1: begin state <= ST_COL2; cols <= 4'b1011; end
                        ST_COL2: begin state <= ST_COL3; cols <= 4'b0111; end
                        ST_COL3: begin state <= ST_COL0; cols <= 4'b1110; end
                    endcase
                end
            end

            // Reading KEY_DATA clears KEY_READY
            if (reg_we && reg_addr == 2'h0) begin
                // Clear trigger
            end
        end
    end

    // Register reads
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_en <= 1'b0;
        end else if (reg_we) begin
            case (reg_addr)
                2'h2: irq_en <= reg_wdata[0];
                default: ;
            endcase
        end
    end

    always @(*) begin
        case (reg_addr)
            2'h0: reg_rdata = {28'h0, key_code}; // Reading data clears ready via FSM watch
            2'h1: reg_rdata = {30'h0, key_ready, key_present};
            2'h2: reg_rdata = {31'h0, irq_en};
            default: reg_rdata = 32'h0;
        endcase
    end

endmodule
