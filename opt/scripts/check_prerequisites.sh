#!/usr/bin/env bash
set -euo pipefail

echo "╔══════════════════════════════════════════════╗"
echo "║     PHASE 3 PREREQUISITES CHECK             ║"
echo "╚══════════════════════════════════════════════╝"

PASS=0
FAIL=0

check() {
    if [[ -f "$1" ]]; then
        echo "  ✓  $1"
        PASS=$((PASS+1))
    else
        echo "  ✗  MISSING: $1"
        FAIL=$((FAIL+1))
    fi
}

echo ""
echo "── Phase 1 Artifacts (Area + Quality) ──────────────────────"
check synth/reports/phase1_area_comparison.csv
check synth/reports/phase1_quality_metrics.txt
check synth/reports/baseline_A_stat.log
check synth/reports/baseline_B_stat.log
check synth/reports/baseline_C_stat.log
check synth/reports/optimized_stat.log

echo ""
echo "── Phase 2 Artifacts (Performance + Power) ─────────────────"
check sim/logs/pcpi_baseline_A.log
check sim/logs/pcpi_baseline_B.log
check sim/logs/pcpi_optimized.log
check sim/logs/integration_baseline_A_mul.log
check sim/logs/integration_baseline_B_mul.log
check sim/logs/integration_optimized_mul.log
check sim/logs/integration_baseline_A_bench.log
check sim/logs/integration_baseline_B_bench.log
check sim/logs/integration_optimized_bench.log
check synth/reports/baseline_A_switching.txt
check synth/reports/baseline_B_switching.txt
check synth/reports/optimized_switching.txt
check synth/reports/phase2_performance.csv

echo ""
echo "── RTL Artifacts (required for re-synthesis) ────────────────"
check ../picorv32.v
check rtl/ksa/ksa_adder.v
check rtl/ksa/ksa_32bit.v
check rtl/ksa/ksa_64bit_pipelined.v
check rtl/csa/csa_cell.v
check rtl/vedic/vedic_mul_2x2.v
check rtl/vedic/vedic_mul_4x4.v
check rtl/vedic/vedic_mul_8x8.v
check rtl/vedic/vedic_mul_16x16.v
check rtl/vedic/vedic_mul_32x32.v
check rtl/pcpi/pcpi_vedic_mul.v

echo ""
echo "── Tool Chain ───────────────────────────────────────────────"
tool_version() {
    local t="$1"
    local v=""
    v=$( (timeout 2 "$t" --version 2>&1 || true) | head -1 )
    if [[ -z "$v" ]]; then
        v=$( (timeout 2 "$t" -V 2>&1 || true) | head -1 )
    fi
    if [[ -z "$v" ]]; then
        v="(version unavailable)"
    fi
    echo "$v"
}

for tool in yosys nextpnr-ice40 icetime icepack python3; do
    if command -v "$tool" >/dev/null 2>&1; then
        ver=$(tool_version "$tool")
        echo "  ✓  $tool -> $ver"
        PASS=$((PASS+1))
    else
        echo "  ✗  MISSING TOOL: $tool"
        FAIL=$((FAIL+1))
    fi
done

echo ""
echo "══════════════════════════════════════════════"
echo "  PASSED: $PASS    FAILED: $FAIL"
if [[ $FAIL -gt 0 ]]; then
    echo "  STATUS: ✗ DO NOT PROCEED - fix missing items first"
    exit 1
else
    echo "  STATUS: ✓ ALL CLEAR - proceed to Phase 3"
fi
echo "══════════════════════════════════════════════"
