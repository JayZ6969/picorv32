#!/usr/bin/env python3
"""Collect Phase 1 quality metrics (Q1-Q5) into synth/reports.

Inputs:
  - sim/logs/lint_ksa.log
  - sim/logs/lint_vedic.log
  - sim/logs/lint_pcpi.log
  - ../picorv32.v (for core diff/module checks)

Output:
  - synth/reports/phase1_quality_metrics.txt
"""

import subprocess
from pathlib import Path


def run(cmd: str):
    p = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return p.stdout.strip()


def count_in_logs(pattern: str, logs):
    total = 0
    for log in logs:
        p = Path(log)
        if not p.exists():
            continue
        text = p.read_text(errors="ignore")
        total += text.count(pattern)
    return total


def main():
    logs = [
        "sim/logs/lint_ksa.log",
        "sim/logs/lint_vedic.log",
        "sim/logs/lint_pcpi.log",
    ]

    q1 = count_in_logs("Warning", logs)
    q2 = count_in_logs("Error", logs)

    core_path = Path("../picorv32.v")
    core_text = core_path.read_text(errors="ignore") if core_path.exists() else ""

    # Q3 tracks whether fast-add related ALU edits are present in core RTL.
    q3_markers = [
        "ENABLE_FAST_ADD",
        "u_alu_add_ksa",
        "u_alu_sub_ksa",
        "alu_add_sum_fast",
        "alu_sub_sum_fast",
    ]
    q3 = sum(1 for marker in q3_markers if marker in core_text)

    # Q4 tracks mandatory core integration coverage from the updated plan:
    # (1) fast add path in ALU, (2) fast mul/PCPI integration path.
    has_fast_add_integration = (
        "ENABLE_FAST_ADD" in core_text and "ksa_adder" in core_text
    )
    has_fast_mul_integration = (
        "pcpi_vedic_mul" in core_text
        or ("ENABLE_FAST_MUL" in core_text and "pcpi_mul" in core_text)
    )

    q4 = int(has_fast_add_integration) + int(has_fast_mul_integration)

    # Undriven/dead code proxy from lint logs.
    dead_keywords = ["UNDRIVEN", "undriven", "UNUSED", "unused"]
    q5 = 0
    for log in logs:
        p = Path(log)
        if not p.exists():
            continue
        text = p.read_text(errors="ignore")
        for kw in dead_keywords:
            q5 += text.count(kw)

    out = Path("synth/reports/phase1_quality_metrics.txt")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        "\n".join(
            [
                f"Q1 Lint warnings:          {q1}   (target: 0)",
                f"Q2 Lint errors:            {q2}   (target: 0)",
                f"Q3 Core fast-add markers:  {q3}   (target: >=3)",
                f"Q4 Core module coverage:   {q4}   (target: >=2)",
                f"Q5 Dead code proxy count:  {q5}   (target: 0)",
            ]
        )
        + "\n"
    )

    print(out.read_text(), end="")


if __name__ == "__main__":
    main()
