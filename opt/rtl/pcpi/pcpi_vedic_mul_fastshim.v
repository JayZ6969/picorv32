`timescale 1ns/1ps

// Baseline-B shim: keep the post-integration picorv32 interface unchanged while
// routing fast-mul requests to the original native fast multiplier.
module pcpi_vedic_mul (
    input         clk,
    input         resetn,
    input         pcpi_valid,
    input  [31:0] pcpi_insn,
    input  [31:0] pcpi_rs1,
    input  [31:0] pcpi_rs2,
    output        pcpi_wr,
    output [31:0] pcpi_rd,
    output        pcpi_wait,
    output        pcpi_ready
);

picorv32_pcpi_fast_mul u_fast_mul (
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

endmodule
