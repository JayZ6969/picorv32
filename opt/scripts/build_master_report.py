#!/usr/bin/env python3
"""Build a merged master metrics CSV from available report artifacts.

Inputs (if present):
  - synth/reports/phase1_area_comparison.csv
  - synth/reports/phase2_performance.csv
  - synth/reports/phase1_quality_metrics.txt

Output:
  - synth/reports/master_metrics.csv
"""

import csv
import re
from pathlib import Path

AREA_CSV = Path("synth/reports/phase1_area_comparison.csv")
PERF_CSV = Path("synth/reports/phase2_performance.csv")
QUALITY_TXT = Path("synth/reports/phase1_quality_metrics.txt")
OUT_CSV = Path("synth/reports/master_metrics.csv")


def read_csv_by_config(path: Path):
    data = {}
    if not path.exists():
        return data
    with path.open(newline="") as f:
        for row in csv.DictReader(f):
            cfg = row.get("config")
            if not cfg:
                continue
            data[cfg] = row
    return data


def read_quality(path: Path):
    out = {}
    if not path.exists():
        return out
    text = path.read_text(errors="ignore")
    patterns = {
        "lint_warnings": r"Q1\s+Lint warnings:\s+(\d+)",
        "lint_errors": r"Q2\s+Lint errors:\s+(\d+)",
        "lines_changed": r"Q3\s+Lines changed in core:\s+(\d+)",
        "modules_added": r"Q4\s+New modules in core:\s+(\d+)",
    }
    for k, pat in patterns.items():
        m = re.search(pat, text)
        if m:
            out[k] = m.group(1)
    return out


def main():
    area = read_csv_by_config(AREA_CSV)
    perf = read_csv_by_config(PERF_CSV)
    quality = read_quality(QUALITY_TXT)

    cfgs = sorted(set(area.keys()) | set(perf.keys()))
    rows = []
    for cfg in cfgs:
        row = {"config": cfg}
        row.update({f"area_{k}": v for k, v in area.get(cfg, {}).items() if k != "config"})
        row.update({f"perf_{k}": v for k, v in perf.get(cfg, {}).items() if k != "config"})
        row.update(quality)
        rows.append(row)

    keys = ["config"] + sorted({k for r in rows for k in r if k != "config"})

    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys, extrasaction="ignore")
        w.writeheader()
        for row in rows:
            w.writerow(row)

    print(f"Master metrics report: {OUT_CSV}")
    print("Run this after synthesis/performance reports are generated.")


if __name__ == "__main__":
    main()
