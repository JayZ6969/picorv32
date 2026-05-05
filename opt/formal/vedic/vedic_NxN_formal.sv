// opt/formal/vedic/vedic_NxN_formal.sv
// Formal property checkers for each level of the Vedic multiplier hierarchy.
// 2x2, 4x4, 8x8 are pure combinational.
// 16x16 and 32x32 are pipelined (require bounded model checking with depth).

`timescale 1ns/1ps

// ════════════════════════════════════════════════════════
// 2×2 — pure combinational
// ════════════════════════════════════════════════════════
module vedic_2x2_formal;
    (* anyconst *) reg [1:0] A, B;
    wire [3:0] P;
    vedic_mul_2x2 #(.WIDTH(2)) dut (.A(A), .B(B), .P(P));

    wire [3:0] ref_P = A * B;

    always @(*) begin
        P1_product_correct: assert (P == ref_P);
    end
    always @(*) begin
        C1_max_inputs: cover (A == 2'b11 && B == 2'b11);
    end
endmodule

// ════════════════════════════════════════════════════════
// 4×4 — pure combinational
// ════════════════════════════════════════════════════════
module vedic_4x4_formal;
    (* anyconst *) reg [3:0] A, B;
    wire [7:0] P;
    vedic_mul_4x4 #(.WIDTH(4)) dut (.A(A), .B(B), .P(P));

    wire [7:0] ref_P = A * B;

    always @(*) begin
        P1_product_correct: assert (P == ref_P);
    end
endmodule

// ════════════════════════════════════════════════════════
// 8×8 — pure combinational
// ════════════════════════════════════════════════════════
module vedic_8x8_formal;
    (* anyconst *) reg [7:0] A, B;
    wire [15:0] P;
    vedic_mul_8x8 #(.WIDTH(8)) dut (.A(A), .B(B), .P(P));

    wire [15:0] ref_P = A * B;

    always @(*) begin
        P1_product_correct: assert (P == ref_P);
    end
endmodule

// ════════════════════════════════════════════════════════
// 16×16 — 1 pipeline stage (needs clk, depth ≥ 3)
// ════════════════════════════════════════════════════════
module vedic_16x16_formal (
    input wire clk
);
    (* anyconst *) reg [15:0] A, B;
    wire [31:0] P;

    vedic_mul_16x16 #(.WIDTH(16)) dut (
        .clk(clk), .A(A), .B(B), .P(P)
    );

    wire [31:0] ref_P = A * B;

    // After 1 pipeline cycle, P should match
    reg [1:0] cnt = 0;
    always @(posedge clk) begin
        if (cnt < 2'd2) cnt <= cnt + 1;
    end

    always @(*) begin
        if (cnt == 2'd2) begin
            P1_product_correct: assert (P == ref_P);
        end
    end

    always @(*) begin
        C1_max: cover (cnt == 2'd2 && A == 16'hFFFF && B == 16'hFFFF);
    end
endmodule

// ════════════════════════════════════════════════════════
// 32×32 — multiple pipeline stages (needs clk, depth ≥ 6)
// Pipeline: 16x16 sub-muls (1 stage each) → reg partial products (1 stage)
//           → CSA L1 → reg (1 stage) → CSA L2 → KSA64 pipelined (1 stage)
// Total: ~4 pipeline stages from input to output
// ════════════════════════════════════════════════════════
module vedic_32x32_formal (
    input wire clk
);
    (* anyconst *) reg [31:0] A, B;
    wire [63:0] P;

    vedic_mul_32x32 #(.WIDTH(32)) dut (
        .clk(clk), .A(A), .B(B), .P(P)
    );

    wire [63:0] ref_P = {32'b0, A} * {32'b0, B};

    // Count pipeline latency — 4 clock cycles for output to stabilize
    reg [2:0] cnt = 0;
    always @(posedge clk) begin
        if (cnt < 3'd5) cnt <= cnt + 1;
    end

    always @(*) begin
        if (cnt == 3'd5) begin
            P1_product_correct: assert (P == ref_P);
        end
    end

    always @(*) begin
        C1_max: cover (cnt == 3'd5 && A == 32'hFFFFFFFF && B == 32'hFFFFFFFF);
        C2_midpoint: cover (cnt == 3'd5 && A == 32'h80000000 && B == 32'h80000000);
    end
endmodule
