#!/usr/bin/env bash
# Phase 5 — fast verification gate (no multi-hour formal).
# Run from repo root: bash opt/scripts/phase5_gate.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OPT="$ROOT/opt"
REPORT="$OPT/synth/reports/phase5_gate.txt"
mkdir -p "$OPT/synth/reports" "$OPT/sim/logs"

cd "$OPT"
{
  echo "Phase 5 gate — $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "repo: $ROOT"
  echo ""

  echo "== lint_pcpi (Verilator) =="
  make -s lint_pcpi 2>&1 | tail -n 20
  echo ""

  echo "== sim_vedic_quick =="
  make -s sim_vedic_quick VVP_PLUSARGS=+quick 2>&1 | tail -n 15
  echo ""

  echo "== sim_pcpi (PCPI_DEFAULT_PLUSARGS: rand_groups=32; first +rand wins in Verilog) =="
  make -s sim_pcpi PCPI_DEFAULT_PLUSARGS='+rand_groups=32 +stress20 +reset_midop' 2>&1 | tail -n 25
  echo ""

  echo "== Phase 4 fast formal (F1+F2 small; F3/F4/F5 skipped) =="
  export PHASE4_FAST=1 SBY_LIVE=0
  bash scripts/formal/complete_phase4.sh 2>&1 | tail -n 35
} | tee "$REPORT"

echo ""
echo "Wrote $REPORT"
