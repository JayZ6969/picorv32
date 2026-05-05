#!/usr/bin/env python3
"""Parse performance metrics from simulation logs into CSV.

Reads METRIC lines and optional 'Average latency: N cycles' lines.
Writes: synth/reports/phase2_performance.csv
"""

import csv
import re
from pathlib import Path

LOGS = {
    "baseline_A_mul": ["sim/logs/integration_baseline_A_mul.log"],
    "baseline_B_mul": ["sim/logs/integration_baseline_B_mul.log"],
    "baseline_A_bench": ["sim/logs/integration_baseline_A_bench.log"],
    "baseline_B_bench": ["sim/logs/integration_baseline_B_bench.log"],
    "optimized_mul": ["sim/logs/integration_optimized_mul.log", "sim/logs/integration.log"],
    "optimized_bench": ["sim/logs/integration_optimized_bench.log", "sim/logs/integration_bench.log"],
    "baseline_A_pcpi": ["sim/logs/pcpi_baseline_A.log"],
    "baseline_B_pcpi": ["sim/logs/pcpi_baseline_B.log"],
    "optimized_pcpi": ["sim/logs/pcpi_optimized.log", "sim/logs/pcpi.log"],
    "optimized_pcpi_rand1k": ["sim/logs/pcpi_rand1k.log"],
}


def newest_existing_path(paths):
    existing = [Path(p) for p in paths if Path(p).exists()]
    if not existing:
        return None
    return max(existing, key=lambda p: p.stat().st_mtime)


def parse_metrics(path: Path):
    metrics = {}
    pcpi_latencies = []
    if not path.exists():
        return metrics

    text = path.read_text(errors="ignore")

    for line in text.splitlines():
        m = re.match(r"METRIC\s+(\w+)\s+([\d.]+)", line.strip())
        if m:
            key, val = m.group(1), m.group(2)
            metrics[key] = float(val)

        # Per-transaction optimized PCPI metric lines.
        m = re.search(r"PCPI_METRIC\b.*\blatency=(\d+)", line)
        if m:
            pcpi_latencies.append(int(m.group(1)))

    m = re.search(r"Average latency:\s*(\d+)\s*cycles", text)
    if m:
        metrics["avg_pcpi_latency"] = float(m.group(1))

    if pcpi_latencies:
        if "avg_pcpi_latency" not in metrics:
            metrics["avg_pcpi_latency"] = sum(pcpi_latencies) / len(pcpi_latencies)
        if "min_pcpi_latency" not in metrics:
            metrics["min_pcpi_latency"] = float(min(pcpi_latencies))
        if "max_pcpi_latency" not in metrics:
            metrics["max_pcpi_latency"] = float(max(pcpi_latencies))
        if "total_mul_ops" not in metrics:
            metrics["total_mul_ops"] = float(len(pcpi_latencies))

    # Legacy integration logs may not emit METRIC total_cycles but do emit this line.
    m = re.search(r"Firmware completed at cycle\s*(\d+)", text)
    if m and "total_cycles" not in metrics:
        metrics["total_cycles"] = float(m.group(1))

    return metrics


def speedup(base, opt):
    if base <= 0 or opt <= 0:
        return 0.0
    return base / opt


def main():
    all_data = {}
    for name, paths in LOGS.items():
        p = newest_existing_path(paths)
        if p is not None:
            all_data[name] = parse_metrics(p)

    print("\n" + "=" * 76)
    print("PHASE 2 PERFORMANCE METRICS -- AVAILABLE CONFIGURATIONS")
    print("=" * 76)

    metrics_to_show = [
        "total_cycles",
        "stall_cycles",
        "stall_pct",
        "effective_ipc",
        "avg_pcpi_latency",
    ]

    print(f"{'Metric':<24}", end="")
    for name in all_data:
        print(f"{name[:17]:>18}", end="")
    print()
    print("-" * 76)

    for metric in metrics_to_show:
        print(f"{metric:<24}", end="")
        for _, d in all_data.items():
            val = d.get(metric, "-")
            if isinstance(val, float):
                print(f"{val:>18.4f}", end="")
            else:
                print(f"{str(val):>18}", end="")
        print()

    if "baseline_A_mul" in all_data and "optimized_mul" in all_data:
        a = all_data["baseline_A_mul"].get("total_cycles", 0)
        o = all_data["optimized_mul"].get("total_cycles", 0)
        print(f"\nSpeedup vs Baseline A (mul_test): {speedup(a, o):.2f}x")

    if "baseline_B_mul" in all_data and "optimized_mul" in all_data:
        b = all_data["baseline_B_mul"].get("total_cycles", 0)
        o = all_data["optimized_mul"].get("total_cycles", 0)
        print(f"Speedup vs Baseline B (mul_test): {speedup(b, o):.2f}x")

    if "baseline_A_bench" in all_data and "optimized_bench" in all_data:
        a = all_data["baseline_A_bench"].get("total_cycles", 0)
        o = all_data["optimized_bench"].get("total_cycles", 0)
        print(f"Speedup vs Baseline A (bench):    {speedup(a, o):.2f}x")

    rows = []
    for name, d in all_data.items():
        row = {"config": name}
        row.update(d)
        rows.append(row)

    keys = ["config"] + sorted({k for r in rows for k in r if k != "config"})
    out_csv = Path("synth/reports/phase2_performance.csv")
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys, extrasaction="ignore")
        w.writeheader()
        for row in rows:
            w.writerow(row)

    print(f"\nCSV written: {out_csv}")


if __name__ == "__main__":
    main()
