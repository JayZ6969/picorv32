// opt/formal/equiv/arithmetic_formal.sv
// Formal arithmetic equivalence checker.
// Proves pcpi_vedic_mul output is bit-exact to RISC-V MUL/MULH/MULHSU/MULHU
// definitions for ALL 32-bit input pairs.

`timescale 1ns/1ps

module arithmetic_formal (
    input wire clk,
    input wire resetn
);
    // Free inputs — solver explores every possible value
    (* anyconst *) reg [31:0] rs1;
    (* anyconst *) reg [31:0] rs2;
    // funct3: default anyconst (single huge Z3 job). For faster runs, opt/scripts/formal
    // run_arithmetic_formal_smtbmc.sh passes -DARITH_FUNCT3_* so only one variant is active.
`ifdef ARITH_FUNCT3_MUL
    wire [1:0] funct3_sel = 2'b00;
`elsif ARITH_FUNCT3_MULH
    wire [1:0] funct3_sel = 2'b01;
`elsif ARITH_FUNCT3_MULHSU
    wire [1:0] funct3_sel = 2'b10;
`elsif ARITH_FUNCT3_MULHU
    wire [1:0] funct3_sel = 2'b11;
`else
    (* anyconst *) reg [1:0] funct3_sel;
`endif

    // Build the instruction word
    wire [31:0] pcpi_insn;
    assign pcpi_insn = {7'b0000001, 5'b00000, 5'b00000, 1'b0, funct3_sel, 5'b00000, 7'b0110011};

    // ── DUT — optimized implementation ──
    wire        pcpi_wr;
    wire [31:0] pcpi_rd;
    wire        pcpi_wait;
    wire        pcpi_ready;

    // Drive pcpi_valid high continuously after reset
    reg running = 0;
    always @(posedge clk) begin
        if (!resetn)
            running <= 0;
        else if (!running)
            running <= 1;
    end

    pcpi_vedic_mul dut (
        .clk(clk), .resetn(resetn),
        .pcpi_valid(running),
        .pcpi_insn(pcpi_insn),
        .pcpi_rs1(rs1),
        .pcpi_rs2(rs2),
        .pcpi_wr(pcpi_wr),
        .pcpi_rd(pcpi_rd),
        .pcpi_wait(pcpi_wait),
        .pcpi_ready(pcpi_ready)
    );

    // ── Reference — pure arithmetic definition ──
    // Use 64-bit intermediate to compute all 4 variants
    wire [63:0] rs1_s64 = {{32{rs1[31]}}, rs1};  // sign-extend to 64
    wire [63:0] rs2_s64 = {{32{rs2[31]}}, rs2};
    wire [63:0] rs1_u64 = {32'b0, rs1};           // zero-extend to 64
    wire [63:0] rs2_u64 = {32'b0, rs2};

    // Signed multiplication: sign-extend, multiply, take bits
    wire [63:0] prod_ss = rs1_s64 * rs2_s64;  // signed × signed
    wire [63:0] prod_su = rs1_s64 * rs2_u64;  // signed × unsigned
    wire [63:0] prod_uu = rs1_u64 * rs2_u64;  // unsigned × unsigned

    reg [31:0] expected;
    always @(*) begin
        case (funct3_sel)
            2'b00: expected = prod_uu[31:0];   // MUL — lower 32 (same for signed/unsigned)
            2'b01: expected = prod_ss[63:32];  // MULH — signed×signed upper
            2'b10: expected = prod_su[63:32];  // MULHSU — signed×unsigned upper
            2'b11: expected = prod_uu[63:32];  // MULHU — unsigned×unsigned upper
        endcase
    end

    // ── Track reset ──
    reg past_valid = 0;
    always @(posedge clk)
        past_valid <= 1;

    // Assumptions: first cycle is reset
    always @(posedge clk) begin
        if (!past_valid)
            assume (!resetn);
        else
            assume (resetn);
    end

    // ── Properties ──
    // When pcpi_ready asserts, the result must match the reference
    always @(posedge clk) begin
        if (past_valid && resetn && pcpi_ready) begin
            P1_mul_correct: assert (pcpi_rd == expected);
            P2_wr_set:      assert (pcpi_wr);
        end
    end

    // ── Cover: all 4 variants complete ──
    always @(posedge clk) begin
        C1_mul:    cover (pcpi_ready && funct3_sel == 2'b00);
        C2_mulh:   cover (pcpi_ready && funct3_sel == 2'b01);
        C3_mulhsu: cover (pcpi_ready && funct3_sel == 2'b10);
        C4_mulhu:  cover (pcpi_ready && funct3_sel == 2'b11);
    end

    // Cover boundary cases
    always @(posedge clk) begin
        C5_max: cover (pcpi_ready && rs1 == 32'hFFFFFFFF && rs2 == 32'hFFFFFFFF);
        C6_mid: cover (pcpi_ready && rs1 == 32'h80000000 && rs2 == 32'h80000000);
    end

endmodule
