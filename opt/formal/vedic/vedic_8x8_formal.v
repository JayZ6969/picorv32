`timescale 1ns/1ps

module vedic_8x8_formal (
    input wire [7:0] A,
    input wire [7:0] B
);

wire [15:0] P;
vedic_mul_8x8 dut (.A(A), .B(B), .P(P));

wire [15:0] P_ref = {8'b0, A} * {8'b0, B};

always @(*) begin
    assert (P == P_ref);
end

endmodule
