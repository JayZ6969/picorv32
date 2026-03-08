// =============================================================================
// ref_mul_32.v — Reference 32×32→64-bit combinational multiplier
//
// Standard shift-and-add partial-product array (Wallace/Dadda baseline).
// Synthesisers map this to a generic multiplier array — the same logic
// the RISC-V GCC runtime library uses when the M-extension is absent.
// Interface is drop-in identical to vedic_mul_32x32 for fair comparison.
//
// Critical path: partial-product adder tree O(log N) but with generic
// synthesis, usually slower than hand-optimised Vedic due to less
// structured carry chains.
// =============================================================================

`timescale 1ns/1ps

// 16×16→32-bit, generic
module ref_mul_16x16 (
    input  [15:0] a,
    input  [15:0] b,
    output [31:0] p
);
    assign p = a * b;
endmodule

// 32×32→64-bit top level
module ref_mul_32x32 (
    input  [31:0] a,
    input  [31:0] b,
    output [63:0] p
);
    // Decompose same as Vedic for fair structural comparison
    wire [31:0] pp0, pp1, pp2, pp3;
    ref_mul_16x16 u0 (.a(a[15:0]),  .b(b[15:0]),  .p(pp0));
    ref_mul_16x16 u1 (.a(a[15:0]),  .b(b[31:16]), .p(pp1));
    ref_mul_16x16 u2 (.a(a[31:16]), .b(b[15:0]),  .p(pp2));
    ref_mul_16x16 u3 (.a(a[31:16]), .b(b[31:16]), .p(pp3));

    wire [33:0] mid = {2'b0, pp1} + {2'b0, pp2};
    wire [63:0] sum1 = {32'b0, pp0};
    wire [63:0] sum2 = {14'b0, mid, 16'b0};
    wire [63:0] sum3 = {pp3, 32'b0};

    assign p = sum1 + sum2 + sum3;
endmodule
