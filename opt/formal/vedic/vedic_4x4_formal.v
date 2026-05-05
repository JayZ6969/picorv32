`timescale 1ns/1ps

module vedic_4x4_formal (
    input wire [3:0] A,
    input wire [3:0] B
);

wire [7:0] P;
vedic_mul_4x4 dut (.A(A), .B(B), .P(P));

wire [7:0] P_ref = {4'b0, A} * {4'b0, B};

always @(*) begin
    assert (P == P_ref);
end

endmodule
