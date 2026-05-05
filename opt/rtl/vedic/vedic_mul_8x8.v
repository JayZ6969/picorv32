`timescale 1ns/1ps

module vedic_mul_8x8 #(
    parameter integer WIDTH = 8
) (
    input  wire [WIDTH-1:0]  A,
    input  wire [WIDTH-1:0]  B,
    output wire [(2*WIDTH)-1:0] P
);

localparam integer HALF = WIDTH / 2;

wire [(2*HALF)-1:0] P_LL;
wire [(2*HALF)-1:0] P_LH;
wire [(2*HALF)-1:0] P_HL;
wire [(2*HALF)-1:0] P_HH;

localparam integer PROD_W = 2 * WIDTH;

wire [PROD_W-1:0] t_ll;
wire [PROD_W-1:0] t_lh;
wire [PROD_W-1:0] t_hl;
wire [PROD_W-1:0] t_hh;

wire [PROD_W-1:0] csa_l1_sum;
wire [PROD_W-1:0] csa_l1_carry;
wire [PROD_W-1:0] csa_l2_sum;
wire [PROD_W-1:0] csa_l2_carry;
wire [PROD_W-1:0] p_ksa;
wire              p_ksa_cout_unused;

vedic_mul_4x4 #(.WIDTH(HALF)) u_ll (.A(A[HALF-1:0]),      .B(B[HALF-1:0]),      .P(P_LL));
vedic_mul_4x4 #(.WIDTH(HALF)) u_lh (.A(A[HALF-1:0]),      .B(B[WIDTH-1:HALF]),  .P(P_LH));
vedic_mul_4x4 #(.WIDTH(HALF)) u_hl (.A(A[WIDTH-1:HALF]),  .B(B[HALF-1:0]),      .P(P_HL));
vedic_mul_4x4 #(.WIDTH(HALF)) u_hh (.A(A[WIDTH-1:HALF]),  .B(B[WIDTH-1:HALF]),  .P(P_HH));

assign t_ll = {{WIDTH{1'b0}}, P_LL};
assign t_lh = {{HALF{1'b0}}, P_LH, {HALF{1'b0}}};
assign t_hl = {{HALF{1'b0}}, P_HL, {HALF{1'b0}}};
assign t_hh = {P_HH, {WIDTH{1'b0}}};

csa_cell #(.WIDTH(PROD_W)) u_csa_l1 (
    .X(t_ll),
    .Y(t_lh),
    .Z(t_hl),
    .SUM(csa_l1_sum),
    .CARRY(csa_l1_carry)
);

csa_cell #(.WIDTH(PROD_W)) u_csa_l2 (
    .X(csa_l1_sum),
    .Y(csa_l1_carry),
    .Z(t_hh),
    .SUM(csa_l2_sum),
    .CARRY(csa_l2_carry)
);

ksa_adder #(.WIDTH(PROD_W)) u_ksa_final (
    .A(csa_l2_sum),
    .B(csa_l2_carry),
    .Cin(1'b0),
    .Sum(p_ksa),
    .Cout(p_ksa_cout_unused)
);

assign P = p_ksa;

endmodule
