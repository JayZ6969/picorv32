#!/usr/bin/env python3
"""Count value-change transitions in a VCD file.

Usage:
  python3 scripts/count_switching.py <vcd_path> [total_cycles]

Outputs METRIC lines for easy downstream parsing.
"""

import sys
from pathlib import Path


def usage():
    print("Usage: python3 scripts/count_switching.py <vcd_path> [total_cycles]")


def main():
    if len(sys.argv) < 2:
        usage()
        sys.exit(1)

    vcd = Path(sys.argv[1])
    if not vcd.exists():
        print(f"ERROR: file not found: {vcd}")
        sys.exit(2)

    total_cycles = None
    if len(sys.argv) >= 3:
        try:
            total_cycles = int(sys.argv[2])
        except ValueError:
            print("ERROR: total_cycles must be an integer")
            sys.exit(3)

    transitions = 0
    timestamps = 0
    in_defs = True

    with vcd.open("r", errors="ignore") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if in_defs:
                if line == "$enddefinitions $end":
                    in_defs = False
                continue

            if line.startswith("#"):
                timestamps += 1
                continue

            c0 = line[0]
            if c0 in "01xXzZ":
                transitions += 1
            elif c0 in "bBrR":
                transitions += 1

    denom = total_cycles if (total_cycles is not None and total_cycles > 0) else max(timestamps, 1)
    per_cycle = transitions / denom

    print(f"Total signal transitions: {transitions}")
    print(f"Timestamps: {timestamps}")
    if total_cycles is not None:
        print(f"Total cycles: {total_cycles}")
    print(f"Transitions per cycle: {per_cycle:.6f}")

    print(f"METRIC switching_transitions {transitions}")
    print(f"METRIC timestamps {timestamps}")
    if total_cycles is not None:
        print(f"METRIC total_cycles {total_cycles}")
    print(f"METRIC switching_per_cycle {per_cycle:.6f}")


if __name__ == "__main__":
    main()
