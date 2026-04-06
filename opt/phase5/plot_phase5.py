#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import shutil
from pathlib import Path

import matplotlib
import numpy as np

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


def load_ppa_compare(path: Path) -> dict[str, tuple[str, str]]:
    out: dict[str, tuple[str, str]] = {}
    if not path.exists():
        return out
    with path.open("r", encoding="utf-8", newline="") as fp:
        for row in csv.DictReader(fp):
            metric = row.get("metric")
            baseline = row.get("baseline")
            optimized = row.get("optimized")
            if metric and baseline is not None and optimized is not None:
                out[metric] = (baseline, optimized)
    return out


def plot_signoff_status(out_dir: Path, metrics: dict[str, str]) -> None:
    labels = ["DRC", "LVS", "IR", "EM"]
    raw_vals = [
        metrics.get("drc_violations", "N/A"),
        metrics.get("lvs_violations", "N/A"),
        metrics.get("ir_violations", "N/A"),
        metrics.get("em_violations", "N/A"),
    ]
    parsed_vals = [to_float(v) for v in raw_vals]
    has_any_numeric = any(v is not None for v in parsed_vals)

    if has_any_numeric:
        vals = [v if v is not None else 0.0 for v in parsed_vals]
        ylabel = "Violation Count"
        title = "Phase 5 Physical Sign-off Status"
        subtitle = None
        colors = ["#e74c3c", "#f39c12", "#8e44ad", "#2980b9"]
    else:
        vals = [1.0 for _ in raw_vals]
        ylabel = "Pending metrics"
        title = "Phase 5 Physical Sign-off Status (Pending Data)"
        subtitle = "Populate phase5_metrics.csv with DRC/LVS/IR/EM counts"
        colors = ["#bdc3c7", "#bdc3c7", "#bdc3c7", "#bdc3c7"]

    fig, ax = plt.subplots(figsize=(8, 5))
    bars = ax.bar(labels, vals, color=colors, alpha=0.9)
    if not has_any_numeric:
        for bar in bars:
            bar.set_hatch("//")
    ax.set_title(title)
    ax.set_ylabel(ylabel)
    ax.grid(axis="y", alpha=0.3)
    ax.set_ylim(0, max(vals + [1.0]) * 1.3)
    if subtitle:
        ax.text(0.5, 0.98, subtitle, transform=ax.transAxes, ha="center", va="top", fontsize=9)

    for bar, raw in zip(bars, raw_vals):
        y = bar.get_height()
        ax.text(bar.get_x() + bar.get_width() / 2, y + 0.2, raw, ha="center", va="bottom", fontweight="bold")

    fig.tight_layout()
    fig.savefig(out_dir / "phase5_signoff_status.png", bbox_inches="tight")
    plt.close(fig)


def plot_ppa_overview(out_dir: Path, metrics: dict[str, str], compare: dict[str, tuple[str, str]]) -> None:
    labels = ["Setup slack ns", "Hold slack ns", "Power mW", "Area um^2"]
    raw_baseline = [
        compare.get("setup_slack_ns", (metrics.get("setup_slack_ns", "N/A"), metrics.get("setup_slack_ns", "N/A")))[0],
        compare.get("hold_slack_ns", (metrics.get("hold_slack_ns", "N/A"), metrics.get("hold_slack_ns", "N/A")))[0],
        compare.get("total_power_mw", (metrics.get("total_power_mw", "N/A"), metrics.get("total_power_mw", "N/A")))[0],
        compare.get("core_area_um2", (metrics.get("core_area_um2", "N/A"), metrics.get("core_area_um2", "N/A")))[0],
    ]
    raw_optimized = [
        compare.get("setup_slack_ns", (metrics.get("setup_slack_ns", "N/A"), metrics.get("setup_slack_ns", "N/A")))[1],
        compare.get("hold_slack_ns", (metrics.get("hold_slack_ns", "N/A"), metrics.get("hold_slack_ns", "N/A")))[1],
        compare.get("total_power_mw", (metrics.get("total_power_mw", "N/A"), metrics.get("total_power_mw", "N/A")))[1],
        compare.get("core_area_um2", (metrics.get("core_area_um2", "N/A"), metrics.get("core_area_um2", "N/A")))[1],
    ]

    baseline_vals = [to_float(v) for v in raw_baseline]
    optimized_vals = [to_float(v) for v in raw_optimized]
    has_any_numeric = any(v is not None for v in baseline_vals + optimized_vals)

    if has_any_numeric:
        bvals = [v if v is not None else 0.0 for v in baseline_vals]
        ovals = [v if v is not None else 0.0 for v in optimized_vals]
        ylabel = "Value"
        title = "Phase 5 PPA Overview (Baseline vs Optimized)"
        subtitle = None
    else:
        bvals = [1.0 for _ in labels]
        ovals = [1.0 for _ in labels]
        ylabel = "Pending metrics"
        title = "Phase 5 PPA Overview (Pending Data)"
        subtitle = "Populate phase5_ppa_compare.csv or phase5_metrics.csv with setup/hold/power/area values"

    x = np.arange(len(labels))
    width = 0.36
    fig, ax = plt.subplots(figsize=(11, 5))
    bars_b = ax.bar(x - width / 2, bvals, width, label="Baseline", color="#4f6ea8", alpha=0.9)
    bars_o = ax.bar(x + width / 2, ovals, width, label="Optimized", color="#2ca66f", alpha=0.9)
    if not has_any_numeric:
        for bar in list(bars_b) + list(bars_o):
            bar.set_hatch("//")
    ax.set_title(title)
    ax.set_ylabel(ylabel)
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.grid(axis="y", alpha=0.3)
    ax.legend(loc="upper right")
    ax.set_ylim(0, max(bvals + ovals + [1.0]) * 1.3)
    if subtitle:
        ax.text(0.5, 0.98, subtitle, transform=ax.transAxes, ha="center", va="top", fontsize=9)

    for bar, raw in zip(bars_b, raw_baseline):
        y = bar.get_height()
        ax.text(bar.get_x() + bar.get_width() / 2, y + 0.2, raw, ha="center", va="bottom", fontsize=8)
    for bar, raw in zip(bars_o, raw_optimized):
        y = bar.get_height()
        ax.text(bar.get_x() + bar.get_width() / 2, y + 0.2, raw, ha="center", va="bottom", fontsize=8)

    fig.tight_layout()
    fig.savefig(out_dir / "phase5_ppa_overview.png", bbox_inches="tight")
    plt.close(fig)


def plot_chip_preview(out_dir: Path) -> bool:
    gds_render = out_dir / "phase5_chip_gds_render.png"
    if gds_render.exists():
        shutil.copyfile(gds_render, out_dir / "phase5_chip_preview.png")
        shutil.copyfile(gds_render, out_dir / "phase5_chip_photo.png")
        return True

    blocks_csv = out_dir / "phase5_chip_blocks.csv"
    if not blocks_csv.exists():
        return False

    rows: list[tuple[str, int]] = []
    with blocks_csv.open("r", encoding="utf-8", newline="") as fp:
        for row in csv.DictReader(fp):
            try:
                rows.append((row["module"], int(row["cell_count"])))
            except (KeyError, ValueError):
                continue
    if not rows:
        return False

    total = sum(v for _, v in rows)
    if total <= 0:
        return False

    fig, ax = plt.subplots(figsize=(10, 6))
    ax.set_title("Phase 5 Chip Layout Preview (Conceptual, Netlist-Based)")
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 60)
    ax.axis("off")

    die_x, die_y, die_w, die_h = 5, 5, 90, 50
    die = plt.Rectangle((die_x, die_y), die_w, die_h, fill=False, linewidth=2.0, edgecolor="black")
    ax.add_patch(die)

    cursor = die_x
    colors = ["#3498db", "#2ecc71", "#9b59b6", "#e67e22", "#1abc9c", "#f1c40f", "#e74c3c", "#95a5a6"]
    for idx, (name, cells) in enumerate(rows[:10]):
        width = die_w * (cells / total)
        if width < 2.0:
            continue
        rect = plt.Rectangle((cursor, die_y), width, die_h, color=colors[idx % len(colors)], alpha=0.75, ec="white", lw=1.0)
        ax.add_patch(rect)
        label = f"{name} ({cells})"
        ax.text(cursor + width / 2, die_y + die_h / 2, label, ha="center", va="center", fontsize=8, rotation=90)
        cursor += width

    ax.text(
        50,
        1.5,
        "Not a real GDS render: this is a conceptual area partition from synthesized module cell counts",
        ha="center",
        va="bottom",
        fontsize=9,
    )

    fig.tight_layout()
    fig.savefig(out_dir / "phase5_chip_preview.png", bbox_inches="tight")
    fig.savefig(out_dir / "phase5_chip_photo.png", bbox_inches="tight")
    plt.close(fig)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 5 plots")
    parser.add_argument("--metrics-csv", required=True)
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()

    out_dir = Path(args.out_dir).resolve()
    metrics_csv = Path(args.metrics_csv).resolve()

    metrics = load_metrics(metrics_csv)
    plot_signoff_status(out_dir, metrics)
    compare = load_ppa_compare(out_dir / "phase5_ppa_compare.csv")
    plot_ppa_overview(out_dir, metrics, compare)
    has_chip_preview = plot_chip_preview(out_dir)

    print(f"Wrote {out_dir / 'phase5_signoff_status.png'}")
    print(f"Wrote {out_dir / 'phase5_ppa_overview.png'}")
    if has_chip_preview:
        print(f"Wrote {out_dir / 'phase5_chip_preview.png'}")
        print(f"Wrote {out_dir / 'phase5_chip_photo.png'}")
    else:
        print(f"Skipped {out_dir / 'phase5_chip_preview.png'} (missing phase5_chip_blocks.csv)")
        print(f"Skipped {out_dir / 'phase5_chip_photo.png'} (missing phase5_chip_blocks.csv)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
