`timescale 1ns/1ps

module vedic_2x2_formal (
    input wire [1:0] A,
    input wire [1:0] B
);

wire [3:0] P;
vedic_mul_2x2 dut (.A(A), .B(B), .P(P));

wire [3:0] P_ref = {2'b00, A} * {2'b00, B};

always @(*) begin
    assert (P == P_ref);
end

endmodule
