#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/hw/flash_and_verify.sh <config>"
  echo "Example: bash scripts/hw/flash_and_verify.sh optimized"
  exit 1
fi

if ! command -v icesprog >/dev/null 2>&1; then
  echo "ERROR: icesprog not found in PATH"
  echo "This Stage 6 flow targets iCELink/iCESugar programmers (USB 1d50:602b)."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

CONFIG="$1"
BIN="hw/bitstreams/${CONFIG}.bin"
LOG_FLASH="hw/logs/flash_${CONFIG}.log"
LOG_VERIFY="hw/logs/verify_${CONFIG}.log"
READBACK="hw/logs/readback_${CONFIG}.bin"

OFFSET="0"
USE_OFFSET=0
if [[ -n "${ICESPROG_OFFSET-}" ]]; then
  OFFSET="${ICESPROG_OFFSET}"
  USE_OFFSET=1
fi

mkdir -p hw/logs

if [[ ! -f "${BIN}" ]]; then
  echo "ERROR: missing bitstream: ${BIN}"
  echo "Run: bash scripts/hw/pack_bitstreams.sh ${CONFIG}"
  exit 1
fi

LEN="$(stat -c%s "${BIN}")"

rm -f "${LOG_FLASH}" "${LOG_VERIFY}" "${READBACK}"

echo "── Flashing ${CONFIG} (offset ${OFFSET}) ──"

flash_cmd=(icesprog -e -w)
if [[ "${USE_OFFSET}" -eq 1 ]]; then
  flash_cmd+=( -o "${OFFSET}" )
fi
flash_cmd+=( "${BIN}" )

if "${flash_cmd[@]}" 2>&1 | tee "${LOG_FLASH}"; then
  echo " ✅ Flash write completed"
else
  echo " ❌ Flash write failed"
  echo " Try: sudo icesprog -p (permissions)"
  exit 1
fi

echo "── Readback verify (len ${LEN}) ──"

read_cmd=(icesprog -r -l "${LEN}")
if [[ "${USE_OFFSET}" -eq 1 ]]; then
  read_cmd+=( -o "${OFFSET}" )
fi
read_cmd+=( "${READBACK}" )

if "${read_cmd[@]}" 2>&1 | tee "${LOG_VERIFY}"; then
  if [[ ! -f "${READBACK}" ]]; then
    echo " ❌ Readback file not created: ${READBACK}"
    exit 1
  fi

  rb_len="$(stat -c%s "${READBACK}")"
  if [[ "${rb_len}" != "${LEN}" ]]; then
    echo " ❌ Readback size mismatch (got ${rb_len}, expected ${LEN})"
    exit 1
  fi

  if cmp -s "${BIN}" "${READBACK}"; then
    echo " ✅ Readback verified (matches bitstream)"
  else
    echo " ❌ Readback mismatch — reflash"
    exit 1
  fi
else
  echo " ❌ Readback failed"
  exit 1
fi

echo "DONE: ${CONFIG} flashed and verified"
echo "Note: you may need to reset/power-cycle the FPGA to reload from flash."
