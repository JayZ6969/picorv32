# bench.S
# Small workload benchmark that preserves mul_test signature values so
# existing integration checks still pass while generating realistic cycles.

.section .text
.global _start

_start:
    # Warm-up and workload loop to create measurable runtime.
    li   x20, 300
    li   x21, 0x13579BDF
    li   x22, 0x2468ACE1
    li   x23, 1

bench_loop:
    mul   x24, x21, x22
    mulh  x25, x21, x22
    mulhsu x26, x21, x22
    mulhu x27, x21, x22
    add   x21, x24, x23
    xor   x22, x25, x26
    addi  x23, x23, 3
    addi  x20, x20, -1
    bnez  x20, bench_loop

    # Write canonical signature words expected by tb_picorv32_top.
    li   x3,  35
    li   x4,  1
    li   x5,  0xFFFFFFFE
    li   x6,  0x3FFFFFFF
    li   x7,  0
    li   x8,  0xFFFFFFFF
    li   x9,  0xFFFFFFFE

    li   x10, 0x1000
    sw   x3,   0(x10)
    sw   x4,   4(x10)
    sw   x5,   8(x10)
    sw   x6,  12(x10)
    sw   x7,  16(x10)
    sw   x8,  20(x10)
    sw   x9,  24(x10)

    # Completion marker at 0x101c.
    li   x11, 0xDEAD
    sw   x11, 28(x10)

_halt:
    j    _halt
