`timescale 1ns/1ps

module vedic_mul_32x32 #(
    parameter integer WIDTH = 32
) (
    input  wire              clk,
    input  wire [WIDTH-1:0] A,
    input  wire [WIDTH-1:0] B,
    output wire [(2*WIDTH)-1:0] P
);

localparam integer HALF = WIDTH / 2;
localparam integer PROD_W = 2 * WIDTH;

wire [(2*HALF)-1:0] P_LL;
wire [(2*HALF)-1:0] P_LH;
wire [(2*HALF)-1:0] P_HL;
wire [(2*HALF)-1:0] P_HH;

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

(* dont_touch = "true" *) reg [PROD_W-1:0] p_ll_r;
(* dont_touch = "true" *) reg [PROD_W-1:0] p_lh_r;
(* dont_touch = "true" *) reg [PROD_W-1:0] p_hl_r;
(* dont_touch = "true" *) reg [PROD_W-1:0] p_hh_r;
(* dont_touch = "true" *) reg [PROD_W-1:0] s1_sum_r;
(* dont_touch = "true" *) reg [PROD_W-1:0] s1_carry_r;
(* dont_touch = "true" *) reg [PROD_W-1:0] s1_hh_r;

vedic_mul_16x16 #(.WIDTH(HALF)) u_ll (.clk(clk), .A(A[HALF-1:0]),      .B(B[HALF-1:0]),      .P(P_LL));
vedic_mul_16x16 #(.WIDTH(HALF)) u_lh (.clk(clk), .A(A[HALF-1:0]),      .B(B[WIDTH-1:HALF]),  .P(P_LH));
vedic_mul_16x16 #(.WIDTH(HALF)) u_hl (.clk(clk), .A(A[WIDTH-1:HALF]),  .B(B[HALF-1:0]),      .P(P_HL));
vedic_mul_16x16 #(.WIDTH(HALF)) u_hh (.clk(clk), .A(A[WIDTH-1:HALF]),  .B(B[WIDTH-1:HALF]),  .P(P_HH));

assign t_ll = {{WIDTH{1'b0}}, P_LL};
assign t_lh = {{HALF{1'b0}}, P_LH, {HALF{1'b0}}};
assign t_hl = {{HALF{1'b0}}, P_HL, {HALF{1'b0}}};
assign t_hh = {P_HH, {WIDTH{1'b0}}};

always @(posedge clk) begin
    p_ll_r <= t_ll;
    p_lh_r <= t_lh;
    p_hl_r <= t_hl;
    p_hh_r <= t_hh;
end

csa_cell #(.WIDTH(PROD_W)) u_csa_l1 (
    .X(p_ll_r),
    .Y(p_lh_r),
    .Z(p_hl_r),
    .SUM(csa_l1_sum),
    .CARRY(csa_l1_carry)
);

// Pipeline cut: register first CSA layer outputs before final reduction.
always @(posedge clk) begin
    s1_sum_r <= csa_l1_sum;
    s1_carry_r <= csa_l1_carry;
    s1_hh_r <= p_hh_r;
end

csa_cell #(.WIDTH(PROD_W)) u_csa_l2 (
    .X(s1_sum_r),
    .Y(s1_carry_r),
    .Z(s1_hh_r),
    .SUM(csa_l2_sum),
    .CARRY(csa_l2_carry)
);

ksa_64bit_pipelined u_ksa_final (
    .clk(clk),
    .A(csa_l2_sum),
    .B(csa_l2_carry),
    .Cin(1'b0),
    .Sum(p_ksa),
    .Cout(p_ksa_cout_unused)
);

assign P = p_ksa;

endmodule
