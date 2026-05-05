#!/usr/bin/env bash
set -euo pipefail

if ! command -v icepack >/dev/null 2>&1; then
  echo "ERROR: icepack not found in PATH"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

mkdir -p hw/bitstreams hw/logs

EXPECTED_SIZE="${EXPECTED_BIN_SIZE:-104090}"

if [[ $# -eq 0 ]]; then
  CONFIGS=(baseline_A baseline_C optimized)
else
  CONFIGS=("$@")
fi

echo "Packing bitstreams for: ${CONFIGS[*]}"

for cfg in "${CONFIGS[@]}"; do
  asc="pnr/${cfg}/design.asc"
  bin="hw/bitstreams/${cfg}.bin"
  log="hw/logs/icepack_${cfg}.log"

  if [[ ! -f "${asc}" ]]; then
    echo "ERROR: missing routed ASC: ${asc}"
    echo "Run: make -C opt p3_pnr"
    exit 1
  fi

echo "── Packing ${cfg} ──"
  icepack "${asc}" "${bin}" 2>&1 | tee "${log}"

  if [[ ! -f "${bin}" ]]; then
    echo "ERROR: bitstream not generated: ${bin}"
    exit 1
  fi

  size="$(stat -c%s "${bin}")"
echo " ✅ Size OK: ${size} bytes"
  if [[ "${size}" != "${EXPECTED_SIZE}" ]]; then
    echo "ERROR: unexpected bitstream size for ${cfg}"
    echo "Expected: ${EXPECTED_SIZE} bytes"
    echo "Got:      ${size} bytes"
    exit 1
  fi

  ls -lh "${bin}" | cat
  echo

done

echo "OK: all bitstreams packed and size-validated"
