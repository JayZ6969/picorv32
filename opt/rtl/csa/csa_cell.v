`timescale 1ns/1ps

module csa_cell #(
    parameter integer WIDTH = 64
) (
    input  wire [WIDTH-1:0] X,
    input  wire [WIDTH-1:0] Y,
    input  wire [WIDTH-1:0] Z,
    output wire [WIDTH-1:0] SUM,
    output wire [WIDTH-1:0] CARRY
);

assign SUM = X ^ Y ^ Z;

generate
    if (WIDTH > 1) begin : gen_carry
        wire [WIDTH-2:0] carry_raw;
        assign carry_raw = (X[WIDTH-2:0] & Y[WIDTH-2:0]) |
                           (X[WIDTH-2:0] & Z[WIDTH-2:0]) |
                           (Y[WIDTH-2:0] & Z[WIDTH-2:0]);
        assign CARRY = {carry_raw, 1'b0};
    end else begin : gen_carry_w1
        assign CARRY = 1'b0;
    end
endgenerate

endmodule
