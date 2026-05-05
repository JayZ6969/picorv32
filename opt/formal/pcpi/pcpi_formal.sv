// opt/formal/pcpi/pcpi_formal.sv
// Formal property checker for PCPI wrapper protocol compliance.
// Proves the pcpi_vedic_mul module follows the PCPI contract for ALL inputs.

`timescale 1ns/1ps

module pcpi_formal (
    input wire clk,
    input wire resetn
);
    // ── Symbolic inputs ──
    (* anyseq *)   reg        pcpi_valid;
    (* anyconst *) reg [31:0] pcpi_insn;
    (* anyconst *) reg [31:0] pcpi_rs1;
    (* anyconst *) reg [31:0] pcpi_rs2;

    // ── DUT ──
    wire        pcpi_wr;
    wire [31:0] pcpi_rd;
    wire        pcpi_wait;
    wire        pcpi_ready;

    pcpi_vedic_mul dut (
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

    // ── Decode ──
    wire is_mul_insn = (pcpi_insn[6:0]   == 7'b0110011) &&
                       (pcpi_insn[31:25] == 7'b0000001) &&
                       (pcpi_insn[14:12] <= 3'b011);

    // ── Track reset state ──
    reg past_valid = 0;
    always @(posedge clk)
        past_valid <= 1;

    // ── Assumptions ──
    // A1: resetn is low on the first cycle, then stays high
    always @(posedge clk) begin
        if (past_valid)
            assume (resetn);
        else
            assume (!resetn);
    end

    // A2: pcpi_valid only asserted for mul instructions
    always @(*) begin
        if (pcpi_valid)
            assume (is_mul_insn);
    end

    // ── Properties to PROVE ──

    // P1: After reset, pcpi_ready and pcpi_wait are low
    always @(posedge clk) begin
        if (!resetn) begin
            P6_reset_clean_ready: assert (!pcpi_ready);
            P6_reset_clean_wait:  assert (!pcpi_wait);
        end
    end

    // P4: pcpi_wr is always high when pcpi_ready is high
    always @(posedge clk) begin
        if (past_valid && resetn) begin
            P4_wr_with_ready: assert (!pcpi_ready || pcpi_wr);
        end
    end

    // P5: pcpi_wait deasserts on the same cycle as pcpi_ready
    always @(posedge clk) begin
        if (past_valid && resetn) begin
            P5_wait_deassert: assert (!pcpi_ready || !pcpi_wait);
        end
    end

    // ── Cover ──
    // C1: A multiply can complete
    always @(posedge clk) begin
        C1_mul_completes: cover (pcpi_ready && pcpi_wr);
    end

endmodule
