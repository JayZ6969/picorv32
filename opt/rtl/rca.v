// =============================================================================
// rca.v — Ripple-Carry Adder (baseline / reference)
//
// The conventional O(N) critical-path adder that KSA replaces.
// Same interface as ksa.v so testbenches are drop-in compatible.
//
//  a, b  [WIDTH-1:0]  Operands
//  sub                1 → A – B (two's complement, cin = 1)
//  sum   [WIDTH-1:0]  Result
//  cout              Carry-out
//
// Critical path: N full-adder stages in series → O(N) gate delays.
// For WIDTH=32: 32 XOR + 32 carry stages on the critical path.
// =============================================================================

`timescale 1ns/1ps

module rca #(
    parameter WIDTH = 32
) (
    input  [WIDTH-1:0] a,
    input  [WIDTH-1:0] b,
    input              sub,   // 0→add, 1→subtract
    output [WIDTH-1:0] sum,
    output             cout
);
    wire [WIDTH-1:0] b_eff = b ^ {WIDTH{sub}};   // ~b when subtracting
    wire [WIDTH:0]   carry;

    assign carry[0] = sub;   // carry-in = 1 for subtraction (two's complement)

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : FA_CHAIN
            // Full adder: sum bit, carry out
            assign sum[i]     = a[i] ^ b_eff[i] ^ carry[i];
            assign carry[i+1] = (a[i] & b_eff[i]) | (a[i] & carry[i]) | (b_eff[i] & carry[i]);
        end
    endgenerate

    assign cout = carry[WIDTH];

endmodule
