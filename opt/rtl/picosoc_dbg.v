/*
 * picosoc_dbg.v — Extended PicoSoC with PCPI signals exposed as top-level outputs
 *
 * Identical to picosoc/picosoc.v except:
 *   - picorv32 is instantiated with PCPI enable
 *   - pcpi_valid, pcpi_ready, pcpi_wait, pcpi_wr, pcpi_insn[13:12] are driven
 *     out as top-level ports so they can be routed to PMOD debug pins.
 *
 * Used only for the Stage 8 debug bitstream — does NOT replace the production
 * icebreaker.v / picosoc.v.
 *
 * NOTE: This file must be read BEFORE picorv32.v in the synthesis flow.
 *       The `PICOSOC_V macro prevents re-inclusion.
 */

`define PICORV32_REGS picosoc_regs_dbg
`define PICOSOC_MEM   ice40up5k_spram
`define PICOSOC_V

module picosoc_dbg (
    input  wire        clk,
    input  wire        resetn,

    /* Standard PicoSoC I/O (same as picosoc.v) */
    output wire        iomem_valid,
    input  wire        iomem_ready,
    output wire [ 3:0] iomem_wstrb,
    output wire [31:0] iomem_addr,
    output wire [31:0] iomem_wdata,
    input  wire [31:0] iomem_rdata,

    input  wire        irq_5,
    input  wire        irq_6,
    input  wire        irq_7,

    output wire        ser_tx,
    input  wire        ser_rx,

    output wire        flash_csb,
    output wire        flash_clk,
    output wire        flash_io0_oe,
    output wire        flash_io1_oe,
    output wire        flash_io2_oe,
    output wire        flash_io3_oe,
    output wire        flash_io0_do,
    output wire        flash_io1_do,
    output wire        flash_io2_do,
    output wire        flash_io3_do,
    input  wire        flash_io0_di,
    input  wire        flash_io1_di,
    input  wire        flash_io2_di,
    input  wire        flash_io3_di,

    /* ── Debug outputs — PCPI protocol signals ── */
    output wire        dbg_pcpi_valid,   /* DBG[0] — trigger on rising edge  */
    output wire        dbg_pcpi_ready,   /* DBG[1]                           */
    output wire        dbg_pcpi_wait,    /* DBG[2]                           */
    output wire        dbg_pcpi_wr,      /* DBG[3]                           */
    output wire        dbg_funct3_1,     /* DBG[4] — pcpi_insn[13] funct3[1] */
    output wire        dbg_funct3_0      /* DBG[5] — pcpi_insn[12] funct3[0] */
);
    parameter integer MEM_WORDS    = 32768;
    parameter [31:0]  STACKADDR    = (4 * MEM_WORDS);
    parameter [31:0]  PROGADDR_RESET = 32'h0010_0000;
    parameter [31:0]  PROGADDR_IRQ   = 32'h0000_0000;

    /* IRQ vector */
    reg [31:0] irq;
    always @* begin
        irq = 32'b0;
        irq[5] = irq_5;
        irq[6] = irq_6;
        irq[7] = irq_7;
    end

    /* Memory bus */
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [ 3:0] mem_wstrb;
    wire [31:0] mem_rdata;

    /* SPI memory */
    wire        spimem_ready;
    wire [31:0] spimem_rdata;

    /* SRAM */
    reg         ram_ready;
    wire [31:0] ram_rdata;

    /* UART registers */
    wire        simpleuart_reg_div_sel = mem_valid && (mem_addr == 32'h0200_0004);
    wire [31:0] simpleuart_reg_div_do;
    wire        simpleuart_reg_dat_sel = mem_valid && (mem_addr == 32'h0200_0008);
    wire [31:0] simpleuart_reg_dat_do;
    wire        simpleuart_reg_dat_wait;

    /* SPI config register */
    wire        spimemio_cfgreg_sel = mem_valid && (mem_addr == 32'h0200_0000);
    wire [31:0] spimemio_cfgreg_do;

    /* IO memory */
    assign iomem_valid = mem_valid && (mem_addr[31:24] > 8'h01);
    assign iomem_wstrb = mem_wstrb;
    assign iomem_addr  = mem_addr;
    assign iomem_wdata = mem_wdata;

    assign mem_ready = (iomem_valid && iomem_ready)
                     || spimem_ready
                     || ram_ready
                     || spimemio_cfgreg_sel
                     || simpleuart_reg_div_sel
                     || (simpleuart_reg_dat_sel && !simpleuart_reg_dat_wait);

    assign mem_rdata = (iomem_valid && iomem_ready) ? iomem_rdata
                     : spimem_ready                 ? spimem_rdata
                     : ram_ready                    ? ram_rdata
                     : spimemio_cfgreg_sel          ? spimemio_cfgreg_do
                     : simpleuart_reg_div_sel        ? simpleuart_reg_div_do
                     : simpleuart_reg_dat_sel        ? simpleuart_reg_dat_do
                     :                                32'h0;

    /* ── PCPI wires ── */
    wire        pcpi_valid;
    wire [31:0] pcpi_insn;
    wire [31:0] pcpi_rs1;
    wire [31:0] pcpi_rs2;
    wire        pcpi_wr;
    wire [31:0] pcpi_rd;
    wire        pcpi_wait;
    wire        pcpi_ready;

    /* Route PCPI to debug outputs */
    assign dbg_pcpi_valid = pcpi_valid;
    assign dbg_pcpi_ready = pcpi_ready;
    assign dbg_pcpi_wait  = pcpi_wait;
    assign dbg_pcpi_wr    = pcpi_wr;
    assign dbg_funct3_1   = pcpi_insn[13];
    assign dbg_funct3_0   = pcpi_insn[12];

    /* ── PicoRV32 core — PCPI enabled but no co-processor attached ── */
    /* The built-in fast_mul PCPI co-processor is instantiated inside
       picorv32 when ENABLE_FAST_MUL=1; we just observe the signals.   */
    picorv32 #(
        .STACKADDR     (STACKADDR),
        .PROGADDR_RESET(PROGADDR_RESET),
        .PROGADDR_IRQ  (PROGADDR_IRQ),
        .BARREL_SHIFTER(0),
        .COMPRESSED_ISA(1),
        .ENABLE_COUNTERS(1),
        .ENABLE_MUL    (1),       /* Use Baseline A iterative mul, since Vedic is too large for SoC on UP5K */
        .ENABLE_FAST_MUL(0),      /* activates internal PCPI fast multiplier */
        .ENABLE_DIV    (0),
        .ENABLE_IRQ    (1),
        .ENABLE_IRQ_QREGS(0),
        .ENABLE_PCPI   (1)        /* expose PCPI port for observation */
    ) cpu (
        .clk          (clk),
        .resetn       (resetn),
        .mem_valid    (mem_valid),
        .mem_instr    (mem_instr),
        .mem_ready    (mem_ready),
        .mem_addr     (mem_addr),
        .mem_wdata    (mem_wdata),
        .mem_wstrb    (mem_wstrb),
        .mem_rdata    (mem_rdata),
        .irq          (irq),
        /* PCPI interface — driven by internal fast_mul */
        .pcpi_valid   (pcpi_valid),
        .pcpi_insn    (pcpi_insn),
        .pcpi_rs1     (pcpi_rs1),
        .pcpi_rs2     (pcpi_rs2),
        .pcpi_wr      (pcpi_wr),
        .pcpi_rd      (pcpi_rd),
        .pcpi_wait    (pcpi_wait),
        .pcpi_ready   (pcpi_ready)
    );

    /* ── SPI memory ── */
    spimemio spimemio (
        .clk    (clk),
        .resetn (resetn),
        .valid  (mem_valid && mem_addr >= 4*MEM_WORDS && mem_addr < 32'h0200_0000),
        .ready  (spimem_ready),
        .addr   (mem_addr[23:0]),
        .rdata  (spimem_rdata),
        .flash_csb    (flash_csb),
        .flash_clk    (flash_clk),
        .flash_io0_oe (flash_io0_oe),
        .flash_io1_oe (flash_io1_oe),
        .flash_io2_oe (flash_io2_oe),
        .flash_io3_oe (flash_io3_oe),
        .flash_io0_do (flash_io0_do),
        .flash_io1_do (flash_io1_do),
        .flash_io2_do (flash_io2_do),
        .flash_io3_do (flash_io3_do),
        .flash_io0_di (flash_io0_di),
        .flash_io1_di (flash_io1_di),
        .flash_io2_di (flash_io2_di),
        .flash_io3_di (flash_io3_di),
        .cfgreg_we(spimemio_cfgreg_sel ? mem_wstrb : 4'b0),
        .cfgreg_di(mem_wdata),
        .cfgreg_do(spimemio_cfgreg_do)
    );

    /* ── Simple UART ── */
    simpleuart simpleuart (
        .clk         (clk),
        .resetn      (resetn),
        .ser_tx      (ser_tx),
        .ser_rx      (ser_rx),
        .reg_div_we  (simpleuart_reg_div_sel ? mem_wstrb : 4'b0),
        .reg_div_di  (mem_wdata),
        .reg_div_do  (simpleuart_reg_div_do),
        .reg_dat_we  (simpleuart_reg_dat_sel ? mem_wstrb[0] : 1'b0),
        .reg_dat_re  (simpleuart_reg_dat_sel && !mem_wstrb),
        .reg_dat_di  (mem_wdata),
        .reg_dat_do  (simpleuart_reg_dat_do),
        .reg_dat_wait(simpleuart_reg_dat_wait)
    );

    /* ── SRAM ── */
    always @(posedge clk)
        ram_ready <= mem_valid && !mem_ready && mem_addr < 4*MEM_WORDS;

    `PICOSOC_MEM #(.WORDS(MEM_WORDS)) memory (
        .clk  (clk),
        .wen  ((mem_valid && !mem_ready && mem_addr < 4*MEM_WORDS) ? mem_wstrb : 4'b0),
        .addr (mem_addr[23:2]),
        .wdata(mem_wdata),
        .rdata(ram_rdata)
    );

endmodule

/* ── Register file stub (same as picosoc.v) ── */
module picosoc_regs_dbg (
    input  clk, wen,
    input  [5:0]  waddr, raddr1, raddr2,
    input  [31:0] wdata,
    output [31:0] rdata1, rdata2
);
    reg [31:0] regs [0:31];
    always @(posedge clk)
        if (wen) regs[waddr[4:0]] <= wdata;
    assign rdata1 = regs[raddr1[4:0]];
    assign rdata2 = regs[raddr2[4:0]];
endmodule
