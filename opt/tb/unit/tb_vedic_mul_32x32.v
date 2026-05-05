// =============================================================
// tb_vedic_mul_32x32.v -- 32x32 Vedic Multiplier Testbench
// 68,000+ vectors across 5 categories
// Reference: Verilog's built-in * operator
// =============================================================
`timescale 1ns/1ps

module tb_vedic_mul_32x32;

reg clk = 0;
reg  [31:0] A, B;
wire [63:0] P;
localparam integer PIPELINE_LATENCY = 4;

always #5 clk = ~clk;

vedic_mul_32x32 dut (
    .clk(clk),
    .A(A),
    .B(B),
    .P(P)
);

wire [63:0] P_ref;
assign P_ref = {32'b0, A} * {32'b0, B};

integer pass_count, fail_count, test_num;

task apply_and_check;
    input [31:0] a_in;
    input [31:0] b_in;
    begin
        A = a_in;
        B = b_in;
        repeat (PIPELINE_LATENCY) @(posedge clk);
        #1;

        if (P !== P_ref) begin
            $display("FAIL test %0d: A=%h B=%h | Got P=%h | Exp P=%h",
                      test_num, a_in, b_in, P, P_ref);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end

        test_num = test_num + 1;
    end
endtask

integer i, j;
reg [31:0] rand_a, rand_b;
integer dump_en;
integer random_tests;
integer progress_step;

initial begin
    // Keep long regressions fast by default; enable waveform with +dump_vcd.
    if ($test$plusargs("dump_vcd")) begin
        dump_en = 1;
        $dumpfile("sim/vcd/vedic_32x32.vcd");
        $dumpvars(0, tb_vedic_mul_32x32);
        $display("VCD: enabled (+dump_vcd)");
    end else begin
        dump_en = 0;
        $display("VCD: disabled (pass +dump_vcd to enable)");
    end

    pass_count = 0;
    fail_count = 0;
    test_num   = 0;
    A = 0;
    B = 0;

    // Default is full regression. Use +quick or +smoke for faster debug loops,
    // or override directly with +rand_tests=<N>.
    random_tests = 67000;
    if ($test$plusargs("quick"))
        random_tests = 4000;
    if ($test$plusargs("smoke"))
        random_tests = 256;
    if ($value$plusargs("rand_tests=%d", random_tests)) begin
        // explicit override accepted
    end
    if (random_tests < 0)
        random_tests = 0;
    progress_step = (random_tests >= 10) ? (random_tests / 10) : 1;

    $display("=========================================");
    $display("Vedic 32x32 Multiplier Testbench Starting");
    $display("=========================================");

    $display("\n[1] Zero and Identity Tests");
    apply_and_check(32'h0,        32'h0);
    apply_and_check(32'hFFFFFFFF, 32'h0);
    apply_and_check(32'h0,        32'hFFFFFFFF);
    apply_and_check(32'h1,        32'hFFFFFFFF);
    apply_and_check(32'hFFFFFFFF, 32'h1);
    apply_and_check(32'h1,        32'h1);

    $display("\n[2] Single-Bit Tests (1024 vectors)");
    for (i = 0; i < 32; i = i + 1) begin
        for (j = 0; j < 32; j = j + 1) begin
            apply_and_check(32'h1 << i, 32'h1 << j);
        end
    end

    $display("\n[3] Power of Two and Boundary Tests");
    apply_and_check(32'hFFFFFFFF, 32'hFFFFFFFF);
    apply_and_check(32'h80000000, 32'h80000000);
    apply_and_check(32'hFFFF0000, 32'h0000FFFF);
    apply_and_check(32'h0000FFFF, 32'hFFFF0000);
    apply_and_check(32'hFFFF0000, 32'hFFFF0000);
    apply_and_check(32'h0000FFFF, 32'h0000FFFF);
    apply_and_check(32'hFF000000, 32'h00FF0000);
    apply_and_check(32'h0000FF00, 32'h000000FF);

    $display("\n[4] Known-Answer Tests");
    apply_and_check(32'd5,     32'd7);
    apply_and_check(32'd100,   32'd100);
    apply_and_check(32'd1000,  32'd1000);
    apply_and_check(32'd65535, 32'd65535);
    apply_and_check(32'd2,     32'd31);
    apply_and_check(32'h00010000, 32'h00010000);
    apply_and_check(32'h00100000, 32'h00100000);

    $display("\n[5] Random Tests (%0d vectors)", random_tests);
    for (i = 0; i < random_tests; i = i + 1) begin
        rand_a = $random;
        rand_b = $random;
        apply_and_check(rand_a, rand_b);
        if ((((i + 1) % progress_step) == 0) || ((i + 1) == random_tests))
            $display("[5] Progress: %0d/%0d", i + 1, random_tests);
    end

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
