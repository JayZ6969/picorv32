`timescale 1ns/1ps

`ifndef ENABLE_FAST_MUL
`define ENABLE_FAST_MUL 0
`endif

`ifndef FIRMWARE
`define FIRMWARE "firmware/mul_test/mul_test.hex"
`endif

module tb_picorv32_baseline_top;

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
    .ENABLE_FAST_MUL (`ENABLE_FAST_MUL),
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
    .mem_rdata (mem_rdata)
);

always @(posedge clk) begin
    if (resetn) begin
        total_cycles <= total_cycles + 1;
        if (uut.pcpi_int_wait)
            stall_cycles <= stall_cycles + 1;
        if (mem_valid && mem_instr && mem_ready)
            insn_retired <= insn_retired + 1;
    end
end

always @(posedge clk) begin
    mem_ready <= 0;
    if (mem_valid && !mem_ready) begin
        mem_ready <= 1;
        mem_rdata <= {mem[mem_addr+3], mem[mem_addr+2], mem[mem_addr+1], mem[mem_addr+0]};
        if (mem_wstrb[0]) mem[mem_addr+0] <= mem_wdata[7:0];
        if (mem_wstrb[1]) mem[mem_addr+1] <= mem_wdata[15:8];
        if (mem_wstrb[2]) mem[mem_addr+2] <= mem_wdata[23:16];
        if (mem_wstrb[3]) mem[mem_addr+3] <= mem_wdata[31:24];
    end
end

initial begin
    $readmemh(`FIRMWARE, mem);
end

initial begin
    if ($test$plusargs("dump_vcd")) begin
        $dumpfile("sim/vcd/picorv32_integration.vcd");
        $dumpvars(0, tb_picorv32_baseline_top);
    end
end

localparam [31:0] DONE_ADDR = 32'h0000101C;

integer timeout_cycles;
integer done_seen;
real stall_pct;
real effective_ipc;

initial begin
    total_cycles = 0;
    stall_cycles = 0;
    insn_retired = 0;
    mem_ready = 0;
    mem_rdata = 0;
    done_seen = 0;

    repeat (4) @(posedge clk);
    resetn = 1;

    timeout_cycles = 500000;
    while (timeout_cycles > 0 && !done_seen) begin
        @(posedge clk);
        timeout_cycles = timeout_cycles - 1;
        if ({mem[DONE_ADDR+3], mem[DONE_ADDR+2], mem[DONE_ADDR+1], mem[DONE_ADDR+0]} == 32'h0000DEAD)
            done_seen = 1;
    end

    if (!done_seen)
        $display("FAIL: timeout waiting for firmware completion");

    stall_pct = (total_cycles > 0) ? (stall_cycles * 100.0 / total_cycles) : 0.0;
    effective_ipc = (total_cycles > 0) ? (insn_retired * 1.0 / total_cycles) : 0.0;

    $display("Firmware completed at cycle %0d", total_cycles);
    $display("ENABLE_FAST_MUL = %0d", `ENABLE_FAST_MUL);
    $display("Firmware: %s", `FIRMWARE);
    $display("METRIC total_cycles %0d", total_cycles);
    $display("METRIC stall_cycles %0d", stall_cycles);
    $display("METRIC insn_retired %0d", insn_retired);
    $display("METRIC stall_pct %.6f", stall_pct);
    $display("METRIC effective_ipc %.6f", effective_ipc);

    $finish;
end

endmodule
