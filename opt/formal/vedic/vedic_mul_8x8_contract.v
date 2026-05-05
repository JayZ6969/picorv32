`timescale 1ns/1ps

module vedic_mul_8x8 (
    input  wire [7:0] A,
    input  wire [7:0] B,
    output wire [15:0] P
);

assign P = {8'b0, A} * {8'b0, B};

endmodule
