// opt/formal/ksa/ksa_formal.sv
// Formal property checker for ksa_adder
// Proves: for all A, B, Cin → Sum == A+B+Cin, Cout correct

`timescale 1ns/1ps

module ksa_formal;
    // Symbolic (free) inputs — solver can assign any value
    (* anyconst *) reg [31:0] A;
    (* anyconst *) reg [31:0] B;
    (* anyconst *) reg        Cin;

    // DUT outputs
    wire [31:0] Sum;
    wire        Cout;

    // Instantiate the KSA
    ksa_adder #(.WIDTH(32)) dut (
        .A   (A),
        .B   (B),
        .Cin (Cin),
        .Sum (Sum),
        .Cout(Cout)
    );

    // Reference: Verilog built-in addition (known correct)
    wire [32:0] ref_result = {1'b0, A} + {1'b0, B} + {32'b0, Cin};

    // ── Properties ──────────────────────────────────────
    // P1: Sum is correct lower 32 bits
    always @(*) begin
        P1_sum_correct: assert (Sum == ref_result[31:0]);
    end

    // P2: Cout is correct carry-out
    always @(*) begin
        P2_cout_correct: assert (Cout == ref_result[32]);
    end

    // P3: Zero + Zero + 0 = 0 (sanity cover)
    always @(*) begin
        P3_zero_cover: cover (A == 0 && B == 0 && Cin == 0 && Sum == 0);
    end

    // P4: All-ones inputs (carry propagation stress)
    always @(*) begin
        P4_allones_cover: cover (
            A == 32'hFFFFFFFF && B == 32'hFFFFFFFF && Cout == 1'b1
        );
    end

    // P5: No spurious carry when inputs small
    always @(*) begin
        P5_no_spurious_carry: assert (
            !(A < 32'h80000000 && B < 32'h80000000 && Cin == 0) || Cout == 0
        );
    end

endmodule
