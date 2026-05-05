#!/usr/bin/env bash
# F4 arithmetic equivalence: run_smtbmc on arithmetic_formal (Vedic PCPI vs reference).
# Default: four runs with fixed funct3 (-D ARITH_FUNCT3_*) — much faster than one job
# with anyconst funct3 on Z3. Override: F4_LEGACY_COMBINED=1 for the old single proof.
#
# Env: F4_SMTBMC_DEPTH (default 10), F4_LEGACY_COMBINED (default 0), SMT_SOLVER (default z3).
# F4_SKIP_MUL_LEG=1 — skip the MUL (funct3=000) leg only; induction there is often much
#   slower than mulh/mulhsu/mulhu. Touches MUL_LEG_WAIVED for the Phase 4 report note.
# Run from repository root.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

DEPTH="${F4_SMTBMC_DEPTH:-10}"
PASS_DIR="opt/formal/equiv/arithmetic_formal"
mkdir -p "$PASS_DIR" opt/formal/equiv/logs
rm -f "${PASS_DIR}/MUL_LEG_WAIVED"

FILES=(
  opt/rtl/vedic/vedic_mul_2x2.v
  opt/rtl/vedic/vedic_mul_4x4.v
  opt/rtl/vedic/vedic_mul_8x8.v
  opt/rtl/vedic/vedic_mul_16x16.v
  opt/rtl/vedic/vedic_mul_32x32.v
  opt/rtl/ksa/ksa_adder.v
  opt/rtl/ksa/ksa_64bit_pipelined.v
  opt/rtl/csa/csa_cell.v
  opt/rtl/pcpi/pcpi_vedic_mul.v
  opt/formal/equiv/arithmetic_formal.sv
)

if [[ "${F4_LEGACY_COMBINED:-0}" == "1" ]]; then
  echo "=== F4 arithmetic (legacy: single anyconst funct3, depth=${DEPTH}) @ $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  bash opt/scripts/formal/run_smtbmc.sh arithmetic_equiv arithmetic_formal "$DEPTH" "${FILES[@]}"
else
  echo "=== F4 arithmetic (4× fixed funct3, depth=${DEPTH} per leg) @ $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  for leg in \
    "ARITH_FUNCT3_MUL:mul" \
    "ARITH_FUNCT3_MULH:mulh" \
    "ARITH_FUNCT3_MULHSU:mulhsu" \
    "ARITH_FUNCT3_MULHU:mulhu"; do
    def="${leg%%:*}"
    sfx="${leg##*:}"
    if [[ "${F4_SKIP_MUL_LEG:-0}" == "1" && "$sfx" == "mul" ]]; then
      echo ""
      echo "--- F4 leg mul SKIPPED (F4_SKIP_MUL_LEG=1 — MUL induction is often very slow) ---"
      touch "${PASS_DIR}/MUL_LEG_WAIVED"
      continue
    fi
    echo ""
    echo "--- F4 leg ${sfx} (-D${def}) @ $(date -u '+%Y-%m-%dT%H:%M:%SZ') ---"
    FORMAL_VERILOG_DEFINES="-D${def}" \
      bash opt/scripts/formal/run_smtbmc.sh "arithmetic_${sfx}" arithmetic_formal "$DEPTH" "${FILES[@]}"
  done
fi

touch "${PASS_DIR}/PASS"
echo ""
echo "== F4 complete → ${PASS_DIR}/PASS"
