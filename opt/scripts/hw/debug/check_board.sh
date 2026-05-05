#!/usr/bin/env bash
set -euo pipefail

if ! command -v lsusb >/dev/null 2>&1; then
  echo "ERROR: lsusb not found. Install usbutils first."
  exit 1
fi

PATTERN='1d50:602b|iCELink|CMSIS-DAP|DAPLink|iCESugar'

echo "Checking for iCELink (CMSIS-DAP) USB device..."
if lsusb | grep -Eiq "${PATTERN}"; then
  echo "OK: programmer detected"
  lsusb | grep -Ei "${PATTERN}" | cat
else
  echo "ERROR: iCELink programmer not detected"
  echo "Expected lsusb match: ${PATTERN}"
  echo "Check USB cable, power, and permissions."
  exit 1
fi

if ! command -v icesprog >/dev/null 2>&1; then
  echo "ERROR: icesprog not found in PATH"
  echo "Install icesprog (iCELink programmer) and retry."
  exit 1
fi

echo "Probing flash via icesprog..."
if icesprog -p; then
  echo "OK: icesprog probe succeeded"
else
  echo "ERROR: icesprog probe failed"
  echo "Try: sudo icesprog -p"
  exit 1
fi
