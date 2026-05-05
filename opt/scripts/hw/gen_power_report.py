#!/usr/bin/env python3
"""
gen_power_report.py — Stage 9 power comparison report generator

Reads all power_<config>.json files from opt/hw/reports/ and generates:
  - A formatted comparison table printed to stdout
  - opt/hw/reports/hw_power.csv  (machine-readable, compatible with Stage 11 correlation)

Designed to work with both:
  (a) JSON files from estimate_power.py  (software estimation, no INA219)
  (b) JSON files from measure_power.py   (real INA219 measurements, if available)

Usage:
    python3 opt/scripts/hw/gen_power_report.py

Run from repo root or opt/.
"""

import json
import csv
import sys
import pathlib

SCRIPT_DIR  = pathlib.Path(__file__).resolve().parent
OPT_DIR     = SCRIPT_DIR.parent.parent
HW_RPT_DIR  = OPT_DIR / "hw" / "reports"
CSV_OUT     = HW_RPT_DIR / "hw_power.csv"

# ── Load all power JSON files ─────────────────────────────────────────────────
def load_results() -> list:
    jsons = sorted(HW_RPT_DIR.glob("power_*.json"))
    if not jsons:
        print(f"ERROR: No power_*.json files found in {HW_RPT_DIR}")
        print("  Run estimate_power.py first:  python3 opt/scripts/hw/estimate_power.py")
        sys.exit(1)

    results = []
    for p in jsons:
        try:
            results.append(json.loads(p.read_text()))
        except Exception as e:
            print(f"WARNING: Could not parse {p.name}: {e}")
    return results


# ── Detect measurement mode ───────────────────────────────────────────────────
def is_measured(r: dict) -> bool:
    """True if this result came from real INA219 measurement (has voltage_avg_V)."""
    return "voltage_avg_V" in r


# ── Get total power (unified for estimated vs measured) ───────────────────────
def get_power_mw(r: dict) -> float:
    if is_measured(r):
        return r.get("power_avg_mW", 0.0)
    return r.get("p_total_mW", 0.0)


def get_current_ma(r: dict) -> float:
    if is_measured(r):
        return r.get("current_avg_mA", 0.0)
    return r.get("i_est_mA", 0.0)


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    results = load_results()
    mode = "MEASURED (INA219)" if any(is_measured(r) for r in results) else "ESTIMATED (iCE40 cell model)"

    print("═" * 72)
    print(f"  STAGE 9 POWER REPORT  [{mode}]")
    print("═" * 72)

    # Table
    col_w = 28
    hdr = (f"  {'Config':<{col_w}}  {'P_total(mW)':>12}  "
           f"{'I_est(mA)':>10}  {'Notes'}")
    print(hdr)
    print("  " + "─" * 68)

    for r in results:
        cfg   = r.get("config", r.get("name", "?"))
        label = r.get("label", cfg)
        p_mw  = get_power_mw(r)
        i_ma  = get_current_ma(r)

        # Extra info for estimated mode
        if not is_measured(r):
            note = f"fmax={r.get('fmax_mhz','?')}MHz α={r.get('activity_factor','?')}"
        else:
            note = f"n={r.get('n_samples','?')} samples"

        print(f"  {label:<{col_w}}  {p_mw:>12.3f}  {i_ma:>10.3f}  {note}")

    print("  " + "─" * 68)

    # Power reduction: optimized vs baseline_A
    baseline = next((r for r in results if "baseline_A" in r.get("config", "")), None)
    optimized = next((r for r in results if r.get("config", "") == "optimized"), None)

    if baseline and optimized:
        b_pw = get_power_mw(baseline)
        o_pw = get_power_mw(optimized)
        reduction = (1 - o_pw / b_pw) * 100 if b_pw > 0 else 0

        print(f"\n  Optimized vs Baseline A:")
        print(f"    Power reduction:           {reduction:+.1f}%")

        # Contextualise against Phase 2
        if not is_measured(baseline):
            print(f"    Phase 2 switching delta:   +13.8%  (optimized = MORE transitions)")
            print(f"    Explanation: Optimized has 2.2× more cells driving higher dynamic")
            print(f"    power. Performance gain is in MOPS/LUT efficiency (3.02×), not")
            print(f"    raw power. This is expected for a throughput-optimised design.")
        else:
            print(f"    Phase 2 switching proxy:  +13.8%  (expected direction: optimized > A)")

    print("\n  Model: " + (results[0].get("model_note", "INA219 measurement") if results else ""))
    print("═" * 72)

    # ── Stage 9 Exit Gate check ───────────────────────────────────────────────
    print("\n  Exit Gate:")
    configs_present = {r.get("config", "") for r in results}
    required = {"baseline_A", "baseline_C", "optimized"}
    missing  = required - configs_present

    checks = [
        ("Power JSON files present (3+)",  len(results) >= 3, f"{len(results)} found"),
        ("baseline_A estimated",            "baseline_A" in configs_present, ""),
        ("optimized estimated",             "optimized"  in configs_present, ""),
        ("P_total > 0 for all configs",
            all(get_power_mw(r) > 0 for r in results), ""),
    ]

    all_ok = True
    for desc, ok, extra in checks:
        sym = "✅" if ok else "❌"
        all_ok = all_ok and ok
        print(f"    {sym}  {desc}{(' — ' + extra) if extra else ''}")

    print(f"\n  Overall Stage 9: {'✅ PASS' if all_ok else '❌ FAIL'}")

    # ── Save CSV ──────────────────────────────────────────────────────────────
    flat_rows = []
    for r in results:
        flat_rows.append({
            "config":       r.get("config", ""),
            "label":        r.get("label", r.get("config", "")),
            "fmax_mhz":     r.get("fmax_mhz", ""),
            "p_static_mW":  r.get("p_static_mW", r.get("static_est_mW", "")),
            "p_dynamic_mW": r.get("p_dynamic_mW", r.get("dynamic_est_mW", "")),
            "p_total_mW":   get_power_mw(r),
            "i_est_mA":     get_current_ma(r),
            "activity_factor": r.get("activity_factor", "measured"),
            "measurement_mode": "INA219" if is_measured(r) else "cell_model",
        })

    with open(CSV_OUT, "w", newline="") as f:
        if flat_rows:
            w = csv.DictWriter(f, fieldnames=flat_rows[0].keys())
            w.writeheader()
            w.writerows(flat_rows)

    print(f"\n  Saved → {CSV_OUT}")


if __name__ == "__main__":
    main()
