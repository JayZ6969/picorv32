#!/usr/bin/env bash
# Phase 5 — synthesis + single-seed PnR: optimized (baseline) vs optimized_abc2 (-abc2).
# Run from repository root: bash opt/scripts/phase5_measure.sh
# Outputs: opt/synth/reports/phase5_measure.json, opt/pnr/reports/p5_* logs
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OPT="$ROOT/opt"
cd "$OPT"

mkdir -p synth/optimized_abc2 synth/reports pnr/optimized_abc2 pnr/reports

REPORT_JSON="$OPT/synth/reports/phase5_measure.json"
PCF="$OPT/constraints/picorv32_ice40up5k.pcf"
FREQ="${P5_NEXTPNR_FREQ_MHZ:-20}"

run_yosys() {
  local name="$1"
  local ys="$2"
  local log="$OPT/synth/reports/p5_${name}_yosys.log"
  echo "== Yosys: $name ==" >&2
  "$YOSYS" -l "$log" -s "$ys"
}

run_pnr() {
  local name="$1"
  local json="$2"
  local asc="$OPT/pnr/${name}/design.asc"
  local rpt="$OPT/pnr/reports/p5_${name}_report.json"
  local plog="$OPT/pnr/reports/p5_${name}_pnr.log"
  mkdir -p "$OPT/pnr/${name}"
  echo "== nextpnr: $name (seed=1, --freq $FREQ) ==" >&2
  set +e
  nextpnr-ice40 --up5k --package sg48 --freq "$FREQ" --json "$json" --pcf "$PCF" \
    --asc "$asc" --report "$rpt" --seed 1 --timing-allow-fail --pcf-allow-unconstrained \
    >"$plog" 2>&1
  local rc=$?
  set -e
  local fmax=""
  fmax=$(grep -m1 "Max frequency for clock" "$plog" 2>/dev/null | sed 's/^.*: //; s/ (.*$//; s/ MHz$//' || true)
  if [[ -z "$fmax" && -f "$rpt" ]]; then
    fmax=$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    f = d.get("fmax") or {}
    if not f:
        print("")
    else:
        v = next(iter(f.values()))
        print(v.get("achieved", "") or "")
except Exception:
    print("")
' "$rpt")
  fi
  local lut4=""
  lut4=$(awk '/^[[:space:]]*SB_LUT4[[:space:]]/{print $2}' "$OPT/synth/reports/${name}_synth_stat.log" 2>/dev/null | tail -n 1 || true)
  echo "$rc|$fmax|$lut4"
}

YOSYS="${YOSYS:-yosys}"

if [[ ! -f "$OPT/synth/optimized/design.json" ]]; then
  echo "[p5] synth/optimized/design.json missing — running synth_optimized.ys" >&2
  run_yosys optimized synth/synth_optimized.ys
else
  echo "[p5] reusing existing synth/optimized/design.json" >&2
fi

if [[ ! -f "$OPT/synth/reports/optimized_synth_stat.log" ]]; then
  echo "[p5] extracting stat from existing json (best-effort)" >&2
  "$YOSYS" -q -p "read_json $OPT/synth/optimized/design.json; tee -q -o $OPT/synth/reports/optimized_synth_stat.log stat" || true
fi

run_yosys optimized_abc2 synth/synth_optimized_abc2.ys

IFS='|' read -r rc0 f0 lut0 < <(run_pnr optimized "$OPT/synth/optimized/design.json")
IFS='|' read -r rc1 f1 lut1 < <(run_pnr optimized_abc2 "$OPT/synth/optimized_abc2/design.json")

python3 - <<PY
import json, os
out = {
    "optimized": {"pnr_exit": int("${rc0:-1}"), "fmax_mhz": "${f0:-}", "lut4": "${lut0:-}"},
    "optimized_abc2": {"pnr_exit": int("${rc1:-1}"), "fmax_mhz": "${f1:-}", "lut4": "${lut1:-}"},
    "nextpnr_freq_request_mhz": ${FREQ},
    "note": "Compared baseline -dsp vs -dsp -abc2 (Yosys 0.9). -retime omitted: collapses closed-memory wrapper.",
}
path = "${REPORT_JSON}"
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as fp:
    json.dump(out, fp, indent=2)
print("Wrote", path)
PY

echo ""
echo "Phase 5 PnR summary:"
echo "  optimized:       rc=$rc0  Fmax=${f0:-?} MHz  LUT4=${lut0:-?}"
echo "  optimized_abc2:  rc=$rc1  Fmax=${f1:-?} MHz  LUT4=${lut1:-?}"
