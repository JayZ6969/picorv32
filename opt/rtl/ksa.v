// =============================================================================
// Kogge-Stone Parallel Prefix Adder — 32-bit, parameterized WIDTH
// Supports addition AND subtraction (pass sub=1 to negate B via two's complement)
//
// Critical-path depth: O(log2 WIDTH) prefix levels instead of O(WIDTH) for RCA.
// For WIDTH=32: 5 prefix levels = ~5 XOR/AND gate delays on the carry path.
//
// Interface:
//   a    [WIDTH-1:0]  Operand A
//   b    [WIDTH-1:0]  Operand B
//   sub               When 1, computes A - B (i.e., A + ~B + 1)
//   sum  [WIDTH-1:0]  Result
//   cout              Carry-out (overflow detection for unsigned arithmetic)
// =============================================================================

`timescale 1ns/1ps

module ksa #(
    parameter WIDTH = 32
) (
    input  [WIDTH-1:0] a,
    input  [WIDTH-1:0] b,
    input              sub,   // 0→add, 1→subtract
    output [WIDTH-1:0] sum,
    output             cout
);

    // -------------------------------------------------------------------------
    // Pre-processing: Generate (G) and Propagate (P) signals per bit
    //   B is conditionally inverted for subtraction; carry-in is sub.
    // -------------------------------------------------------------------------
    wire [WIDTH-1:0] b_eff = b ^ {WIDTH{sub}};   // ~b when sub=1, b when sub=0

    wire [WIDTH-1:0] g0 = a & b_eff;              // bit-level generate
    wire [WIDTH-1:0] p0 = a ^ b_eff;              // bit-level propagate (also used as XOR sum bits)

    // -------------------------------------------------------------------------
    // Prefix network — Kogge-Stone topology
    // Each stage doubles the span of the carry look-ahead.
    // After log2(WIDTH) stages, G[i] contains the group-generate for bits [i:0],
    // which equals the carry INTO bit i+1.
    //
    // Naming:  g[stage][bit], p[stage][bit]
    //   g[k][i]  = carry generated for prefix [i .. 0]
    //   p[k][i]  = carry propagated  for prefix [i .. 0]
    // -------------------------------------------------------------------------
    localparam LEVELS = $clog2(WIDTH);   // 5 for WIDTH=32

    // Unpack into 2-D arrays via wires.
    // Verilog-2001 doesn't allow 2-D port arrays, so we use flat wire banks.
    wire [WIDTH-1:0] g [0:LEVELS];
    wire [WIDTH-1:0] p [0:LEVELS];

    assign g[0] = g0;
    assign p[0] = p0;

    genvar k, i;
    generate
        for (k = 0; k < LEVELS; k = k + 1) begin : PREFIX_STAGE
            localparam SPAN = 1 << k;   // 1,2,4,8,16 for k=0..4
            for (i = 0; i < WIDTH; i = i + 1) begin : BIT
                if (i >= SPAN) begin
                    // Black-cell (Kogge-Stone operator):
                    //   G[k+1][i] = G[k][i] | (P[k][i] & G[k][i-SPAN])
                    //   P[k+1][i] = P[k][i] & P[k][i-SPAN]
                    assign g[k+1][i] = g[k][i] | (p[k][i] & g[k][i-SPAN]);
                    assign p[k+1][i] = p[k][i] & p[k][i-SPAN];
                end else begin
                    // Buffer-cell: bit doesn't yet have a predecessor at this span
                    assign g[k+1][i] = g[k][i];
                    assign p[k+1][i] = p[k][i];
                end
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Post-processing: form final carry chain, then XOR with propagate bits
    //   carry[i]  = carry into position i
    //   carry[0]  = sub  (the initial carry-in of the two's-complement trick)
    //
    //   For i > 0:
    //     carry[i] = G_group[i-1] | (P_group[i-1] & cin)
    //
    //   where G_group and P_group are the full-prefix (group) signals from
    //   the Kogge-Stone tree covering bits [i-1:0].
    //   This correctly propagates the carry-in through long chains of
    //   generate=0, propagate=1 bits (e.g., -B when B=0).
    // -------------------------------------------------------------------------
    wire [WIDTH:0] carry;
    assign carry[0] = sub;
    genvar j;
    generate
        for (j = 1; j <= WIDTH; j = j + 1) begin : CARRY_OUT
            assign carry[j] = g[LEVELS][j-1] | (p[LEVELS][j-1] & sub);
        end
    endgenerate

    // Sum bit i = propagate[i] XOR carry[i]
    assign sum  = p0 ^ carry[WIDTH-1:0];
    assign cout = carry[WIDTH];

endmodule
