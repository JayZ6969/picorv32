# mul_test.S
# Tests MUL/MULH/MULHSU/MULHU and writes signature to 0x1000.

.section .text
.global _start

_start:
    # MUL tests
    li   x1,  5
    li   x2,  7
    mul  x3,  x1, x2

    li   x1,  -1
    li   x2,  -1
    mul  x4,  x1, x2

    li   x1,  0x7FFFFFFF
    li   x2,  2
    mul  x5,  x1, x2

    # MULH tests
    li   x1,  0x7FFFFFFF
    li   x2,  0x7FFFFFFF
    mulh x6,  x1, x2

    li   x1, -1
    li   x2, -1
    mulh x7,  x1, x2

    # MULHSU test
    li    x1, -1
    li    x2, -1
    mulhsu x8, x1, x2

    # MULHU test
    li   x1,  0xFFFFFFFF
    li   x2,  0xFFFFFFFF
    mulhu x9, x1, x2

    # Write signature words
    li   x10, 0x1000
    sw   x3,   0(x10)
    sw   x4,   4(x10)
    sw   x5,   8(x10)
    sw   x6,  12(x10)
    sw   x7,  16(x10)
    sw   x8,  20(x10)
    sw   x9,  24(x10)

    # Completion marker
    li   x11, 0xDEAD
    sw   x11, 28(x10)

_halt:
    j    _halt
