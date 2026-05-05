#!/usr/bin/env python3
"""Generate a concise Phase 3 summary text report.

Inputs:
  - synth/reports/phase3_area_final.csv
  - synth/reports/phase3_timing.csv
  - synth/reports/phase3_composites.csv
  - synth/reports/master_metrics.csv

Output:
  - synth/reports/phase3_report_summary.txt
"""

import csv
from datetime import datetime
from pathlib import Path

MAX_PCPI_LATENCY_CYCLES = 4
FMAX_TARGET_MHZ = 18.0


def load_csv(path, key="config"):
    p = Path(path)
    if not p.exists():
        return {}
    with p.open(newline="") as f:
        return {r[key]: r for r in csv.DictReader(f) if key in r}


def to_int(v, default=0):
    try:
        return int(float(v))
    except Exception:
        return default


def to_float(v):
    try:
        if v in (None, ""):
            return None
        return float(v)
    except Exception:
        return None


def to_bool(v, default=False):
    if v in (None, ""):
        return default
    return str(v).strip().lower() in ("1", "true", "yes", "y")


def fmt_f(v, digits=2):
    if v is None:
        return "N/A"
    return f"{v:.{digits}f}"


def main():
    area = load_csv("synth/reports/phase3_area_final.csv")
    timing = load_csv("synth/reports/phase3_timing.csv")
    comps = load_csv("synth/reports/phase3_composites.csv")
    master = load_csv("synth/reports/master_metrics.csv")

    cfgs = ["baseline_A", "baseline_B", "baseline_C", "optimized"]

    lines = []
    lines.append("=" * 80)
    lines.append("PHASE 3 SUMMARY")
    lines.append(f"Generated: {datetime.now():%Y-%m-%d %H:%M:%S}")
    lines.append("=" * 80)
    lines.append("")

    lines.append("Artifacts")
    for p in [
        "synth/reports/phase3_area_final.csv",
        "synth/reports/phase3_timing.csv",
        "synth/reports/phase3_composites.csv",
        "synth/reports/master_metrics.csv",
    ]:
        exists = Path(p).exists()
        lines.append(f"  {'OK' if exists else 'MISSING'}  {p}")
    lines.append("")

    lines.append("Key Results")
    for cfg in cfgs:
        a = area.get(cfg, {})
        t = timing.get(cfg, {})
        l = a.get("label", cfg)
        luts = to_int(a.get("SB_LUT4"), 0)
        carry = to_int(a.get("SB_CARRY"), 0)
        bram = to_int(a.get("SB_RAM40_4K"), 0)
        fmax = to_float(t.get("T1_fmax_mhz"))
        routed = not to_bool(t.get("routing_failed"), False)
        rc = to_int(t.get("pnr_exit_code"), 0)
        lines.append(
            f"  {l:<30} LUT4={luts:<5} CARRY={carry:<5} BRAM={bram:<2} "
            f"Fmax={fmt_f(fmax, 2):>6} MHz  PnR={'OK' if routed else 'FAIL'} (rc={rc})"
        )
    lines.append("")

    lines.append("Composite Metrics (optimized)")
    oc = comps.get("optimized", {})
    lines.append(f"  cycles_per_MUL:   {oc.get('cycles_per_MUL', 'N/A')}")
    lines.append(f"  throughput_MOPS:  {oc.get('throughput_MOPS', 'N/A')}")
    lines.append(f"  E1_ADP:           {oc.get('E1_ADP', 'N/A')}")
    lines.append(f"  E2_ACP:           {oc.get('E2_ACP', 'N/A')}")
    lines.append(f"  E3_speedup_A:     {oc.get('E3_speedup_A', 'N/A')}")
    lines.append(f"  E4_speedup_B:     {oc.get('E4_speedup_B', 'N/A')}")
    lines.append(f"  E5_MOPS_LUT:      {oc.get('E5_MOPS_LUT', 'N/A')}")
    lines.append("")

    lines.append("Master Checks")
    mopt = master.get("optimized", {})
    mb = master.get("baseline_B", {})
    if mopt:
        lines.append(f"  Synthesis LUT4 <= 5280: {'PASS' if to_int(mopt.get('SB_LUT4'), 0) <= 5280 else 'FAIL'}")
        routed = not to_bool(mopt.get("routing_failed"), True)
        lines.append(f"  Optimized PnR succeeded: {'PASS' if routed else 'FAIL'}")
        fmax = to_float(mopt.get("Fmax_MHz"))
        fmax_ok = (fmax is not None) and (fmax >= 12.0) and routed
        lines.append(f"  Fmax >= 12 MHz (routed): {'PASS' if fmax_ok else 'FAIL'}")
        fmax_target_ok = (fmax is not None) and (fmax >= FMAX_TARGET_MHZ) and routed
        lines.append(
            f"  Fmax >= {int(FMAX_TARGET_MHZ)} MHz (target): {'PASS' if fmax_target_ok else 'FAIL'}"
        )
        lat = to_int(mopt.get("pcpi_latency"), 0)
        lat_ok = 0 < lat <= MAX_PCPI_LATENCY_CYCLES
        lines.append(
            f"  MUL latency <= {MAX_PCPI_LATENCY_CYCLES} cycles: {'PASS' if lat_ok else 'FAIL'}"
        )
        lines.append(f"  BRAM budget <= 2: {'PASS' if to_int(mopt.get('SB_RAM40_4K'), 99) <= 2 else 'FAIL'}")

        b_carry = to_int(mb.get("SB_CARRY"), 0)
        o_carry = to_int(mopt.get("SB_CARRY"), 0)
        carry_ok = b_carry > 0 and o_carry < b_carry
        lines.append(f"  KSA reduced SB_CARRY vs Baseline B: {'PASS' if carry_ok else 'FAIL'}")

        b_route_failed = to_bool(mb.get("routing_failed"), False)
        lines.append(
            "  Baseline B routing failure: "
            + ("INFO (expected at high LUT utilisation on UP5K)" if b_route_failed else "INFO (not observed)")
        )

        if mb.get("timing_note"):
            lines.append(f"  Baseline B note: {mb.get('timing_note')}")
        if mopt.get("timing_note"):
            lines.append(f"  Optimized note: {mopt.get('timing_note')}")
    else:
        lines.append("  MISSING optimized row in master_metrics.csv")

    out = Path("synth/reports/phase3_report_summary.txt")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")
    print(f"Phase 3 summary written: {out}")


if __name__ == "__main__":
    main()
