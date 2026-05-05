// =============================================================
// ksa_formal.v -- Formal properties for KSA correctness
// Proves Sum/Cout equivalence to A+B+Cin for all inputs.
// =============================================================
`timescale 1ns/1ps

module ksa_formal (
    input wire [31:0] A,
    input wire [31:0] B,
    input wire        Cin
);

wire [31:0] Sum;
wire        Cout;

ksa_32bit dut (.A(A), .B(B), .Cin(Cin), .Sum(Sum), .Cout(Cout));

wire [32:0] ref = {1'b0, A} + {1'b0, B} + {32'b0, Cin};

always @(*) begin
    assert (Sum == ref[31:0]);
end

always @(*) begin
    assert (Cout == ref[32]);
end

wire [31:0] Sum_swap;
wire        Cout_swap;
ksa_32bit dut_swap (.A(B), .B(A), .Cin(Cin), .Sum(Sum_swap), .Cout(Cout_swap));

always @(*) begin
    assert (Sum == Sum_swap);
    assert (Cout == Cout_swap);
end

wire [31:0] Sum_zero;
wire        Cout_zero;
ksa_32bit dut_zero (.A(A), .B(32'h0), .Cin(1'b0), .Sum(Sum_zero), .Cout(Cout_zero));

always @(*) begin
    assert (Sum_zero == A);
    assert (Cout_zero == 1'b0);
end

endmodule
