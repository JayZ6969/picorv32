`timescale 1ns/1ps

`ifndef BASELINE_CONFIG
`define BASELINE_CONFIG 0
`endif

module tb_pcpi_baseline_mul;

reg clk = 0;
reg resetn = 0;
always #5 clk = ~clk;

reg         pcpi_valid;
reg  [31:0] pcpi_insn;
reg  [31:0] pcpi_rs1;
reg  [31:0] pcpi_rs2;
wire        pcpi_wr;
wire [31:0] pcpi_rd;
wire        pcpi_wait;
wire        pcpi_ready;

// BASELINE_CONFIG:
//   0 -> picorv32_pcpi_mul (iterative)
//   1 -> picorv32_pcpi_fast_mul (native fast)
generate
if (`BASELINE_CONFIG == 0) begin : G_ITER
    picorv32_pcpi_mul dut (
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
end else begin : G_FAST
    picorv32_pcpi_fast_mul dut (
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
end
endgenerate

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

integer pass_count, fail_count;
integer op_count;
integer latency_sum;
integer wait_cycle_sum;
integer latency;
integer i;
integer timeout_ctr;
reg [31:0] exp;

// A compact vector set gives stable and quick measurements.
reg [31:0] vec_a [0:31];
reg [31:0] vec_b [0:31];
reg [2:0] vec_f [0:31];

initial begin
    vec_a[0]=32'd5;          vec_b[0]=32'd7;          vec_f[0]=3'b000;
    vec_a[1]=32'hFFFFFFFF;   vec_b[1]=32'hFFFFFFFF;   vec_f[1]=3'b000;
    vec_a[2]=32'h7FFFFFFF;   vec_b[2]=32'd2;          vec_f[2]=3'b000;
    vec_a[3]=32'h80000000;   vec_b[3]=32'd2;          vec_f[3]=3'b000;

    vec_a[4]=32'h7FFFFFFF;   vec_b[4]=32'h7FFFFFFF;   vec_f[4]=3'b001;
    vec_a[5]=32'hFFFFFFFF;   vec_b[5]=32'hFFFFFFFF;   vec_f[5]=3'b001;
    vec_a[6]=32'h80000000;   vec_b[6]=32'h80000000;   vec_f[6]=3'b001;
    vec_a[7]=32'hFFFFFFFF;   vec_b[7]=32'h80000000;   vec_f[7]=3'b001;

    vec_a[8]=32'hFFFFFFFF;   vec_b[8]=32'hFFFFFFFF;   vec_f[8]=3'b010;
    vec_a[9]=32'h80000000;   vec_b[9]=32'hFFFFFFFF;   vec_f[9]=3'b010;
    vec_a[10]=32'h7FFFFFFF;  vec_b[10]=32'hFFFFFFFF;  vec_f[10]=3'b010;
    vec_a[11]=32'h00000001;  vec_b[11]=32'hFFFFFFFF;  vec_f[11]=3'b010;

    vec_a[12]=32'hFFFFFFFF;  vec_b[12]=32'hFFFFFFFF;  vec_f[12]=3'b011;
    vec_a[13]=32'h80000000;  vec_b[13]=32'h80000000;  vec_f[13]=3'b011;
    vec_a[14]=32'h00010000;  vec_b[14]=32'h00010000;  vec_f[14]=3'b011;
    vec_a[15]=32'h89ABCDEF;  vec_b[15]=32'h01234567;  vec_f[15]=3'b011;

    for (i = 16; i < 32; i = i + 1) begin
        vec_a[i] = $random;
        vec_b[i] = $random;
        vec_f[i] = i[1:0];
    end
end

task run_one;
    input [31:0] rs1_in;
    input [31:0] rs2_in;
    input [2:0]  funct3;
    begin
        @(negedge clk);
        pcpi_valid = 1'b1;
        pcpi_insn  = make_mul_insn(funct3);
        pcpi_rs1   = rs1_in;
        pcpi_rs2   = rs2_in;

        latency = 0;
        timeout_ctr = 2000;
        while (!pcpi_ready && timeout_ctr > 0) begin
            @(posedge clk);
            latency = latency + 1;
            if (pcpi_wait)
                wait_cycle_sum = wait_cycle_sum + 1;
            timeout_ctr = timeout_ctr - 1;
        end

        if (timeout_ctr == 0) begin
            $display("FAIL: timeout waiting for ready");
            fail_count = fail_count + 1;
        end else begin
            exp = expected_result(rs1_in, rs2_in, funct3);
            if (pcpi_rd !== exp) begin
                $display("FAIL: funct3=%b rs1=%h rs2=%h got=%h exp=%h", funct3, rs1_in, rs2_in, pcpi_rd, exp);
                fail_count = fail_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end
            op_count = op_count + 1;
            latency_sum = latency_sum + latency;
        end

        @(negedge clk);
        pcpi_valid = 1'b0;
        pcpi_insn  = 32'b0;
        pcpi_rs1   = 32'b0;
        pcpi_rs2   = 32'b0;

        @(posedge clk);
    end
endtask

real avg_lat;
real avg_wait;

initial begin
    pcpi_valid = 0;
    pcpi_insn  = 0;
    pcpi_rs1   = 0;
    pcpi_rs2   = 0;

    pass_count = 0;
    fail_count = 0;
    op_count = 0;
    latency_sum = 0;
    wait_cycle_sum = 0;

    repeat (4) @(posedge clk);
    resetn = 1;
    repeat (2) @(posedge clk);

    if (`BASELINE_CONFIG == 0)
        $display("BASELINE_CONFIG=0 (iterative mul)");
    else
        $display("BASELINE_CONFIG=1 (fast_mul)");

    for (i = 0; i < 32; i = i + 1)
        run_one(vec_a[i], vec_b[i], vec_f[i]);

    avg_lat = (op_count > 0) ? (latency_sum * 1.0 / op_count) : 0.0;
    avg_wait = (op_count > 0) ? (wait_cycle_sum * 1.0 / op_count) : 0.0;

    $display("RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("Average latency: %0d cycles", (op_count > 0) ? (latency_sum / op_count) : 0);
    $display("METRIC op_count %0d", op_count);
    $display("METRIC latency_sum %0d", latency_sum);
    $display("METRIC wait_cycle_sum %0d", wait_cycle_sum);
    $display("METRIC avg_latency %0f", avg_lat);
    $display("METRIC avg_wait_cycles %0f", avg_wait);

    if (fail_count == 0)
        $display("STATUS: ALL PASS");
    else
        $display("STATUS: FAILURES DETECTED");

    $finish;
end

endmodule
