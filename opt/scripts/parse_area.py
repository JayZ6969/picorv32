#!/usr/bin/env python3
"""Parse area reports for baseline and optimized configurations.

Expected inputs under synth/reports:
  - baseline_A_stat.log
  - baseline_B_stat.log
  - baseline_C_stat.log
  - optimized_stat.log

Outputs:
  - console table
  - synth/reports/phase1_area_comparison.csv
"""

import csv
import re
from pathlib import Path

CONFIGS = {
    "Baseline A (iterative)": "synth/reports/baseline_A_stat.log",
    "Baseline B (fast_mul)": "synth/reports/baseline_B_stat.log",
    "Baseline C (core only)": "synth/reports/baseline_C_stat.log",
    "Optimized (Vedic+KSA)": "synth/reports/optimized_stat.log",
}

CELLS = ["TOTAL_CELLS", "SB_LUT4", "SB_DFF", "SB_CARRY", "SB_MAC16", "SB_RAM40_4K"]


def parse_stat(path: Path):
    if not path.exists():
        return {c: 0 for c in CELLS}
    text = path.read_text(errors="ignore")
    out = {"TOTAL_CELLS": 0}

    m_total = re.search(r"Number of cells:\s*(\d+)", text)
    if m_total:
        out["TOTAL_CELLS"] = int(m_total.group(1))

    for c in CELLS:
        if c == "TOTAL_CELLS":
            continue
        m = re.search(rf"{re.escape(c)}\s+(\d+)", text)
        out[c] = int(m.group(1)) if m else 0

    for c in CELLS:
        if c not in out:
            out[c] = 0

    return out


def pct(delta, base):
    if base == 0:
        return 0.0
    return delta * 100.0 / base


def main():
    data = {name: parse_stat(Path(path)) for name, path in CONFIGS.items()}

    print("\n" + "=" * 84)
    print("PHASE 1 AREA METRICS -- ALL CONFIGURATIONS")
    print("=" * 84)

    header = f"{'Config':<30}" + "".join(f"{c:>11}" for c in CELLS)
    print(header)
    print("-" * 84)
    for name, d in data.items():
        row = f"{name:<30}" + "".join(f"{d[c]:>11}" for c in CELLS)
        print(row)

    opt = data["Optimized (Vedic+KSA)"]
    b = data["Baseline B (fast_mul)"]
    c = data["Baseline C (core only)"]

    print("\n--- DELTA: Optimized vs Baseline B ---")
    for cell in CELLS:
        delta = opt[cell] - b[cell]
        print(f"  {cell:<14}: {delta:+7d}  ({pct(delta, b[cell]):+6.1f}%)")

    print("\n--- DELTA: Optimized vs Baseline C ---")
    for cell in CELLS:
        delta = opt[cell] - c[cell]
        print(f"  {cell:<14}: {delta:+7d}")

    out_csv = Path("synth/reports/phase1_area_comparison.csv")
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["config"] + CELLS)
        for name, d in data.items():
            w.writerow([name] + [d[c] for c in CELLS])

    print(f"\nCSV written: {out_csv}")


if __name__ == "__main__":
    main()
