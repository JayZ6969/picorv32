#!/usr/bin/env python3
"""Compare switching metrics (W1-W4 proxy) across Baseline A/B and Optimized."""

import re
from pathlib import Path

SWITCHING_FILES = {
    "Baseline A": [
        "synth/reports/baseline_A_switching.txt",
        "sim/logs/switching_baseline_A_mul.log",
    ],
    "Baseline B": [
        "synth/reports/baseline_B_switching.txt",
        "sim/logs/switching_baseline_B_mul.log",
    ],
    "Optimized": [
        "synth/reports/optimized_switching.txt",
        "sim/logs/switching_optimized_mul.log",
    ],
}

CYCLE_LOGS = {
    "Baseline A": "sim/logs/integration_baseline_A_mul.log",
    "Baseline B": "sim/logs/integration_baseline_B_mul.log",
    "Optimized": "sim/logs/integration_optimized_mul.log",
}


def first_existing(paths):
    for p in paths:
        pp = Path(p)
        if pp.exists():
            return pp
    return None


def get_transitions(path: Path):
    if path is None or not path.exists():
        return None
    text = path.read_text(errors="ignore")

    for pat in [r"Total signal transitions:\s*(\d+)", r"METRIC\s+switching_transitions\s+(\d+)"]:
        m = re.search(pat, text)
        if m:
            return int(m.group(1))
    return None


def get_cycles(path: Path):
    if path is None or not path.exists():
        return None
    text = path.read_text(errors="ignore")
    m = re.search(r"METRIC\s+total_cycles\s+(\d+)", text)
    if m:
        return int(m.group(1))
    m = re.search(r"Firmware completed at cycle\s*(\d+)", text)
    if m:
        return int(m.group(1))
    return None


def fmt_num(v):
    return str(v) if v is not None else "N/A"


def fmt_float(v):
    return f"{v:.2f}" if v is not None else "N/A"


def main():
    print("\n" + "=" * 64)
    print("POWER PROXY - SWITCHING ACTIVITY COMPARISON (W1-W4)")
    print("=" * 64)
    print(f"\n  {'Config':<16} {'W1: Total Trans':>16} {'Cycles':>10} {'W2: Trans/Cycle':>16}")
    print("  " + "-" * 60)

    transitions = {}
    for name in ["Baseline A", "Baseline B", "Optimized"]:
        sw_path = first_existing(SWITCHING_FILES[name])
        c_path = Path(CYCLE_LOGS[name])

        t = get_transitions(sw_path)
        c = get_cycles(c_path)
        w2 = (t / c) if (t is not None and c not in (None, 0)) else None

        transitions[name] = t
        print(f"  {name:<16} {fmt_num(t):>16} {fmt_num(c):>10} {fmt_float(w2):>16}")

    opt_t = transitions.get("Optimized")
    if opt_t is not None:
        for base in ["Baseline A", "Baseline B"]:
            base_t = transitions.get(base)
            if base_t not in (None, 0):
                delta = (opt_t - base_t) * 100.0 / base_t
                tendency = "more" if delta > 0 else "fewer"
                power_bias = "more" if delta > 0 else "less"
                print(
                    f"\n  W1 delta Optimized vs {base}: {delta:+.1f}% "
                    f"({tendency} transitions = {power_bias} dynamic power)"
                )

    print("=" * 64)


if __name__ == "__main__":
    main()
