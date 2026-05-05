#include <stdint.h>

#define UART_DATA   (*(volatile uint32_t*)0x02000008)
#define UART_DIV    (*(volatile uint32_t*)0x02000004)
#define UART_TX     (*(volatile uint32_t*)0x02000000)

static void uart_wait_tx(void) {
    while (UART_TX & 0x1) { /* busy‑wait */ }
}

void uart_init(uint32_t baud) {
    UART_DIV = baud;
}

void uart_putc(char c) {
    UART_TX = c;
    uart_wait_tx();
}

void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}
