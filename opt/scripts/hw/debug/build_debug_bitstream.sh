#!/usr/bin/env bash
# build_debug_bitstream.sh — Stage 8 debug bitstream build
#
# Synthesises, places-and-routes, and packs a debug bitstream that exposes
# 6 PCPI protocol signals on PMOD 1A pins for logic analyser capture.
#
# Output:
#   opt/hw/bitstreams/optimized_dbg.bin
#
# Run from repo root (picorv32/) or opt/:
#   bash opt/scripts/hw/build_debug_bitstream.sh
#
# Requirements: yosys, nextpnr-ice40, icepack (icestorm)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT_DIR="$(cd "${OPT_DIR}/.." && pwd)"

PICOSOC_DIR="${ROOT_DIR}/picosoc"
RTL_DIR="${OPT_DIR}/rtl"
SYNTH_DIR="${OPT_DIR}/synth/debug"
PNR_DIR="${OPT_DIR}/pnr/debug"
BIT_DIR="${OPT_DIR}/hw/bitstreams"
LOG_DIR="${OPT_DIR}/hw/logs"
PCF="${OPT_DIR}/constraints/icebreaker_dbg.pcf"

mkdir -p "${SYNTH_DIR}" "${PNR_DIR}" "${BIT_DIR}" "${LOG_DIR}"

# ── Tool checks ───────────────────────────────────────────────────────────────
for tool in yosys nextpnr-ice40 icepack; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "ERROR: '${tool}' not found in PATH."
        exit 1
    fi
done

echo "════════════════════════════════════════════════════"
echo "  Stage 8 — Debug Bitstream Build"
echo "════════════════════════════════════════════════════"
echo ""

# ── Step 1: Synthesis ─────────────────────────────────────────────────────────
SYNTH_LOG="${LOG_DIR}/synth_debug.log"
echo "── Step 1/3: Yosys synthesis ──"
yosys -p "
    read_verilog -I${ROOT_DIR} ${ROOT_DIR}/picorv32.v
    read_verilog ${PICOSOC_DIR}/ice40up5k_spram.v
    read_verilog ${PICOSOC_DIR}/spimemio.v
    read_verilog ${PICOSOC_DIR}/simpleuart.v
    read_verilog ${RTL_DIR}/picosoc_dbg.v
    read_verilog ${RTL_DIR}/icebreaker_dbg.v
    synth_ice40 -top icebreaker_dbg -json ${SYNTH_DIR}/design.json
    tee -q -o ${LOG_DIR}/synth_debug_stat.log stat
" 2>&1 | tee "${SYNTH_LOG}"

if [[ ! -f "${SYNTH_DIR}/design.json" ]]; then
    echo " ❌ Synthesis failed — check ${SYNTH_LOG}"
    exit 1
fi
echo " ✅ Synthesis OK → ${SYNTH_DIR}/design.json"
echo ""

# ── Step 2: Place-and-Route ───────────────────────────────────────────────────
PNR_LOG="${LOG_DIR}/pnr_debug.log"
echo "── Step 2/3: nextpnr-ice40 place-and-route ──"
nextpnr-ice40 \
    --up5k \
    --package sg48 \
    --freq 12 \
    --json "${SYNTH_DIR}/design.json" \
    --pcf  "${PCF}" \
    --asc  "${PNR_DIR}/design.asc" \
    --report "${PNR_DIR}/debug_report.json" \
    --log    "${PNR_LOG}" \
    --seed 1 \
    --timing-allow-fail \
    --pcf-allow-unconstrained \
    2>&1 | tee "${PNR_LOG}"

if [[ ! -f "${PNR_DIR}/design.asc" ]]; then
    echo " ❌ PnR failed — check ${PNR_LOG}"
    exit 1
fi

# Extract achieved Fmax
FMAX=$(grep -oP 'Max frequency.*?(\d+\.\d+) MHz' "${PNR_LOG}" | tail -1 | grep -oP '\d+\.\d+' | tail -1 || echo "unknown")
echo " ✅ PnR OK  (Fmax reported: ${FMAX} MHz)"
echo ""

# ── Step 3: Pack bitstream ────────────────────────────────────────────────────
DBG_BIN="${BIT_DIR}/optimized_dbg.bin"
echo "── Step 3/3: icepack → bitstream ──"
icepack "${PNR_DIR}/design.asc" "${DBG_BIN}" 2>&1 | tee "${LOG_DIR}/icepack_debug.log"

SIZE="$(stat -c%s "${DBG_BIN}")"
if [[ "${SIZE}" -eq 104090 ]]; then
    echo " ✅ Bitstream size OK: ${SIZE} bytes → ${DBG_BIN}"
else
    echo " ⚠️  Unexpected bitstream size: ${SIZE} (expected 104090)"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "════════════════════════════════════════════════════"
echo "  Debug bitstream ready: ${DBG_BIN}"
echo ""
echo "  Next steps:"
echo "  1. Flash debug bitstream:"
echo "     bash opt/scripts/hw/flash_and_verify.sh optimized_dbg"
echo "  2. Flash LA-loop firmware:"
echo "     bash opt/scripts/hw/flash_firmware.sh opt/firmware/hw/mul_loop_hw.bin"
echo "  3. Connect logic analyser to PMOD 1A:"
echo "     CH0=pcpi_valid (trigger↑)  CH1=pcpi_ready"
echo "     CH2=pcpi_wait              CH3=pcpi_wr"
echo "     CH4=funct3[1]              CH5=funct3[0]"
echo "  4. Capture (fx2lafw @ 48 MHz, 500k samples):"
echo "     sigrok-cli --driver=fx2lafw --config samplerate=48M \\"
echo "       --samples 500000 \\"
echo "       --channels D0=pcpi_valid,D1=pcpi_ready,D2=pcpi_wait,D3=pcpi_wr,D4=funct3_1,D5=funct3_0 \\"
echo "       --triggers D0=r \\"
echo "       --output-file opt/hw/captures/pcpi_capture.sr"
echo "  5. Analyse:"
echo "     python3 opt/scripts/hw/analyse_pcpi_capture.py opt/hw/captures/pcpi_capture.sr"
echo "════════════════════════════════════════════════════"
