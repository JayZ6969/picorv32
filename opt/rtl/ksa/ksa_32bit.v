`timescale 1ns/1ps

module ksa_32bit #(
    parameter integer WIDTH = 32
) (
    input  wire [WIDTH-1:0] A,
    input  wire [WIDTH-1:0] B,
    input  wire             Cin,
    output wire [WIDTH-1:0] Sum,
    output wire             Cout
);

ksa_adder #(
    .WIDTH(WIDTH)
) u_ksa_adder (
    .A(A),
    .B(B),
    .Cin(Cin),
    .Sum(Sum),
    .Cout(Cout)
);

endmodule