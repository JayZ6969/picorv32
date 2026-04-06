#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
from collections import Counter
import re
import shutil
import subprocess
from pathlib import Path


def read_pcpi_baseline(path: Path) -> tuple[str, str, str]:
    if not path.exists():
        return "N/A", "N/A", "N/A"

    with path.open("r", encoding="utf-8", newline="") as fp:
        reader = csv.DictReader(fp)
        for row in reader:
            if row.get("metric") == "avg_cycles":
                return row.get("baseline_seq", "N/A"), row.get("vedic", "N/A"), row.get("speedup", "N/A")
    return "N/A", "N/A", "N/A"


def run_and_capture(cmd: list[str], cwd: Path, log_path: Path) -> tuple[int, str]:
    proc = subprocess.run(cmd, cwd=str(cwd), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    output = proc.stdout or ""
    log_path.write_text(output, encoding="utf-8")
    return proc.returncode, output


def run_verilator_lint(root: Path, out_dir: Path) -> tuple[str, int, int]:
    if shutil.which("verilator") is None:
        return "tool-missing", -1, -1

    cmd = [
        "verilator",
        "--lint-only",
        "-Wno-fatal",
        "-Wall",
        "-Wno-DECLFILENAME",
        "-Wno-MULTITOP",
        str(root / "picorv32.v"),
        str(root / "opt/rtl/ksa.v"),
        str(root / "opt/rtl/vedic_mul_32.v"),
        str(root / "opt/rtl/picorv32_pcpi_vedic_mul.v"),
    ]
    rc, text = run_and_capture(cmd, root, out_dir / "phase4_verilator_lint.log")
    err_count = len(re.findall(r"%Error-[A-Za-z0-9_]+:", text))
    warn_count = len(re.findall(r"%Warning-[A-Za-z0-9_]+:", text))
    if err_count > 0:
        status = "fail"
    elif warn_count > 0:
        status = "warn"
    else:
        status = "pass"
    return status, err_count, warn_count


def extract_warning_classes(log_text: str) -> Counter[str]:
    classes = re.findall(r"%Warning-([A-Za-z0-9_]+):", log_text)
    return Counter(classes)


def load_waiver_classes(path: Path) -> set[str]:
    if not path.exists():
        return set()
    waivers: set[str] = set()
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        waivers.add(line)
    return waivers


def write_lint_breakdown(path: Path, warn_counts: Counter[str], waiver_classes: set[str]) -> tuple[int, int]:
    total = sum(warn_counts.values())
    unwaived = 0
    rows: list[tuple[str, int, str]] = []
    for cls, count in sorted(warn_counts.items(), key=lambda item: (-item[1], item[0])):
        waived = "yes" if cls in waiver_classes else "no"
        if waived == "no":
            unwaived += count
        rows.append((cls, count, waived))

    with path.open("w", encoding="utf-8", newline="") as fp:
        writer = csv.writer(fp)
        writer.writerow(["warning_class", "count", "waived"])
        writer.writerows(rows)

    return total, unwaived


def run_yosys_check(root: Path, out_dir: Path) -> tuple[str, int, int]:
    if shutil.which("yosys") is None:
        return "tool-missing", -1, -1

    script = " ; ".join(
        [
            f"read_verilog -sv {root / 'picorv32.v'} {root / 'opt/rtl/ksa.v'} {root / 'opt/rtl/vedic_mul_32.v'} {root / 'opt/rtl/picorv32_pcpi_vedic_mul.v'}",
            "prep -top picorv32",
            "check -assert",
            "stat",
        ]
    )
    rc, text = run_and_capture(["yosys", "-p", script], root, out_dir / "phase4_yosys_check.log")

    warn_count = len(re.findall(r"^Warning:", text, flags=re.MULTILINE))
    m = re.search(r"Number of cells:\s*([0-9]+)", text)
    cell_count = int(m.group(1)) if m else -1
    status = "pass" if rc == 0 else "fail"
    return status, warn_count, cell_count


def cdc_single_clock_proxy(root: Path) -> tuple[str, str]:
    src = (root / "picorv32.v").read_text(encoding="utf-8", errors="ignore")

    top_match = re.search(r"module\s+picorv32\b(.*?)endmodule", src, flags=re.DOTALL)
    top_src = top_match.group(1) if top_match else src

    clocks = set(re.findall(r"posedge\s+([A-Za-z_][A-Za-z0-9_]*)", top_src))
    clocks = {c for c in clocks if "reset" not in c.lower()}
    if len(clocks) <= 1:
        return "pass-proxy", f"single-clock-domain ({next(iter(clocks), 'clk')})"
    return "needs-cdc-tool", f"multiple clocks detected: {', '.join(sorted(clocks))}"


def formal_reference_proxy(root: Path) -> tuple[str, str]:
    table = root / "opt/results/phase2/table1_verification.csv"
    if not table.exists():
        return "needs-formal-tool", "phase2 formal table missing"

    with table.open("r", encoding="utf-8", newline="") as fp:
        for row in csv.DictReader(fp):
            suite = row.get("Test Suite", "")
            if "GF(2) formal algebra" in suite:
                passed = row.get("Passed", "0").strip()
                failed = row.get("Failed", "0").strip()
                if failed == "0" and passed != "0":
                    return "pass-reference", f"phase2 GF(2) passed={passed}, failed={failed}"
                return "needs-formal-tool", f"phase2 GF(2) incomplete (passed={passed}, failed={failed})"
    return "needs-formal-tool", "phase2 GF(2) row not found"


def write_csv(path: Path, rows: list[tuple[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as fp:
        writer = csv.writer(fp)
        writer.writerow(["metric", "value"])
        writer.writerows(rows)


def write_summary(path: Path, rows: dict[str, str], blockers: list[str]) -> None:
    lines = [
        "# Phase 4 Summary",
        "",
        "## Pre-ASIC Sign-off Metrics (Measured)",
        f"- Verilator lint status: {rows['lint_status']}",
        f"- Verilator lint errors: {rows['lint_errors']}",
        f"- Verilator lint warnings (total): {rows['lint_warnings_total']}",
        f"- Verilator lint warnings (unwaived): {rows['lint_warnings_unwaived']}",
        f"- Yosys check status: {rows['yosys_check_status']}",
        f"- Yosys check warnings: {rows['yosys_check_warnings']}",
        f"- Yosys cell count: {rows['yosys_cell_count']}",
        f"- CDC status: {rows['cdc_status']} ({rows['cdc_note']})",
        f"- Formal status: {rows['formal_status']} ({rows['formal_note']})",
        f"- Constraints status: {rows['constraints_status']}",
        f"- Readiness status: {rows['readiness_status']}",
        "",
        "## Baseline Comparison Reference",
        f"- Baseline avg cycles: {rows['baseline_avg_cycles']}",
        f"- Optimized avg cycles: {rows['optimized_avg_cycles']}",
        f"- Speedup: {rows['baseline_speedup']}",
        "",
        "## Logs",
        "- phase4_verilator_lint.log",
        "- phase4_yosys_check.log",
        "- phase4_lint_warning_breakdown.csv",
    ]

    if blockers:
        lines.extend(["", "## Blockers"])
        lines.extend([f"- {b}" for b in blockers])

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Phase 4 summary artifacts")
    parser.add_argument("--baseline-csv", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--root", required=True)
    args = parser.parse_args()

    out_dir = Path(args.out_dir).resolve()
    root = Path(args.root).resolve()
    baseline_csv = Path(args.baseline_csv).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    base_cycles, opt_cycles, speedup = read_pcpi_baseline(baseline_csv)
    lint_status_raw, lint_errors, _ = run_verilator_lint(root, out_dir)
    yosys_status, yosys_warnings, yosys_cells = run_yosys_check(root, out_dir)

    lint_log_text = (out_dir / "phase4_verilator_lint.log").read_text(encoding="utf-8", errors="ignore")
    warning_classes = extract_warning_classes(lint_log_text)
    waiver_classes = load_waiver_classes(root / "opt/phase4/lint_waivers.txt")
    lint_warnings_total, lint_warnings_unwaived = write_lint_breakdown(
        out_dir / "phase4_lint_warning_breakdown.csv",
        warning_classes,
        waiver_classes,
    )

    if lint_errors > 0:
        lint_status = "fail"
    elif lint_warnings_unwaived > 0:
        lint_status = "warn"
    else:
        lint_status = "pass"

    cdc_status, cdc_note = cdc_single_clock_proxy(root)
    formal_status, formal_note = formal_reference_proxy(root)
    constraints_status = "present" if any(root.glob("scripts/quartus/*.sdc")) else "missing"

    blockers: list[str] = []
    if lint_status_raw == "tool-missing":
        blockers.append("Verilator not installed (cannot run lint).")
    elif lint_status == "fail":
        blockers.append(f"Verilator lint has {lint_errors} error(s).")
    elif lint_status == "warn":
        blockers.append(f"Verilator lint has {lint_warnings_unwaived} unwaived warning(s); needs waiver/cleanup for sign-off.")
    if yosys_status == "tool-missing":
        blockers.append("Yosys not installed (cannot run structural checks).")
    if cdc_status != "pass-proxy":
        blockers.append("CDC closure requires dedicated CDC tool for multi-clock analysis.")
    if formal_status != "pass-reference":
        blockers.append("Formal sign-off reference missing/incomplete.")

    readiness_status = "pending"
    if lint_status == "pass" and yosys_status == "pass" and cdc_status == "pass-proxy" and formal_status == "pass-reference" and constraints_status == "present" and not blockers:
        readiness_status = "ready"

    rows = [
        ("phase", "4"),
        ("lint_status", lint_status),
        ("lint_errors", str(lint_errors if lint_errors >= 0 else "N/A")),
        ("lint_warnings_total", str(lint_warnings_total)),
        ("lint_warnings_unwaived", str(lint_warnings_unwaived)),
        ("yosys_check_status", yosys_status),
        ("yosys_check_warnings", str(yosys_warnings if yosys_warnings >= 0 else "N/A")),
        ("yosys_cell_count", str(yosys_cells if yosys_cells >= 0 else "N/A")),
        ("cdc_status", cdc_status),
        ("cdc_note", cdc_note),
        ("formal_status", formal_status),
        ("formal_note", formal_note),
        ("constraints_status", constraints_status),
        ("baseline_avg_cycles", base_cycles),
        ("optimized_avg_cycles", opt_cycles),
        ("baseline_speedup", speedup),
        ("readiness_status", readiness_status),
    ]

    write_csv(out_dir / "phase4_metrics.csv", rows)
    row_dict = {k: v for k, v in rows}
    write_summary(out_dir / "phase4_summary.md", row_dict, blockers)

    print(f"Wrote {out_dir / 'phase4_metrics.csv'}")
    print(f"Wrote {out_dir / 'phase4_summary.md'}")
    print(f"Wrote {out_dir / 'phase4_verilator_lint.log'}")
    print(f"Wrote {out_dir / 'phase4_yosys_check.log'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
