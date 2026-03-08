// =============================================================================
// picorv32_pcpi_vedic_mul — PCPI multiplier using Vedic 32×32 core
//
// Drop-in replacement for picorv32_pcpi_fast_mul / picorv32_pcpi_mul.
// Handles MUL, MULH, MULHSU, MULHU via sign correction on top of an unsigned
// 32×32 Vedic core.
//
// Latency: 3 clock cycles (registered input → vedic core → registered output)
// pcpi_wait stays 0 (3-cycle latency hidden by the active shift-register,
// mirroring the fast_mul approach).
//
// Signed correction identity (Baugh-Wooley style):
//   signed(A) × signed(B)  =  unsigned(A) × unsigned(B)
//                             − A[31] × B × 2^32
//                             − B[31] × A × 2^32
//                             + A[31] × B[31] × 2^64  (only 64 bits → zero)
//   signed(A) × unsigned(B) = unsigned(A) × unsigned(B)
//                             − A[31] × B × 2^32
// =============================================================================

`timescale 1ns/1ps

// vedic_mul_32.v must be compiled in the same compilation unit.
// Pass both files to iverilog: iverilog ... vedic_mul_32.v picorv32_pcpi_vedic_mul.v ...

module picorv32_pcpi_vedic_mul (
    input         clk,
    input         resetn,

    input         pcpi_valid,
    input  [31:0] pcpi_insn,
    input  [31:0] pcpi_rs1,
    input  [31:0] pcpi_rs2,

    output        pcpi_wr,
    output [31:0] pcpi_rd,
    output        pcpi_wait,
    output        pcpi_ready
);

    // ------------------------------------------------------------------
    // Instruction decode (same as picorv32_pcpi_fast_mul)
    // ------------------------------------------------------------------
    wire pcpi_insn_valid = pcpi_valid
                         && pcpi_insn[6:0]  == 7'b0110011
                         && pcpi_insn[31:25] == 7'b0000001;

    reg instr_mul, instr_mulh, instr_mulhsu, instr_mulhu;

    always @* begin
        instr_mul    = 0;
        instr_mulh   = 0;
        instr_mulhsu = 0;
        instr_mulhu  = 0;
        if (resetn && pcpi_insn_valid) begin
            case (pcpi_insn[14:12])
                3'b000: instr_mul    = 1;
                3'b001: instr_mulh   = 1;
                3'b010: instr_mulhsu = 1;
                3'b011: instr_mulhu  = 1;
            endcase
        end
    end

    wire instr_any_mul  = |{instr_mul, instr_mulh, instr_mulhsu, instr_mulhu};
    wire instr_any_mulh = |{instr_mulh, instr_mulhsu, instr_mulhu};
    wire rs1_signed     = |{instr_mulh, instr_mulhsu};
    wire rs2_signed     =   instr_mulh;

    // ------------------------------------------------------------------
    // Stage 0 − capture operands + flags
    // ------------------------------------------------------------------
    reg [31:0] s0_a, s0_b;
    reg        s0_rs1_sgn, s0_rs2_sgn, s0_mulh;
    reg        s0_valid;

    always @(posedge clk) begin
        if (!resetn) begin
            s0_valid <= 0;
        end else begin
            s0_valid   <= instr_any_mul;
            s0_a       <= pcpi_rs1;
            s0_b       <= pcpi_rs2;
            s0_rs1_sgn <= rs1_signed;
            s0_rs2_sgn <= rs2_signed;
            s0_mulh    <= instr_any_mulh;
        end
    end

    // ------------------------------------------------------------------
    // Stage 1 − combinational Vedic 32×32 (unsigned core) + sign correction
    // ------------------------------------------------------------------
    wire [63:0] vedic_prod;
    vedic_mul_32x32 u_vedic (
        .a (s0_a),
        .b (s0_b),
        .p (vedic_prod)
    );

    // Sign corrections (applied to upper 32 bits only)
    //   If rs1 is signed-negative (s0_a[31]=1): subtract B << 32
    //   If rs2 is signed-negative (s0_b[31]=1): subtract A << 32
    wire [31:0] corr_a = (s0_rs1_sgn && s0_a[31]) ? (~s0_b + 1) : 32'b0; // -B mod 2^32
    wire [31:0] corr_b = (s0_rs2_sgn && s0_b[31]) ? (~s0_a + 1) : 32'b0; // -A mod 2^32

    wire [63:0] full_product = vedic_prod
                             + {corr_a, 32'b0}
                             + {corr_b, 32'b0};

    reg [63:0] s1_prod;
    reg        s1_mulh;
    reg        s1_valid;

    always @(posedge clk) begin
        if (!resetn) begin
            s1_valid <= 0;
        end else begin
            s1_valid <= s0_valid;
            s1_prod  <= full_product;
            s1_mulh  <= s0_mulh;
        end
    end

    // ------------------------------------------------------------------
    // Stage 2 − output register
    // ------------------------------------------------------------------
    reg [31:0] s2_result;
    reg        s2_valid;

    always @(posedge clk) begin
        if (!resetn) begin
            s2_valid <= 0;
        end else begin
            s2_valid  <= s1_valid;
            s2_result <= s1_mulh ? s1_prod[63:32] : s1_prod[31:0];
        end
    end

    // ------------------------------------------------------------------
    // PCPI output — ready/wr pulse when stage-2 data is valid
    // ------------------------------------------------------------------
    assign pcpi_wr    = s2_valid;
    assign pcpi_ready = s2_valid;
    assign pcpi_wait  = 1'b0;   // no stall; latency absorbed by 3-stage pipe
    assign pcpi_rd    = s2_result;

endmodule
