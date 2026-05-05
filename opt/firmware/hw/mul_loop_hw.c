/*
 * mul_loop_hw.c — Stage 8 Logic Analyser capture firmware
 *
 * Runs MUL / MULH continuously so a logic analyser can capture
 * PCPI protocol waveforms without missing any events.
 *
 * A small delay loop between bursts creates visible gaps, making it
 * easy to identify individual transactions in the captured trace.
 *
 * Expected UART output on startup:
 *   LA_LOOP_START
 * (board then loops forever — reset to stop)
 *
 * Build together with mul_test_hw using build_firmware.sh.
 * Baud divisor: 104  (12 MHz / 104 ≈ 115384 baud ≈ 115200)
 */

#include "uart.h"
#include <stdint.h>

#define BAUD_DIVISOR  104U

/* Use distinct, non-trivial operands to avoid constant-folding */
static volatile uint32_t a = 0x12345678U;
static volatile uint32_t b = 0x9ABCDEF0U;
static volatile uint32_t ah = 0x76D457EDU;
static volatile uint32_t bh = 0x462DF78CU;

int main(void)
{
    uart_init(BAUD_DIVISOR);
    uart_puts("LA_LOOP_START\r\n");

    volatile uint32_t r;

    for (;;) {
        /* Burst: 4 MUL + 4 MULH — gives 8 PCPI transactions per burst */
        asm volatile ("mul  %0, %1, %2" : "=r"(r) : "r"(a),  "r"(b));
        asm volatile ("mul  %0, %1, %2" : "=r"(r) : "r"(ah), "r"(bh));
        asm volatile ("mulh %0, %1, %2" : "=r"(r) : "r"(a),  "r"(b));
        asm volatile ("mulh %0, %1, %2" : "=r"(r) : "r"(ah), "r"(bh));
        asm volatile ("mul  %0, %1, %2" : "=r"(r) : "r"(b),  "r"(ah));
        asm volatile ("mul  %0, %1, %2" : "=r"(r) : "r"(bh), "r"(a));
        asm volatile ("mulh %0, %1, %2" : "=r"(r) : "r"(b),  "r"(ah));
        asm volatile ("mulh %0, %1, %2" : "=r"(r) : "r"(bh), "r"(a));

        /* ~100-cycle inter-burst gap so LA can distinguish transactions */
        for (volatile int d = 0; d < 20; ++d) { /* ~5 cycles each */ }
    }
}
