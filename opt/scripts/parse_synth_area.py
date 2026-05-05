#!/usr/bin/env python3
"""Parse post-synthesis area for 5 Phase 3 configurations."""

import csv
import re
from pathlib import Path

CONFIGS = {
    "baseline_A": "synth/reports/baseline_A_synth_stat.log",
    "baseline_B": "synth/reports/baseline_B_synth_stat.log",
    "baseline_C": "synth/reports/baseline_C_synth_stat.log",
    "baseline_C_ksa": "synth/reports/baseline_C_ksa_synth_stat.log",
    "optimized": "synth/reports/optimized_synth_stat.log",
}

LABELS = {
    "baseline_A": "Baseline A  (Iterative MUL)",
    "baseline_B": "Baseline B  (Fast MUL/DSP)",
    "baseline_C": "Baseline C  (Core only)",
    "baseline_C_ksa": "Baseline C' (Core + KSA)",
    "optimized": "Optimized   (Vedic + KSA)",
}

CELLS = ["SB_LUT4", "SB_DFF", "SB_CARRY", "SB_MAC16", "SB_RAM40_4K"]


def parse(path):
    out = {c: None for c in CELLS}
    p = Path(path)
    if not p.exists():
        return out

    text = p.read_text(errors="ignore")
    for cell in CELLS:
        matches = re.findall(rf"\b{cell}\b\s+(\d+)", text)
        out[cell] = int(matches[-1]) if matches else 0
    return out


def delta(new, old):
    if new is None or old in (None, 0):
        return None, None
    d = new - old
    pct = d * 100.0 / old
    return d, pct


def main():
    data = {cfg: parse(path) for cfg, path in CONFIGS.items()}

    print("\n" + "=" * 80)
    print("STAGE 1 - POST-SYNTHESIS AREA (A1-A8)")
    print("=" * 80)
    print(f"\n  {'Config':<32}", end="")
    for c in CELLS:
        print(f"{c:>10}", end="")
    print(f"  {'UTIL%':>6}")
    print("  " + "-" * 76)

    for cfg, d in data.items():
        lut = d.get("SB_LUT4") or 0
        util = f"{lut / 5280 * 100:.1f}" if lut else "-"
        print(f"  {LABELS[cfg]:<32}", end="")
        for c in CELLS:
            v = d.get(c)
            print(f"{str(v) if v is not None else '-':>10}", end="")
        print(f"  {util:>6}%")

    opt = data["optimized"]
    b_a = data["baseline_A"]
    b_b = data["baseline_B"]
    b_c = data["baseline_C"]
    b_ck = data["baseline_C_ksa"]

    print("\n  -- AREA ISOLATION ----------------------------------------")

    rows = [
        ("Total overhead vs Baseline B", opt["SB_LUT4"], b_b["SB_LUT4"]),
        ("Total add cost vs Core-only", opt["SB_LUT4"], b_c["SB_LUT4"]),
        ("Pure KSA cost (C' - C)", b_ck["SB_LUT4"], b_c["SB_LUT4"]),
        ("Pure Vedic cost (Opt - C')", opt["SB_LUT4"], b_ck["SB_LUT4"]),
    ]

    for label, new, old in rows:
        d, pct = delta(new, old)
        if d is None:
            print(f"  {label:<50} N/A")
        else:
            print(f"  {label:<50} {d:+6d} LUT4 ({pct:+.1f}%)")

    if opt.get("SB_CARRY") is not None and b_b.get("SB_CARRY") is not None:
        if opt["SB_CARRY"] < b_b["SB_CARRY"]:
            print(
                f"\n  ✓ KSA reduced SB_CARRY: {b_b['SB_CARRY']} -> {opt['SB_CARRY']}"
                f" ({opt['SB_CARRY'] - b_b['SB_CARRY']:+d})"
            )
        else:
            print(
                f"\n  ✗ SB_CARRY not reduced: B={b_b['SB_CARRY']} Opt={opt['SB_CARRY']}"
            )

    print(
        f"\n  DSP blocks: B_A={b_a.get('SB_MAC16')}  B_B={b_b.get('SB_MAC16')}  "
        f"Optimized={opt.get('SB_MAC16')}"
    )

    print("\n  BRAM check:")
    for cfg, d in data.items():
        bram = d.get("SB_RAM40_4K", 0)
        if bram and bram > 0:
            print(f"  ✗ {cfg}: SB_RAM40_4K={bram} (unexpected)")
        else:
            print(f"  ✓ {cfg}: SB_RAM40_4K=0")

    out_csv = Path("synth/reports/phase3_area_final.csv")
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["config", "label"] + CELLS)
        w.writeheader()
        for cfg, d in data.items():
            row = {"config": cfg, "label": LABELS[cfg]}
            row.update(d)
            w.writerow(row)

    print(f"\n  CSV: {out_csv}")
    print("=" * 80)


if __name__ == "__main__":
    main()
