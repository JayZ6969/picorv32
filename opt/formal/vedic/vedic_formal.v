`timescale 1ns/1ps

module vedic_formal (
    input wire        clk,
    input wire [31:0] A,
    input wire [31:0] B
);

wire [63:0] P;
vedic_mul_32x32 dut (.clk(clk), .A(A), .B(B), .P(P));

reg [31:0] A_r0;
reg [31:0] A_r1;
reg [31:0] A_r2;
reg [31:0] A_r3;
reg [31:0] B_r0;
reg [31:0] B_r1;
reg [31:0] B_r2;
reg [31:0] B_r3;
reg [3:0]  valid_r;

wire [63:0] P_ref = {32'b0, A_r3} * {32'b0, B_r3};

wire [63:0] P_zero;
vedic_mul_32x32 dut_zero (.clk(clk), .A(32'b0), .B(B), .P(P_zero));

wire [63:0] P_swap;
vedic_mul_32x32 dut_swap (.clk(clk), .A(B), .B(A), .P(P_swap));

initial begin
    A_r0 = 32'd0;
    A_r1 = 32'd0;
    A_r2 = 32'd0;
    A_r3 = 32'd0;
    B_r0 = 32'd0;
    B_r1 = 32'd0;
    B_r2 = 32'd0;
    B_r3 = 32'd0;
    valid_r = 4'b0000;
end

always @(posedge clk) begin
    A_r0 <= A;
    A_r1 <= A_r0;
    A_r2 <= A_r1;
    A_r3 <= A_r2;
    B_r0 <= B;
    B_r1 <= B_r0;
    B_r2 <= B_r1;
    B_r3 <= B_r2;
    valid_r <= {valid_r[2:0], 1'b1};

    assert (P_zero == 64'b0);

    if (valid_r[3]) begin
        assert (P == P_ref);
        assert (P_swap == P_ref);
        assert (P[31:0] == (A_r3 * B_r3));
    end
end

endmodule
