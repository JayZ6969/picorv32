#!/usr/bin/env bash
# Inner script: run full Phase 4, log to file, drop to shell when done (for Byobu).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
# Default: standard Phase 4 (skip large Vedic only; run F4). Use PHASE4_QUICK=0 for full.
export PHASE4_QUICK="${PHASE4_QUICK:-}"
mkdir -p opt/formal/logs
set +e
bash opt/scripts/formal/complete_phase4.sh 2>&1 | tee opt/formal/logs/phase4_byobu.log
ec="${PIPESTATUS[0]}"
set -e
echo ""
echo "=== complete_phase4.sh finished with exit code ${ec} ==="
echo "Log: ${ROOT}/opt/formal/logs/phase4_byobu.log"
echo "Report: ${ROOT}/opt/formal/phase4_report.txt"
exec bash -l
