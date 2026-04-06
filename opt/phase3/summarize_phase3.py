#!/usr/bin/env python3
"""
Phase 3 summary generator for FPGA synthesis and functional verification.

Inputs (from picosoc flow):
  - <board>.rpt (icetime timing report)
  - <board>.json (post-synth netlist metadata)
  - <board>.log (yosys synthesis log)

Outputs:
  - phase3_metrics.csv
  - phase3_summary.md

Usage:
  python summarize_phase3.py --board icebreaker --picosoc-dir ../../picosoc --out-dir ../results/phase3/icebreaker
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Optional


def parse_timing(rpt_path: Path) -> tuple[Optional[float], Optional[float]]:
    if not rpt_path.exists():
        return None, None

    text = rpt_path.read_text(encoding="utf-8", errors="ignore")

    delay_ns = None
    fmax_mhz = None

    delay_patterns = [
        r"Total path delay:\s*([0-9]+(?:\.[0-9]+)?)\s*ns",
        r"Critical path:\s*([0-9]+(?:\.[0-9]+)?)\s*ns",
    ]
    fmax_patterns = [
        r"([0-9]+(?:\.[0-9]+)?)\s*MHz",
        r"fmax\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*MHz",
    ]

    for pattern in delay_patterns:
        m = re.search(pattern, text, flags=re.IGNORECASE)
        if m:
            delay_ns = float(m.group(1))
            break

    for pattern in fmax_patterns:
        m = re.search(pattern, text, flags=re.IGNORECASE)
        if m:
            fmax_mhz = float(m.group(1))
            break

    if delay_ns is not None and fmax_mhz is None and delay_ns > 0:
        fmax_mhz = 1000.0 / delay_ns

    return delay_ns, fmax_mhz


def parse_yosys_cells(log_path: Path) -> Optional[int]:
    if not log_path.exists():
        return None

    text = log_path.read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"Number of cells:\s*([0-9]+)", text)
    if m:
        return int(m.group(1))
    return None


def parse_json_module_count(json_path: Path) -> Optional[int]:
    if not json_path.exists():
        return None

    try:
        data = json.loads(json_path.read_text(encoding="utf-8", errors="ignore"))
    except json.JSONDecodeError:
        return None

    modules = data.get("modules", {})
    return len(modules) if isinstance(modules, dict) else None


def write_metrics_csv(out_csv: Path, rows: list[tuple[str, str]]) -> None:
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.writer(fp)
        writer.writerow(["metric", "value"])
        writer.writerows(rows)


def write_summary_md(
    out_md: Path,
    board: str,
    target_freq_mhz: float,
    delay_ns: Optional[float],
    fmax_mhz: Optional[float],
    cell_count: Optional[int],
    module_count: Optional[int],
) -> None:
    timing_status = "UNKNOWN"
    if fmax_mhz is not None:
        timing_status = "PASS" if fmax_mhz >= target_freq_mhz else "FAIL"

    lines = [
        f"# Phase 3 Summary ({board})",
        "",
        "## Synthesis / Timing",
        f"- Target frequency: {target_freq_mhz:.2f} MHz",
        f"- Critical path delay: {delay_ns:.3f} ns" if delay_ns is not None else "- Critical path delay: N/A",
        f"- Estimated Fmax: {fmax_mhz:.3f} MHz" if fmax_mhz is not None else "- Estimated Fmax: N/A",
        f"- Timing status vs target: {timing_status}",
        "",
        "## Netlist / Resource Indicators",
        f"- Yosys top-level cell count: {cell_count}" if cell_count is not None else "- Yosys top-level cell count: N/A",
        f"- JSON module count: {module_count}" if module_count is not None else "- JSON module count: N/A",
        "",
        "## Functional Verification Checklist (Hardware)",
        "- [ ] FPGA programmed successfully",
        "- [ ] UART heartbeat observed",
        "- [ ] Smoke firmware output captured",
        "- [ ] MUL/MULH/MULHU/MULHSU behavior verified",
        "- [ ] 30-minute stability run passed",
    ]

    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 3 FPGA summary artifacts")
    parser.add_argument("--board", required=True, choices=["icebreaker", "hx8kdemo"])
    parser.add_argument(
        "--artifact-prefix",
        default=None,
        help="Artifact filename prefix (defaults to board name, e.g. icebreaker_fit)",
    )
    parser.add_argument("--picosoc-dir", required=True, help="Path to picosoc directory")
    parser.add_argument("--out-dir", required=True, help="Output directory for phase 3 summary artifacts")
    parser.add_argument("--target-mhz", type=float, default=12.0, help="Target clock frequency in MHz")
    args = parser.parse_args()

    picosoc_dir = Path(args.picosoc_dir).resolve()
    out_dir = Path(args.out_dir).resolve()
    artifact_prefix = args.artifact_prefix or args.board

    rpt_path = picosoc_dir / f"{artifact_prefix}.rpt"
    log_path = picosoc_dir / f"{artifact_prefix}.log"
    json_path = picosoc_dir / f"{artifact_prefix}.json"

    delay_ns, fmax_mhz = parse_timing(rpt_path)
    cell_count = parse_yosys_cells(log_path)
    module_count = parse_json_module_count(json_path)

    rows = [
        ("board", args.board),
        ("artifact_prefix", artifact_prefix),
        ("target_freq_mhz", f"{args.target_mhz:.3f}"),
        ("critical_path_delay_ns", f"{delay_ns:.6f}" if delay_ns is not None else "N/A"),
        ("estimated_fmax_mhz", f"{fmax_mhz:.6f}" if fmax_mhz is not None else "N/A"),
        ("timing_met", "yes" if (fmax_mhz is not None and fmax_mhz >= args.target_mhz) else "no"),
        ("yosys_cell_count", str(cell_count) if cell_count is not None else "N/A"),
        ("json_module_count", str(module_count) if module_count is not None else "N/A"),
    ]

    write_metrics_csv(out_dir / "phase3_metrics.csv", rows)
    write_summary_md(
        out_dir / "phase3_summary.md",
        args.board,
        args.target_mhz,
        delay_ns,
        fmax_mhz,
        cell_count,
        module_count,
    )

    print(f"Wrote {out_dir / 'phase3_metrics.csv'}")
    print(f"Wrote {out_dir / 'phase3_summary.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
