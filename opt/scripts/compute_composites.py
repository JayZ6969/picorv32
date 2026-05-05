#!/usr/bin/env python3
"""Compute E1-E5 composite metrics from area, timing, and performance artifacts."""

import csv
import re
from pathlib import Path

CONFIGS = ["baseline_A", "baseline_B", "baseline_C", "optimized"]
LABELS = {
    "baseline_A": "Baseline A  (Iterative MUL)",
    "baseline_B": "Baseline B  (Fast MUL/DSP)",
    "baseline_C": "Baseline C  (Core only)",
    "optimized": "Optimized   (Vedic + KSA)",
}


def load_csv(path, key_col="config"):
    p = Path(path)
    if not p.exists():
        return {}
    with p.open(newline="") as f:
        return {r[key_col]: r for r in csv.DictReader(f) if key_col in r}


def sf(d, k):
    try:
        return float(d.get(k) or 0)
    except Exception:
        return 0.0


def si(d, k):
    try:
        return int(float(d.get(k) or 0))
    except Exception:
        return 0


def get_pcpi_latency(cfg):
    logs = {
        "baseline_A": "sim/logs/pcpi_baseline_A.log",
        "baseline_B": "sim/logs/pcpi_baseline_B.log",
        "optimized": "sim/logs/pcpi_optimized.log",
    }
    path = logs.get(cfg)
    if not path:
        return None

    p = Path(path)
    if not p.exists():
        return None
    text = p.read_text(errors="ignore")

    m = re.search(r"METRIC avg_pcpi_latency\s+(\d+)", text)
    if not m:
        m = re.search(r"Average latency:\s*(\d+)", text)
    return int(m.group(1)) if m else None


def get_fw_cycles(cfg, firmware="mul"):
    logs = {
        "baseline_A": f"sim/logs/integration_baseline_A_{firmware}.log",
        "baseline_B": f"sim/logs/integration_baseline_B_{firmware}.log",
        "optimized": f"sim/logs/integration_optimized_{firmware}.log",
    }
    path = logs.get(cfg)
    if not path:
        return None

    p = Path(path)
    if not p.exists():
        return None
    text = p.read_text(errors="ignore")

    m = re.search(r"METRIC total_cycles\s+(\d+)", text)
    if not m:
        m = re.search(r"Firmware completed at cycle\s*(\d+)", text)
    return int(m.group(1)) if m else None


def main():
    area = load_csv("synth/reports/phase3_area_final.csv")
    timing = load_csv("synth/reports/phase3_timing.csv")

    composites = {}
    fw_a = get_fw_cycles("baseline_A", "mul")
    fw_b = get_fw_cycles("baseline_B", "mul")

    for cfg in CONFIGS:
        a = area.get(cfg, {})
        t = timing.get(cfg, {})

        luts = si(a, "SB_LUT4")
        fmax = sf(t, "T1_fmax_mhz")
        crit_ns = sf(t, "T2_crit_path_ns") or (1000.0 / fmax if fmax else 0.0)
        cycles = get_pcpi_latency(cfg)
        fw_cyc = get_fw_cycles(cfg, "mul")

        e1 = round(luts * crit_ns, 2) if luts and crit_ns else None
        e2 = luts * cycles if (luts and cycles) else None
        e3 = round(fw_a / fw_cyc, 3) if (fw_a and fw_cyc) else None
        e4 = round(fw_b / fw_cyc, 3) if (fw_b and fw_cyc) else None

        mops = (fmax / cycles) if (fmax and cycles) else None
        e5 = round(mops / luts, 8) if (mops and luts) else None

        composites[cfg] = {
            "config": cfg,
            "label": LABELS[cfg],
            "LUT4": luts,
            "Fmax_MHz": round(fmax, 1) if fmax else None,
            "crit_path_ns": round(crit_ns, 3) if crit_ns else None,
            "cycles_per_MUL": cycles,
            "fw_cycles_mul": fw_cyc,
            "E1_ADP": e1,
            "E2_ACP": e2,
            "E3_speedup_A": e3,
            "E4_speedup_B": e4,
            "E5_MOPS_LUT": e5,
            "throughput_MOPS": round(mops, 3) if mops else None,
        }

    print("\n" + "=" * 80)
    print("STAGE 4 - COMPOSITE EFFICIENCY METRICS (E1-E5)")
    print("=" * 80)

    cols = [
        ("LUT4", "LUT4"),
        ("Fmax_MHz", "Fmax(MHz)"),
        ("cycles_per_MUL", "Cyc/MUL"),
        ("throughput_MOPS", "MOPS"),
        ("E1_ADP", "E1:ADP"),
        ("E2_ACP", "E2:ACP"),
        ("E3_speedup_A", "E3:Spd/A"),
        ("E4_speedup_B", "E4:Spd/B"),
        ("E5_MOPS_LUT", "E5:MOPS/LUT"),
    ]

    print(f"\n  {'Config':<30}", end="")
    for _, lbl in cols:
        print(f"{lbl:>12}", end="")
    print()
    print("  " + "-" * 140)

    for cfg in CONFIGS:
        row = composites[cfg]
        print(f"  {row['label']:<30}", end="")
        for key, _ in cols:
            val = row.get(key)
            if val is None:
                cell = "N/A"
            elif isinstance(val, float):
                cell = f"{val:.6f}" if key == "E5_MOPS_LUT" else f"{val:.2f}"
            else:
                cell = str(val)
            print(f"{cell:>12}", end="")
        print()

    out_csv = Path("synth/reports/phase3_composites.csv")
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    keys = ["config", "label"] + [k for k, _ in cols]
    with out_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys, extrasaction="ignore")
        w.writeheader()
        for cfg in CONFIGS:
            w.writerow(composites[cfg])

    print(f"\n  CSV: {out_csv}")
    print("=" * 80)


if __name__ == "__main__":
    main()
