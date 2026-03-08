// =============================================================================
// tb_pcpi_compare.v — MUL latency: picorv32_pcpi_mul vs picorv32_pcpi_vedic_mul
//
// This is the primary Phase 2 metric for the report:
// how many clock cycles does each MUL implementation take from
// pcpi_valid assertion to pcpi_ready assertion?
//
// picorv32_pcpi_mul (baseline):   ~32 cycles (shift-and-add, STEPS_AT_ONCE=1)
// picorv32_pcpi_vedic_mul (opt):  3 cycles   (fixed pipeline latency)
//
// Emits:
//   results/pcpi_latency.csv    — per-operation latency histogram
//   results/pcpi_summary.csv    — aggregate statistics
//
// Run:
//   iverilog -o build/tb_pcpi_compare tb_pcpi_compare.v \
//            ../picorv32.v rtl/vedic_mul_32.v rtl/picorv32_pcpi_vedic_mul.v
//   vvp build/tb_pcpi_compare
// =============================================================================

`timescale 1ns/1ps

module tb_pcpi_compare;

    // -----------------------------------------------------------------------
    // Clock + reset
    // -----------------------------------------------------------------------
    reg clk, resetn;
    always #5 clk = ~clk;   // 100 MHz

    // -----------------------------------------------------------------------
    // PCPI bus — SEPARATE valid lines so each DUT is only active when
    //            we're measuring IT (otherwise crosstalk poisons results)
    // -----------------------------------------------------------------------
    reg         base_valid, ved_valid;   // individual enable per DUT
    reg  [31:0] pcpi_insn;
    reg  [31:0] pcpi_rs1;
    reg  [31:0] pcpi_rs2;

    // MUL instruction encoding: opcode=0110011, funct7=0000001, funct3=000
    localparam MUL_INSN = 32'b0000001_00010_00001_000_00011_0110011;

    // -----------------------------------------------------------------------
    // DUT 1: Baseline sequential multiplier
    // -----------------------------------------------------------------------
    wire        base_wr, base_wait, base_ready;
    wire [31:0] base_rd;

    picorv32_pcpi_mul #(.STEPS_AT_ONCE(1), .CARRY_CHAIN(4)) dut_base (
        .clk        (clk),
        .resetn     (resetn),
        .pcpi_valid (base_valid),
        .pcpi_insn  (pcpi_insn),
        .pcpi_rs1   (pcpi_rs1),
        .pcpi_rs2   (pcpi_rs2),
        .pcpi_wr    (base_wr),
        .pcpi_rd    (base_rd),
        .pcpi_wait  (base_wait),
        .pcpi_ready (base_ready)
    );

    // -----------------------------------------------------------------------
    // DUT 2: Vedic-based pipelined multiplier
    // -----------------------------------------------------------------------
    wire        ved_wr, ved_wait, ved_ready;
    wire [31:0] ved_rd;

    picorv32_pcpi_vedic_mul dut_ved (
        .clk        (clk),
        .resetn     (resetn),
        .pcpi_valid (ved_valid),
        .pcpi_insn  (pcpi_insn),
        .pcpi_rs1   (pcpi_rs1),
        .pcpi_rs2   (pcpi_rs2),
        .pcpi_wr    (ved_wr),
        .pcpi_rd    (ved_rd),
        .pcpi_wait  (ved_wait),
        .pcpi_ready (ved_ready)
    );

    // -----------------------------------------------------------------------
    // Files
    // -----------------------------------------------------------------------
    integer fd_lat, fd_sum;
    integer SAMPLES = 64;

    // -----------------------------------------------------------------------
    // Measurement state
    // -----------------------------------------------------------------------
    integer base_cycles;
    integer ved_cycles;
    integer base_total_cycles, ved_total_cycles;
    integer base_min, ved_min, base_max, ved_max;
    integer pass_base, fail_base, pass_ved, fail_ved;
    integer i;

    reg [31:0] lfsr_a, lfsr_b;
    reg [63:0] expected_full;
    reg [31:0] expected_lo;

    // Capture pcpi_rd at the cycle ready fires (before advancing clock)
    reg [31:0] base_rd_cap, ved_rd_cap;

    task next_lfsr;
        begin
            lfsr_a = {lfsr_a[30:0], lfsr_a[31]^lfsr_a[21]^lfsr_a[1]^lfsr_a[0]};
            lfsr_b = {lfsr_b[30:0], lfsr_b[31]^lfsr_b[21]^lfsr_b[1]^lfsr_b[0]};
        end
    endtask

    // -----------------------------------------------------------------------
    // Main
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("build/dump_pcpi_compare.vcd");
        $dumpvars(0, tb_pcpi_compare);

        fd_lat = $fopen("results/pcpi_latency.csv", "w");
        fd_sum = $fopen("results/pcpi_summary.csv", "w");
        $fwrite(fd_lat, "sample,a_hex,b_hex,expected_lo,base_cycles,ved_cycles,base_result,ved_result,base_ok,ved_ok\n");

        clk = 0; resetn = 0;
        base_valid = 0; ved_valid = 0; pcpi_insn = MUL_INSN;
        pcpi_rs1 = 0; pcpi_rs2 = 0;

        base_total_cycles = 0; ved_total_cycles = 0;
        base_min = 9999; ved_min = 9999;
        base_max = 0;    ved_max = 0;
        pass_base = 0; fail_base = 0;
        pass_ved = 0;  fail_ved = 0;

        lfsr_a = 32'hDEAD_BEEF;
        lfsr_b = 32'hCAFE_0101;

        repeat(4) @(posedge clk);
        resetn = 1;
        repeat(2) @(posedge clk);

        $display("=====================================================");
        $display("  PCPI MUL Latency: Sequential vs Vedic");
        $display("  Based on 100 MHz clock (10 ns period)");
        $display("=====================================================");

        for (i = 0; i < SAMPLES; i = i + 1) begin
            next_lfsr;
            pcpi_rs1 = lfsr_a;
            pcpi_rs2 = lfsr_b;
            expected_full = {32'b0, lfsr_a} * {32'b0, lfsr_b};
            expected_lo   = expected_full[31:0];

            // --- Baseline: measure until ready ---
            // Sample signals after #1ps delay post-posedge so NBA assignments
            // from the module's always @(posedge clk) blocks have resolved.
            base_cycles = 0;
            base_valid = 1;
            while (!base_ready) begin
                @(posedge clk); #1;
                base_cycles = base_cycles + 1;
                if (base_cycles > 200) begin
                    $display("TIMEOUT: baseline MUL took >200 cycles");
                    disable main_loop;
                end
            end
            // base_ready==1 here, base_rd holds the valid result
            base_rd_cap = base_rd;
            base_valid = 0;
            @(posedge clk); #1;  // let module clear ready

            if (base_rd_cap === expected_lo) pass_base = pass_base + 1;
            else begin
                fail_base = fail_base + 1;
                $display("BASE FAIL i=%0d: got %h want %h", i, base_rd_cap, expected_lo);
            end

            repeat(4) @(posedge clk);  // drain before next sample

            // --- Vedic: measure until ready ---
            ved_cycles = 0;
            ved_valid = 1;
            while (!ved_ready) begin
                @(posedge clk); #1;
                ved_cycles = ved_cycles + 1;
                if (ved_cycles > 20) begin
                    $display("TIMEOUT: vedic MUL took >20 cycles");
                    disable main_loop;
                end
            end
            ved_rd_cap = ved_rd;
            ved_valid = 0;
            @(posedge clk); #1;

            if (ved_rd_cap === expected_lo) pass_ved = pass_ved + 1;
            else begin
                fail_ved = fail_ved + 1;
                $display("VED FAIL i=%0d: got %h want %h", i, ved_rd_cap, expected_lo);
            end

            base_total_cycles = base_total_cycles + base_cycles;
            ved_total_cycles  = ved_total_cycles  + ved_cycles;
            if (base_cycles < base_min) base_min = base_cycles;
            if (ved_cycles  < ved_min)  ved_min  = ved_cycles;
            if (base_cycles > base_max) base_max = base_cycles;
            if (ved_cycles  > ved_max)  ved_max  = ved_cycles;

            $fwrite(fd_lat, "%0d,%h,%h,%h,%0d,%0d,%h,%h,%0d,%0d\n",
                    i, lfsr_a, lfsr_b, expected_lo,
                    base_cycles, ved_cycles,
                    base_rd_cap, ved_rd_cap,
                    (base_rd_cap===expected_lo)?1:0,
                    (ved_rd_cap===expected_lo)?1:0);

            repeat(4) @(posedge clk);
        end

        begin : main_loop end   // label anchor for disable

        $fclose(fd_lat);

        $fwrite(fd_sum, "metric,baseline_seq,vedic,speedup\n");
        $fwrite(fd_sum, "avg_cycles,%.2f,%.2f,%.2fx\n",
                1.0*base_total_cycles/SAMPLES,
                1.0*ved_total_cycles/SAMPLES,
                1.0*base_total_cycles/ved_total_cycles);
        $fwrite(fd_sum, "min_cycles,%0d,%0d,%.2fx\n", base_min, ved_min,
                (ved_min>0) ? 1.0*base_min/ved_min : 0);
        $fwrite(fd_sum, "max_cycles,%0d,%0d,%.2fx\n", base_max, ved_max,
                (ved_max>0) ? 1.0*base_max/ved_max : 0);
        $fwrite(fd_sum, "avg_latency_ns,%.2f,%.2f,%.2fx\n",
                10.0*base_total_cycles/SAMPLES,
                10.0*ved_total_cycles/SAMPLES,
                1.0*base_total_cycles/ved_total_cycles);
        $fwrite(fd_sum, "pass_count,%0d,%0d,N/A\n", pass_base, pass_ved);
        $fwrite(fd_sum, "fail_count,%0d,%0d,N/A\n", fail_base, fail_ved);
        $fclose(fd_sum);

        $display("\n--- Results (100 MHz = 10 ns/cycle) ---");
        $display("                    Baseline (seq)   Vedic (3-stage)");
        $display("  Avg cycles:     %8.1f        %8.1f    (%.1fx speedup)",
                 1.0*base_total_cycles/SAMPLES,
                 1.0*ved_total_cycles/SAMPLES,
                 1.0*base_total_cycles/ved_total_cycles);
        $display("  Min cycles:     %8d        %8d", base_min, ved_min);
        $display("  Max cycles:     %8d        %8d", base_max, ved_max);
        $display("  Avg latency ns: %8.1f        %8.1f",
                 10.0*base_total_cycles/SAMPLES,
                 10.0*ved_total_cycles/SAMPLES);
        $display("  Pass / Fail:    %4d/%0d          %4d/%0d",
                 pass_base, fail_base, pass_ved, fail_ved);
        $finish;
    end

endmodule
