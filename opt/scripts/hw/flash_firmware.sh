#!/usr/bin/env bash
set -euo pipefail

# Stage 7 – Flash firmware binary to SPI flash and verify via UART output.
# This script expects a compiled firmware binary (e.g., firmware/bench/bench.bin)
# and writes it to the flash offset used by the PicoSoC design (1 MiB).
# It uses `icesprog`, which works with iCELink / iCESugar programmers.

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <firmware-bin>"
  echo "Example: $0 firmware/bench/bench.bin"
  exit 1
fi

if ! command -v icesprog >/dev/null 2>&1; then
  echo "ERROR: icesprog not found in PATH"
  exit 1
fi

# ROOT_DIR = repo root  (opt/scripts/hw → ../../.. = picorv32/)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# Resolve firmware path to absolute BEFORE we cd, so a relative path
# like opt/firmware/hw/mul_test_hw.bin works from the repo root.
FW_BIN="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

cd "${ROOT_DIR}"

if [[ ! -f "${FW_BIN}" ]]; then
  echo "ERROR: firmware binary not found: ${FW_BIN}"
  exit 1
fi

# Flash offset for firmware in the PicoSoC design (see picosoc.v PROGADDR_RESET)
OFFSET="0x00100000"

LOG_FLASH="opt/hw/logs/flash_firmware.log"
LOG_VERIFY="opt/hw/logs/verify_firmware.log"
READBACK="opt/hw/logs/readback_firmware.bin"

mkdir -p opt/hw/logs

echo "── Flashing firmware ${FW_BIN} at offset ${OFFSET} ──"
if icesprog -e -w -o "${OFFSET}" "${FW_BIN}" 2>&1 | tee "${LOG_FLASH}"; then
  echo " ✅ Firmware flash succeeded"
else
  echo " ❌ Firmware flash failed"
  exit 1
fi

LEN="$(stat -c%s "${FW_BIN}")"
echo "── Readback verify (len ${LEN}) ──"
if icesprog -r -l "${LEN}" -o "${OFFSET}" "${READBACK}" 2>&1 | tee "${LOG_VERIFY}"; then
  if cmp -s "${FW_BIN}" "${READBACK}"; then
    echo " ✅ Firmware readback matches"
  else
    echo " ❌ Firmware readback mismatch"
    exit 1
  fi
else
  echo " ❌ Readback failed"
  exit 1
fi

echo "DONE: Firmware flashed and verified. Reset the FPGA to run the new code."
