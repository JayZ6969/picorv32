// =============================================================================
// tb_mul_compare.v — Side-by-side: Reference Multiplier vs Vedic 32×32
//
// Methodology: identical stimulus applied to both DUTs simultaneously.
// Propagation time measured with $realtime, results emitted to CSV.
//
// Emits:
//   results/mul_timing.csv
//   results/mul_summary.csv
//
// Run:
//   iverilog -o build/tb_mul_compare tb_mul_compare.v \
//            rtl/ref_mul_32.v rtl/vedic_mul_32.v && vvp build/tb_mul_compare
// =============================================================================

`timescale 1ps/1ps

module tb_mul_compare;

    // -----------------------------------------------------------------------
    // DUT: Reference (generic) multiplier
    // -----------------------------------------------------------------------
    reg  [31:0] ref_a, ref_b;
    wire [63:0] ref_p;
    ref_mul_32x32 dut_ref (.a(ref_a), .b(ref_b), .p(ref_p));

    // -----------------------------------------------------------------------
    // DUT: Vedic multiplier (optimised)
    // -----------------------------------------------------------------------
    reg  [31:0] ved_a, ved_b;
    wire [63:0] ved_p;
    vedic_mul_32x32 dut_ved (.a(ved_a), .b(ved_b), .p(ved_p));

    // -----------------------------------------------------------------------
    // Files
    // -----------------------------------------------------------------------
    integer fd_timing, fd_summary;
    integer SAMPLES = 2048;

    initial begin
        $dumpfile("build/dump_mul_compare.vcd");
        $dumpvars(0, tb_mul_compare);
    end

    real ref_t0, ref_t1, ref_delay;
    real ved_t0, ved_t1, ved_delay;
    real ref_total, ved_total;
    real ref_min, ved_min, ref_max, ved_max;
    integer pass_ref, pass_ved, fail_ref, fail_ved;
    integer i;

    reg [31:0] lfsr_a, lfsr_b;
    task next_lfsr;
        begin
            lfsr_a = {lfsr_a[30:0], lfsr_a[31]^lfsr_a[21]^lfsr_a[1]^lfsr_a[0]};
            lfsr_b = {lfsr_b[30:0], lfsr_b[31]^lfsr_b[21]^lfsr_b[1]^lfsr_b[0]};
        end
    endtask

    reg [63:0] ref_expected;

    initial begin
        fd_timing  = $fopen("results/mul_timing.csv",  "w");
        fd_summary = $fopen("results/mul_summary.csv", "w");
        $fwrite(fd_timing, "sample,a_hex,b_hex,ref_delay_ps,ved_delay_ps,ref_correct,ved_correct\n");

        lfsr_a = 32'hDEAD_CAFE;
        lfsr_b = 32'hBEEF_1234;
        ref_total = 0; ved_total = 0;
        ref_min = 1e18; ved_min = 1e18;
        ref_max = 0;    ved_max = 0;
        pass_ref = 0; pass_ved = 0;
        fail_ref = 0; fail_ved = 0;

        $display("=====================================================");
        $display("  Multiplier Comparison: Reference vs Vedic (32x32)");
        $display("  Samples: %0d  |  Timescale: 1ps/1ps", SAMPLES);
        $display("=====================================================");

        for (i = 0; i < SAMPLES; i = i + 1) begin
            next_lfsr;

            // Reference
            ref_t0 = $realtime;
            ref_a = lfsr_a; ref_b = lfsr_b;
            #1;
            ref_t1 = $realtime;
            ref_delay = ref_t1 - ref_t0;

            // Vedic
            ved_t0 = $realtime;
            ved_a = lfsr_a; ved_b = lfsr_b;
            #1;
            ved_t1 = $realtime;
            ved_delay = ved_t1 - ved_t0;

            // Expected: 64-bit unsigned product
            ref_expected = {32'b0, lfsr_a} * {32'b0, lfsr_b};

            if (ref_p === ref_expected) pass_ref = pass_ref + 1;
            else begin
                fail_ref = fail_ref + 1;
                $display("REF FAIL i=%0d a=%h b=%h got=%h want=%h", i, lfsr_a, lfsr_b, ref_p, ref_expected);
            end

            if (ved_p === ref_expected) pass_ved = pass_ved + 1;
            else begin
                fail_ved = fail_ved + 1;
                $display("VED FAIL i=%0d a=%h b=%h got=%h want=%h", i, lfsr_a, lfsr_b, ved_p, ref_expected);
            end

            ref_total = ref_total + ref_delay;
            ved_total = ved_total + ved_delay;
            if (ref_delay < ref_min) ref_min = ref_delay;
            if (ved_delay < ved_min) ved_min = ved_delay;
            if (ref_delay > ref_max) ref_max = ref_delay;
            if (ved_delay > ved_max) ved_max = ved_delay;

            $fwrite(fd_timing, "%0d,%h,%h,%.2f,%.2f,%0d,%0d\n",
                    i, lfsr_a, lfsr_b,
                    ref_delay, ved_delay,
                    (ref_p===ref_expected) ? 1:0,
                    (ved_p===ref_expected) ? 1:0);
        end

        $fclose(fd_timing);

        $fwrite(fd_summary, "metric,reference,vedic,improvement_pct\n");
        $fwrite(fd_summary, "avg_delay_ps,%.4f,%.4f,%.2f\n",
                ref_total/SAMPLES, ved_total/SAMPLES,
                100.0*(ref_total-ved_total)/ref_total);
        $fwrite(fd_summary, "min_delay_ps,%.4f,%.4f,%.2f\n",
                ref_min, ved_min,
                100.0*(ref_min-ved_min)/ref_min);
        $fwrite(fd_summary, "max_delay_ps,%.4f,%.4f,%.2f\n",
                ref_max, ved_max,
                100.0*(ref_max-ved_max)/ref_max);
        $fwrite(fd_summary, "pass_count,%0d,%0d,0\n", pass_ref, pass_ved);
        $fwrite(fd_summary, "fail_count,%0d,%0d,0\n", fail_ref, fail_ved);
        $fclose(fd_summary);

        $display("\n--- Results ---");
        $display("                    Reference        Vedic");
        $display("  Avg delay (ps): %8.2f         %8.2f   (%.1f%% reduction)",
                 ref_total/SAMPLES, ved_total/SAMPLES,
                 100.0*(ref_total-ved_total)/ref_total);
        $display("  Pass:           %8d          %8d", pass_ref, pass_ved);
        $display("  Fail:           %8d          %8d", fail_ref, fail_ved);
        $display("\nCSV written to results/mul_timing.csv and results/mul_summary.csv");
        $finish;
    end

endmodule
