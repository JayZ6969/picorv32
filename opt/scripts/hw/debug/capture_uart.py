#!/usr/bin/env python3
"""
capture_uart.py — Stage 7 UART output capture and parser

Usage:
    python3 opt/scripts/hw/capture_uart.py <config> [port] [baud]

    config  : name tag for log file (e.g. optimized, baseline_A, baseline_C)
    port    : serial port (default: /dev/ttyUSB1, override via env UART_PORT)
    baud    : baud rate   (default: 115200, override via env UART_BAUD)

Output:
    opt/hw/logs/uart_<config>.log   — raw UART lines
    Prints parsed results to stdout.
    Exits 0 on HW_STATUS PASS, 1 on FAIL or timeout.

Example:
    python3 opt/scripts/hw/capture_uart.py optimized
    python3 opt/scripts/hw/capture_uart.py optimized /dev/ttyACM0
"""

import os
import sys
import time
import pathlib

# ── Serial import with helpful error message ──────────────────────────────────
try:
    import serial
except ImportError:
    print("ERROR: pyserial not installed.  Run:  pip3 install pyserial")
    sys.exit(1)

# ── Config ────────────────────────────────────────────────────────────────────
SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parents[3]
OPT_DIR = ROOT_DIR / "opt"
LOG_DIR = OPT_DIR / "hw" / "logs"

TIMEOUT_SEC = 60        # max wait for HW_DONE
SETTLE_MS   = 500       # ms to wait after opening port (board reset settling)

# ── CLI args ──────────────────────────────────────────────────────────────────
if len(sys.argv) < 2:
    print(__doc__)
    sys.exit(1)

config  = sys.argv[1]
port    = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("UART_PORT", "/dev/ttyUSB1")
baud    = int(sys.argv[3]) if len(sys.argv) > 3 else int(os.environ.get("UART_BAUD", "115200"))

log_path = LOG_DIR / f"uart_{config}.log"
LOG_DIR.mkdir(parents=True, exist_ok=True)

# ── Capture ───────────────────────────────────────────────────────────────────
print(f"Opening {port} @ {baud} baud …")
try:
    ser = serial.Serial(port, baud, timeout=1)
except serial.SerialException as e:
    print(f"ERROR: Cannot open {port}: {e}")
    sys.exit(1)

time.sleep(SETTLE_MS / 1000.0)

lines    = []
deadline = time.time() + TIMEOUT_SEC
started  = False

print(f"Waiting for HW_START (timeout {TIMEOUT_SEC}s) …")
while time.time() < deadline:
    try:
        raw = ser.readline()
    except serial.SerialException as e:
        print(f"ERROR: Serial read failed: {e}")
        break

    if not raw:
        continue

    line = raw.decode("ascii", errors="replace").strip()
    
    # DEBUG: Print everything we receive so we know if the board is alive
    if raw:
        print(f"[DEBUG RX] {raw!r}")

    if not line:
        continue

    if not started and "HW_START" in line:
        started = True
        print(f"  → {line}")

    if started:
        print(f"  {line}")
        lines.append(line)
        if "HW_DONE" in line:
            break

ser.close()

# ── Save log ──────────────────────────────────────────────────────────────────
with open(log_path, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"\nSaved log → {log_path}")

# ── Parse results ─────────────────────────────────────────────────────────────
if not started:
    print("\n❌ ERROR: Never received HW_START — check port, firmware flash, and reset.")
    sys.exit(1)

status_lines  = [l for l in lines if "HW_STATUS" in l]
cycles_lines  = [l for l in lines if "HW_CYCLES_PER_MUL" in l]
fail_lines    = [l for l in lines if l.startswith("FAIL")]
done          = any("HW_DONE" in l for l in lines)

status_str = status_lines[0]  if status_lines  else "NOT FOUND"
cycles_str = cycles_lines[0]  if cycles_lines  else "NOT FOUND"

passed = "PASS" in status_str and not fail_lines and done

# ── Parse cycle count ─────────────────────────────────────────────────────────
cycles_val = None
if cycles_lines:
    try:
        cycles_val = int(cycles_lines[0].split()[-1])
    except (ValueError, IndexError):
        pass

# ── Summary ───────────────────────────────────────────────────────────────────
print("\n══════════════════════════════════════════")
print(f"  Config: {config}")
print(f"  {status_str}")
print(f"  {cycles_str}")
if cycles_val is not None:
    match = "✅ matches Phase 3" if cycles_val == 7 else f"⚠️  expected 7"
    print(f"  Cycles/MUL = {cycles_val}  ({match})")
if fail_lines:
    print(f"\n  ❌ {len(fail_lines)} FAIL line(s):")
    for fl in fail_lines:
        print(f"    {fl}")
print(f"\n  Overall: {'✅ PASS' if passed else '❌ FAIL'}")
print("══════════════════════════════════════════\n")

sys.exit(0 if passed else 1)
