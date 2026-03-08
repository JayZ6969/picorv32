// =============================================================================
// arith_bench.c — Arithmetic benchmark for PicoRV32 variant comparison
//
// Measures CPI (cycles-per-instruction) for ADD, SUB, and MUL workloads
// by hammering tight loops and reading the RISC-V mcycle CSR.
//
// Each variant (baseline / +KSA / +Vedic / +Both) is compiled and run
// separately; the cycle counts are printed via the simple UART stub.
//
// Build:
//   riscv32-unknown-elf-gcc -O2 -march=rv32im -mabi=ilp32 \
//       -nostdlib -T../firmware/sections.lds \
//       arith_bench.c ../firmware/start.S ../firmware/print.c \
//       -o arith_bench.elf
//   riscv32-unknown-elf-objcopy -O binary arith_bench.elf arith_bench.bin
//
// The testbench simulates until it sees a DONE marker written to address
// 0x10000000 (exit trap).
// =============================================================================

#include "../firmware/firmware.h"

// ── RISC-V CSR helpers ────────────────────────────────────────────────────────
static inline uint32_t rdcycle(void) {
    uint32_t cyc;
    asm volatile ("rdcycle %0" : "=r"(cyc));
    return cyc;
}

static inline uint32_t rdinstret(void) {
    uint32_t ret;
    asm volatile ("rdinstret %0" : "=r"(ret));
    return ret;
}

// ── Output via memory-mapped serial port (same address as firmware/print.c) ──
#define OUTPORT 0x10000000
static void print_uint32_hex(uint32_t v) {
    static const char hex[] = "0123456789ABCDEF";
    char buf[9];
    for (int i = 7; i >= 0; i--) {
        buf[i] = hex[v & 0xF];
        v >>= 4;
    }
    buf[8] = 0;
    for (int i = 0; i < 8; i++)
        print_chr(buf[i]);
}

// ── Benchmark parameters ───────────────────────────────────────────────────────
#define ITERS 2000   // iterations per test (each iteration = 8 ops of that type)

// ── Benchmark kernels — volatile to prevent DCE ───────────────────────────────

// ADD: accumulate into volatile to force real ADD instructions
static uint32_t bench_add(void) {
    volatile uint32_t acc = 0;
    uint32_t a = 0xDEAD_BEEF, b = 0x0101_0101;
    uint32_t t0 = rdcycle();
    for (int i = 0; i < ITERS; i++) {
        // 8 back-to-back dependent ADDs (tests carry-chain depth)
        acc += a; a += b;
        acc += a; a += b;
        acc += a; a += b;
        acc += a; a += b;
        acc += a; a += b;
        acc += a; a += b;
        acc += a; a += b;
        acc += a; a += b;
    }
    uint32_t t1 = rdcycle();
    // Prevent the compiler from discarding acc
    if (acc == 0xDEADBEEF) { volatile int dummy = 1; (void)dummy; }
    return t1 - t0;
}

// SUB: same kernel but with subtraction
static uint32_t bench_sub(void) {
    volatile uint32_t acc = 0xFFFF_FFFF;
    uint32_t a = 0xDEAD_BEEF, b = 0x0101_0101;
    uint32_t t0 = rdcycle();
    for (int i = 0; i < ITERS; i++) {
        acc -= a; a -= b;
        acc -= a; a -= b;
        acc -= a; a -= b;
        acc -= a; a -= b;
        acc -= a; a -= b;
        acc -= a; a -= b;
        acc -= a; a -= b;
        acc -= a; a -= b;
    }
    uint32_t t1 = rdcycle();
    if (acc == 0) { volatile int dummy = 1; (void)dummy; }
    return t1 - t0;
}

// MUL: requires M-extension (ENABLE_MUL or ENABLE_VEDIC_MUL)
static uint32_t bench_mul(void) {
    volatile uint32_t acc = 1;
    uint32_t a = 0x1234_5678, b = 0x9ABC_DEF0;
    uint32_t t0 = rdcycle();
    for (int i = 0; i < ITERS; i++) {
        acc *= a; a += b;
        acc *= a; a += b;
        acc *= a; a += b;
        acc *= a; a += b;
    }
    uint32_t t1 = rdcycle();
    if (acc == 0) { volatile int dummy = 1; (void)dummy; }
    return t1 - t0;
}

// MULH: upper 32 bits of 64-bit product
static uint32_t bench_mulh(void) {
    volatile uint32_t acc = 0;
    uint32_t a = 0xDEAD_BEEF, b = 0xCAFE_BABE;
    uint32_t t0 = rdcycle();
    for (int i = 0; i < ITERS; i++) {
        uint32_t h;
        asm volatile ("mulhu %0, %1, %2" : "=r"(h) : "r"(a), "r"(b));
        acc ^= h; a += b;
        asm volatile ("mulhu %0, %1, %2" : "=r"(h) : "r"(a), "r"(b));
        acc ^= h; a += b;
        asm volatile ("mulhu %0, %1, %2" : "=r"(h) : "r"(a), "r"(b));
        acc ^= h; a += b;
        asm volatile ("mulhu %0, %1, %2" : "=r"(h) : "r"(a), "r"(b));
        acc ^= h; a += b;
    }
    uint32_t t1 = rdcycle();
    if (acc == 0xDEADBEEF) { volatile int dummy = 1; (void)dummy; }
    return t1 - t0;
}

// ── Functional correctness self-test ─────────────────────────────────────────

static int selftest(void) {
    int errors = 0;

    // ADD
    volatile uint32_t r;
    r = (uint32_t)0xDEAD0000 + (uint32_t)0x0000BEEF;
    if (r != 0xDEADBEEF) errors++;

    // SUB
    r = (uint32_t)0xFFFF0000 - (uint32_t)0x00010000;
    if (r != 0xFFFE0000) errors++;

    // MUL (lower 32)
    r = (uint32_t)0x1234 * (uint32_t)0x5678;
    if (r != (0x1234 * 0x5678)) errors++;

    // MULH (upper 32 of signed)
    {
        int32_t a = -1234567, b = 7654321;
        int64_t prod = (int64_t)a * (int64_t)b;
        uint32_t hi;
        asm volatile ("mulh %0, %1, %2" : "=r"(hi) : "r"(a), "r"(b));
        if (hi != (uint32_t)(prod >> 32)) errors++;
    }

    // MULHU
    {
        uint32_t a = 0xFFFFFFFF, b = 0xFFFFFFFF;
        uint64_t prod = (uint64_t)a * (uint64_t)b;
        uint32_t hi;
        asm volatile ("mulhu %0, %1, %2" : "=r"(hi) : "r"(a), "r"(b));
        if (hi != (uint32_t)(prod >> 32)) errors++;
    }

    return errors;
}

// ── Entry point ──────────────────────────────────────────────────────────────

void main(void) {
    // Banner
    print_str("\n\n");
    print_str("============================================\n");
    print_str("  PicoRV32 Arithmetic Benchmark\n");
    print_str("  ITERS=");
    print_dec(ITERS);
    print_str("  OPS_PER_ITER=8\n");
    print_str("============================================\n");

    // Functional correctness
    int errs = selftest();
    if (errs == 0) {
        print_str("[SELF-TEST] PASS\n");
    } else {
        print_str("[SELF-TEST] FAIL  errors=");
        print_dec(errs);
        print_str("\n");
    }

    uint32_t total_ops = (uint32_t)ITERS * 8;

    // ── ADD ──
    {
        uint32_t cyc = bench_add();
        print_str("ADD  cycles="); print_uint32_hex(cyc);
        print_str("  ops="); print_dec(total_ops);
        // CPI × 100 (fixed-point)
        uint32_t cpi100 = (cyc * 100) / total_ops;
        print_str("  CPI*100="); print_dec(cpi100);
        print_str("\n");
    }

    // ── SUB ──
    {
        uint32_t cyc = bench_sub();
        print_str("SUB  cycles="); print_uint32_hex(cyc);
        print_str("  ops="); print_dec(total_ops);
        uint32_t cpi100 = (cyc * 100) / total_ops;
        print_str("  CPI*100="); print_dec(cpi100);
        print_str("\n");
    }

    // ── MUL ──
    {
        uint32_t cyc = bench_mul();
        print_str("MUL  cycles="); print_uint32_hex(cyc);
        print_str("  ops="); print_dec(total_ops / 2); // 4 muls per iteration
        uint32_t cpi100 = (cyc * 100) / (total_ops / 2);
        print_str("  CPI*100="); print_dec(cpi100);
        print_str("\n");
    }

    // ── MULHU ──
    {
        uint32_t cyc = bench_mulh();
        print_str("MULHU cycles="); print_uint32_hex(cyc);
        print_str("  ops="); print_dec(total_ops / 2);
        uint32_t cpi100 = (cyc * 100) / (total_ops / 2);
        print_str("  CPI*100="); print_dec(cpi100);
        print_str("\n");
    }

    print_str("============================================\n");
    print_str("  DONE\n");
    print_str("============================================\n");

    // Signal end-of-simulation to testbench (standard PicoRV32 convention)
    *(volatile uint32_t*)0x20000000 = 0x00000001;
}
