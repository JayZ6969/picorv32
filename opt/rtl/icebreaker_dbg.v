/*
 * icebreaker_dbg.v — iCESugar v1.5 top-level with PCPI debug pins
 *
 * Adapted for the MuseLab iCESugar v1.5 board (iCELink/DAPLink programmer).
 * Pin mapping from official repo: https://github.com/wuxx/icesugar
 *
 * LEDs: Regular GPIO (NOT SB_RGBA_DRV)
 *   - ledr_n (pin 41), ledg_n (pin 40): onboard, active-low
 *   - led1-led5 (pins 27,25,21,23,26): on PMOD 3 connector
 *
 * Debug pin mapping (PMOD 2):
 *   dbg[0] = pcpi_valid  (pin 46, trigger for logic analyser)
 *   dbg[1] = pcpi_ready  (pin 44)
 *   dbg[2] = pcpi_wait   (pin 42)
 *   dbg[3] = pcpi_wr     (pin 37)
 *   dbg[4] = funct3[1]   (pin 36)
 *   dbg[5] = funct3[0]   (pin 38)
 */

module icebreaker_dbg (
    input  wire clk,

    output wire ser_tx,
    input  wire ser_rx,

    /* Onboard LEDs */
    output wire led1, led2, led3, led4, led5,
    output wire ledr_n, ledg_n,

    /* SPI Flash */
    output wire flash_csb,
    output wire flash_clk,
    inout  wire flash_io0,
    inout  wire flash_io1,
    inout  wire flash_io2,
    inout  wire flash_io3,

    /* Debug header — 6 PCPI observation pins */
    output wire [5:0] dbg
);
    parameter integer MEM_WORDS = 32768;

    /* ── Reset sequencer ── */
    reg [5:0] reset_cnt = 0;
    wire resetn = &reset_cnt;
    always @(posedge clk)
        reset_cnt <= reset_cnt + !resetn;

    /* ── LED GPIO ── */
    wire [7:0] leds;
    assign led1   =  leds[1];
    assign led2   =  leds[2];
    assign led3   =  leds[3];
    assign led4   =  leds[4];
    assign led5   =  leds[5];
    assign ledr_n = !leds[6];
    assign ledg_n = !leds[7];

    /* ── SPI flash IO buffers ── */
    wire flash_io0_oe, flash_io0_do, flash_io0_di;
    wire flash_io1_oe, flash_io1_do, flash_io1_di;
    wire flash_io2_oe, flash_io2_do, flash_io2_di;
    wire flash_io3_oe, flash_io3_do, flash_io3_di;

    SB_IO #(.PIN_TYPE(6'b1010_01), .PULLUP(1'b0)) flash_io_buf [3:0] (
        .PACKAGE_PIN  ({flash_io3,    flash_io2,    flash_io1,    flash_io0}),
        .OUTPUT_ENABLE({flash_io3_oe, flash_io2_oe, flash_io1_oe, flash_io0_oe}),
        .D_OUT_0      ({flash_io3_do, flash_io2_do, flash_io1_do, flash_io0_do}),
        .D_IN_0       ({flash_io3_di, flash_io2_di, flash_io1_di, flash_io0_di})
    );

    /* ── IO memory (GPIO) ── */
    wire        iomem_valid;
    reg         iomem_ready;
    wire [ 3:0] iomem_wstrb;
    wire [31:0] iomem_addr;
    wire [31:0] iomem_wdata;
    reg  [31:0] iomem_rdata;

    reg [31:0] gpio;
    assign leds = gpio;

    always @(posedge clk) begin
        if (!resetn) begin
            gpio <= 0;
        end else begin
            iomem_ready <= 0;
            if (iomem_valid && !iomem_ready && iomem_addr[31:24] == 8'h03) begin
                iomem_ready <= 1;
                iomem_rdata <= gpio;
                if (iomem_wstrb[0]) gpio[ 7: 0] <= iomem_wdata[ 7: 0];
                if (iomem_wstrb[1]) gpio[15: 8] <= iomem_wdata[15: 8];
                if (iomem_wstrb[2]) gpio[23:16] <= iomem_wdata[23:16];
                if (iomem_wstrb[3]) gpio[31:24] <= iomem_wdata[31:24];
            end
        end
    end

    /* ── PCPI debug wires ── */
    wire dbg_pcpi_valid;
    wire dbg_pcpi_ready;
    wire dbg_pcpi_wait;
    wire dbg_pcpi_wr;
    wire dbg_funct3_1;
    wire dbg_funct3_0;

    assign dbg[0] = dbg_pcpi_valid;
    assign dbg[1] = dbg_pcpi_ready;
    assign dbg[2] = dbg_pcpi_wait;
    assign dbg[3] = dbg_pcpi_wr;
    assign dbg[4] = dbg_funct3_1;
    assign dbg[5] = dbg_funct3_0;

    /* ── Debug PicoSoC ── */
    picosoc_dbg #(.MEM_WORDS(MEM_WORDS)) soc (
        .clk           (clk),
        .resetn        (resetn),

        .iomem_valid   (iomem_valid),
        .iomem_ready   (iomem_ready),
        .iomem_wstrb   (iomem_wstrb),
        .iomem_addr    (iomem_addr),
        .iomem_wdata   (iomem_wdata),
        .iomem_rdata   (iomem_rdata),

        .irq_5         (1'b0),
        .irq_6         (1'b0),
        .irq_7         (1'b0),

        .ser_tx        (ser_tx),
        .ser_rx        (ser_rx),

        .flash_csb     (flash_csb),
        .flash_clk     (flash_clk),
        .flash_io0_oe  (flash_io0_oe),
        .flash_io1_oe  (flash_io1_oe),
        .flash_io2_oe  (flash_io2_oe),
        .flash_io3_oe  (flash_io3_oe),
        .flash_io0_do  (flash_io0_do),
        .flash_io1_do  (flash_io1_do),
        .flash_io2_do  (flash_io2_do),
        .flash_io3_do  (flash_io3_do),
        .flash_io0_di  (flash_io0_di),
        .flash_io1_di  (flash_io1_di),
        .flash_io2_di  (flash_io2_di),
        .flash_io3_di  (flash_io3_di),

        .dbg_pcpi_valid(dbg_pcpi_valid),
        .dbg_pcpi_ready(dbg_pcpi_ready),
        .dbg_pcpi_wait (dbg_pcpi_wait),
        .dbg_pcpi_wr   (dbg_pcpi_wr),
        .dbg_funct3_1  (dbg_funct3_1),
        .dbg_funct3_0  (dbg_funct3_0)
    );

endmodule
