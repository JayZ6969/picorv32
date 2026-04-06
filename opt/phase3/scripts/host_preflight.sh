#!/usr/bin/env bash
set -euo pipefail

echo "== Host FPGA/ASIC Tool Preflight =="

TOOLS=(
  yosys
  nextpnr-ice40
  icepack
  icetime
  iceprog
  iverilog
  vvp
  riscv32-unknown-elf-gcc
  riscv32-unknown-elf-objcopy
  riscv32-unknown-elf-cpp
)

OPTIONAL_TOOLS=(
  yosys-config
  icesprog
  openFPGALoader
)

for t in "${TOOLS[@]}"; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "OK   $t -> $(command -v "$t")"
  else
    echo "MISS $t"
  fi
done

echo
for t in "${OPTIONAL_TOOLS[@]}"; do
  if command -v "$t" >/dev/null 2>&1; then
    echo "OK   $t -> $(command -v "$t")"
  else
    echo "MISS $t (optional / board-dependent)"
  fi
done

echo
echo "== USB devices (FPGA/programmer related) =="
lsusb | grep -Ei '1d50:602b|0403:6010|0403:6014|lattice|ice|ftdi|fpgalink' || true

echo
if command -v icesprog >/dev/null 2>&1; then
  echo "== iCESugar probe (icesprog -p) =="
  icesprog -p || true
fi

if command -v iceprog >/dev/null 2>&1; then
  echo "== iceprog flash ID probe (if FTDI programmer present) =="
  iceprog -t || true
fi

echo
echo "Preflight done."
