// =============================================================================
// Module      : cpu_core.v
// Project     : 32-Bit Custom FPGA Microcontroller
// Description : CPU Core module. Integrates all 5 pipelined stages (IF, ID, EX,
//               MEM, WB), status register, hazard detection, forwarding,
//               branch evaluation, and interrupt exception logic.
// =============================================================================

`timescale 1ns/1ps

module cpu_core (
    input  wire        clk,
    input  wire        rst_n,

    // Instruction memory interface (Fetch)
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    // Data memory interface (MEM stage)
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire        dmem_we,
    output wire        dmem_re,
    output wire        dmem_byte,
    input  wire [31:0] dmem_rdata,

    // Interrupt interface
    input  wire        irq_req,       // Interrupt request from PIC
    input  wire [31:0] irq_vector,    // ISR address from PIC
    output reg         irq_ack,       // Interrupt acknowledge pulse
    output reg         in_isr,        // Currently in ISR (supervisor mode)

    // Debug unit interface
    output wire [31:0] dbu_pc,
    output wire [31:0] dbu_instr,
    output wire        dbu_valid,
    input  wire [4:0]  dbu_reg_sel,
    output wire [31:0] dbu_reg_val,
    input  wire        dbu_halt_in
);

    // -------------------------------------------------------------------------
    // Wires and registers for pipeline stages
    // -------------------------------------------------------------------------

    // Hazard signals
    wire stall_if, stall_id, flush_if, flush_id, flush_ex;
    reg flush_if_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flush_if_reg <= 1'b0;
        end else begin
            flush_if_reg <= flush_if;
        end
    end
    wire flush_if_extended = flush_if | flush_if_reg;

    // IF stage wires
    wire [31:0] pc_out;
    wire [31:0] if_pc_plus4;
    wire [31:0] if_instruction;

    // IF/ID Pipeline Register outputs
    wire [31:0] id_pc_plus4;
    wire [31:0] id_instruction;

    // ID Stage Decoded signals
    wire [5:0]  id_opcode;
    wire [4:0]  id_rd;
    wire [4:0]  id_rs1;
    wire [4:0]  id_rs2;
    wire [4:0]  id_rs2_decoded;
    assign id_rs2 = (id_opcode == 6'h1C || id_opcode == 6'h1D || id_opcode == 6'h1E || id_opcode == 6'h1F) ? id_rd : id_rs2_decoded;
    wire [10:0] id_func;
    wire [15:0] id_imm16;
    wire [25:0] id_target26;
    wire [31:0] id_imm32_signed;

    // ID Stage Control signals
    wire [4:0]  id_alu_op;
    wire        id_alu_src;
    wire        id_mem_read;
    wire        id_mem_write;
    wire        id_mem_byte;
    wire        id_reg_write;
    wire        id_branch;
    wire        id_jump;
    wire        id_mem_to_reg;
    wire        id_alu_update_flags;
    wire        id_is_call;
    wire        id_is_ret;
    wire        id_is_push;
    wire        id_is_pop;
    wire        id_halt;
    wire        id_is_io_in;
    wire        id_is_io_out;

    // Register File outputs
    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;

    // ID/EX Pipeline Register outputs
    wire [5:0]  ex_opcode;
    wire [4:0]  ex_alu_op;
    wire        ex_alu_src;
    wire        ex_mem_read;
    wire        ex_mem_write;
    wire        ex_mem_byte;
    wire        ex_reg_write;
    wire        ex_branch;
    wire        ex_jump;
    wire        ex_alu_update_flags;
    wire        ex_mem_to_reg;
    wire        ex_is_call;
    wire        ex_is_ret;
    wire        ex_is_push;
    wire        ex_is_pop;
    wire        ex_halt;
    wire        ex_is_io_in;
    wire        ex_is_io_out;

    wire [31:0] ex_pc_plus4;
    wire [31:0] ex_rs1_data;
    wire [31:0] ex_rs2_data;
    wire [31:0] ex_immediate;
    wire [4:0]  ex_rd_addr;
    wire [4:0]  ex_rs1_addr;
    wire [4:0]  ex_rs2_addr;
    wire [25:0] ex_jump_target;

    // Forwarding unit outputs
    wire [1:0]  forward_a;
    wire [1:0]  forward_b;
    reg  [31:0] operand_a_forwarded;
    reg  [31:0] operand_b_forwarded;
    wire [31:0] alu_operand_b;

    // ALU outputs
    wire [31:0] ex_alu_result;
    wire        ex_alu_z;
    wire        ex_alu_n;
    wire        ex_alu_c;
    wire        ex_alu_v;

    // Status Register
    wire [7:0]  status_out;

    // Interrupt save/restore
    reg  [31:0] epc;
    reg  [7:0]  esr;
    reg         irq_taken_ack;

    // Branch Unit outputs
    wire        branch_taken;
    wire [31:0] branch_target;
    wire [31:0] branch_target_final;

    // EX/MEM Pipeline Register outputs
    wire        mem_mem_read;
    wire        mem_mem_write;
    wire        mem_mem_byte;
    wire        mem_reg_write;
    wire        mem_mem_to_reg;
    wire        mem_is_call;
    wire        mem_halt;
    wire        mem_is_io_in;
    wire        mem_is_io_out;
    wire [31:0] mem_alu_result;
    wire [31:0] mem_rs2_data;
    wire [4:0]  mem_rd_addr;
    wire [31:0] mem_pc_plus4;
    wire [31:0] mem_io_addr;
    wire [7:0]  mem_flags;

    // MEM/WB Pipeline Register outputs
    wire        wb_reg_write;
    wire        wb_mem_to_reg;
    wire        wb_is_call;
    wire [31:0] wb_read_data;
    wire [31:0] wb_alu_result;
    wire [4:0]  wb_rd_addr;
    wire [31:0] wb_pc_plus4;

    // Writeback select
    wire [31:0] wb_write_data;
    wire [4:0]  wb_rd_addr_final;
    wire        wb_is_push;
    wire        wb_is_pop;

    // Additional control overrides
    wire        global_stall = dbu_halt_in | ex_halt | mem_halt;

    // -------------------------------------------------------------------------
    // 1. INSTRUCTION FETCH (IF) STAGE
    // -------------------------------------------------------------------------

    program_counter pc_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .stall         (stall_if | global_stall),
        .pc_load       (branch_taken | (ex_opcode == 6'h25) | (ex_opcode == 6'h24)), // branch / JMP / IRET / INT
        .pc_load_addr  (branch_target_final),
        .irq_load      (irq_taken_ack),
        .irq_vector    (irq_vector),
        .pc_out        (pc_out)
    );

    assign imem_addr   = pc_out;
    reg [31:0] pc_out_d1;
    reg [31:0] pc_out_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out_d1 <= 32'h0;
            pc_out_d2 <= 32'h0;
        end else if (!(stall_if | global_stall)) begin
            pc_out_d1 <= pc_out;
            pc_out_d2 <= pc_out_d1;
        end
    end
    assign if_pc_plus4 = pc_out_d2 + 32'd4;

    instruction_register ir_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .stall           (stall_if | global_stall),
        .flush           (flush_if_extended),
        .instruction_in  (imem_rdata),
        .instruction_out (if_instruction)
    );

    if_id_reg if_id_reg_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .stall          (stall_id | global_stall),
        .flush          (flush_if_extended),
        .if_pc_plus4    (if_pc_plus4),
        .if_instruction (if_instruction),
        .id_pc_plus4    (id_pc_plus4),
        .id_instruction (id_instruction)
    );

    // -------------------------------------------------------------------------
    // 2. INSTRUCTION DECODE (ID) STAGE
    // -------------------------------------------------------------------------

    instruction_decoder decoder_inst (
        .instruction  (id_instruction),
        .opcode       (id_opcode),
        .rd           (id_rd),
        .rs1          (id_rs1),
        .rs2          (id_rs2_decoded),
        .func         (id_func),
        .imm16        (id_imm16),
        .target26     (id_target26),
        .imm32_signed (id_imm32_signed)
    );

    control_unit control_inst (
        .opcode           (id_opcode),
        .alu_op           (id_alu_op),
        .alu_src          (id_alu_src),
        .mem_read         (id_mem_read),
        .mem_write        (id_mem_write),
        .mem_byte         (id_mem_byte),
        .reg_write        (id_reg_write),
        .branch           (id_branch),
        .jump             (id_jump),
        .mem_to_reg       (id_mem_to_reg),
        .alu_update_flags (id_alu_update_flags),
        .is_call          (id_is_call),
        .is_ret           (id_is_ret),
        .is_push          (id_is_push),
        .is_pop           (id_is_pop),
        .halt             (id_halt),
        .is_io_in         (id_is_io_in),
        .is_io_out        (id_is_io_out)
    );

    register_file reg_file_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .we         (wb_reg_write),
        .rd_addr    (wb_rd_addr_final),
        .rd_data    (wb_write_data),
        .rs1_addr   (dbu_halt_in ? dbu_reg_sel : id_rs1),
        .rs1_data   (id_rs1_data),
        .rs2_addr   (id_rs2),
        .rs2_data   (id_rs2_data),
        .wb_is_push (wb_is_push),
        .wb_is_pop  (wb_is_pop)
    );

    assign dbu_reg_val = id_rs1_data;

    id_ex_reg id_ex_reg_inst (
        .clk                 (clk),
        .rst_n               (rst_n),
        .flush               (flush_id),
        .stall               (stall_id | global_stall),
        .id_opcode           (id_opcode),
        .id_alu_op           (id_alu_op),
        .id_alu_src          (id_alu_src),
        .id_mem_read         (id_mem_read),
        .id_mem_write        (id_mem_write),
        .id_mem_byte         (id_mem_byte),
        .id_reg_write        (id_reg_write),
        .id_branch           (id_branch),
        .id_jump             (id_jump),
        .id_alu_update_flags (id_alu_update_flags),
        .id_mem_to_reg       (id_mem_to_reg),
        .id_is_call          (id_is_call),
        .id_is_ret           (id_is_ret),
        .id_is_push          (id_is_push),
        .id_is_pop           (id_is_pop),
        .id_halt             (id_halt),
        .id_is_io_in         (id_is_io_in),
        .id_is_io_out        (id_is_io_out),
        .id_pc_plus4         (id_pc_plus4),
        .id_rs1_data         (id_rs1_data),
        .id_rs2_data         (id_rs2_data),
        .id_immediate        (id_imm32_signed),
        .id_rd_addr          (id_rd),
        .id_rs1_addr         (id_rs1),
        .id_rs2_addr         (id_rs2),
        .id_jump_target      (id_target26),
        .ex_opcode           (ex_opcode),
        .ex_alu_op           (ex_alu_op),
        .ex_alu_src          (ex_alu_src),
        .ex_mem_read         (ex_mem_read),
        .ex_mem_write        (ex_mem_write),
        .ex_mem_byte         (ex_mem_byte),
        .ex_reg_write        (ex_reg_write),
        .ex_branch           (ex_branch),
        .ex_jump             (ex_jump),
        .ex_alu_update_flags (ex_alu_update_flags),
        .ex_mem_to_reg       (ex_mem_to_reg),
        .ex_is_call          (ex_is_call),
        .ex_is_ret           (ex_is_ret),
        .ex_is_push          (ex_is_push),
        .ex_is_pop           (ex_is_pop),
        .ex_halt             (ex_halt),
        .ex_is_io_in         (ex_is_io_in),
        .ex_is_io_out        (ex_is_io_out),
        .ex_pc_plus4         (ex_pc_plus4),
        .ex_rs1_data         (ex_rs1_data),
        .ex_rs2_data         (ex_rs2_data),
        .ex_immediate        (ex_immediate),
        .ex_rd_addr          (ex_rd_addr),
        .ex_rs1_addr         (ex_rs1_addr),
        .ex_rs2_addr         (ex_rs2_addr),
        .ex_jump_target      (ex_jump_target)
    );

    // -------------------------------------------------------------------------
    // 3. EXECUTE (EX) STAGE
    // -------------------------------------------------------------------------

    forwarding_unit forward_inst (
        .ex_rs1_addr     (ex_rs1_addr),
        .ex_rs2_addr     (ex_rs2_addr),
        .exmem_reg_write (mem_reg_write),
        .exmem_rd_addr   (mem_rd_addr),
        .memwb_reg_write (wb_reg_write),
        .memwb_rd_addr   (wb_rd_addr_final),
        .forward_a       (forward_a),
        .forward_b       (forward_b)
    );

    // Forwarding Muxes
    always @(*) begin
        case (forward_a)
            2'b10:   operand_a_forwarded = mem_alu_result;
            2'b01:   operand_a_forwarded = wb_write_data;
            default: operand_a_forwarded = ex_rs1_data;
        endcase

        case (forward_b)
            2'b10:   operand_b_forwarded = mem_alu_result;
            2'b01:   operand_b_forwarded = wb_write_data;
            default: operand_b_forwarded = ex_rs2_data;
        endcase
    end

    assign alu_operand_b = ex_is_push ? 32'd4 : (ex_alu_src ? ex_immediate : operand_b_forwarded);

    alu alu_inst (
        .operand_a (operand_a_forwarded),
        .operand_b (alu_operand_b),
        .alu_op    (ex_alu_op),
        .result    (ex_alu_result),
        .flag_z    (ex_alu_z),
        .flag_n    (ex_alu_n),
        .flag_c    (ex_alu_c),
        .flag_v    (ex_alu_v)
    );

    branch_unit branch_inst (
        .pc_plus4      (ex_pc_plus4),
        .rs1_data      (operand_a_forwarded),
        .immediate     (ex_immediate),
        .jump_target   (ex_jump_target),
        .is_branch     (ex_branch),
        .is_jump       (ex_jump),
        .is_ret        (ex_is_ret),
        .opcode        (ex_opcode),
        .flag_z        (status_out[0]),
        .flag_n        (status_out[1]),
        .flag_v        (status_out[3]),
        .branch_taken  (branch_taken),
        .branch_target (branch_target)
    );

    // Branch Target Overrides: IRET (restore to EPC) / INT (vector 7)
    assign branch_target_final = (ex_opcode == 6'h25) ? epc : 
                                 (ex_opcode == 6'h24) ? 32'h0000_11E0 : branch_target;

    status_register status_reg_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .alu_update      (ex_alu_update_flags),
        .alu_z           (ex_alu_z),
        .alu_n           (ex_alu_n),
        .alu_c           (ex_alu_c),
        .alu_v           (ex_alu_v),
        .irq_disable_i   (irq_taken_ack | (ex_opcode == 6'h24)), // Disable on HW or SW INT
        .irq_enable_i    (ex_opcode == 6'h25), // Enable on IRET
        .set_supervisor  (irq_taken_ack | (ex_opcode == 6'h24)),
        .clr_supervisor  (ex_opcode == 6'h25),
        .set_timer_flag  (1'b0),
        .clr_timer_flag  (1'b0),
        .direct_write    (ex_opcode == 6'h25),
        .direct_data     (esr),
        .status          (status_out)
    );

    // Exception and Interrupt Save Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            epc           <= 32'h0;
            esr           <= 8'h10; // Interrupts enabled by default
            in_isr        <= 1'b0;
            irq_ack       <= 1'b0;
            irq_taken_ack <= 1'b0;
        end else begin
            irq_taken_ack <= 1'b0;
            irq_ack       <= 1'b0;

            if (irq_req && status_out[4] && !in_isr && !global_stall) begin
                // Take Hardware Interrupt
                epc           <= pc_out; // Address of next fetched instruction
                esr           <= status_out;
                in_isr        <= 1'b1;
                irq_taken_ack <= 1'b1;
                irq_ack       <= 1'b1; // Pulse acknowledgment
            end else if (ex_opcode == 6'h24 && !global_stall) begin
                // Take Software Interrupt (INT)
                epc           <= ex_pc_plus4; // Return point is next instruction
                esr           <= status_out;
                in_isr        <= 1'b1;
            end else if (ex_opcode == 6'h25 && !global_stall) begin
                // Exit ISR (IRET)
                in_isr        <= 1'b0;
            end
        end
    end

    // Pass the original register values down for Store operations or POP addresses
    wire [31:0] ex_store_data = ex_is_pop ? operand_a_forwarded : operand_b_forwarded;

    wire mem_is_push_wire;
    wire mem_is_pop_wire;

    ex_mem_reg ex_mem_reg_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (flush_ex),
        .ex_mem_read    (ex_mem_read),
        .ex_mem_write   (ex_mem_write),
        .ex_mem_byte    (ex_mem_byte),
        .ex_reg_write   (ex_reg_write),
        .ex_mem_to_reg  (ex_mem_to_reg),
        .ex_is_call     (ex_is_call),
        .ex_is_push     (ex_is_push),
        .ex_is_pop      (ex_is_pop),
        .ex_halt        (ex_halt),
        .ex_is_io_in    (ex_is_io_in),
        .ex_is_io_out   (ex_is_io_out),
        .ex_alu_result  (ex_alu_result),
        .ex_rs2_data    (ex_store_data),
        .ex_rd_addr     (ex_rd_addr),
        .ex_pc_plus4    (ex_pc_plus4),
        .ex_io_addr     (operand_b_forwarded), // Address for peripheral I/O (from immediate or register)
        .ex_flags       (status_out),
        .mem_mem_read   (mem_mem_read),
        .mem_mem_write  (mem_mem_write),
        .mem_mem_byte   (mem_mem_byte),
        .mem_reg_write  (mem_reg_write),
        .mem_mem_to_reg (mem_mem_to_reg),
        .mem_is_call    (mem_is_call),
        .mem_is_push    (mem_is_push_wire),
        .mem_is_pop     (mem_is_pop_wire),
        .mem_halt       (mem_halt),
        .mem_is_io_in   (mem_is_io_in),
        .mem_is_io_out  (mem_is_io_out),
        .mem_alu_result (mem_alu_result),
        .mem_rs2_data   (mem_rs2_data),
        .mem_rd_addr    (mem_rd_addr),
        .mem_pc_plus4   (mem_pc_plus4),
        .mem_io_addr    (mem_io_addr),
        .mem_flags      (mem_flags)
    );

    // -------------------------------------------------------------------------
    // 4. MEMORY ACCESS (MEM) STAGE
    // -------------------------------------------------------------------------

    // For POP, read address is original SP (saved in mem_rs2_data), for other memory ops use ALU output.
    // Wait, let's distinguish POP vs. standard memory operations.
    // In control unit, OP_POP sets is_pop=1 (which maps to ex_is_pop).
    // Let's pass ex_is_pop and ex_is_push to MEM and WB stages.
    // We can run memory mapping directly.
    
    assign dmem_addr  = (mem_mem_read && !mem_mem_to_reg) ? mem_rs2_data : mem_alu_result;
    assign dmem_wdata = mem_rs2_data;
    assign dmem_we    = mem_mem_write;
    assign dmem_re    = mem_mem_read;
    assign dmem_byte  = mem_mem_byte;

    // Latch POP signals to WB
    reg wb_is_push_reg, wb_is_pop_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_is_push_reg <= 1'b0;
            wb_is_pop_reg  <= 1'b0;
        end else begin
            wb_is_push_reg <= mem_is_push_wire;
            wb_is_pop_reg  <= mem_is_pop_wire;
        end
    end
    assign wb_is_push = wb_is_push_reg;
    assign wb_is_pop  = wb_is_pop_reg;

    mem_wb_reg mem_wb_reg_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .mem_reg_write  (mem_reg_write),
        .mem_mem_to_reg (mem_mem_to_reg),
        .mem_is_call    (mem_is_call),
        .mem_read_data  (dmem_rdata),
        .mem_alu_result (mem_alu_result),
        .mem_rd_addr    (mem_rd_addr),
        .mem_pc_plus4   (mem_pc_plus4),
        .wb_reg_write   (wb_reg_write),
        .wb_mem_to_reg  (wb_mem_to_reg),
        .wb_is_call     (wb_is_call),
        .wb_read_data   (wb_read_data),
        .wb_alu_result  (wb_alu_result),
        .wb_rd_addr     (wb_rd_addr),
        .wb_pc_plus4    (wb_pc_plus4)
    );

    // -------------------------------------------------------------------------
    // 5. WRITE BACK (WB) STAGE
    // -------------------------------------------------------------------------

    // CALL writes return PC to register 30 (Link Register)
    assign wb_rd_addr_final = wb_is_call ? 5'd30 : wb_rd_addr;

    assign wb_write_data = wb_is_call    ? wb_pc_plus4 : 
                           wb_mem_to_reg ? wb_read_data : wb_alu_result;

    // -------------------------------------------------------------------------
    // HAZARD DETECTION UNIT
    // -------------------------------------------------------------------------

    hazard_detection_unit hazard_inst (
        .ex_mem_read   (ex_mem_read),
        .ex_rd_addr    (ex_rd_addr),
        .id_rs1_addr   (id_rs1),
        .id_rs2_addr   (id_rs2),
        .branch_taken  (branch_taken),
        .jump_taken    (ex_jump),
        .irq_taken     (irq_taken_ack),
        .stall_if      (stall_if),
        .stall_id      (stall_id),
        .flush_if      (flush_if),
        .flush_id      (flush_id),
        .flush_ex      (flush_ex)
    );

    // -------------------------------------------------------------------------
    // DEBUG UNIT HOOKS
    // -------------------------------------------------------------------------
    assign dbu_pc    = wb_pc_plus4 - 32'd4;
    assign dbu_instr = wb_read_data; // Approximation
    assign dbu_valid = wb_reg_write;

endmodule
