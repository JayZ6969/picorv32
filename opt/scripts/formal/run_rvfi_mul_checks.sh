#!/usr/bin/env bash
# Sync project picorv32.v into riscv-formal and run RVFI checks for MUL/MULH/MULHSU/MULHU.
# Run from repository root (directory containing picorv32.v and opt/).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

CORE_DIR="opt/riscv-formal/cores/picorv32"
CHK_DIR="${CORE_DIR}/checks"

if [[ ! -f picorv32.v ]]; then
  echo "error: picorv32.v not found in ${ROOT}" >&2
  exit 1
fi
if [[ ! -d "$CORE_DIR" ]]; then
  echo "error: ${CORE_DIR} missing (vendored riscv-formal tree)" >&2
  exit 1
fi

mkdir -p opt/formal/rvfi/logs

echo "== Copy picorv32.v -> ${CORE_DIR}/picorv32.v"
cp -f picorv32.v "${CORE_DIR}/picorv32.v"

echo "== genchecks.py (checks.cfg → checks/*.sby + makefile)"
(
  cd "$CORE_DIR"
  python3 ../../checks/genchecks.py
)

echo "== RVFI MUL family (insn_*_ch0)"
RVFI_MUL_JOBS="${RVFI_MUL_JOBS:-$(nproc)}"
make -C "$CHK_DIR" \
  insn_mul_ch0 insn_mulh_ch0 insn_mulhsu_ch0 insn_mulhu_ch0 \
  -j"${RVFI_MUL_JOBS}" 2>&1 | tee opt/formal/rvfi/logs/mul_rvfi.log

echo "== Done. Log: opt/formal/rvfi/logs/mul_rvfi.log (set RVFI_MUL_JOBS=1 if four parallel Z3 jobs overload RAM/CPU)"
