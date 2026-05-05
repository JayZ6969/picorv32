// =============================================================
// tb_pcpi_vedic_mul.v -- PCPI protocol and functional testbench
//
// Tests:
//   - Pipelined response timing for PCPI multiply operations
//   - pcpi_wait behavior during execution
//   - MUL, MULH, MULHSU, MULHU correctness
//   - Back-to-back requests
//   - Back-to-back stress (20 ops, no inserted idle cycles)
//   - Reset asserted mid-operation
//   - pcpi_valid drop mid-pipeline
// =============================================================
`timescale 1ns/1ps

module tb_pcpi_vedic_mul;

reg clk, resetn;

reg         pcpi_valid;
reg  [31:0] pcpi_insn;
reg  [31:0] pcpi_rs1;
reg  [31:0] pcpi_rs2;
wire        pcpi_wr;
wire [31:0] pcpi_rd;
wire        pcpi_wait;
wire        pcpi_ready;

pcpi_vedic_mul dut (
    .clk        (clk),
    .resetn     (resetn),
    .pcpi_valid (pcpi_valid),
    .pcpi_insn  (pcpi_insn),
    .pcpi_rs1   (pcpi_rs1),
    .pcpi_rs2   (pcpi_rs2),
    .pcpi_wr    (pcpi_wr),
    .pcpi_rd    (pcpi_rd),
    .pcpi_wait  (pcpi_wait),
    .pcpi_ready (pcpi_ready)
);

always #5 clk = ~clk;

function [31:0] make_mul_insn;
    input [2:0] funct3;
    begin
        make_mul_insn = {7'b0000001, 5'd2, 5'd1, funct3, 5'd3, 7'b0110011};
    end
endfunction

function [31:0] expected_result;
    input [31:0] rs1, rs2;
    input [2:0]  funct3;
    reg signed [63:0] signed_prod;
    reg signed [63:0] mixed_prod;
    reg [63:0] unsigned_prod;
    begin
        case (funct3)
            3'b000: expected_result = (rs1 * rs2);
            3'b001: begin
                signed_prod = $signed(rs1) * $signed(rs2);
                expected_result = signed_prod[63:32];
            end
            3'b010: begin
                mixed_prod = $signed(rs1) * $signed({1'b0, rs2});
                expected_result = mixed_prod[63:32];
            end
            3'b011: begin
                unsigned_prod = {32'b0, rs1} * {32'b0, rs2};
                expected_result = unsigned_prod[63:32];
            end
            default: expected_result = 32'hDEADBEEF;
        endcase
    end
endfunction

integer pass_count, fail_count, test_num;
integer cycle_count;
integer latency_sum;
integer wait_cycle_sum;
integer num_transactions;
integer min_latency;
integer max_latency;
integer k;
reg [31:0] exp;
integer dump_en;

task measure_and_check;
    input [31:0] rs1_in;
    input [31:0] rs2_in;
    input [2:0]  funct3;
    integer      lat;
    integer      wait_cycles;
    integer      timeout_ctr;
    begin
        @(negedge clk);
        pcpi_valid = 1'b1;
        pcpi_insn  = make_mul_insn(funct3);
        pcpi_rs1   = rs1_in;
        pcpi_rs2   = rs2_in;

        lat = 0;
        wait_cycles = 0;
        timeout_ctr = 200;
        while (!pcpi_ready && timeout_ctr > 0) begin
            @(posedge clk); #1;
            lat = lat + 1;
            timeout_ctr = timeout_ctr - 1;
            if (pcpi_wait)
                wait_cycles = wait_cycles + 1;
        end

        if (timeout_ctr == 0) begin
            $display("FAIL test %0d: TIMEOUT waiting for pcpi_ready", test_num);
            fail_count = fail_count + 1;
            @(negedge clk);
            pcpi_valid = 1'b0;
            pcpi_insn  = 32'b0;
            pcpi_rs1   = 32'b0;
            pcpi_rs2   = 32'b0;
            test_num = test_num + 1;
            disable measure_and_check;
        end

        exp = expected_result(rs1_in, rs2_in, funct3);
        if (pcpi_rd !== exp) begin
            $display("FAIL test %0d: funct3=%b rs1=%h rs2=%h | got=%h exp=%h",
                     test_num, funct3, rs1_in, rs2_in, pcpi_rd, exp);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end

        $display("PCPI_METRIC funct3=%0d rs1=%h rs2=%h latency=%0d wait_cycles=%0d result=%h",
                 funct3, rs1_in, rs2_in, lat, wait_cycles, pcpi_rd);

        latency_sum = latency_sum + lat;
        wait_cycle_sum = wait_cycle_sum + wait_cycles;
        num_transactions = num_transactions + 1;
        if (lat < min_latency)
            min_latency = lat;
        if (lat > max_latency)
            max_latency = lat;

        @(negedge clk);
        pcpi_valid = 1'b0;
        pcpi_insn  = 32'b0;
        pcpi_rs1   = 32'b0;
        pcpi_rs2   = 32'b0;

        @(posedge clk); #1;
        test_num = test_num + 1;
    end
endtask

task run_valid_drop_transaction;
    input [31:0] rs1_in;
    input [31:0] rs2_in;
    input [2:0]  funct3;
    integer      lat;
    integer      wait_cycles;
    integer      timeout_ctr;
    begin
        @(negedge clk);
        pcpi_valid = 1'b1;
        pcpi_insn  = make_mul_insn(funct3);
        pcpi_rs1   = rs1_in;
        pcpi_rs2   = rs2_in;

        lat = 0;
        wait_cycles = 0;
        timeout_ctr = 200;

        @(posedge clk); #1;
        lat = lat + 1;
        if (pcpi_wait)
            wait_cycles = wait_cycles + 1;
        pcpi_valid = 1'b0;

        while (!pcpi_ready && timeout_ctr > 0) begin
            @(posedge clk); #1;
            lat = lat + 1;
            timeout_ctr = timeout_ctr - 1;
            if (pcpi_wait)
                wait_cycles = wait_cycles + 1;
        end

        if (timeout_ctr == 0) begin
            $display("FAIL test %0d: TIMEOUT during valid-drop sequence", test_num);
            fail_count = fail_count + 1;
            @(negedge clk);
            pcpi_valid = 1'b0;
            test_num = test_num + 1;
            disable run_valid_drop_transaction;
        end

        exp = expected_result(rs1_in, rs2_in, funct3);
        if (pcpi_rd !== exp) begin
            $display("FAIL test %0d: valid-drop data mismatch got=%h exp=%h", test_num, pcpi_rd, exp);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end

        $display("PCPI_METRIC funct3=%0d rs1=%h rs2=%h latency=%0d wait_cycles=%0d result=%h valid_drop=1",
                 funct3, rs1_in, rs2_in, lat, wait_cycles, pcpi_rd);

        latency_sum = latency_sum + lat;
        wait_cycle_sum = wait_cycle_sum + wait_cycles;
        num_transactions = num_transactions + 1;
        if (lat < min_latency)
            min_latency = lat;
        if (lat > max_latency)
            max_latency = lat;

        @(negedge clk);
        pcpi_valid = 1'b0;
        test_num = test_num + 1;
    end
endtask

task run_back_to_back_stress;
    input integer num_ops;
    integer op_idx;
    integer lat;
    integer wait_cycles;
    integer timeout_ctr;
    reg [31:0] rs1_local;
    reg [31:0] rs2_local;
    reg [2:0]  funct3_local;
    begin
        @(negedge clk);
        pcpi_valid = 1'b1;

        for (op_idx = 0; op_idx < num_ops; op_idx = op_idx + 1) begin
            rs1_local = 32'h0101_0001 ^ (op_idx * 32'h0001_0021);
            rs2_local = 32'h8000_0001 + (op_idx * 32'h0000_0011);
            funct3_local = op_idx[2:0] & 3'b011;

            pcpi_insn  = make_mul_insn(funct3_local);
            pcpi_rs1   = rs1_local;
            pcpi_rs2   = rs2_local;

            lat = 0;
            wait_cycles = 0;
            timeout_ctr = 200;

            // Consume at least one cycle so we never sample ready/data
            // from the previous transaction.
            @(posedge clk); #1;
            lat = lat + 1;
            timeout_ctr = timeout_ctr - 1;
            if (pcpi_wait)
                wait_cycles = wait_cycles + 1;

            while (!pcpi_ready && timeout_ctr > 0) begin
                @(posedge clk); #1;
                lat = lat + 1;
                timeout_ctr = timeout_ctr - 1;
                if (pcpi_wait)
                    wait_cycles = wait_cycles + 1;
            end

            if (timeout_ctr == 0) begin
                $display("FAIL test %0d: TIMEOUT in back-to-back stress", test_num);
                fail_count = fail_count + 1;
                @(negedge clk);
                pcpi_valid = 1'b0;
                pcpi_insn  = 32'b0;
                pcpi_rs1   = 32'b0;
                pcpi_rs2   = 32'b0;
                test_num = test_num + 1;
                disable run_back_to_back_stress;
            end

            exp = expected_result(rs1_local, rs2_local, funct3_local);
            if (pcpi_rd !== exp) begin
                $display("FAIL test %0d: stress funct3=%b rs1=%h rs2=%h | got=%h exp=%h",
                         test_num, funct3_local, rs1_local, rs2_local, pcpi_rd, exp);
                fail_count = fail_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end

            $display("PCPI_METRIC funct3=%0d rs1=%h rs2=%h latency=%0d wait_cycles=%0d result=%h stress=1",
                     funct3_local, rs1_local, rs2_local, lat, wait_cycles, pcpi_rd);

            latency_sum = latency_sum + lat;
            wait_cycle_sum = wait_cycle_sum + wait_cycles;
            num_transactions = num_transactions + 1;
            if (lat < min_latency)
                min_latency = lat;
            if (lat > max_latency)
                max_latency = lat;

            test_num = test_num + 1;

            // No inserted idle cycle: drive next request on the very next
            // negedge after this completion.
            if (op_idx != num_ops - 1)
                @(negedge clk);
        end

        @(negedge clk);
        pcpi_valid = 1'b0;
        pcpi_insn  = 32'b0;
        pcpi_rs1   = 32'b0;
        pcpi_rs2   = 32'b0;
    end
endtask

task run_reset_midop_sequence;
    integer settle_ctr;
    begin
        @(negedge clk);
        pcpi_valid = 1'b1;
        pcpi_insn  = make_mul_insn(3'b000);
        pcpi_rs1   = 32'h1234_5678;
        pcpi_rs2   = 32'h0000_00ff;

        repeat (2) @(posedge clk);

        @(negedge clk);
        resetn    = 1'b0;
        pcpi_valid = 1'b0;
        pcpi_insn  = 32'b0;
        pcpi_rs1   = 32'b0;
        pcpi_rs2   = 32'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        settle_ctr = 4;
        while (settle_ctr > 0) begin
            @(posedge clk); #1;
            settle_ctr = settle_ctr - 1;
        end

        if (pcpi_ready || pcpi_wr) begin
            $display("FAIL test %0d: unexpected ready/wr after reset-midop (ready=%0d wr=%0d)",
                     test_num, pcpi_ready, pcpi_wr);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end
        test_num = test_num + 1;

        // Sanity check post-reset operation
        measure_and_check(32'h1111_1111, 32'h0000_0009, 3'b000);
    end
endtask

integer i;
reg [31:0] rand_a, rand_b;
integer random_groups;
integer random_progress_step;
integer run_stress20;
integer run_reset_midop;

initial begin
    if ($test$plusargs("dump_vcd")) begin
        dump_en = 1;
        $dumpfile("sim/vcd/pcpi_vedic_mul.vcd");
        $dumpvars(0, tb_pcpi_vedic_mul);
        $display("VCD: enabled (+dump_vcd)");
    end else begin
        dump_en = 0;
        $display("VCD: disabled (pass +dump_vcd to enable)");
    end

    clk        = 0;
    resetn     = 0;
    pcpi_valid = 0;
    pcpi_insn  = 0;
    pcpi_rs1   = 0;
    pcpi_rs2   = 0;
    pass_count = 0;
    fail_count = 0;
    test_num   = 0;
    latency_sum = 0;
    wait_cycle_sum = 0;
    num_transactions = 0;
    min_latency = 32'h7fffffff;
    max_latency = 0;

    random_groups = 1000;
    if ($test$plusargs("rand1k"))
        random_groups = 1000;
    if ($value$plusargs("rand_groups=%d", random_groups)) begin
        // explicit override accepted
    end
    if (random_groups < 0)
        random_groups = 0;
    random_progress_step = (random_groups >= 10) ? (random_groups / 10) : 1;

    run_stress20 = $test$plusargs("stress20") ? 1 : 0;
    run_reset_midop = $test$plusargs("reset_midop") ? 1 : 0;

    repeat (4) @(posedge clk);
    @(negedge clk) resetn = 1;
    repeat (2) @(posedge clk);

    $display("=========================================");
    $display("PCPI Vedic Multiplier Testbench Starting");
    $display("=========================================");

    $display("\n[1] MUL Instruction Tests");
    measure_and_check(32'd0,         32'd0,        3'b000);
    measure_and_check(32'd1,         32'd1,        3'b000);
    measure_and_check(32'd5,         32'd7,        3'b000);
    measure_and_check(32'hFFFFFFFF,  32'h1,        3'b000);
    measure_and_check(32'hFFFFFFFF,  32'hFFFFFFFF, 3'b000);
    measure_and_check(32'h80000000,  32'h2,        3'b000);

    $display("\n[2] MULH Instruction Tests");
    measure_and_check(32'hFFFFFFFF,  32'hFFFFFFFF, 3'b001);
    measure_and_check(32'h80000000,  32'h80000000, 3'b001);
    measure_and_check(32'h7FFFFFFF,  32'h7FFFFFFF, 3'b001);
    measure_and_check(32'hFFFFFFFF,  32'h80000000, 3'b001);
    measure_and_check(32'd100,       32'd200,      3'b001);

    $display("\n[3] MULHSU Instruction Tests");
    measure_and_check(32'hFFFFFFFF,  32'hFFFFFFFF, 3'b010);
    measure_and_check(32'h80000000,  32'hFFFFFFFF, 3'b010);
    measure_and_check(32'h7FFFFFFF,  32'hFFFFFFFF, 3'b010);
    measure_and_check(32'hFFFFFFFF,  32'h00000001, 3'b010);
    measure_and_check(32'h00000001,  32'hFFFFFFFF, 3'b010);

    $display("\n[4] MULHU Instruction Tests");
    measure_and_check(32'hFFFFFFFF,  32'hFFFFFFFF, 3'b011);
    measure_and_check(32'h80000000,  32'h80000000, 3'b011);
    measure_and_check(32'h00010000,  32'h00010000, 3'b011);
    measure_and_check(32'd65536,     32'd65536,    3'b011);

    $display("\n[5] Back-to-Back Transaction Test");
    for (i = 0; i < 5; i = i + 1) begin
        measure_and_check(32'd10 * (i + 1), 32'd10 * (i + 1), 3'b000);
    end

    if (run_stress20) begin
        $display("\n[5b] Back-to-Back Stress Test (20 ops, no inserted idle cycles)");
        run_back_to_back_stress(20);
    end

    $display("\n[6] Random Tests (%0d vectors x 4 variants)", random_groups);
    for (i = 0; i < random_groups; i = i + 1) begin
        rand_a = $random;
        rand_b = $random;
        measure_and_check(rand_a, rand_b, 3'b000);
        measure_and_check(rand_a, rand_b, 3'b001);
        measure_and_check(rand_a, rand_b, 3'b010);
        measure_and_check(rand_a, rand_b, 3'b011);
        if ((((i + 1) % random_progress_step) == 0) || ((i + 1) == random_groups))
            $display("[6] Progress: %0d/%0d groups", i + 1, random_groups);
    end

    $display("\n[7] Valid Drop Mid-Pipeline");
    run_valid_drop_transaction(32'h12345678, 32'h9ABCDEF0, 3'b000);

    if (run_reset_midop) begin
        $display("\n[8] Reset Mid-Operation Test");
        run_reset_midop_sequence();
    end

    $display("\n=========================================");
    $display("RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("Average latency: %0d cycles", (num_transactions > 0) ? (latency_sum / num_transactions) : 0);
    $display("METRIC avg_pcpi_latency %0d", (num_transactions > 0) ? (latency_sum / num_transactions) : 0);
    $display("METRIC min_pcpi_latency %0d", (num_transactions > 0) ? min_latency : 0);
    $display("METRIC max_pcpi_latency %0d", max_latency);
    $display("METRIC total_mul_ops %0d", num_transactions);
    $display("METRIC total_pcpi_wait_cycles %0d", wait_cycle_sum);
    $display("METRIC avg_pcpi_wait_cycles %0d", (num_transactions > 0) ? (wait_cycle_sum / num_transactions) : 0);
    $display("METRIC fail_count %0d", fail_count);
    $display("METRIC test_status %0d", (fail_count == 0) ? 1 : 0);
    if (fail_count == 0)
        $display("STATUS: ALL PASS");
    else
        $display("STATUS: FAILURES DETECTED");
    $display("=========================================");

    $finish;
end

endmodule
