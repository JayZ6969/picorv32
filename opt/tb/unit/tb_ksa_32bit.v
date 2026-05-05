// =============================================================
// tb_ksa_32bit.v -- Comprehensive KSA 32-bit Testbench
// Tests: directed, carry-chain exhaustive, random (2075+ vectors)
// Pass criterion: all results match Verilog's built-in + operator
// =============================================================
`timescale 1ns/1ps

module tb_ksa_32bit;

reg  [31:0] A, B;
reg         Cin;
wire [31:0] Sum;
wire        Cout;

ksa_32bit dut (
    .A   (A),
    .B   (B),
    .Cin (Cin),
    .Sum (Sum),
    .Cout(Cout)
);

reg [32:0] expected;
integer pass_count;
integer fail_count;
integer test_num;

task apply_and_check;
    input [31:0] a_in;
    input [31:0] b_in;
    input        cin_in;
    begin
        A   = a_in;
        B   = b_in;
        Cin = cin_in;
        #10;

        expected = {1'b0, a_in} + {1'b0, b_in} + {32'b0, cin_in};

        if (Sum !== expected[31:0] || Cout !== expected[32]) begin
            $display("FAIL test %0d: A=%h B=%h Cin=%b | Got Sum=%h Cout=%b | Exp Sum=%h Cout=%b",
                      test_num, a_in, b_in, cin_in,
                      Sum, Cout,
                      expected[31:0], expected[32]);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end

        test_num = test_num + 1;
    end
endtask

integer i;
reg [31:0] rand_a, rand_b;
reg        rand_cin;
integer dump_en;

initial begin
    if ($test$plusargs("dump_vcd")) begin
        dump_en = 1;
        $dumpfile("sim/vcd/ksa_32bit.vcd");
        $dumpvars(0, tb_ksa_32bit);
        $display("VCD: enabled (+dump_vcd)");
    end else begin
        dump_en = 0;
        $display("VCD: disabled (pass +dump_vcd to enable)");
    end

    pass_count = 0;
    fail_count = 0;
    test_num   = 0;

    $display("=========================================");
    $display("KSA 32-bit Testbench Starting");
    $display("=========================================");

    $display("\n[1] Directed Edge Cases");
    apply_and_check(32'h00000000, 32'h00000000, 1'b0);
    apply_and_check(32'h00000000, 32'h00000000, 1'b1);
    apply_and_check(32'hFFFFFFFF, 32'h00000001, 1'b0);
    apply_and_check(32'hFFFFFFFF, 32'hFFFFFFFF, 1'b0);
    apply_and_check(32'hFFFFFFFF, 32'hFFFFFFFF, 1'b1);

    for (i = 0; i < 32; i = i + 1) begin
        apply_and_check(32'h1 << i, 32'h0, 1'b0);
        apply_and_check(32'h0, 32'h1 << i, 1'b0);
        apply_and_check(32'h1 << i, 32'h1 << i, 1'b0);
    end

    apply_and_check(32'hAAAAAAAA, 32'h55555555, 1'b0);
    apply_and_check(32'hAAAAAAAA, 32'h55555555, 1'b1);
    apply_and_check(32'h55555555, 32'hAAAAAAAA, 1'b0);
    apply_and_check(32'h80000000, 32'h80000000, 1'b0);
    apply_and_check(32'h7FFFFFFF, 32'h00000001, 1'b0);
    apply_and_check(32'h7FFFFFFF, 32'h7FFFFFFF, 1'b0);

    $display("[1] Done: %0d tests", test_num);

    $display("\n[2] Carry Chain Tests");
    for (i = 0; i < 32; i = i + 1) begin
        apply_and_check((32'h1 << i) - 1, 32'h1, 1'b0);
        apply_and_check(32'hFFFFFFFF >> (31-i), 32'h1, 1'b0);
    end

    apply_and_check(32'h00000001, 32'h00000001, 1'b0);
    apply_and_check(32'h00000003, 32'h00000001, 1'b0);
    apply_and_check(32'h0000000F, 32'h00000001, 1'b0);
    apply_and_check(32'h000000FF, 32'h00000001, 1'b0);
    apply_and_check(32'h0000FFFF, 32'h00000001, 1'b0);
    apply_and_check(32'hFFFFFFFF, 32'h00000001, 1'b0);

    $display("[2] Done: carry chain tests complete");

    $display("\n[3] Random Tests (2000 vectors)");
    for (i = 0; i < 2000; i = i + 1) begin
        rand_a   = $random;
        rand_b   = $random;
        rand_cin = $random & 1'b1;
        apply_and_check(rand_a, rand_b, rand_cin);
    end
    $display("[3] Done: 2000 random vectors tested");

    $display("\n=========================================");
    $display("RESULTS: %0d PASSED, %0d FAILED (of %0d total)",
              pass_count, fail_count, test_num);
    if (fail_count == 0)
        $display("STATUS: ALL PASS");
    else
        $display("STATUS: FAILURES DETECTED");
    $display("=========================================");

    $finish;
end

endmodule
