#!/usr/bin/env bash
# Sync picorv32.v, regenerate RVFI checks, run `make -C checks` (makefile `all`).
# checks.cfg [filter-checks] removes reg/pc_fwd/pc_bwd/liveness/unique/cover — each
# can rival overnight F2 16×16 on Z3 for this Vedic core. See opt/docs/P5_RVFI_Formal.md.

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

echo "== genchecks.py"
(
  cd "$CORE_DIR"
  python3 ../../checks/genchecks.py
)

RVFI_FULL_JOBS="${RVFI_FULL_JOBS:-$(nproc)}"
echo "== make -C checks (default goal = all; -j${RVFI_FULL_JOBS}) — SBY output streams below (interleaved if -j>1; RVFI_FULL_JOBS=1 for serial)"
make -C "$CHK_DIR" -j"${RVFI_FULL_JOBS}" 2>&1 | tee opt/formal/rvfi/logs/full_rvfi_make.log

echo "== Done. Log: opt/formal/rvfi/logs/full_rvfi_make.log (RVFI_FULL_JOBS=1 for less parallelism)"
