#!/usr/bin/env python3
"""
capture_led.py — Stage 7 LED-based Hardware Validation

Since the iCESugar v1.5 DAPLink doesn't bridge FPGA UART to USB CDC,
this script guides the user through reading the LED blink pattern
to extract test results.

The firmware (mul_test_hw.c) signals results via the onboard red/green LEDs:
  1. Red LED ON briefly          → CPU started, running tests
  2. Green LED steady            → Tests running  
  3. 3 fast flashes (both LEDs)  → Tests completed
  4. GREEN blink ×10             → ALL PASS  (or RED blink = FAIL)
  5. RED blink ×N                → N = cycles per MUL (expect 7)
  6. Pause, then repeat from 3

Usage:
    python3 opt/scripts/hw/capture_led.py <config>
"""

import sys
import os
import pathlib
import datetime

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
OPT_DIR    = SCRIPT_DIR.parent.parent
LOG_DIR    = OPT_DIR / "hw" / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)

if len(sys.argv) < 2:
    print(__doc__)
    sys.exit(1)

config = sys.argv[1]

print("══════════════════════════════════════════")
print("  Stage 7 — LED-based Hardware Validation")
print("══════════════════════════════════════════")
print()
print("  The firmware signals test results via the onboard LEDs.")
print("  Watch the iCESugar board's red/green LEDs carefully.")
print()
print("  LED Pattern Guide:")
print("    1. RED ON briefly         → CPU booted, tests running")
print("    2. 3 fast flashes (both)  → Tests completed")
print("    3. GREEN blink ×10        → ALL TESTS PASSED ✅")
print("       RED blink ×10          → TESTS FAILED ❌")
print("    4. RED blink ×N           → N = cycles per MUL (expect 7)")
print("    5. Pause, then repeats from step 2")
print()

# Interactive prompts
led_color = input("  What color is blinking after the 3 flashes? (green/red): ").strip().lower()
passed = led_color.startswith("g")

cycles_str = input("  How many RED blinks after the green/red phase? (count them): ").strip()
try:
    cycles = int(cycles_str)
except ValueError:
    cycles = -1

print()

# Build result log
timestamp = datetime.datetime.now().isoformat()
log_lines = [
    f"# Stage 7 LED Validation — {config}",
    f"# Timestamp: {timestamp}",
    f"# Method: LED blink observation (DAPLink doesn't bridge UART)",
    f"",
    f"HW_START",
    f"HW_STATUS {'PASS' if passed else 'FAIL'}",
    f"HW_CYCLES_PER_MUL {cycles}",
    f"HW_DONE",
]

log_path = LOG_DIR / f"uart_{config}.log"
with open(log_path, "w") as f:
    f.write("\n".join(log_lines) + "\n")

print("══════════════════════════════════════════")
print(f"  Config: {config}")
print(f"  HW_STATUS {'PASS' if passed else 'FAIL'}")
print(f"  HW_CYCLES_PER_MUL {cycles}")
if cycles > 0:
    match = "✅ matches Phase 3" if cycles == 7 else f"⚠️  expected 7"
    print(f"  Cycles/MUL = {cycles}  ({match})")
print(f"\n  Overall: {'✅ PASS' if passed else '❌ FAIL'}")
print("══════════════════════════════════════════")
print(f"\n  Log saved → {log_path}")

sys.exit(0 if passed else 1)
