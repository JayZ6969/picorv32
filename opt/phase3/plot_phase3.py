#!/usr/bin/env python3
"""
Generate Phase 3 visualization charts from phase3_metrics.csv.

Outputs:
  - phase3_timing.png
  - phase3_resources.png
    - phase3_baseline_compare.png (if pcpi_summary.csv is available)

Usage:
  python plot_phase3.py --metrics-csv ../results/phase3/icebreaker/phase3_metrics.csv \
                        --out-dir ../results/phase3/icebreaker
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def load_metrics(path: Path) -> dict[str, str]:
    metrics: dict[str, str] = {}
    with path.open("r", encoding="utf-8", newline="") as fp:
        reader = csv.DictReader(fp)
        for row in reader:
            metrics[row["metric"]] = row["value"]
    return metrics


def load_pcpi_summary(path: Path) -> dict[str, dict[str, str]]:
    table: dict[str, dict[str, str]] = {}
    if not path.exists():
        return table
    with path.open("r", encoding="utf-8", newline="") as fp:
        reader = csv.DictReader(fp)
        for row in reader:
            metric = row.get("metric")
            if metric:
                table[metric] = row
    return table


def as_float(value: str) -> float | None:
    if value is None or value == "N/A":
        return None
    try:
        return float(value)
    except ValueError:
        return None


def as_int(value: str) -> int | None:
    if value is None or value == "N/A":
        return None
    try:
        return int(float(value))
    except ValueError:
        return None


def parse_cells_from_log(path: Path) -> int | None:
    if not path.exists():
        return None
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if "Number of cells:" in line:
            try:
                return int(line.split(":", 1)[1].strip())
            except ValueError:
                return None
    return None


def parse_module_count_from_json(path: Path) -> int | None:
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8", errors="ignore"))
    except json.JSONDecodeError:
        return None
    modules = data.get("modules", {})
    return len(modules) if isinstance(modules, dict) else None


def plot_timing(out_dir: Path, board: str, target_mhz: float, fmax_mhz: float | None, delay_ns: float | None) -> None:
    fig, ax = plt.subplots(figsize=(8, 5))

    labels = ["Target MHz", "Estimated Fmax MHz"]
    values = [target_mhz, fmax_mhz if fmax_mhz is not None else 0.0]
    colors = ["#7f8c8d", "#2ecc71" if (fmax_mhz is not None and fmax_mhz >= target_mhz) else "#e74c3c"]

    bars = ax.bar(labels, values, color=colors, alpha=0.9)
    ax.set_ylabel("Frequency (MHz)")
    ax.set_title(f"Phase 3 Timing Summary ({board})")
    ax.set_ylim(0, max(values + [1.0]) * 1.25)
    ax.grid(axis="y", alpha=0.3)

    for bar, val in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width() / 2, val + 0.2, f"{val:.2f}", ha="center", va="bottom", fontweight="bold")

    if delay_ns is not None:
        ax.text(
            0.02,
            0.97,
            f"Critical path delay: {delay_ns:.3f} ns",
            transform=ax.transAxes,
            va="top",
            fontsize=10,
        )

    fig.tight_layout()
    fig.savefig(out_dir / "phase3_timing.png", bbox_inches="tight")
    plt.close(fig)


def plot_resources(
    out_dir: Path,
    board: str,
    opt_cells: int | None,
    opt_modules: int | None,
    base_cells: int | None,
    base_modules: int | None,
) -> None:
    fig, ax = plt.subplots(figsize=(8, 5))

    if base_cells is not None and base_modules is not None:
        labels = ["Yosys Cells", "JSON Modules"]
        x = [0, 1]
        width = 0.36
        baseline_vals = [base_cells, base_modules]
        optimized_vals = [opt_cells if opt_cells is not None else 0, opt_modules if opt_modules is not None else 0]

        b0 = ax.bar([i - width / 2 for i in x], baseline_vals, width=width, color="#e74c3c", alpha=0.85, label="Baseline")
        b1 = ax.bar([i + width / 2 for i in x], optimized_vals, width=width, color="#2ecc71", alpha=0.85, label="Optimized")

        ax.set_xticks(x)
        ax.set_xticklabels(labels)
        ax.set_ylabel("Count")
        ax.set_title(f"Phase 3 Resource Comparison ({board})")
        ymax = max(baseline_vals + optimized_vals + [1])
        ax.set_ylim(0, ymax * 1.30)
        ax.grid(axis="y", alpha=0.3)
        ax.legend()

        for bar, val in list(zip(b0, baseline_vals)) + list(zip(b1, optimized_vals)):
            ax.text(bar.get_x() + bar.get_width() / 2, val + max(1, int(0.01 * ymax)), f"{val}", ha="center", va="bottom", fontweight="bold", fontsize=9)

        if opt_cells is not None and base_cells > 0:
            cell_delta = 100.0 * (opt_cells - base_cells) / base_cells
            module_delta = 100.0 * ((opt_modules or 0) - base_modules) / base_modules if base_modules > 0 else 0.0
            ax.text(
                0.5,
                0.98,
                f"Cell delta: {cell_delta:+.1f}% | Module delta: {module_delta:+.1f}%",
                transform=ax.transAxes,
                va="top",
                ha="center",
                fontsize=10,
            )
    else:
        labels = ["Yosys Cell Count", "JSON Module Count"]
        values = [opt_cells if opt_cells is not None else 0, opt_modules if opt_modules is not None else 0]
        colors = ["#3498db", "#9b59b6"]

        bars = ax.bar(labels, values, color=colors, alpha=0.9)
        ax.set_ylabel("Count")
        ax.set_title(f"Phase 3 Netlist Indicators ({board})")
        ax.set_ylim(0, max(values + [1]) * 1.25)
        ax.grid(axis="y", alpha=0.3)

        for bar, val in zip(bars, values):
            ax.text(bar.get_x() + bar.get_width() / 2, val + max(1, int(0.01 * max(values + [1]))), f"{val}", ha="center", va="bottom", fontweight="bold")

    fig.tight_layout()
    fig.savefig(out_dir / "phase3_resources.png", bbox_inches="tight")
    plt.close(fig)


def plot_baseline_compare(out_dir: Path, board: str, pcpi_table: dict[str, dict[str, str]]) -> bool:
    avg_cycles = pcpi_table.get("avg_cycles")
    avg_latency = pcpi_table.get("avg_latency_ns")
    if not avg_cycles or not avg_latency:
        return False

    base_cycles = as_float(avg_cycles.get("baseline_seq", "N/A"))
    opt_cycles = as_float(avg_cycles.get("vedic", "N/A"))
    base_ns = as_float(avg_latency.get("baseline_seq", "N/A"))
    opt_ns = as_float(avg_latency.get("vedic", "N/A"))
    if None in (base_cycles, opt_cycles, base_ns, opt_ns):
        return False

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    fig.suptitle(f"Phase 3 Baseline Comparison ({board})", fontweight="bold")

    labels = ["Baseline", "Optimized"]
    cyc_values = [float(base_cycles), float(opt_cycles)]
    ns_values = [float(base_ns), float(opt_ns)]
    colors = ["#e74c3c", "#2ecc71"]

    bars0 = axes[0].bar(labels, cyc_values, color=colors, alpha=0.9)
    axes[0].set_ylabel("Latency (cycles)")
    axes[0].set_title("PCPI MUL Avg Cycles")
    axes[0].set_ylim(0, max(cyc_values) * 1.25)
    axes[0].grid(axis="y", alpha=0.3)
    for bar, val in zip(bars0, cyc_values):
        axes[0].text(bar.get_x() + bar.get_width() / 2, val + 0.5, f"{val:.1f}", ha="center", va="bottom", fontweight="bold")

    bars1 = axes[1].bar(labels, ns_values, color=colors, alpha=0.9)
    axes[1].set_ylabel("Latency (ns)")
    axes[1].set_title("PCPI MUL Avg Latency @ 100 MHz")
    axes[1].set_ylim(0, max(ns_values) * 1.25)
    axes[1].grid(axis="y", alpha=0.3)
    for bar, val in zip(bars1, ns_values):
        axes[1].text(bar.get_x() + bar.get_width() / 2, val + 1.0, f"{val:.1f}", ha="center", va="bottom", fontweight="bold")

    speedup = (base_cycles / opt_cycles) if opt_cycles and opt_cycles > 0 else None
    if speedup is not None:
        fig.text(0.5, 0.02, f"Speedup: {speedup:.2f}x", ha="center", va="bottom", fontsize=11, fontweight="bold", color="#3498db")

    fig.tight_layout(rect=[0, 0.05, 1, 0.95])
    fig.savefig(out_dir / "phase3_baseline_compare.png", bbox_inches="tight")
    plt.close(fig)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 3 charts from metrics CSV")
    parser.add_argument("--metrics-csv", required=True, help="Path to phase3_metrics.csv")
    parser.add_argument("--out-dir", required=True, help="Output directory for PNG files")
    args = parser.parse_args()

    metrics_csv = Path(args.metrics_csv).resolve()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    metrics = load_metrics(metrics_csv)
    pcpi_table = load_pcpi_summary(out_dir / "pcpi_summary.csv")

    board = metrics.get("board", "unknown")
    artifact_prefix = metrics.get("artifact_prefix", board)
    target_mhz = as_float(metrics.get("target_freq_mhz", "N/A")) or 0.0
    delay_ns = as_float(metrics.get("critical_path_delay_ns", "N/A"))
    fmax_mhz = as_float(metrics.get("estimated_fmax_mhz", "N/A"))
    cell_count = as_int(metrics.get("yosys_cell_count", "N/A"))
    module_count = as_int(metrics.get("json_module_count", "N/A"))

    baseline_log = out_dir / f"{board}.log"
    baseline_json = out_dir / f"{board}.json"
    if artifact_prefix == board:
        base_cells = None
        base_modules = None
    else:
        base_cells = parse_cells_from_log(baseline_log)
        base_modules = parse_module_count_from_json(baseline_json)

    plot_timing(out_dir, board, target_mhz, fmax_mhz, delay_ns)
    plot_resources(out_dir, board, cell_count, module_count, base_cells, base_modules)
    baseline_plotted = plot_baseline_compare(out_dir, board, pcpi_table)

    print(f"Wrote {out_dir / 'phase3_timing.png'}")
    print(f"Wrote {out_dir / 'phase3_resources.png'}")
    if baseline_plotted:
        print(f"Wrote {out_dir / 'phase3_baseline_compare.png'}")
    else:
        print(f"Skipped {out_dir / 'phase3_baseline_compare.png'} (missing/invalid pcpi_summary.csv)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
