// =============================================================================
// tb_adder_compare.v — Side-by-side timing analysis: RCA vs KSA (32-bit)
//
// Methodology
// -----------
// Both adders are instantiated identically.  Each receives the same
// stimulus, driven from a shared 32-bit LFSR.  Propagation delay is
// measured by recording $realtime at input change and output settle.
//
// The testbench emits:
//   results/adder_timing.csv      — per-input sample timing data
//   results/adder_summary.csv     — aggregated statistics (min/avg/max)
//
// The critical-path delay comparison is the key Phase 1 metric.
//
// Run:
//   iverilog -o build/tb_adder_compare tb_adder_compare.v \
//            rtl/rca.v rtl/ksa.v && vvp build/tb_adder_compare
// =============================================================================

`timescale 1ps/1ps    // picosecond resolution for accurate delay capture

module tb_adder_compare;

    // -----------------------------------------------------------------------
    // DUT: Ripple-Carry Adder (baseline)
    // -----------------------------------------------------------------------
    reg  [31:0] rca_a, rca_b;
    reg         rca_sub;
    wire [31:0] rca_sum;
    wire        rca_cout;

    rca #(.WIDTH(32)) dut_rca (
        .a   (rca_a),
        .b   (rca_b),
        .sub (rca_sub),
        .sum (rca_sum),
        .cout(rca_cout)
    );

    // -----------------------------------------------------------------------
    // DUT: Kogge-Stone Adder (optimised)
    // -----------------------------------------------------------------------
    reg  [31:0] ksa_a, ksa_b;
    reg         ksa_sub;
    wire [31:0] ksa_sum;
    wire        ksa_cout;

    ksa #(.WIDTH(32)) dut_ksa (
        .a   (ksa_a),
        .b   (ksa_b),
        .sub (ksa_sub),
        .sum (ksa_sum),
        .cout(ksa_cout)
    );

    // -----------------------------------------------------------------------
    // VCD + file handles
    // -----------------------------------------------------------------------
    integer fd_timing, fd_summary;
    integer SAMPLES = 2048;

    initial begin
        $dumpfile("build/dump_adder_compare.vcd");
        $dumpvars(0, tb_adder_compare);
    end

    // -----------------------------------------------------------------------
    // Measurement helpers
    // -----------------------------------------------------------------------
    real rca_t_start, rca_t_end, rca_delay;
    real ksa_t_start, ksa_t_end, ksa_delay;

    real rca_total, ksa_total;
    real rca_min,   ksa_min;
    real rca_max,   ksa_max;
    integer pass_rca, pass_ksa, fail_rca, fail_ksa;
    integer i;

    // LFSR for pseudo-random input
    reg [31:0] lfsr_a, lfsr_b;
    reg        do_sub;

    task next_lfsr;
        begin
            lfsr_a = {lfsr_a[30:0], lfsr_a[31] ^ lfsr_a[21] ^ lfsr_a[1] ^ lfsr_a[0]};
            lfsr_b = {lfsr_b[30:0], lfsr_b[31] ^ lfsr_b[21] ^ lfsr_b[1] ^ lfsr_b[0]};
            do_sub = lfsr_a[0] ^ lfsr_b[1];
        end
    endtask

    // Reference result
    reg [32:0] ref_full;
    reg [31:0] ref_sum;
    reg        ref_cout;

    // -----------------------------------------------------------------------
    // Main
    // -----------------------------------------------------------------------
    initial begin
        // Create output directories / files
        fd_timing  = $fopen("results/adder_timing.csv", "w");
        fd_summary = $fopen("results/adder_summary.csv", "w");

        $fwrite(fd_timing, "sample,a_hex,b_hex,sub,rca_delay_ps,ksa_delay_ps,rca_correct,ksa_correct\n");

        // Init
        lfsr_a = 32'hDEAD_BEEF;
        lfsr_b = 32'hCAFE_BABE;
        rca_total = 0; ksa_total = 0;
        rca_min = 1e18; ksa_min = 1e18;
        rca_max = 0;    ksa_max = 0;
        pass_rca = 0; pass_ksa = 0;
        fail_rca = 0; fail_ksa = 0;

        $display("=====================================================");
        $display("  Adder Comparison: RCA vs KSA (32-bit)");
        $display("  Samples: %0d  |  Timescale: 1ps/1ps", SAMPLES);
        $display("=====================================================");

        for (i = 0; i < SAMPLES; i = i + 1) begin
            next_lfsr;

            // ─── RCA measurement ─────────────────────────────────────────
            rca_t_start = $realtime;
            rca_a = lfsr_a; rca_b = lfsr_b; rca_sub = do_sub;
            #1;   // allow propagation
            rca_t_end = $realtime;
            rca_delay = rca_t_end - rca_t_start;

            // ─── KSA measurement ──────────────────────────────────────────
            ksa_t_start = $realtime;
            ksa_a = lfsr_a; ksa_b = lfsr_b; ksa_sub = do_sub;
            #1;
            ksa_t_end = $realtime;
            ksa_delay = ksa_t_end - ksa_t_start;

            // ─── Reference check ─────────────────────────────────────────
            ref_full  = do_sub ? ({1'b0,lfsr_a} + {1'b0,~lfsr_b} + 33'd1)
                                : ({1'b0,lfsr_a} + {1'b0, lfsr_b});
            ref_sum   = ref_full[31:0];
            ref_cout  = ref_full[32];

            if (rca_sum === ref_sum && rca_cout === ref_cout) pass_rca = pass_rca + 1;
            else begin
                fail_rca = fail_rca + 1;
                $display("RCA FAIL i=%0d a=%h b=%h sub=%b", i, lfsr_a, lfsr_b, do_sub);
            end

            if (ksa_sum === ref_sum && ksa_cout === ref_cout) pass_ksa = pass_ksa + 1;
            else begin
                fail_ksa = fail_ksa + 1;
                $display("KSA FAIL i=%0d a=%h b=%h sub=%b", i, lfsr_a, lfsr_b, do_sub);
            end

            // Accumulate stats
            rca_total = rca_total + rca_delay;
            ksa_total = ksa_total + ksa_delay;
            if (rca_delay < rca_min) rca_min = rca_delay;
            if (ksa_delay < ksa_min) ksa_min = ksa_delay;
            if (rca_delay > rca_max) rca_max = rca_delay;
            if (ksa_delay > ksa_max) ksa_max = ksa_delay;

            // Write per-sample row
            $fwrite(fd_timing, "%0d,%h,%h,%0d,%.2f,%.2f,%0d,%0d\n",
                    i, lfsr_a, lfsr_b, do_sub,
                    rca_delay, ksa_delay,
                    (rca_sum===ref_sum && rca_cout===ref_cout) ? 1 : 0,
                    (ksa_sum===ref_sum && ksa_cout===ref_cout) ? 1 : 0);
        end

        // ─── Summary ─────────────────────────────────────────────────────
        $fclose(fd_timing);

        $fwrite(fd_summary, "metric,rca,ksa,improvement_pct\n");
        $fwrite(fd_summary, "avg_delay_ps,%.4f,%.4f,%.2f\n",
                rca_total/SAMPLES, ksa_total/SAMPLES,
                100.0*(rca_total - ksa_total)/rca_total);
        $fwrite(fd_summary, "min_delay_ps,%.4f,%.4f,%.2f\n",
                rca_min, ksa_min,
                100.0*(rca_min - ksa_min)/rca_min);
        $fwrite(fd_summary, "max_delay_ps,%.4f,%.4f,%.2f\n",
                rca_max, ksa_max,
                100.0*(rca_max - ksa_max)/rca_max);
        $fwrite(fd_summary, "pass_count,%0d,%0d,0\n", pass_rca, pass_ksa);
        $fwrite(fd_summary, "fail_count,%0d,%0d,0\n", fail_rca, fail_ksa);
        $fclose(fd_summary);

        $display("\n--- Results ---");
        $display("                    RCA              KSA");
        $display("  Avg delay (ps): %8.2f         %8.2f   (%.1f%% reduction)",
                 rca_total/SAMPLES, ksa_total/SAMPLES,
                 100.0*(rca_total-ksa_total)/rca_total);
        $display("  Min delay (ps): %8.2f         %8.2f", rca_min, ksa_min);
        $display("  Max delay (ps): %8.2f         %8.2f", rca_max, ksa_max);
        $display("  Pass:           %8d          %8d", pass_rca, pass_ksa);
        $display("  Fail:           %8d          %8d", fail_rca, fail_ksa);
        $display("\nCSV written to results/adder_timing.csv and results/adder_summary.csv");
        $finish;
    end

endmodule
