// =============================================================
// tb_picorv32_top.v -- Full PicoRV32 Integration Testbench
//
// Instantiates PicoRV32 with the custom fast multiplier,
// loads firmware, and checks memory-mapped signatures.
// =============================================================
`timescale 1ns/1ps

`ifndef FIRMWARE
`define FIRMWARE "firmware/mul_test/mul_test.hex"
`endif

module tb_picorv32_top;

reg clk = 0;
reg resetn = 0;
always #5 clk = ~clk;

reg [7:0] mem [0:8191];

wire        mem_valid;
wire        mem_instr;
reg         mem_ready;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire  [3:0] mem_wstrb;
reg  [31:0] mem_rdata;

wire        trap;

integer total_cycles;
integer stall_cycles;
integer insn_retired;

picorv32 #(
    .ENABLE_MUL      (1),
    .ENABLE_FAST_MUL (1),
    .ENABLE_FAST_ADD (1),
    .BARREL_SHIFTER  (1)
) uut (
    .clk       (clk),
    .resetn    (resetn),
    .trap      (trap),
    .mem_valid (mem_valid),
    .mem_instr (mem_instr),
    .mem_ready (mem_ready),
    .mem_addr  (mem_addr),
    .mem_wdata (mem_wdata),
    .mem_wstrb (mem_wstrb),
    .mem_rdata (mem_rdata),
    .irq       (32'b0),
    .eoi       (),
    .trace_valid(),
    .trace_data()
);

always @(posedge clk) begin
    if (resetn) begin
        total_cycles <= total_cycles + 1;
        if (uut.pcpi_int_wait)
            stall_cycles <= stall_cycles + 1;
        if (mem_valid && mem_instr && mem_ready)
            insn_retired <= insn_retired + 1;
    end

    mem_ready <= 0;
    if (mem_valid && !mem_ready) begin
        mem_ready <= 1;

        mem_rdata <= {mem[mem_addr+3], mem[mem_addr+2],
                      mem[mem_addr+1], mem[mem_addr+0]};

        if (mem_wstrb[0]) mem[mem_addr+0] <= mem_wdata[7:0];
        if (mem_wstrb[1]) mem[mem_addr+1] <= mem_wdata[15:8];
        if (mem_wstrb[2]) mem[mem_addr+2] <= mem_wdata[23:16];
        if (mem_wstrb[3]) mem[mem_addr+3] <= mem_wdata[31:24];
    end
end

initial begin
    $readmemh(`FIRMWARE, mem);
end

localparam [31:0] DONE_ADDR = 32'h0000101C;
localparam [31:0] SIG_BASE  = 32'h00001000;

localparam [31:0] EXP_MUL_5x7       = 32'd35;
localparam [31:0] EXP_MUL_NEG1xNEG1 = 32'd1;
localparam [31:0] EXP_MUL_OVERFLOW  = 32'hFFFFFFFE;
localparam [31:0] EXP_MULH_MAXMAX   = 32'h3FFFFFFF;
localparam [31:0] EXP_MULH_NEG1NEG1 = 32'h00000000;
localparam [31:0] EXP_MULHSU_NEG1MAX = 32'hFFFFFFFF;
localparam [31:0] EXP_MULHU_MAXMAX  = 32'hFFFFFFFE;

integer timeout_cycles;
integer pass_count, fail_count;
integer done_seen;
reg [31:0] sig_val;
integer dump_en;
real stall_pct;
real effective_ipc;

initial begin
`ifdef DUMP_VCD
    begin
        dump_en = 1;
        $dumpfile("sim/vcd/picorv32_integration.vcd");
        $dumpvars(0, tb_picorv32_top);
        $display("VCD: enabled (DUMP_VCD define)");
    end
`else
    if ($test$plusargs("dump_vcd")) begin
        dump_en = 1;
        $dumpfile("sim/vcd/picorv32_integration.vcd");
        $dumpvars(0, tb_picorv32_top);
        $display("VCD: enabled (+dump_vcd)");
    end else begin
        dump_en = 0;
        $display("VCD: disabled (pass +dump_vcd to enable)");
    end
`endif

    pass_count = 0;
    fail_count = 0;
    done_seen = 0;
    total_cycles = 0;
    stall_cycles = 0;
    insn_retired = 0;
    mem_ready = 0;
    mem_rdata = 0;

    repeat (4) @(posedge clk);
    resetn = 1;
    $display("Core released from reset at time %0t", $time);

    timeout_cycles = 200000;
    while (timeout_cycles > 0 && !done_seen) begin
        @(posedge clk);
        timeout_cycles = timeout_cycles - 1;
        if ({mem[DONE_ADDR+3], mem[DONE_ADDR+2], mem[DONE_ADDR+1], mem[DONE_ADDR+0]} == 32'h0000DEAD) begin
            done_seen = 1;
            $display("Firmware completed at cycle %0d", total_cycles);
        end
    end

    if (!done_seen) begin
        $display("FAIL: Firmware timeout -- core never completed");
        $finish;
    end

    stall_pct = (total_cycles > 0) ? (stall_cycles * 100.0 / total_cycles) : 0.0;
    effective_ipc = (total_cycles > 0) ? (insn_retired * 1.0 / total_cycles) : 0.0;

    $display("METRIC total_cycles %0d", total_cycles);
    $display("METRIC stall_cycles %0d", stall_cycles);
    $display("METRIC insn_retired %0d", insn_retired);
    $display("METRIC stall_pct %.6f", stall_pct);
    $display("METRIC effective_ipc %.6f", effective_ipc);

    $display("\n=== Checking Memory Signature ===");

    sig_val = {mem[SIG_BASE+3], mem[SIG_BASE+2], mem[SIG_BASE+1], mem[SIG_BASE+0]};
    if (sig_val == EXP_MUL_5x7) begin
        $display("PASS: MUL 5x7 = %h", sig_val);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: MUL 5x7 got %h exp %h", sig_val, EXP_MUL_5x7);
        fail_count = fail_count + 1;
    end

    sig_val = {mem[SIG_BASE+7], mem[SIG_BASE+6], mem[SIG_BASE+5], mem[SIG_BASE+4]};
    if (sig_val == EXP_MUL_NEG1xNEG1) begin
        $display("PASS: MUL -1x-1 lower = %h", sig_val);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: MUL -1x-1 lower got %h exp %h", sig_val, EXP_MUL_NEG1xNEG1);
        fail_count = fail_count + 1;
    end

    sig_val = {mem[SIG_BASE+11], mem[SIG_BASE+10], mem[SIG_BASE+9], mem[SIG_BASE+8]};
    if (sig_val == EXP_MUL_OVERFLOW) begin
        $display("PASS: MUL overflow lower = %h", sig_val);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: MUL overflow lower got %h exp %h", sig_val, EXP_MUL_OVERFLOW);
        fail_count = fail_count + 1;
    end

    sig_val = {mem[SIG_BASE+15], mem[SIG_BASE+14], mem[SIG_BASE+13], mem[SIG_BASE+12]};
    if (sig_val == EXP_MULH_MAXMAX) begin
        $display("PASS: MULH max*max upper = %h", sig_val);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: MULH max*max upper got %h exp %h", sig_val, EXP_MULH_MAXMAX);
        fail_count = fail_count + 1;
    end

    sig_val = {mem[SIG_BASE+19], mem[SIG_BASE+18], mem[SIG_BASE+17], mem[SIG_BASE+16]};
    if (sig_val == EXP_MULH_NEG1NEG1) begin
        $display("PASS: MULH -1*-1 upper = %h", sig_val);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: MULH -1*-1 upper got %h exp %h", sig_val, EXP_MULH_NEG1NEG1);
        fail_count = fail_count + 1;
    end

    sig_val = {mem[SIG_BASE+23], mem[SIG_BASE+22], mem[SIG_BASE+21], mem[SIG_BASE+20]};
    if (sig_val == EXP_MULHSU_NEG1MAX) begin
        $display("PASS: MULHSU -1*UINT_MAX upper = %h", sig_val);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: MULHSU -1*UINT_MAX upper got %h exp %h", sig_val, EXP_MULHSU_NEG1MAX);
        fail_count = fail_count + 1;
    end

    sig_val = {mem[SIG_BASE+27], mem[SIG_BASE+26], mem[SIG_BASE+25], mem[SIG_BASE+24]};
    if (sig_val == EXP_MULHU_MAXMAX) begin
        $display("PASS: MULHU UINT_MAX*UINT_MAX upper = %h", sig_val);
        pass_count = pass_count + 1;
    end else begin
        $display("FAIL: MULHU UINT_MAX*UINT_MAX upper got %h exp %h", sig_val, EXP_MULHU_MAXMAX);
        fail_count = fail_count + 1;
    end

    $display("\n=========================================");
    $display("INTEGRATION RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
    if (fail_count == 0)
        $display("STATUS: ALL PASS");
    else
        $display("STATUS: FAILURES");
    $display("=========================================");

    $finish;
end

endmodule
