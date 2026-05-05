#!/usr/bin/env bash
# Phase 4 formal — from repository root.
#
# PHASE4_QUICK (choose one):
#   unset / ""  — STANDARD (default): F1, F2 2×2–8×8, F3, F4, F5 MUL-only RVFI;
#                 skip Vedic 16×16 / 32×32; report --skip-large-vedic --with-rvfi
#   1           — MINIMAL: skips F4; F5 MUL-only only; --skip-slow --with-rvfi
#   0           — FULL: F4 + full F5 (make -C checks); skips F2 16×16 / 32×32 by default
#                 (they often exceed overnight). Opt-in: PHASE4_LARGE_VEDIC=1
#                 report: --skip-large-vedic --with-rvfi-full unless LARGE_VEDIC=1
#
# PHASE4_LARGE_VEDIC=1 — only with PHASE4_QUICK=0: run F2 vedic_16x16 + vedic_32x32.
#
# PHASE4_SKIP_F5=1 — skip RVFI (F5); report omits F5 rows (F1–F4 only).
#
# PHASE4_SKIP_F3=1 — skip F3 PCPI (run_smtbmc); report marks F3 waived.
#
# PHASE4_FAST=1 — smoke path: same as PHASE4_QUICK=1 + PHASE4_SKIP_F5=1 +
#   PHASE4_SKIP_F3=1 (F1 + small Vedic 2×2–8×8 only; minutes-scale).
#
# F4: set F4_SKIP_MUL_LEG=1 to skip only the MUL (×) funct3 leg (often slow on Z3
# induction); mulh / mulhsu / mulhu still run. Export in the shell before invoking.
#
# F5: minimal = opt/scripts/formal/run_rvfi_mul_checks.sh (four insn_mul* targets).
#     full    = opt/scripts/formal/run_rvfi_full_checks.sh (entire checks makefile).
# See opt/docs/P5_RVFI_Formal.md (checks.cfg [filter-checks] trims overnight-scale RVFI).
#
# Uses sby for small jobs; run_smtbmc for PCPI and F4 (SBY 0.64 smtbmc issues).
#
# Live output: run_smtbmc.sh streams yosys-smtbmc ## lines to stdout (tee). sby uses
# --live csv by default (property status). Set SBY_LIVE=0 to disable; FORMAL_YOSYS_QUIET=1
# / SMTBMC_NOPROGRESS=1 for quieter yosys/smtbmc (see run_smtbmc.sh header).
# SBY_JOBS (default: nproc): passed as sby -j for F1 / small Vedic. F5 full RVFI uses
# make -j via RVFI_FULL_JOBS; F5 MUL-only uses RVFI_MUL_JOBS (both default nproc).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

PHASE4_QUICK="${PHASE4_QUICK:-}"
PHASE4_LARGE_VEDIC="${PHASE4_LARGE_VEDIC:-}"
PHASE4_SKIP_F5="${PHASE4_SKIP_F5:-}"
PHASE4_SKIP_F3="${PHASE4_SKIP_F3:-}"

if [[ "${PHASE4_FAST:-}" == "1" ]]; then
  PHASE4_QUICK=1
  PHASE4_SKIP_F5=1
  PHASE4_SKIP_F3=1
fi

SBY_JOBS="${SBY_JOBS:-$(nproc)}"

SBY_LIVE_OPT=()
if [[ "${SBY_LIVE:-1}" != "0" ]]; then
  SBY_LIVE_OPT=(--live csv)
fi

mkdir -p opt/formal/ksa/logs opt/formal/vedic/logs opt/formal/pcpi/logs opt/formal/equiv/logs \
  opt/formal/rvfi/logs

echo "=== F1 KSA ==="
sby "${SBY_LIVE_OPT[@]}" -j"$SBY_JOBS" -f opt/formal/ksa/ksa_formal.sby 2>&1 | tee opt/formal/ksa/logs/ksa_formal.log

echo "=== F2 Vedic 2x2 4x4 8x8 ==="
for lvl in 2x2 4x4 8x8; do
  echo "-- vedic_${lvl} @ $(date -u '+%Y-%m-%dT%H:%M:%SZ') --"
  sby "${SBY_LIVE_OPT[@]}" -j"$SBY_JOBS" -f "opt/formal/vedic/vedic_${lvl}.sby" 2>&1 | tee "opt/formal/vedic/logs/vedic_${lvl}.log"
done

if [[ "$PHASE4_QUICK" == "0" && "$PHASE4_LARGE_VEDIC" == "1" ]]; then
  echo "=== F2 Vedic 16x16 (run_smtbmc; PHASE4_LARGE_VEDIC=1 — may exceed overnight) ==="
  bash opt/scripts/formal/run_smtbmc.sh vedic_16x16 vedic_16x16_formal 5 \
    opt/rtl/vedic/vedic_mul_2x2.v opt/rtl/vedic/vedic_mul_4x4.v \
    opt/rtl/vedic/vedic_mul_8x8.v opt/rtl/vedic/vedic_mul_16x16.v \
    opt/rtl/ksa/ksa_adder.v opt/rtl/csa/csa_cell.v \
    opt/formal/vedic/vedic_NxN_formal.sv \
    2>&1 | tee opt/formal/vedic/logs/vedic_16x16.log

  echo "=== F2 Vedic 32x32 (run_smtbmc; PHASE4_LARGE_VEDIC=1 — very long) ==="
  bash opt/scripts/formal/run_smtbmc.sh vedic_32x32 vedic_32x32_formal 8 \
    opt/rtl/vedic/vedic_mul_2x2.v opt/rtl/vedic/vedic_mul_4x4.v \
    opt/rtl/vedic/vedic_mul_8x8.v opt/rtl/vedic/vedic_mul_16x16.v \
    opt/rtl/vedic/vedic_mul_32x32.v opt/rtl/ksa/ksa_adder.v \
    opt/rtl/ksa/ksa_64bit_pipelined.v opt/rtl/csa/csa_cell.v \
    opt/formal/vedic/vedic_NxN_formal.sv \
    2>&1 | tee opt/formal/vedic/logs/vedic_32x32.log
elif [[ "$PHASE4_QUICK" == "0" ]]; then
  echo "=== F2 Vedic 16x16 / 32x32 — skipped (set PHASE4_LARGE_VEDIC=1 with PHASE4_QUICK=0 to run) ==="
else
  echo "=== F2 Vedic 16x16 / 32x32 — skipped (standard/minimal; with PHASE4_QUICK=0 set PHASE4_LARGE_VEDIC=1 to run) ==="
fi

if [[ "$PHASE4_SKIP_F3" == "1" ]]; then
  echo "=== F3 PCPI — skipped (PHASE4_SKIP_F3=1) @ $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
else
  echo "=== F3 PCPI (run_smtbmc) ==="
  bash opt/scripts/formal/run_smtbmc.sh pcpi_protocol pcpi_formal 12 \
    opt/rtl/vedic/vedic_mul_2x2.v opt/rtl/vedic/vedic_mul_4x4.v \
    opt/rtl/vedic/vedic_mul_8x8.v opt/rtl/vedic/vedic_mul_16x16.v \
    opt/rtl/vedic/vedic_mul_32x32.v opt/rtl/ksa/ksa_adder.v \
    opt/rtl/ksa/ksa_64bit_pipelined.v opt/rtl/csa/csa_cell.v \
    opt/rtl/pcpi/pcpi_vedic_mul.v opt/formal/pcpi/pcpi_formal.sv \
    2>&1 | tee opt/formal/pcpi/logs/pcpi_formal.log
fi

if [[ "$PHASE4_QUICK" != "1" ]]; then
  echo "=== F4 arithmetic equivalence (run_smtbmc) ==="
  bash opt/scripts/formal/run_arithmetic_formal_smtbmc.sh 2>&1 | tee opt/formal/equiv/logs/arithmetic_formal.log
else
  echo "=== F4 arithmetic — skipped (PHASE4_QUICK=1 minimal mode) ==="
fi

if [[ "$PHASE4_SKIP_F5" == "1" ]]; then
  echo "=== F5 RVFI — skipped (PHASE4_SKIP_F5=1) @ $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
elif [[ "$PHASE4_QUICK" == "0" ]]; then
  echo "=== F5 RVFI — full suite @ $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  bash opt/scripts/formal/run_rvfi_full_checks.sh
else
  echo "=== F5 RVFI — MUL instruction family only @ $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  bash opt/scripts/formal/run_rvfi_mul_checks.sh
fi

echo "=== Report ==="
report_args=()
if [[ "$PHASE4_QUICK" == "0" ]]; then
  [[ "$PHASE4_LARGE_VEDIC" == "1" ]] || report_args+=(--skip-large-vedic)
elif [[ "$PHASE4_QUICK" == "1" ]]; then
  report_args+=(--skip-slow)
else
  report_args+=(--skip-large-vedic)
fi
if [[ "$PHASE4_SKIP_F5" != "1" ]]; then
  if [[ "$PHASE4_QUICK" == "0" ]]; then
    report_args+=(--with-rvfi-full)
  else
    report_args+=(--with-rvfi)
  fi
fi
export PHASE4_QUICK PHASE4_LARGE_VEDIC PHASE4_SKIP_F5 PHASE4_SKIP_F3
python3 opt/scripts/formal/gen_formal_report.py "${report_args[@]}"
cat opt/formal/phase4_report.txt
