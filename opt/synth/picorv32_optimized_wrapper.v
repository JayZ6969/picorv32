`timescale 1ns/1ps

module picorv32_optimized_wrapper (
    input  wire        clk,
    input  wire        resetn,
    output wire        trap,
    output wire        mem_valid,
    output wire        mem_instr,
    output wire [7:0]  mem_addr_lo,
    output wire [7:0]  mem_wdata_lo,
    output wire [3:0]  mem_wstrb
);

wire [31:0] mem_rdata = 32'b0;
wire        mem_ready = 1'b1;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0]  mem_wstrb_int;

assign mem_addr_lo = mem_addr[7:0];
assign mem_wdata_lo = mem_wdata[7:0];
assign mem_wstrb = mem_wstrb_int;

picorv32 #(
    .ENABLE_COUNTERS(0),
    .ENABLE_COUNTERS64(0),
    .LATCHED_MEM_RDATA(1),
    .ENABLE_MUL(1),
    .ENABLE_FAST_MUL(1),
    .ENABLE_FAST_ADD(1),
    .BARREL_SHIFTER(0)
) u_core (
    .clk(clk),
    .resetn(resetn),
    .trap(trap),
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(mem_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb_int),
    .mem_rdata(mem_rdata),
    .irq(32'b0),
    .eoi(),
    .trace_valid(),
    .trace_data()
);

endmodule
