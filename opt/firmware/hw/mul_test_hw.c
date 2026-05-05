#include "uart.h"
#include <stdint.h>

static const uint32_t A[] = {
    0x00000000, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF,
    0x12153524, 0x8484D609, 0xB2C28465, 0x06B97B0D,
    0x3B23F176, 0x76D457ED, 0x7CFDE9F9, 0xE2F784C5,
    0x72AFF7E5, 0x12345678
};

static const uint32_t B[] = {
    0xFFFFFFFF, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF,
    0xC0895E81, 0xB1F05663, 0x89375212, 0x46DF998D,
    0x1E8DCD3D, 0x462DF78C, 0xE33724C6, 0xD513D2AA,
    0xBBD27277, 0x9ABCDEF0
};

static const uint32_t EXP_MUL[] = {
    0x00000000, 0x00000001, 0x00000000, 0x00000001,
    0x5676FF24, 0xC0B5CB7B, 0x5EC8A91A, 0x4D068B29,
    0xB1EA071E, 0x1F9EC09C, 0x70C8FA96, 0x86E6C4D2,
    0x4D0A3573, 0x242D2080
};

static const uint32_t EXP_MULH[] = {
    0x00000000, 0x00000000, 0x40000000, 0x3FFFFFFF,
    0xFB8466BD, 0x25A714D0, 0x23D6E37C, 0x01DC9740,
    0x070EF881, 0x20936646, 0xF1F22900, 0x04DE2D2D,
    0xE174D9D0, 0xF36D0B94
};

int main(void) {
    uart_init(115200);
    uart_puts("HW_START\r\n");

    int fail = 0;
    uint32_t r;

    for (int i = 0; i < 14; ++i) {
        asm volatile("mul  %0, %1, %2" : "=r"(r) : "r"(A[i]), "r"(B[i]));
        if (r != EXP_MUL[i]) { fail++; }
    }

    for (int i = 0; i < 14; ++i) {
        asm volatile("mulh %0, %1, %2" : "=r"(r) : "r"(A[i]), "r"(B[i]));
        if (r != EXP_MULH[i]) { fail++; }
    }

    uart_puts(fail ? "HW_STATUS FAIL\r\n" : "HW_STATUS PASS\r\n");

    /* Measure cycles per MUL */
    uint32_t t0, t1;
    asm volatile("csrr %0, mcycle" : "=r"(t0));
    for (int i = 0; i < 14; ++i) {
        asm volatile("mul  %0, %1, %2" : "=r"(r) : "r"(A[i]), "r"(B[i]));
    }
    asm volatile("csrr %0, mcycle" : "=r"(t1));
    uint32_t avg = (t1 - t0) / 14;
    uart_puts("HW_CYCLES_PER_MUL ");
    char buf[12];
    int pos = 0;
    uint32_t v = avg;
    do { buf[pos++] = '0' + v % 10; v /= 10; } while (v);
    for (int i = pos-1; i >= 0; --i) uart_putc(buf[i]);
    uart_puts("\r\n");

    uart_puts("HW_DONE\r\n");
    while (1) {}
}
