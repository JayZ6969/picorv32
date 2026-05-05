#!/usr/bin/env python3
"""
analyse_pcpi_capture.py — Stage 8 PCPI protocol timing analyser

Reads a sigrok .sr archive (or a pre-exported CSV) and measures:
  - pcpi_valid → pcpi_ready latency in clock cycles
  - pcpi_wait pulse width in cycles
  - pcpi_wr assertion timing
  - Protocol violations (deviations from expected 7-cycle latency)

Usage:
    # From a sigrok .sr capture:
    python3 opt/scripts/hw/analyse_pcpi_capture.py opt/hw/captures/pcpi_capture.sr

    # From a pre-exported CSV (faster):
    sigrok-cli -i opt/hw/captures/pcpi_capture.sr -O csv > opt/hw/captures/pcpi_capture.csv
    python3 opt/scripts/hw/analyse_pcpi_capture.py opt/hw/captures/pcpi_capture.csv

Output:
    opt/hw/logs/pcpi_protocol_hw.txt   — machine-readable summary
    Prints analysis table to stdout.
    Exits 0 if 0 violations, 1 otherwise.

Expected results (Phase 3 simulation):
    pcpi_valid → pcpi_ready = 7 cycles
    pcpi_wait held for 6 cycles
    pcpi_wr asserts on same cycle as pcpi_ready

Channel mapping (as captured):
    D0 = pcpi_valid   (trigger source)
    D1 = pcpi_ready
    D2 = pcpi_wait
    D3 = pcpi_wr
    D4 = funct3[1]    (optional, used to distinguish MUL/MULH)
    D5 = funct3[0]
"""

import sys
import csv
import pathlib
import zipfile
import io
import re

# ── Constants ─────────────────────────────────────────────────────────────────
EXPECTED_LATENCY_CYC = 7   # valid→ready clock cycles (Phase 3 result)
EXPECTED_WAIT_CYC    = 6   # wait pulse width
SAMPLE_RATE_HZ       = 48_000_000   # sigrok capture rate (Hz)
CLK_FREQ_HZ          = 12_000_000   # iCEBreaker system clock

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
OPT_DIR    = SCRIPT_DIR.parent.parent
LOG_DIR    = OPT_DIR / "hw" / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
OUT_FILE   = LOG_DIR / "pcpi_protocol_hw.txt"

# ── CSV loader ────────────────────────────────────────────────────────────────
def load_csv_rows(path: pathlib.Path):
    """
    Load sigrok CSV export.
    sigrok CSV format:
        ; <metadata comments>
        ; samplerate: 48000000 Hz
        0,0,0,0,0,0
        1,0,0,0,0,0
        ...
    Returns list of dicts with keys: sample, valid, ready, wait, wr, f3_1, f3_0
    Also returns detected sample_rate (Hz).
    """
    rows = []
    sample_rate = SAMPLE_RATE_HZ

    with open(path, newline="") as f:
        for line in f:
            # Parse metadata
            if line.startswith(";"):
                m = re.search(r"samplerate:\s*(\d+)", line)
                if m:
                    sample_rate = int(m.group(1))
                continue
            if not line.strip():
                continue
            parts = line.strip().split(",")
            if len(parts) < 5:
                continue
            try:
                row = {
                    "sample": int(parts[0]),
                    "valid":  int(parts[1]),
                    "ready":  int(parts[2]),
                    "wait":   int(parts[3]),
                    "wr":     int(parts[4]),
                    "f3_1":   int(parts[5]) if len(parts) > 5 else 0,
                    "f3_0":   int(parts[6]) if len(parts) > 6 else 0,
                }
                rows.append(row)
            except (ValueError, IndexError):
                continue

    return rows, sample_rate


def load_sr_and_export_csv(sr_path: pathlib.Path):
    """
    Read a sigrok .sr zip archive and extract the raw logic data.
    Returns CSV rows by parsing the internal 'logic-1' binary blob
    using sigrok's simple binary format: each byte = 8 channels.
    Falls back to asking the user to export manually if complex.
    """
    try:
        import struct
        with zipfile.ZipFile(sr_path) as zf:
            # Read metadata
            meta_text = zf.read("metadata").decode("utf-8", errors="replace")
            sample_rate = SAMPLE_RATE_HZ
            for line in meta_text.splitlines():
                if "samplerate" in line.lower():
                    m = re.search(r"(\d+)", line)
                    if m:
                        sample_rate = int(m.group(1))

            # Find logic data file
            logic_files = [n for n in zf.namelist() if n.startswith("logic-")]
            if not logic_files:
                raise ValueError("No logic-* file found in .sr archive")

            raw = zf.read(logic_files[0])

        rows = []
        for i, byte in enumerate(raw):
            rows.append({
                "sample": i,
                "valid": (byte >> 0) & 1,
                "ready": (byte >> 1) & 1,
                "wait":  (byte >> 2) & 1,
                "wr":    (byte >> 3) & 1,
                "f3_1":  (byte >> 4) & 1,
                "f3_0":  (byte >> 5) & 1,
            })
        return rows, sample_rate

    except Exception as e:
        print(f"WARNING: Could not parse .sr directly ({e})")
        print("  Please export to CSV first:")
        print(f"    sigrok-cli -i {sr_path} -O csv > {sr_path.with_suffix('.csv')}")
        print(f"  Then re-run with the .csv file.")
        sys.exit(1)


# ── Clock-edge detector ───────────────────────────────────────────────────────
def samples_per_clock(sample_rate: int, clk_hz: int = CLK_FREQ_HZ) -> float:
    return sample_rate / clk_hz


# ── Transaction extractor ─────────────────────────────────────────────────────
def extract_transactions(rows, samp_per_clk: float):
    """
    Scan rows for PCPI transactions:
      - Rising edge of pcpi_valid → start
      - Rising edge of pcpi_ready → end
    Returns list of transaction dicts.
    """
    transactions = []
    in_txn    = False
    t_valid   = None
    t_wait_lo = None   # first sample wait=1 after valid
    t_wait_hi = None   # last sample wait=1 before ready
    prev_valid = 0
    prev_ready = 0

    for r in rows:
        v = r["valid"]
        rdy = r["ready"]
        w   = r["wait"]
        wr  = r["wr"]
        s   = r["sample"]

        # Rising edge of valid
        if v == 1 and prev_valid == 0:
            in_txn    = True
            t_valid   = s
            t_wait_lo = None
            t_wait_hi = None

        if in_txn:
            # Track wait pulse
            if w == 1:
                if t_wait_lo is None:
                    t_wait_lo = s
                t_wait_hi = s

            # Rising edge of ready
            if rdy == 1 and prev_ready == 0:
                dur_samp = s - t_valid
                lat_cyc  = round(dur_samp / samp_per_clk)

                wait_samp = (t_wait_hi - t_wait_lo + 1) if (t_wait_lo and t_wait_hi) else 0
                wait_cyc  = round(wait_samp / samp_per_clk)

                # Decode instruction type from funct3
                f3 = (r["f3_1"] << 1) | r["f3_0"]
                insn_type = {0: "MUL", 1: "MULH", 2: "MULHSU", 3: "MULHU"}.get(f3, "?")

                transactions.append({
                    "sample_valid": t_valid,
                    "sample_ready": s,
                    "lat_cyc":      lat_cyc,
                    "wait_cyc":     wait_cyc,
                    "wr_on_ready":  wr,
                    "insn":         insn_type,
                })
                in_txn = False

        prev_valid = v
        prev_ready = rdy

    return transactions


# ── Analysis ──────────────────────────────────────────────────────────────────
def analyse(path_str: str):
    path = pathlib.Path(path_str)
    if not path.exists():
        print(f"ERROR: File not found: {path}")
        sys.exit(1)

    print(f"Loading capture: {path}")

    if path.suffix.lower() == ".sr":
        rows, sample_rate = load_sr_and_export_csv(path)
    else:
        rows, sample_rate = load_csv_rows(path)

    if not rows:
        print("ERROR: No data rows parsed from capture file.")
        sys.exit(1)

    samp_per_clk = samples_per_clock(sample_rate)
    print(f"  Sample rate:     {sample_rate/1e6:.0f} MHz")
    print(f"  Samples/clock:   {samp_per_clk:.2f}")
    print(f"  Total samples:   {len(rows)}")

    txns = extract_transactions(rows, samp_per_clk)
    if not txns:
        print("ERROR: No PCPI transactions detected.")
        print("  Check: is pcpi_valid toggling? Is the firmware running?")
        sys.exit(1)

    print(f"  Transactions:    {len(txns)}\n")

    # ── Print table ───────────────────────────────────────────────────────────
    HDR = f"{'#':>5}  {'Insn':<6}  {'lat(cyc)':>8}  {'wait(cyc)':>9}  {'wr_ok':>5}  {'Status'}"
    print(HDR)
    print("─" * len(HDR))

    violations = 0
    lat_sum    = 0

    for i, t in enumerate(txns[:50]):   # print first 50
        ok_lat  = (t["lat_cyc"]  == EXPECTED_LATENCY_CYC)
        ok_wait = (t["wait_cyc"] == EXPECTED_WAIT_CYC)
        ok_wr   = (t["wr_on_ready"] == 1)
        ok      = ok_lat and ok_wait and ok_wr

        if not ok:
            violations += 1

        lat_sum += t["lat_cyc"]
        status = "✅ OK" if ok else f"❌ lat={t['lat_cyc']} wait={t['wait_cyc']} wr={t['wr_on_ready']}"
        print(f"  {i:>3}  {t['insn']:<6}  {t['lat_cyc']:>8}  {t['wait_cyc']:>9}  "
              f"{'✅' if ok_wr else '❌':>5}  {status}")

    if len(txns) > 50:
        print(f"  … ({len(txns) - 50} more transactions not shown)")

    # Count violations in full dataset
    total_violations = sum(
        1 for t in txns
        if t["lat_cyc"] != EXPECTED_LATENCY_CYC
        or t["wait_cyc"] != EXPECTED_WAIT_CYC
        or t["wr_on_ready"] != 1
    )

    avg_lat = lat_sum / len(txns[:50])

    print(f"\n{'═'*60}")
    print(f"  Total transactions captured:  {len(txns)}")
    print(f"  Protocol violations (all):    {total_violations}")
    print(f"  Avg valid→ready (first 50):   {avg_lat:.2f} cycles  (expected {EXPECTED_LATENCY_CYC})")
    overall = "✅ PASS" if total_violations == 0 else "❌ FAIL"
    print(f"  Overall:                      {overall}")
    print(f"{'═'*60}\n")

    # ── Save machine-readable result ──────────────────────────────────────────
    with open(OUT_FILE, "w") as f:
        f.write(f"total_events     {len(txns)}\n")
        f.write(f"violations       {total_violations}\n")
        f.write(f"expected_latency {EXPECTED_LATENCY_CYC}\n")
        f.write(f"avg_latency_cyc  {avg_lat:.2f}\n")
        f.write(f"status           {'PASS' if total_violations == 0 else 'FAIL'}\n")

    print(f"Saved → {OUT_FILE}")
    sys.exit(0 if total_violations == 0 else 1)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    analyse(sys.argv[1])
