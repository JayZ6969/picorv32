`timescale 1ns/1ps

module vedic_mul_2x2 #(
    parameter integer WIDTH = 2
) (
    input  wire [WIDTH-1:0] A,
    input  wire [WIDTH-1:0] B,
    output wire [(2*WIDTH)-1:0] P
);

wire m00, m01, m10, m11;
wire ha_sum, ha_carry;

assign m00 = A[0] & B[0];
assign m01 = A[0] & B[1];
assign m10 = A[1] & B[0];
assign m11 = A[1] & B[1];

assign P[0] = m00;

assign ha_sum   = m01 ^ m10;
assign ha_carry = m01 & m10;

assign P[1] = ha_sum;
assign P[2] = m11 ^ ha_carry;
assign P[3] = m11 & ha_carry;

endmodule
