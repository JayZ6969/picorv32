#!/usr/bin/env python3
"""Extract T1-T7 style timing metrics from PnR outputs."""

import csv
import json
import re
from pathlib import Path

CONFIGS = ["baseline_A", "baseline_B", "baseline_C", "baseline_C_ksa", "optimized"]
LABELS = {
    "baseline_A": "Baseline A  (Iterative MUL)",
    "baseline_B": "Baseline B  (Fast MUL/DSP)",
    "baseline_C": "Baseline C  (Core only)",
    "baseline_C_ksa": "Baseline C' (Core + KSA)",
    "optimized": "Optimized   (Vedic + KSA)",
}


def parse_icetime(path):
    out = {}
    p = Path(path)
    if not p.exists():
        return out

    text = p.read_text(errors="ignore")

    m = re.search(r"Max frequency.*?:\s*([\d.]+)\s*MHz", text)
    if m:
        out["T1_fmax_mhz"] = float(m.group(1))
        out["T1_fmax_source"] = "icetime"

    m = re.search(r"Total path delay:\s*([\d.]+)\s*ns", text)
    if m:
        out["T2_crit_path_ns"] = float(m.group(1))
    elif "T1_fmax_mhz" in out and out["T1_fmax_mhz"] > 0:
        out["T2_crit_path_ns"] = round(1000.0 / out["T1_fmax_mhz"], 3)

    m = re.search(r"Total number of logic levels:\s*(\d+)", text)
    if m:
        out["T7_logic_levels"] = int(m.group(1))
    else:
        m = re.search(r"(\d+)\s+logic levels", text)
        if m:
            out["T7_logic_levels"] = int(m.group(1))

    r = re.search(r"Resolvable net names on path:(.*?)(?:\n\n|\Z)", text, re.DOTALL)
    if r:
        lines = re.findall(r"^\s*[\d.]+\s+ns\s+\.\.\s+[\d.]+\s+ns\s+\S+", r.group(1), re.MULTILINE)
        if lines:
            out["T4_crit_path_nets"] = len(lines)
        first_net = re.search(r"^\s*[\d.]+\s+ns\s+\.\.\s+[\d.]+\s+ns\s+(\S+)", r.group(1), re.MULTILINE)
        if first_net:
            name = first_net.group(1)
            if "u_core.pcpi_mul.u_mul_abs" in name:
                out.setdefault("T3_crit_path_module", "vedic_mul_32x32")
            elif "u_core.pcpi_mul" in name:
                out.setdefault("T3_crit_path_module", "pcpi_vedic_mul")

    return out


def parse_nextpnr_json(path):
    out = {}
    p = Path(path)
    if not p.exists():
        return out

    try:
        data = json.loads(p.read_text())
    except Exception:
        return out

    fmax = data.get("fmax", {})
    for _, clk in fmax.items():
        achieved = float(clk.get("achieved", 0.0) or 0.0)
        constrained = float(clk.get("constraint", clk.get("constrained", 0.0)) or 0.0)
        if achieved > 0 and "T1_fmax_mhz" not in out:
            out["T1_fmax_mhz"] = achieved
            out["T1_fmax_source"] = "nextpnr_json"
        if constrained > 0:
            out["T1_fmax_constrained"] = constrained
            out["T5_timing_met"] = achieved >= constrained if achieved > 0 else False
            if achieved > 0:
                out["T5_setup_slack_ns"] = round(1000.0 / constrained - 1000.0 / achieved, 3)
        break

    return out


def parse_nextpnr_log(path):
    out = {}
    p = Path(path)
    if not p.exists():
        return out

    text = p.read_text(errors="ignore")

    # Extract an informative critical-path owner module from user RTL files.
    cp_section = re.search(
        r"Critical path report for clock.*?(?=Critical path report for cross-domain path|\Z)",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    cp_text = cp_section.group(0) if cp_section else text

    rtl_files = re.findall(r"rtl/[\w/.-]+\.v", cp_text)
    if rtl_files:
        priority = [
            "rtl/vedic/vedic_mul_32x32.v",
            "rtl/pcpi/pcpi_vedic_mul.v",
            "rtl/ksa/ksa_adder.v",
        ]
        chosen = None
        for p in priority:
            if p in rtl_files:
                chosen = p
                break
        if chosen is None:
            chosen = rtl_files[0]
        out["T3_crit_path_module"] = Path(chosen).stem

    if "T3_crit_path_module" not in out:
        m = re.search(r"Critical path.*?end:\s*(\S+)", text, re.IGNORECASE)
        if m:
            raw = m.group(1).replace("\\", "")
            parts = raw.split(".")
            out["T3_crit_path_module"] = parts[-2] if len(parts) > 1 else raw[:40]

    m = re.search(
        r"Max frequency for clock '.*?':\s*([\d.]+)\s*MHz\s*\((?:PASS|FAIL) at\s*([\d.]+)\s*MHz\)",
        text,
        re.IGNORECASE,
    )
    if m:
        achieved = float(m.group(1))
        target = float(m.group(2))
        out.setdefault("T1_fmax_mhz", achieved)
        out.setdefault("T1_fmax_source", "nextpnr_log")
        out.setdefault("T1_fmax_constrained", target)
        out.setdefault("T5_timing_met", achieved >= target)
        if achieved > 0:
            out.setdefault("T5_setup_slack_ns", round(1000.0 / target - 1000.0 / achieved, 3))

    m = re.search(r"(\d+)\s+nets? in critical path", text, re.IGNORECASE)
    if m:
        out["T4_crit_path_nets"] = int(m.group(1))
    else:
        r = re.search(r"Resolvable net names on path:(.*?)(?:\n\n|\Z)", cp_text, re.DOTALL)
        if r:
            lines = re.findall(r"^\s*[\d.]+\s+ns\s+\.\.\s+[\d.]+\s+ns\s+\S+", r.group(1), re.MULTILINE)
            if lines:
                out["T4_crit_path_nets"] = len(lines)

    if "hold" in text.lower():
        out["T6_hold_ok"] = "hold violation" not in text.lower()
    else:
        out["T6_hold_ok"] = True

    out["routing_failed"] = bool(
        re.search(
            r"routing failed|no route found|unable to find a placement location",
            text,
            re.IGNORECASE,
        )
    )
    return out


def parse_pnr_exit(path):
    p = Path(path)
    if not p.exists():
        return {}
    try:
        rc = int(p.read_text().strip())
    except Exception:
        return {}
    return {"routing_failed": rc != 0, "pnr_exit_code": rc}


def main():
    all_data = {}
    for cfg in CONFIGS:
        d = {"config": cfg, "label": LABELS[cfg]}
        d.update(parse_icetime(f"pnr/reports/{cfg}_timing.rpt"))
        d.update(parse_nextpnr_json(f"pnr/reports/{cfg}_report.json"))
        d.update(parse_nextpnr_log(f"pnr/reports/{cfg}_pnr_stdout.log"))
        d.update(parse_pnr_exit(f"pnr/reports/{cfg}_pnr.exit"))

        d.setdefault("routing_failed", False)
        d.setdefault("pnr_exit_code", 0)
        d.setdefault("T1_fmax_source", "none")
        d["timing_provisional"] = bool(
            d["routing_failed"] and d.get("T1_fmax_source") in ("nextpnr_log", "nextpnr_json")
        )

        all_data[cfg] = d

    print("\n" + "=" * 80)
    print("STAGE 3 - TIMING METRICS (T1-T7)")
    print("=" * 80)

    rows = [
        ("T1_fmax_mhz", "T1: Fmax (MHz)", "num"),
        ("T1_fmax_source", "T1: Fmax source", "str"),
        ("T2_crit_path_ns", "T2: Critical path (ns)", "num"),
        ("T3_crit_path_module", "T3: Crit path module", "str"),
        ("T4_crit_path_nets", "T4: Crit path nets", "int"),
        ("T5_setup_slack_ns", "T5: Setup slack (ns)", "num"),
        ("T6_hold_ok", "T6: Hold OK", "bool"),
        ("T7_logic_levels", "T7: Logic levels", "int"),
        ("T5_timing_met", "Timing met", "bool"),
        ("routing_failed", "Routing failed", "bool"),
        ("timing_provisional", "Timing provisional", "bool"),
        ("pnr_exit_code", "PnR exit code", "int"),
    ]

    print(f"\n  {'Metric':<30}", end="")
    for cfg in CONFIGS:
        print(f"{LABELS[cfg][:22]:>23}", end="")
    print()
    print("  " + "-" * 122)

    for key, label, kind in rows:
        print(f"  {label:<30}", end="")
        for cfg in CONFIGS:
            val = all_data[cfg].get(key)
            if val is None:
                cell = "-"
            elif kind == "bool":
                cell = "YES" if val else "NO"
            elif kind == "str":
                cell = str(val)[:22]
            elif kind == "int":
                cell = str(int(val))
            else:
                cell = f"{float(val):.3f}"
            print(f"{cell:>23}", end="")
        print()

    out_csv = Path("synth/reports/phase3_timing.csv")
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = ["config", "label"] + [k for k, _, _ in rows] + ["T1_fmax_constrained"]
    with out_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        for cfg in CONFIGS:
            w.writerow(all_data[cfg])

    print(f"\n  CSV: {out_csv}")
    print("=" * 80)


if __name__ == "__main__":
    main()
