`timescale 1ns/1ps

module vedic_16x16_ag_formal (
    input wire        clk,
    input wire [15:0] A,
    input wire [15:0] B
);

wire [31:0] P;
vedic_mul_16x16 dut (.clk(clk), .A(A), .B(B), .P(P));

reg [15:0] A_r;
reg [15:0] B_r;
reg        valid_r;

initial begin
    A_r = 16'd0;
    B_r = 16'd0;
    valid_r = 1'b0;
end

always @(posedge clk) begin
    if (valid_r) begin
        assert (P == ({16'b0, A_r} * {16'b0, B_r}));
    end

    valid_r <= 1'b1;
    A_r <= A;
    B_r <= B;
end

endmodule
