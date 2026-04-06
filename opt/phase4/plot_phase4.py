#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def load_metrics(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    with path.open("r", encoding="utf-8", newline="") as fp:
        for row in csv.DictReader(fp):
            data[row["metric"]] = row["value"]
    return data


def to_float(v: str) -> float | None:
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def status_to_score(v: str) -> float:
    if v in ("pass", "present", "ready"):
        return 1.0
    if v in ("warn",):
        return 0.5
    return 0.0


def plot_signoff_status(out_dir: Path, metrics: dict[str, str]) -> None:
    issue_labels = ["Lint Errors", "Lint Warnings", "Yosys Warnings"]
    lint_warn_val = metrics.get("lint_warnings_unwaived", metrics.get("lint_warnings", "N/A"))
    issue_raw = [
        metrics.get("lint_errors", "N/A"),
        lint_warn_val,
        metrics.get("yosys_check_warnings", "N/A"),
    ]
    issue_vals = [to_float(v) if to_float(v) is not None else 0.0 for v in issue_raw]

    check_labels = ["Lint", "Yosys", "CDC", "Formal", "Constraints"]
    check_raw = [
        metrics.get("lint_status", "N/A"),
        metrics.get("yosys_check_status", "N/A"),
        metrics.get("cdc_status", "N/A"),
        metrics.get("formal_status", "N/A"),
        metrics.get("constraints_status", "N/A"),
    ]
    check_vals = [status_to_score(v) for v in check_raw]

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))

    ax = axes[0]
    bars = ax.bar(issue_labels, issue_vals, color=["#e74c3c", "#f39c12", "#8e44ad"], alpha=0.9)
    ax.set_title("Phase 4 Issue Counts")
    ax.set_ylabel("Count")
    ax.grid(axis="y", alpha=0.3)
    ax.set_ylim(0, max(issue_vals + [1.0]) * 1.35)
    for bar, raw in zip(bars, issue_raw):
        y = bar.get_height()
        ax.text(bar.get_x() + bar.get_width() / 2, y + 0.15, raw, ha="center", va="bottom", fontweight="bold")

    ax = axes[1]
    status_colors = []
    for raw, val in zip(check_raw, check_vals):
        if raw in ("pass", "present", "ready"):
            status_colors.append("#2ecc71")
        elif raw in ("warn",):
            status_colors.append("#f39c12")
        else:
            status_colors.append("#bdc3c7")
    bars = ax.bar(check_labels, check_vals, color=status_colors, alpha=0.9)
    for bar, raw in zip(bars, check_raw):
        if raw not in ("pass", "present", "ready", "warn"):
            bar.set_hatch("//")
        y = bar.get_height()
        ax.text(bar.get_x() + bar.get_width() / 2, y + 0.05, raw, ha="center", va="bottom", fontsize=9, fontweight="bold")
    ax.set_title("Phase 4 Sign-off Check Status")
    ax.set_ylabel("Pass=1 / Not-closed=0")
    ax.set_ylim(0, 1.35)
    ax.grid(axis="y", alpha=0.3)

    fig.suptitle(f"Phase 4 Sign-off Dashboard (Readiness: {metrics.get('readiness_status', 'N/A')})", fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(out_dir / "phase4_signoff_status.png", bbox_inches="tight")
    plt.close(fig)


def plot_baseline_delta(out_dir: Path, metrics: dict[str, str]) -> bool:
    baseline = to_float(metrics.get("baseline_avg_cycles", "N/A"))
    optimized = to_float(metrics.get("optimized_avg_cycles", "N/A"))
    if baseline is None or optimized is None:
        return False

    fig, ax = plt.subplots(figsize=(8, 5))
    labels = ["Baseline", "Optimized"]
    values = [baseline, optimized]
    bars = ax.bar(labels, values, color=["#e74c3c", "#2ecc71"], alpha=0.9)
    ax.set_title("Phase 4 Baseline Latency Reference")
    ax.set_ylabel("Avg cycles (PCPI MUL)")
    ax.grid(axis="y", alpha=0.3)
    ax.set_ylim(0, max(values) * 1.3)

    for bar, val in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width() / 2, val + 0.2, f"{val:.2f}", ha="center", va="bottom", fontweight="bold")

    speedup = baseline / optimized if optimized > 0 else 0
    ax.text(0.5, 0.95, f"Reference speedup: {speedup:.2f}x", transform=ax.transAxes, ha="center", va="top")

    fig.tight_layout()
    fig.savefig(out_dir / "phase4_baseline_delta.png", bbox_inches="tight")
    plt.close(fig)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 4 plots")
    parser.add_argument("--metrics-csv", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    out_dir = Path(args.out_dir).resolve()
    metrics_csv = Path(args.metrics_csv).resolve()

    metrics = load_metrics(metrics_csv)
    plot_signoff_status(out_dir, metrics)
    baseline_ok = plot_baseline_delta(out_dir, metrics)

    print(f"Wrote {out_dir / 'phase4_signoff_status.png'}")
    if baseline_ok:
        print(f"Wrote {out_dir / 'phase4_baseline_delta.png'}")
    else:
        print(f"Skipped {out_dir / 'phase4_baseline_delta.png'} (missing baseline values)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
