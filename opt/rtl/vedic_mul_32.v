// =============================================================================
// Vedic Multiplier — Urdhva-Tiryakbhyam (UT) decomposition, 32 × 32 → 64 bit
//
// Hierarchy:
//   vedic_mul_32x32  (32×32 → 64)
//     └── vedic_mul_16x16  (×4) + CSA/adder tree
//           └── vedic_mul_8x8  (×4) + CSA/adder tree
//                 └── vedic_mul_4x4  (×4) + CSA/adder tree
//                       └── vedic_mul_2x2  (×4, base case)
//
// All multiplications are combinational (zero-latency when synthesised).
// For pipelined use, instantiate inside the PCPI wrapper and register I/O.
// =============================================================================

`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// 2×2 base cell — produces a 4-bit product using explicit full-adder logic
// ---------------------------------------------------------------------------
module vedic_mul_2x2 (
    input  [1:0] a,
    input  [1:0] b,
    output [3:0] p
);
    // UT partial products for 2-bit operands:
    //   p[0]        = a[0]·b[0]
    //   p[1]        = a[1]·b[0] XOR a[0]·b[1]  (sum)
    //   carry_1     = a[1]·b[0] AND a[0]·b[1]  (carry into bit 2)
    //   p[2]        = a[1]·b[1] XOR carry_1
    //   p[3]        = a[1]·b[1] AND carry_1
    wire pp00 = a[0] & b[0];
    wire pp10 = a[1] & b[0];
    wire pp01 = a[0] & b[1];
    wire pp11 = a[1] & b[1];

    assign p[0] = pp00;
    assign p[1] = pp10 ^ pp01;
    wire   c1   = pp10 & pp01;
    assign p[2] = pp11 ^ c1;
    assign p[3] = pp11 & c1;
endmodule


// ---------------------------------------------------------------------------
// 4×4 → 8-bit   (four 2×2 units + partial-product summation)
// ---------------------------------------------------------------------------
module vedic_mul_4x4 (
    input  [3:0] a,
    input  [3:0] b,
    output [7:0] p
);
    // Partition: a = {Ah[1:0], Al[1:0]}, b = {Bh[1:0], Bl[1:0]}
    wire [3:0] pp0, pp1, pp2, pp3;
    vedic_mul_2x2 u0 (.a(a[1:0]), .b(b[1:0]), .p(pp0)); // Al×Bl   → bits [3:0]
    vedic_mul_2x2 u1 (.a(a[1:0]), .b(b[3:2]), .p(pp1)); // Al×Bh   → bits [5:2]
    vedic_mul_2x2 u2 (.a(a[3:2]), .b(b[1:0]), .p(pp2)); // Ah×Bl   → bits [5:2]
    vedic_mul_2x2 u3 (.a(a[3:2]), .b(b[3:2]), .p(pp3)); // Ah×Bh   → bits [7:4]

    // Accumulate: result = pp3<<4 + (pp1+pp2)<<2 + pp0
    // pp0 contributes [3:0] directly.
    // pp1+pp2 aligned at bit 2 → 5-bit sum at [6:2]
    // pp3 aligned at bit 4 → contributes [7:4]
    wire [5:0] mid = {2'b0, pp1} + {2'b0, pp2};         // 6-bit @ bit-2 alignment
    wire [7:0] sum1 = {4'b0, pp0};                        // fill low
    wire [7:0] sum2 = {2'b0, mid, 2'b0};                 // middle aligned
    wire [7:0] sum3 = {pp3, 4'b0};                        // high aligned

    assign p = sum1 + sum2 + sum3;
endmodule


// ---------------------------------------------------------------------------
// 8×8 → 16-bit  (four 4×4 units + partial-product summation)
// ---------------------------------------------------------------------------
module vedic_mul_8x8 (
    input  [7:0] a,
    input  [7:0] b,
    output [15:0] p
);
    wire [7:0] pp0, pp1, pp2, pp3;
    vedic_mul_4x4 u0 (.a(a[3:0]), .b(b[3:0]), .p(pp0)); // Al×Bl  → [7:0]
    vedic_mul_4x4 u1 (.a(a[3:0]), .b(b[7:4]), .p(pp1)); // Al×Bh  → [11:4]
    vedic_mul_4x4 u2 (.a(a[7:4]), .b(b[3:0]), .p(pp2)); // Ah×Bl  → [11:4]
    vedic_mul_4x4 u3 (.a(a[7:4]), .b(b[7:4]), .p(pp3)); // Ah×Bh  → [15:8]

    wire [9:0] mid = {2'b0, pp1} + {2'b0, pp2};          // 10-bit @ bit-4 alignment
    wire [15:0] sum1 = {8'b0, pp0};
    wire [15:0] sum2 = {2'b0, mid, 4'b0};
    wire [15:0] sum3 = {pp3, 8'b0};

    assign p = sum1 + sum2 + sum3;
endmodule


// ---------------------------------------------------------------------------
// 16×16 → 32-bit (four 8×8 units + partial-product summation)
// ---------------------------------------------------------------------------
module vedic_mul_16x16 (
    input  [15:0] a,
    input  [15:0] b,
    output [31:0] p
);
    wire [15:0] pp0, pp1, pp2, pp3;
    vedic_mul_8x8 u0 (.a(a[7:0]),  .b(b[7:0]),  .p(pp0)); // Al×Bl  → [15:0]
    vedic_mul_8x8 u1 (.a(a[7:0]),  .b(b[15:8]), .p(pp1)); // Al×Bh  → [23:8]
    vedic_mul_8x8 u2 (.a(a[15:8]), .b(b[7:0]),  .p(pp2)); // Ah×Bl  → [23:8]
    vedic_mul_8x8 u3 (.a(a[15:8]), .b(b[15:8]), .p(pp3)); // Ah×Bh  → [31:16]

    wire [17:0] mid = {2'b0, pp1} + {2'b0, pp2};          // 18-bit @ bit-8 alignment
    wire [31:0] sum1 = {16'b0, pp0};
    wire [31:0] sum2 = {6'b0, mid, 8'b0};
    wire [31:0] sum3 = {pp3, 16'b0};

    assign p = sum1 + sum2 + sum3;
endmodule


// ---------------------------------------------------------------------------
// 32×32 → 64-bit (four 16×16 units + partial-product summation)
// This is the top-level module instantiated by the PCPI wrapper.
// ---------------------------------------------------------------------------
module vedic_mul_32x32 (
    input  [31:0] a,
    input  [31:0] b,
    output [63:0] p
);
    wire [31:0] pp0, pp1, pp2, pp3;
    vedic_mul_16x16 u0 (.a(a[15:0]),  .b(b[15:0]),  .p(pp0)); // Al×Bl  → [31:0]
    vedic_mul_16x16 u1 (.a(a[15:0]),  .b(b[31:16]), .p(pp1)); // Al×Bh  → [47:16]
    vedic_mul_16x16 u2 (.a(a[31:16]), .b(b[15:0]),  .p(pp2)); // Ah×Bl  → [47:16]
    vedic_mul_16x16 u3 (.a(a[31:16]), .b(b[31:16]), .p(pp3)); // Ah×Bh  → [63:32]

    // middle partial products (pp1+pp2) span 33 bits at alignment bit 16
    wire [33:0] mid = {2'b0, pp1} + {2'b0, pp2};

    wire [63:0] sum1 = {32'b0, pp0};
    wire [63:0] sum2 = {14'b0, mid, 16'b0};
    wire [63:0] sum3 = {pp3, 32'b0};

    assign p = sum1 + sum2 + sum3;
endmodule
