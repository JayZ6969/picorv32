`timescale 1ns/1ps

// Two-stage 64-bit KSA: lower 32 bits then upper 32 bits with registered carry.
module ksa_64bit_pipelined (
    input  wire        clk,
    input  wire [63:0] A,
    input  wire [63:0] B,
    input  wire        Cin,
    output wire [63:0] Sum,
    output wire        Cout
);

wire [31:0] sum_lo_w;
wire        carry_lo_w;
wire [31:0] sum_hi_w;

reg [31:0] sum_lo_r;
reg        carry_lo_r;
reg [31:0] a_hi_r;
reg [31:0] b_hi_r;

ksa_adder #(.WIDTH(32)) u_lo (
    .A(A[31:0]),
    .B(B[31:0]),
    .Cin(Cin),
    .Sum(sum_lo_w),
    .Cout(carry_lo_w)
);

// Pipeline split: register lower sum/carry and upper inputs.
always @(posedge clk) begin
    sum_lo_r <= sum_lo_w;
    carry_lo_r <= carry_lo_w;
    a_hi_r <= A[63:32];
    b_hi_r <= B[63:32];
end

ksa_adder #(.WIDTH(32)) u_hi (
    .A(a_hi_r),
    .B(b_hi_r),
    .Cin(carry_lo_r),
    .Sum(sum_hi_w),
    .Cout(Cout)
);

assign Sum = {sum_hi_w, sum_lo_r};

endmodule
