#!/usr/bin/env bash
# build_firmware.sh — Stage 7+8 firmware build script
# Produces:
#   opt/firmware/hw/mul_test_hw.{elf,bin}   ← Stage 7 functional + cycle test
#   opt/firmware/hw/mul_loop_hw.{elf,bin}   ← Stage 8 LA capture loop
#
# Run from the repo root (picorv32/) or from opt/:
#   bash opt/scripts/hw/build_firmware.sh
#
# Requirements:
#   riscv32-unknown-elf-gcc   (or riscv64-unknown-elf-gcc with -m32)
#   riscv32-unknown-elf-objcopy

set -euo pipefail

# ── Locate repo root ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Script lives at opt/scripts/hw/ → root is two levels up from opt/
OPT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT_DIR="$(cd "${OPT_DIR}/.." && pwd)"

FW_DIR="${OPT_DIR}/firmware/hw"
PICOSOC_DIR="${ROOT_DIR}/picosoc"
LDS="${PICOSOC_DIR}/icebreaker_sections.lds"
STARTUP="${PICOSOC_DIR}/start.s"

# ── Toolchain detection ───────────────────────────────────────────────────────
if command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
    GCC="riscv32-unknown-elf-gcc"
    OBJCOPY="riscv32-unknown-elf-objcopy"
elif command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
    GCC="riscv64-unknown-elf-gcc"
    OBJCOPY="riscv64-unknown-elf-objcopy"
else
    echo "ERROR: No RISC-V GCC toolchain found in PATH."
    echo "  Install riscv32-unknown-elf-gcc or riscv64-unknown-elf-gcc."
    exit 1
fi

echo "── Toolchain: ${GCC}"
echo "── Firmware source: ${FW_DIR}"
echo "── Linker script:   ${LDS}"
echo "── Startup:         ${STARTUP}"
echo ""

# ── Common compile flags ──────────────────────────────────────────────────────
CFLAGS=(
    -march=rv32im
    -mabi=ilp32
    -Os
    -ffreestanding
    -nostdlib
    -ffunction-sections
    -fdata-sections
    -Wall
    -I"${FW_DIR}"
    -DICEBREAKER
    -T"${LDS}"
)

# ── Build helper ──────────────────────────────────────────────────────────────
build_fw() {
    local NAME="$1"
    local MAIN="$2"
    local ELF="${FW_DIR}/${NAME}.elf"
    local BIN="${FW_DIR}/${NAME}.bin"

    echo "── Building ${NAME} ──"
    "${GCC}" "${CFLAGS[@]}" \
        "${STARTUP}" \
        "${FW_DIR}/uart.c" \
        "${MAIN}" \
        -o "${ELF}"

    "${OBJCOPY}" -O binary "${ELF}" "${BIN}"

    local SIZE
    SIZE="$(stat -c%s "${BIN}")"
    echo "   ELF: ${ELF}"
    echo "   BIN: ${BIN}  (${SIZE} bytes)"

    # Sanity: firmware must be > 0 and < 4 MiB flash
    if [[ "${SIZE}" -eq 0 || "${SIZE}" -gt $((4 * 1024 * 1024)) ]]; then
        echo " ❌ Binary size looks wrong: ${SIZE} bytes"
        exit 1
    fi
    echo " ✅ ${NAME} built OK (${SIZE} bytes)"
    echo ""
}

# ── Build both firmware images ────────────────────────────────────────────────
build_fw "mul_test_hw"  "${FW_DIR}/mul_test_hw.c"
build_fw "mul_loop_hw"  "${FW_DIR}/mul_loop_hw.c"

echo "══════════════════════════════════════════"
echo "  All firmware built successfully."
echo ""
echo "  Next steps:"
echo "  1. Flash mul_test_hw:  bash opt/scripts/hw/flash_firmware.sh opt/firmware/hw/mul_test_hw.bin"
echo "  2. Capture UART:       python3 opt/scripts/hw/capture_uart.py optimized"
echo "  3. For Stage 8 LA:"
echo "     bash opt/scripts/hw/build_debug_bitstream.sh"
echo "     bash opt/scripts/hw/flash_firmware.sh opt/firmware/hw/mul_loop_hw.bin"
echo "══════════════════════════════════════════"
