module vedic_mul_16x16_ref (
    input  wire        clk,
    input  wire [15:0] A,
    input  wire [15:0] B,
    output wire [31:0] P
);

reg [15:0] A_r;
reg [15:0] B_r;

always @(posedge clk) begin
    A_r <= A;
    B_r <= B;
end

assign P = {16'b0, A_r} * {16'b0, B_r};

endmodule
