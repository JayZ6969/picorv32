// =============================================================================
// tb_ksa.v — Comprehensive testbench for the 32-bit Kogge-Stone Adder
//
// Covers:
//   • ADD:  unsigned, signed, zero, max-value, random, overflow/carry-out
//   • SUB:  borrow, zero result, max-negative, random
//   • Edge cases: 0+0, MAX+1(→carry), 0-1(→borrow=carry-out from KSA)
//
// Compile & run:
//   iverilog -o tb_ksa tb_ksa.v ../rtl/ksa.v && ./tb_ksa
//   gtkwave dump_ksa.vcd &
// =============================================================================

`timescale 1ns/1ps

module tb_ksa;

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    reg  [31:0] a;
    reg  [31:0] b;
    reg         sub;
    wire [31:0] sum;
    wire        cout;

    ksa #(.WIDTH(32)) dut (
        .a   (a),
        .b   (b),
        .sub (sub),
        .sum (sum),
        .cout(cout)
    );

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("dump_ksa.vcd");
        $dumpvars(0, tb_ksa);
    end

    // -------------------------------------------------------------------------
    // Tracking
    // -------------------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check_add;
        input [31:0] ta, tb_in;
        input        tsub;
        input [31:0] expect_sum;
        input        expect_cout;
        input [63:0] test_name_placeholder; // just a number
        reg   [32:0] full;
        begin
            a   = ta;
            b   = tb_in;
            sub = tsub;
            #5;  // propagation
            full = tsub ? ({1'b0,ta} + {1'b0,~tb_in} + 33'd1)
                        : ({1'b0,ta} + {1'b0, tb_in});
            if (sum !== expect_sum || cout !== expect_cout) begin
                $display("FAIL  a=%h b=%h sub=%b  got sum=%h cout=%b  want sum=%h cout=%b",
                         ta, tb_in, tsub, sum, cout, expect_sum, expect_cout);
                fail_cnt = fail_cnt + 1;
            end else begin
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    // Self-checking task using Verilog arithmetic as oracle
    task auto_check;
        input [31:0] ta, tb_in;
        input        tsub;
        reg   [32:0] ref_full;
        reg   [31:0] ref_sum;
        reg          ref_cout;
        begin
            a   = ta;
            b   = tb_in;
            sub = tsub;
            #5;
            ref_full = tsub ? ({1'b0,ta} + {1'b0,~tb_in} + 33'd1)
                             : ({1'b0,ta} + {1'b0, tb_in});
            ref_sum  = ref_full[31:0];
            ref_cout = ref_full[32];
            if (sum !== ref_sum || cout !== ref_cout) begin
                $display("FAIL  a=%08h b=%08h sub=%b  got sum=%08h cout=%b  want sum=%08h cout=%b",
                         ta, tb_in, tsub, sum, cout, ref_sum, ref_cout);
                fail_cnt = fail_cnt + 1;
            end else begin
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Random stimulus
    // -------------------------------------------------------------------------
    integer i;
    reg [31:0] randa, randb;

    initial begin
        $display("=====================================================");
        $display("  tb_ksa — Kogge-Stone Adder Testbench");
        $display("=====================================================");

        // --------- Directed ADD tests ----------------------------------------
        $display("\n[1] Directed ADD tests");

        // 0 + 0 = 0, no carry
        auto_check(32'h0000_0000, 32'h0000_0000, 1'b0);
        // 1 + 1 = 2
        auto_check(32'h0000_0001, 32'h0000_0001, 1'b0);
        // MAX + 0 = MAX
        auto_check(32'hFFFF_FFFF, 32'h0000_0000, 1'b0);
        // MAX + 1 = 0 with carry-out
        auto_check(32'hFFFF_FFFF, 32'h0000_0001, 1'b0);
        // MAX + MAX = 0xFFFFFFFE with carry-out
        auto_check(32'hFFFF_FFFF, 32'hFFFF_FFFF, 1'b0);
        // 0x5555_5555 + 0xAAAA_AAAA = 0xFFFF_FFFF
        auto_check(32'h5555_5555, 32'hAAAA_AAAA, 1'b0);
        // 0x8000_0000 + 0x8000_0000 = overflow → 0 + carry
        auto_check(32'h8000_0000, 32'h8000_0000, 1'b0);
        // Alternating patterns
        auto_check(32'hDEAD_BEEF, 32'h0102_0304, 1'b0);
        auto_check(32'hCAFE_BABE, 32'h0BAD_F00D, 1'b0);

        // --------- Directed SUB tests ----------------------------------------
        $display("[2] Directed SUB tests");

        // 0 - 0 = 0, no borrow (cout=1 means no borrow in two's complement)
        auto_check(32'h0000_0000, 32'h0000_0000, 1'b1);
        // 1 - 1 = 0
        auto_check(32'h0000_0001, 32'h0000_0001, 1'b1);
        // 0 - 1 = 0xFFFFFFFF (borrow, cout=0)
        auto_check(32'h0000_0000, 32'h0000_0001, 1'b1);
        // MAX - MAX = 0
        auto_check(32'hFFFF_FFFF, 32'hFFFF_FFFF, 1'b1);
        // MAX - 0 = MAX
        auto_check(32'hFFFF_FFFF, 32'h0000_0000, 1'b1);
        // 0x1000_0000 - 0x0FFF_FFFF = 1
        auto_check(32'h1000_0000, 32'h0FFF_FFFF, 1'b1);
        // Signed: negative result
        auto_check(32'h0000_0005, 32'h0000_000A, 1'b1);
        // 0x8000_0000 - 1 = 0x7FFF_FFFF
        auto_check(32'h8000_0000, 32'h0000_0001, 1'b1);
        // 0 - MAX = 1 (two's complement)
        auto_check(32'h0000_0000, 32'hFFFF_FFFF, 1'b1);
        // Sign boundary
        auto_check(32'h7FFF_FFFF, 32'h8000_0000, 1'b1);

        // --------- Random tests ----------------------------------------------
        $display("[3] Pseudo-random tests (1024 ADD + 1024 SUB)");
        randa = 32'hDEAD_BEEF;
        randb = 32'hCAFE_BABE;

        for (i = 0; i < 1024; i = i+1) begin
            // LFSR-style random
            randa = {randa[30:0], randa[31] ^ randa[21] ^ randa[1] ^ randa[0]};
            randb = {randb[30:0], randb[31] ^ randb[21] ^ randb[1] ^ randb[0]};
            auto_check(randa, randb, 1'b0);  // ADD
        end

        randa = 32'hABCD_EF01;
        randb = 32'h1234_5678;
        for (i = 0; i < 1024; i = i+1) begin
            randa = {randa[30:0], randa[31] ^ randa[21] ^ randa[1] ^ randa[0]};
            randb = {randb[30:0], randb[31] ^ randb[21] ^ randb[1] ^ randb[0]};
            auto_check(randa, randb, 1'b1);  // SUB
        end

        // --------- Carry-propagation stress ----------------------------------
        $display("[4] Carry-propagation patterns");
        // All bits set except LSB → adding 1 should produce carry chain
        auto_check(32'hFFFF_FFFE, 32'h0000_0001, 1'b0);
        auto_check(32'hFFFF_FFFC, 32'h0000_0003, 1'b0);
        auto_check(32'hFFFF_FFF0, 32'h0000_000F, 1'b0);
        auto_check(32'hFFFF_FF00, 32'h0000_00FF, 1'b0);
        auto_check(32'hFFFF_0000, 32'h0000_FFFF, 1'b0);
        auto_check(32'hFF00_0000, 32'h00FF_FFFF, 1'b0);
        auto_check(32'hF000_0000, 32'h0FFF_FFFF, 1'b0);
        auto_check(32'h8000_0000, 32'h7FFF_FFFF, 1'b0);

        // --------- Summary ----------------------------------------------------
        $display("\n=====================================================");
        $display("  Results: %0d PASSED   %0d FAILED", pass_cnt, fail_cnt);
        $display("=====================================================");
        if (fail_cnt == 0)
            $display("  ** ALL TESTS PASSED **");
        else
            $display("  ** FAILURES DETECTED — check output above **");

        $finish;
    end

    // Timeout watchdog
    initial #1_000_000 begin
        $display("TIMEOUT: simulation exceeded 1ms limit");
        $finish;
    end

endmodule
