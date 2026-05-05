#!/bin/bash
# opt/scripts/formal/run_smtbmc.sh
# Direct yosys-smtbmc runner — bypasses sby to avoid v0.64 hierarchy bug.
#
# Usage: bash opt/scripts/formal/run_smtbmc.sh <name> <top> <depth> <verilog_files...>
# Example: bash opt/scripts/formal/run_smtbmc.sh vedic_16x16 vedic_16x16_formal 5 \
#              opt/rtl/vedic/vedic_mul_2x2.v opt/rtl/vedic/vedic_mul_4x4.v ...
#
# Verbosity (default: live solver progress on stdout + full logs under workdir):
#   FORMAL_YOSYS_QUIET=1   — yosys only to yosys.log (-ql), no console spam
#   SMTBMC_NOPROGRESS=1    — pass --noprogress to yosys-smtbmc (less "waiting for solver" spam)
# Basecase/induction logs are still tee'd to stdout so you see ## lines in real time.

set -euo pipefail

NAME="$1"; shift
TOP="$1"; shift
DEPTH="$1"; shift
# Remaining args are Verilog files

# Optional: SMT_SOLVER=z3 (default). Newer Yosys may support boolector/bitwuzla.
SOLVER="${SMT_SOLVER:-z3}"

WORKDIR="opt/formal/_work_${NAME}"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
echo "[$NAME] Workdir: $WORKDIR  (e.g. tail -f $WORKDIR/basecase.log while SMT runs)"

# Step 1: Create Yosys script to generate SMT2
YOSYS_SCRIPT="$WORKDIR/design.ys"
{
    for f in "$@"; do
        base=$(basename "$f")
        # Optional -D… only for arithmetic_formal.sv (see run_arithmetic_formal_smtbmc.sh).
        defs=""
        if [[ "$base" == "arithmetic_formal.sv" && -n "${FORMAL_VERILOG_DEFINES:-}" ]]; then
            defs="${FORMAL_VERILOG_DEFINES} "
        fi
        if [[ "$base" == *.sv ]]; then
            echo "read_verilog -sv -formal ${defs}$f"
        else
            echo "read_verilog -formal ${defs}$f"
        fi
    done
    echo "prep -top $TOP"
    echo "async2sync"
    echo "write_smt2 -wires $WORKDIR/design.smt2"
} > "$YOSYS_SCRIPT"

echo "[$NAME] Running Yosys (solver=$SOLVER)..."
if [[ "${FORMAL_YOSYS_QUIET:-0}" == "1" ]]; then
    yosys -ql "$WORKDIR/yosys.log" "$YOSYS_SCRIPT"
else
    # -v2: headings + important steps on console; full log still in yosys.log
    yosys -v2 -l "$WORKDIR/yosys.log" "$YOSYS_SCRIPT"
fi
if [ $? -ne 0 ]; then
    echo "[$NAME] ❌ Yosys FAILED"
    cat "$WORKDIR/yosys.log" | tail -20
    exit 1
fi

# Step 2: Run yosys-smtbmc (basecase) — tee so stdout shows progress while log is saved
echo "[$NAME] Running SMT basecase (depth=$DEPTH)..."
if [[ "${SMTBMC_NOPROGRESS:-0}" == "1" ]]; then
    yosys-smtbmc -s "$SOLVER" --presat --noprogress \
        -t "$DEPTH" --append 0 \
        --dump-vcd "$WORKDIR/trace.vcd" \
        "$WORKDIR/design.smt2" \
        2>&1 | tee "$WORKDIR/basecase.log"
else
    yosys-smtbmc -s "$SOLVER" --presat \
        -t "$DEPTH" --append 0 \
        --dump-vcd "$WORKDIR/trace.vcd" \
        "$WORKDIR/design.smt2" \
        2>&1 | tee "$WORKDIR/basecase.log"
fi
BC_RC=${PIPESTATUS[0]}

# Step 3: Run yosys-smtbmc (induction)
echo "[$NAME] Running SMT induction (depth=$DEPTH)..."
if [[ "${SMTBMC_NOPROGRESS:-0}" == "1" ]]; then
    yosys-smtbmc -s "$SOLVER" --presat -i --noprogress \
        -t "$DEPTH" --append 0 \
        --dump-vcd "$WORKDIR/trace_induct.vcd" \
        "$WORKDIR/design.smt2" \
        2>&1 | tee "$WORKDIR/induction.log"
else
    yosys-smtbmc -s "$SOLVER" --presat -i \
        -t "$DEPTH" --append 0 \
        --dump-vcd "$WORKDIR/trace_induct.vcd" \
        "$WORKDIR/design.smt2" \
        2>&1 | tee "$WORKDIR/induction.log"
fi
IND_RC=${PIPESTATUS[0]}

# Step 4: Parse results
BC_PASS=$(grep -c "Status: PASSED" "$WORKDIR/basecase.log" 2>/dev/null || true)
IND_PASS=$(grep -c "Status: PASSED" "$WORKDIR/induction.log" 2>/dev/null || true)

echo ""
echo "[$NAME] Basecase:  $([ "$BC_PASS" -gt 0 ] && echo '✅ PASS' || echo '❌ FAIL') (rc=$BC_RC)"
echo "[$NAME] Induction: $([ "$IND_PASS" -gt 0 ] && echo '✅ PASS' || echo '❌ FAIL') (rc=$IND_RC)"

if [ "$BC_PASS" -gt 0 ] && [ "$IND_PASS" -gt 0 ]; then
    echo "[$NAME] ✅ PROVED by k-induction"
    echo "DONE (PASS)" >> "$WORKDIR/result.txt"
    echo "DONE (PASS, rc=0)"
    exit 0
else
    echo "[$NAME] ❌ PROOF FAILED"
    echo "Basecase log:"
    cat "$WORKDIR/basecase.log" | tail -10
    echo "Induction log:"
    cat "$WORKDIR/induction.log" | tail -10
    echo "DONE (FAIL)" >> "$WORKDIR/result.txt"
    echo "DONE (FAIL, rc=1)"
    exit 1
fi
