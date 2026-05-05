`timescale 1ns/1ps

module pcpi_vedic_mul (
    input  wire        clk,
    input  wire        resetn,
    input  wire        pcpi_valid,
    input  wire [31:0] pcpi_insn,
    input  wire [31:0] pcpi_rs1,
    input  wire [31:0] pcpi_rs2,
    output reg         pcpi_wr,
    output reg  [31:0] pcpi_rd,
    output reg         pcpi_wait,
    output reg         pcpi_ready
);

wire opcode_match;
wire funct7_match;
wire [2:0] funct3;
wire dec_mul;
wire dec_mulh;
wire dec_mulhsu;
wire dec_mulhu;
wire dec_any_mul;
wire op_a_signed;
wire op_b_signed;
wire sign_a_w;
wire sign_b_w;
wire result_neg_w;
wire [31:0] rs1_neg_w;
wire [31:0] rs2_neg_w;
wire        rs1_neg_cout_unused;
wire        rs2_neg_cout_unused;
wire [31:0] a_abs_w;
wire [31:0] b_abs_w;

assign opcode_match = (pcpi_insn[6:0] == 7'b0110011);
assign funct7_match = (pcpi_insn[31:25] == 7'b0000001);
assign funct3 = pcpi_insn[14:12];

assign dec_mul    = opcode_match && funct7_match && (funct3 == 3'b000);
assign dec_mulh   = opcode_match && funct7_match && (funct3 == 3'b001);
assign dec_mulhsu = opcode_match && funct7_match && (funct3 == 3'b010);
assign dec_mulhu  = opcode_match && funct7_match && (funct3 == 3'b011);
assign dec_any_mul = dec_mul || dec_mulh || dec_mulhsu || dec_mulhu;

assign op_a_signed = dec_mul || dec_mulh || dec_mulhsu;
assign op_b_signed = dec_mul || dec_mulh;
assign sign_a_w = op_a_signed && pcpi_rs1[31];
assign sign_b_w = op_b_signed && pcpi_rs2[31];
assign result_neg_w = sign_a_w ^ sign_b_w;

ksa_adder #(.WIDTH(32)) u_rs1_twos (
    .A(~pcpi_rs1),
    .B(32'b0),
    .Cin(1'b1),
    .Sum(rs1_neg_w),
    .Cout(rs1_neg_cout_unused)
);

ksa_adder #(.WIDTH(32)) u_rs2_twos (
    .A(~pcpi_rs2),
    .B(32'b0),
    .Cin(1'b1),
    .Sum(rs2_neg_w),
    .Cout(rs2_neg_cout_unused)
);

assign a_abs_w = sign_a_w ? rs1_neg_w : pcpi_rs1;
assign b_abs_w = sign_b_w ? rs2_neg_w : pcpi_rs2;

/* verilator lint_off UNUSED */
wire [14:0] unused_insn_fields = {pcpi_insn[24:15], pcpi_insn[11:7]};
/* verilator lint_on UNUSED */

reg        busy;
reg [2:0]  stage;
reg [31:0] a_abs_r;
reg [31:0] b_abs_r;
reg [63:0] unsigned_product_r;
reg        sel_high_r;
reg        result_neg_r;

wire [63:0] unsigned_prod_w;
wire [63:0] unsigned_prod_neg_w;
wire [63:0] signed_prod_w;
wire        unsigned_prod_neg_cout_unused;

vedic_mul_32x32 #(.WIDTH(32)) u_mul_abs (
    .clk(clk),
    .A(a_abs_r),
    .B(b_abs_r),
    .P(unsigned_prod_w)
);

ksa_adder #(.WIDTH(64)) u_unsigned_prod_twos (
    .A(~unsigned_product_r),
    .B(64'b0),
    .Cin(1'b1),
    .Sum(unsigned_prod_neg_w),
    .Cout(unsigned_prod_neg_cout_unused)
);

assign signed_prod_w = result_neg_r ? unsigned_prod_neg_w : unsigned_product_r;

always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        busy      <= 1'b0;
        stage     <= 3'd0;
        a_abs_r   <= 32'd0;
        b_abs_r   <= 32'd0;
        unsigned_product_r <= 64'd0;
        sel_high_r <= 1'b0;
        result_neg_r <= 1'b0;

        pcpi_wr    <= 1'b0;
        pcpi_rd    <= 32'd0;
        pcpi_wait  <= 1'b0;
        pcpi_ready <= 1'b0;
    end else begin
        pcpi_wr    <= 1'b0;
        pcpi_ready <= 1'b0;
        pcpi_wait  <= busy;

        if (!busy) begin
            if (pcpi_valid && dec_any_mul) begin
                busy       <= 1'b1;
                stage      <= 3'd0;
                a_abs_r    <= a_abs_w;
                b_abs_r    <= b_abs_w;
                sel_high_r <= dec_mulh || dec_mulhsu || dec_mulhu;
                result_neg_r <= result_neg_w;
                pcpi_wait  <= 1'b1;
            end
        end else begin
            case (stage)
                3'd0: begin
                    // Wait for the 16x16 CSA L1 register stage.
                    stage <= 3'd1;
                end
                3'd1: begin
                    // Wait for the 32x32 partial-product register stage.
                    stage <= 3'd2;
                end
                3'd2: begin
                    // Wait for the first CSA reduction register stage.
                    stage <= 3'd3;
                end
                3'd3: begin
                    // Wait for the KSA mid-stage register.
                    stage <= 3'd4;
                end
                3'd4: begin
                    // Capture pipelined unsigned 32x32 Vedic product.
                    unsigned_product_r <= unsigned_prod_w;
                    stage <= 3'd5;
                end
                3'd5: begin
                    pcpi_wr    <= 1'b1;
                    pcpi_ready <= 1'b1;
                    pcpi_rd    <= sel_high_r ? signed_prod_w[63:32] : signed_prod_w[31:0];
                    pcpi_wait  <= 1'b0;
                    busy       <= 1'b0;
                    stage      <= 3'd0;
                end
                default: begin
                    stage <= 3'd0;
                end
            endcase
        end
    end
end

endmodule
