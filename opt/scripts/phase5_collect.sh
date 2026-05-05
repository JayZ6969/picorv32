#!/usr/bin/env bash
# Merge Phase 5 artifacts into one file for archiving / CI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OPT="$ROOT/opt"
OUT="$OPT/synth/reports/phase5_complete.txt"
mkdir -p "$OPT/synth/reports"
{
  echo "======== Phase 5 complete bundle $(date -u '+%Y-%m-%dT%H:%M:%SZ') ========"
  echo ""
  echo "--- phase5_measure.json ---"
  cat "$OPT/synth/reports/phase5_measure.json" 2>/dev/null || echo "(missing — run phase5_measure.sh)"
  echo ""
  echo "--- phase5_gate.txt (tail) ---"
  tail -n 200 "$OPT/synth/reports/phase5_gate.txt" 2>/dev/null || echo "(missing — run phase5_gate.sh)"
} >"$OUT"
echo "Wrote $OUT"
