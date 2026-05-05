`timescale 1ns/1ps

module ksa_adder #(
    parameter integer WIDTH = 32
) (
    input  wire [WIDTH-1:0] A,
    input  wire [WIDTH-1:0] B,
    input  wire             Cin,
    output wire [WIDTH-1:0] Sum,
    output wire             Cout
);

localparam integer STAGES = (WIDTH <= 1) ? 1 : $clog2(WIDTH);

wire [WIDTH-1:0] p_base;
/* verilator lint_off UNOPTFLAT */
wire [WIDTH-1:0] g_stage [0:STAGES];
wire [WIDTH-1:0] p_stage [0:STAGES];
/* verilator lint_on UNOPTFLAT */
wire [WIDTH:0]   carry;

genvar i;
generate
    for (i = 0; i < WIDTH; i = i + 1) begin : gen_pre
        assign p_base[i] = A[i] ^ B[i];
        assign g_stage[0][i] = A[i] & B[i];
        assign p_stage[0][i] = p_base[i];
    end
endgenerate

genvar s, j;
generate
    for (s = 0; s < STAGES; s = s + 1) begin : gen_stage
        localparam integer DIST = (1 << s);
        for (j = 0; j < WIDTH; j = j + 1) begin : gen_node
            if (j < DIST) begin
                assign g_stage[s+1][j] = g_stage[s][j];
                assign p_stage[s+1][j] = p_stage[s][j];
            end else begin
                assign g_stage[s+1][j] = g_stage[s][j] | (p_stage[s][j] & g_stage[s][j-DIST]);
                assign p_stage[s+1][j] = p_stage[s][j] & p_stage[s][j-DIST];
            end
        end
    end
endgenerate

assign carry[0] = Cin;

generate
    for (i = 0; i < WIDTH; i = i + 1) begin : gen_carry_sum
        assign carry[i+1] = g_stage[STAGES][i] | (p_stage[STAGES][i] & Cin);
        assign Sum[i] = p_base[i] ^ carry[i];
    end
endgenerate

assign Cout = carry[WIDTH];

endmodule
