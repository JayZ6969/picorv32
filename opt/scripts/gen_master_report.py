#!/usr/bin/env python3
"""Generate consolidated Phase 3 master report and master CSV."""

import csv
import re
from datetime import datetime
from pathlib import Path

CONFIGS = ["baseline_A", "baseline_B", "baseline_C", "optimized"]
LABELS = {
    "baseline_A": "Baseline A  (Iterative MUL)",
    "baseline_B": "Baseline B  (Fast MUL/DSP)",
    "baseline_C": "Baseline C  (Core only)",
    "optimized": "Optimized   (Vedic + KSA)",
}
MAX_PCPI_LATENCY_CYCLES = 8
FMAX_TARGET_MHZ = 18.0


def load_csv(path, key="config"):
    p = Path(path)
    if not p.exists():
        return {}
    with p.open(newline="") as f:
        return {r[key]: r for r in csv.DictReader(f) if key in r}


def sf(d, k, default=0.0):
    try:
        return float(d.get(k) or default)
    except Exception:
        return default


def sfn(d, k):
    v = d.get(k)
    if v in (None, ""):
        return None
    try:
        return float(v)
    except Exception:
        return None


def si(d, k, default=0):
    try:
        return int(float(d.get(k) or default))
    except Exception:
        return default


def sb(d, k, default=False):
    v = d.get(k)
    if v in (None, ""):
        return default
    if isinstance(v, bool):
        return v
    return str(v).strip().lower() in ("1", "true", "yes", "y")


def get_metric(path, metric):
    if not path:
        return None
    p = Path(path)
    if not p.exists():
        return None
    text = p.read_text(errors="ignore")
    m = re.search(rf"METRIC\s+{re.escape(metric)}\s+([\d.]+)", text)
    return float(m.group(1)) if m else None


def get_switching(cfg):
    path = Path(f"synth/reports/{cfg}_switching.txt")
    if not path.exists():
        return None
    text = path.read_text(errors="ignore")
    m = re.search(r"Total signal transitions:\s*(\d+)", text)
    if m:
        return int(m.group(1))
    m = re.search(r"METRIC\s+switching_transitions\s+(\d+)", text)
    return int(m.group(1)) if m else None


def pct_delta(new, old):
    if new is None or old in (None, 0):
        return None
    return (new - old) * 100.0 / old


def fmt_fmax(v):
    return "N/A" if v is None else f"{v:.1f}"


def write_text(path, lines):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("\n".join(lines).rstrip() + "\n")


def count_token(path, token):
    p = Path(path)
    if not p.exists():
        return None
    return p.read_text(errors="ignore").count(token)


def extract_yosys_version(log_text):
    m = re.search(r"^\s*(Yosys\s+[^\n]+)", log_text, flags=re.MULTILINE)
    return m.group(1).strip() if m else "unknown"


def write_phase3_diagnostics(master):
    b_b = master.get("baseline_B", {})
    opt = master.get("optimized", {})

    # A1: Baseline B routing status note.
    b_util = b_b.get("LUT_util_pct", 0)
    b_route = "FAIL" if b_b.get("routing_failed", True) else "OK"
    write_text(
        "synth/reports/baseline_B_pnr_note.txt",
        [
            "NOTE: Baseline B (ENABLE_FAST_MUL=1) on iCE40UP5K routing diagnostics.",
            f"PnR status: {b_route}",
            f"LUT utilisation: {b_util:.1f}%",
            "Expected interpretation: if routing fails near saturation, this is an expected device-limit result,",
            "not a project defect in optimized RTL.",
        ],
    )

    # A2: DSP mapping diagnosis for Baseline B.
    b_log = Path("synth/reports/baseline_B_yosys_full.log")
    b_log_text = b_log.read_text(errors="ignore") if b_log.exists() else ""
    yosys_ver = extract_yosys_version(b_log_text)
    dsp_pass_seen = bool(re.search(r"ice40_dsp", b_log_text, flags=re.IGNORECASE))
    sb_mac16_log_hits = len(re.findall(r"SB_MAC16", b_log_text, flags=re.IGNORECASE))
    sb_mac16_area = int(b_b.get("SB_MAC16", 0) or 0)
    write_text(
        "synth/reports/dsp_mapping_note.txt",
        [
            "NOTE: Baseline B DSP mapping diagnosis.",
            f"Yosys version (from log): {yosys_ver}",
            f"ice40_dsp pass mentioned in log: {'YES' if dsp_pass_seen else 'NO'}",
            f"SB_MAC16 mentions in baseline_B_yosys_full.log: {sb_mac16_log_hits}",
            f"SB_MAC16 count in reports (phase3/master): {sb_mac16_area}",
            "Interpretation: SB_MAC16=0 means fast_mul is currently mapped into LUT/carry resources on this flow.",
        ],
    )

    # A3: BRAM mismatch diagnosis note.
    b_ram = int(master.get("baseline_A", {}).get("SB_RAM40_4K", 0) or 0)
    o_ram = int(opt.get("SB_RAM40_4K", 0) or 0)
    b_json_cnt = count_token("synth/baseline_A/design.json", "SB_RAM40_4K")
    o_json_cnt = count_token("synth/optimized/design.json", "SB_RAM40_4K")
    write_text(
        "synth/reports/bram_mismatch_note.txt",
        [
            "NOTE: BRAM count mismatch diagnostics.",
            f"Reported SB_RAM40_4K baseline_A: {b_ram}",
            f"Reported SB_RAM40_4K optimized: {o_ram}",
            f"Token count in synth/baseline_A/design.json: {b_json_cnt if b_json_cnt is not None else 'missing file'}",
            f"Token count in synth/optimized/design.json: {o_json_cnt if o_json_cnt is not None else 'missing file'}",
            "Interpretation: count differences reflect synthesis/memory-mapping choices and should be reviewed before netlist freeze.",
        ],
    )


def main():
    area = load_csv("synth/reports/phase3_area_final.csv")
    timing = load_csv("synth/reports/phase3_timing.csv")
    comps = load_csv("synth/reports/phase3_composites.csv")

    perf_logs = {
        "baseline_A": "sim/logs/integration_baseline_A_mul.log",
        "baseline_B": "sim/logs/integration_baseline_B_mul.log",
        "baseline_C": None,
        "optimized": "sim/logs/integration_optimized_mul.log",
    }

    master = {}
    for cfg in CONFIGS:
        a = area.get(cfg, {})
        t = timing.get(cfg, {})
        c = comps.get(cfg, {})

        luts = si(a, "SB_LUT4")
        fmax = sfn(t, "T1_fmax_mhz")
        routing_failed = sb(t, "routing_failed", False)
        lut_util = round(luts / 5280 * 100.0, 1) if luts else 0

        timing_note = ""
        if routing_failed:
            timing_note = f"Routing failed - device over-utilized at {lut_util:.1f}% LUT"
            if cfg == "baseline_B":
                timing_note += " (expected for fast_mul baseline on UP5K)"
        elif fmax is None:
            timing_note = "No routed Fmax available"

        master[cfg] = {
            "label": LABELS[cfg],
            "SB_LUT4": luts,
            "SB_DFF": si(a, "SB_DFF"),
            "SB_CARRY": si(a, "SB_CARRY"),
            "SB_MAC16": si(a, "SB_MAC16"),
            "SB_RAM40_4K": si(a, "SB_RAM40_4K"),
            "LUT_util_pct": lut_util,
            "Fmax_MHz": fmax,
            "fmax_source": t.get("T1_fmax_source", "none"),
            "timing_provisional": sb(t, "timing_provisional", False),
            "routing_failed": routing_failed,
            "timing_note": timing_note,
            "pnr_exit_code": si(t, "pnr_exit_code", 0),
            "crit_path_ns": sfn(t, "T2_crit_path_ns"),
            "crit_module": t.get("T3_crit_path_module", "-"),
            "setup_slack_ns": sfn(t, "T5_setup_slack_ns"),
            "timing_met": sb(t, "T5_timing_met", False),
            "logic_levels": si(t, "T7_logic_levels"),
            "total_cycles": get_metric(perf_logs[cfg], "total_cycles"),
            "stall_cycles": get_metric(perf_logs[cfg], "stall_cycles"),
            "stall_pct": get_metric(perf_logs[cfg], "stall_pct"),
            "eff_ipc": get_metric(perf_logs[cfg], "effective_ipc"),
            "pcpi_latency": sfn(c, "cycles_per_MUL") if c else None,
            "throughput_MOPS": sfn(c, "throughput_MOPS") if c else None,
            "switching_trans": get_switching(cfg),
            "E1_ADP": sfn(c, "E1_ADP") if c else None,
            "E2_ACP": sfn(c, "E2_ACP") if c else None,
            "E3_speedup_A": sfn(c, "E3_speedup_A") if c else None,
            "E4_speedup_B": sfn(c, "E4_speedup_B") if c else None,
            "E5_MOPS_LUT": sfn(c, "E5_MOPS_LUT") if c else None,
        }

    opt = master["optimized"]
    b_a = master["baseline_A"]
    b_b = master["baseline_B"]

    lut_delta_b = pct_delta(opt["SB_LUT4"], b_b["SB_LUT4"])
    fmax_delta_b = pct_delta(opt["Fmax_MHz"], b_b["Fmax_MHz"])
    carry_delta_b = pct_delta(opt["SB_CARRY"], b_b["SB_CARRY"])

    checks = []
    infos = []

    def chk(name, passed, actual, target):
        checks.append((name, bool(passed), str(actual), str(target)))

    chk("Synthesis LUT4 <= 5280", opt["SB_LUT4"] <= 5280, f"{opt['SB_LUT4']} LUT4", "<=5280")
    chk("Optimized PnR succeeded", not opt["routing_failed"], "NO" if opt["routing_failed"] else "YES", "YES")
    if opt["routing_failed"]:
        fmax_actual = "route_failed"
        fmax_ok = False
    elif opt["Fmax_MHz"] is None:
        fmax_actual = "no_fmax"
        fmax_ok = False
    else:
        fmax_actual = f"{opt['Fmax_MHz']:.1f} MHz"
        fmax_ok = opt["Fmax_MHz"] >= 12.0
    chk("Fmax >= 12 MHz (routed design)", fmax_ok, fmax_actual, ">=12")

    if opt["routing_failed"] or opt["Fmax_MHz"] is None:
        fmax_target_actual = fmax_actual
        fmax_target_ok = False
    else:
        fmax_target_actual = f"{opt['Fmax_MHz']:.1f} MHz"
        fmax_target_ok = opt["Fmax_MHz"] >= FMAX_TARGET_MHZ
    chk(
        f"Fmax >= {int(FMAX_TARGET_MHZ)} MHz (target)",
        fmax_target_ok,
        fmax_target_actual,
        f">={int(FMAX_TARGET_MHZ)}",
    )

    opt_latency = int(opt.get("pcpi_latency") or 0)
    chk(
        f"MUL latency <= {MAX_PCPI_LATENCY_CYCLES} cycles",
        0 < opt_latency <= MAX_PCPI_LATENCY_CYCLES,
        opt_latency,
        f"<={MAX_PCPI_LATENCY_CYCLES}",
    )
    chk("BRAM budget <= 2 blocks", opt["SB_RAM40_4K"] <= 2, opt["SB_RAM40_4K"], "<=2")

    if fmax_delta_b is not None and not (opt["routing_failed"] or b_b["routing_failed"]):
        chk("Fmax degradation vs Baseline B <= 25%", abs(fmax_delta_b) <= 25.0, f"{fmax_delta_b:+.1f}%", "<=25%")
    if lut_delta_b is not None:
        chk("LUT overhead vs Baseline B <= 35%", lut_delta_b <= 35.0, f"{lut_delta_b:+.1f}%", "<=35%")
    if b_b["SB_CARRY"] > 0:
        chk(
            "KSA reduced SB_CARRY vs Baseline B",
            opt["SB_CARRY"] < b_b["SB_CARRY"],
            f"{opt['SB_CARRY']} ({carry_delta_b:+.1f}%)" if carry_delta_b is not None else str(opt["SB_CARRY"]),
            f"<{b_b['SB_CARRY']}",
        )

    infos.append(
        (
            "Baseline B routing failure expected on UP5K",
            "YES" if b_b["routing_failed"] else "NO",
            f"{b_b['LUT_util_pct']:.1f}% LUT util",
        )
    )

    write_phase3_diagnostics(master)

    all_pass = all(v[1] for v in checks)

    print("\n" + "=" * 80)
    print("PICORV32 OPTIMIZATION - MASTER COMPARISON REPORT")
    print(f"Generated: {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 80)

    print("\nArea summary (LUT4 / CARRY / Fmax MHz):")
    for cfg in CONFIGS:
        d = master[cfg]
        route = "FAIL" if d["routing_failed"] else "OK"
        print(
            f"  {d['label']:<30} LUT4={d['SB_LUT4']:<6} CARRY={d['SB_CARRY']:<6} "
            f"Fmax={fmt_fmax(d['Fmax_MHz']):>6}  PnR={route:<4}  src={d['fmax_source']}"
        )

    if any(master[cfg]["timing_provisional"] for cfg in CONFIGS):
        print("\nNote: provisional timing values were inferred from nextpnr logs for designs with non-zero PnR exit codes.")

    print("\nChecks:")
    for name, passed, actual, target in checks:
        print(f"  {'PASS' if passed else 'FAIL'}  {name:<42} actual={actual:<12} target={target}")

    print("\nInfo:")
    for name, actual, detail in infos:
        print(f"  INFO  {name:<42} actual={actual:<12} detail={detail}")

    print(f"\nOVERALL: {'ALL PASS' if all_pass else 'FAILURES PRESENT'}")
    print("=" * 80)

    fieldnames = [
        "config", "label", "SB_LUT4", "SB_DFF", "SB_CARRY", "SB_MAC16", "SB_RAM40_4K", "LUT_util_pct",
        "Fmax_MHz", "fmax_source", "timing_provisional", "routing_failed", "timing_note", "pnr_exit_code",
        "crit_path_ns", "crit_module", "setup_slack_ns", "timing_met", "logic_levels",
        "total_cycles", "stall_cycles", "stall_pct", "eff_ipc", "pcpi_latency", "throughput_MOPS",
        "switching_trans", "E1_ADP", "E2_ACP", "E3_speedup_A", "E4_speedup_B", "E5_MOPS_LUT",
    ]

    out_csv = Path("synth/reports/master_metrics.csv")
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        for cfg in CONFIGS:
            w.writerow({"config": cfg, **master[cfg]})

    print(f"Master CSV: {out_csv}")


if __name__ == "__main__":
    main()
