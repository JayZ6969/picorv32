module vedic_mul_32x32_ref (
    input  wire [31:0] A,
    input  wire [31:0] B,
    output wire [63:0] P
);

assign P = {32'b0, A} * {32'b0, B};

endmodule
