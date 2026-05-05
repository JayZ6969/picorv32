# Phase 1 Documentation: Implementation, Prerequisites, and Verification

This document captures what was implemented for Phase 1, the tool prerequisites, tested versions, and exact commands to verify Phase 1.

## 1. Phase 1 Scope

Phase 1 in this workspace includes:

- 32-bit Kogge-Stone adder RTL.
- PicoRV32 ALU fast-add integration for add/sub using KSA under `ENABLE_FAST_ADD`.
- Hierarchical Vedic multiplier RTL (2x2, 4x4, 8x8, 16x16, 32x32).
- PCPI wrapper for Vedic multiplier integration.
- PicoRV32 fast-multiply integration update to use the new PCPI Vedic multiplier.
- Lint and simulation verification flow for KSA and Vedic multiplier.
- Baseline measurement framework for area/quality reporting across:
  - Baseline A (iterative)
  - Baseline B (native fast via shim)
  - Baseline C (core only)
  - Optimized (KSA + Vedic + `pcpi_vedic_mul`)

## 2. Files Added/Updated for Phase 1

### Added RTL

- `opt/rtl/ksa/ksa_32bit.v`
- `opt/rtl/vedic/vedic_mul_2x2.v`
- `opt/rtl/vedic/vedic_mul_4x4.v`
- `opt/rtl/vedic/vedic_mul_8x8.v`
- `opt/rtl/vedic/vedic_mul_16x16.v`
- `opt/rtl/vedic/vedic_mul_32x32.v`
- `opt/rtl/pcpi/pcpi_vedic_mul.v`

### Added testbenches

- `opt/tb/unit/tb_ksa_32bit.v`
- `opt/tb/unit/tb_vedic_mul_32x32.v`

### Updated integration/build files

- `picorv32.v`
  - Fast-multiply PCPI instantiation switched to `pcpi_vedic_mul`.
  - Added ALU fast-add integration (`ENABLE_FAST_ADD`) with KSA add/sub paths (`u_alu_add_ksa`, `u_alu_sub_ksa`).
- `Makefile`
  - Added Phase 1 targets:
    - `lint`
    - `sim_ksa`
    - `sim_vedic`
    - `all` (Phase 1 aggregate target)
- `opt/scripts/collect_quality_metrics.py`
  - Q3/Q4 now use structural core integration markers (fast-add + fast-mul coverage) instead of brittle text proxies.

## 3. Prerequisites for Phase 1

Phase 1 does not require formal tooling (`sby`, `z3`, etc.).
It only needs lint and simulation tools.

### Required tools

- Bash shell
- GNU Make
- Verilator (for lint)
- Icarus Verilog (`iverilog` + `vvp`) (for simulation)
- Python 3 (optional helper scripts/log processing)

### Tested versions in this environment

- GNU Make: 4.3
- Verilator: 4.038
- Icarus Verilog compiler (`iverilog`): 11.0 (stable)
- Icarus runtime (`vvp`): 11.0 (stable)
- Python: 3.10.12

### Version check commands

Run from repo root:

```bash
make --version | head -n 1
verilator --version
iverilog -V | head -n 1
vvp -V | head -n 1
python3 --version
```

## 4. Phase 1 Implementation Steps (What Was Done)

1. Created optimization directory layout under `opt/`.
2. Implemented KSA adder in `opt/rtl/ksa/ksa_32bit.v`.
3. Implemented recursive Vedic hierarchy:
   - `vedic_mul_2x2.v`
   - `vedic_mul_4x4.v`
   - `vedic_mul_8x8.v`
   - `vedic_mul_16x16.v`
   - `vedic_mul_32x32.v`
4. Implemented PCPI wrapper in `opt/rtl/pcpi/pcpi_vedic_mul.v`.
5. Added unit testbenches for KSA and 32x32 Vedic multiplier.
6. Updated PicoRV32 integration for fast-mul and fast-add paths (`pcpi_vedic_mul` and `ENABLE_FAST_ADD` KSA add/sub wiring).
7. Added root Makefile Phase 1 lint/sim targets.
8. Hardened Phase 1 quality metric logic so Q3/Q4 reflect structural core integration markers.
9. Fixed lint issues (unused/warnings/width-related) until clean lint and passing simulation were achieved.

### Baseline measurement setup used in this flow

Baseline configurations used in reports:

- Baseline A (iterative): `ENABLE_MUL=1`, `ENABLE_FAST_MUL=0`
- Baseline B (native fast): `ENABLE_MUL=1`, `ENABLE_FAST_MUL=1` with `pcpi_vedic_mul_fastshim`
- Baseline C (core only): `ENABLE_MUL=0`, `ENABLE_FAST_MUL=0`
- Optimized: `ENABLE_MUL=1`, `ENABLE_FAST_MUL=1` with KSA + Vedic + `pcpi_vedic_mul`

Primary Phase 1 baseline metrics:

- Area metrics from synthesis reports
  - `TOTAL_CELLS`, `SB_LUT4`, `SB_DFF`, `SB_CARRY`, `SB_MAC16`, `SB_RAM40_4K`
- Quality metrics from lint/integration checks
  - `Q1/Q2`: lint warnings/errors
  - `Q3`: core fast-add marker coverage in `picorv32.v`
  - `Q4`: core module integration coverage (fast-add + fast-mul markers)
  - `Q5`: dead-code proxy

Primary output artifacts:

- `opt/synth/reports/phase1_area_comparison.csv`
- `opt/synth/reports/phase1_area_summary.txt`
- `opt/synth/reports/phase1_quality_metrics.txt`
- `opt/synth/reports/master_metrics.csv`

### Current validated quality snapshot

- `Q1 Lint warnings`: 0
- `Q2 Lint errors`: 0
- `Q3 Core fast-add markers`: 5
- `Q4 Core module coverage`: 2
- `Q5 Dead code proxy count`: 0

## 5. Commands to Verify Phase 1

Run from repo root:

```bash
cd /mnt/toshiba4tb/workspace/projects/picorv32
```

### Baseline Measurement Quick Run

Use this one command to run the full baseline measurement pipeline:

```bash
make -C opt baseline_capture_all
```

This captures baseline and optimized reports for area/performance/switching/quality under `opt/synth/reports`.

### A) Lint

```bash
make lint
```

Expected outcome:

- Verilator lint passes for KSA, Vedic hierarchy, and PCPI wrapper.
- Final line includes: `All lint checks passed`.

### B) KSA unit simulation

```bash
make sim_ksa
```

Expected outcome (current testbench/log behavior):

- `RESULTS: 2177 PASSED, 0 FAILED`
- `STATUS: ALL PASS`

Log file:

- `opt/sim/logs/ksa.log`

### C) Vedic unit simulation

```bash
make sim_vedic
```

Expected outcome (current testbench/log behavior):

- `RESULTS: 68045 PASSED, 0 FAILED`
- `STATUS: ALL PASS`

Log file:

- `opt/sim/logs/vedic.log`

### D) Aggregate Phase 1 target

```bash
make all
```

This runs the Phase 1 aggregate defined in root `Makefile`:

- `lint`
- `sim_ksa`
- `sim_vedic`

Expected outcome:

- All three steps complete successfully.

## 6. Quick Pass/Fail Check Commands

```bash
grep -E "STATUS: ALL PASS|RESULTS:" opt/sim/logs/ksa.log
grep -E "STATUS: ALL PASS|RESULTS:" opt/sim/logs/vedic.log
```

If both logs show `STATUS: ALL PASS` and lint passes, Phase 1 verification is complete.

## 7. Troubleshooting Notes

- Use uppercase `-C` with make when targeting subdirectories:
  - Correct: `make -C opt ...`
  - Incorrect: `make -c opt ...`
- If simulation appears slow, avoid extra waveform dumping unless needed.
- If a previous run was interrupted, re-run the target directly; no manual state reset is required for standard Phase 1 checks.

## 8. Definition of Done for Phase 1

Phase 1 is considered complete when all of the following pass:

- `make lint`
- `make sim_ksa`
- `make sim_vedic`
- (optional aggregate) `make all`
- `opt/synth/reports/phase1_quality_metrics.txt` meets thresholds: `Q1=0`, `Q2=0`, `Q3>=3`, `Q4>=2`, `Q5=0`

## 9. Parameter and Variable Reference (Phase 1)

This section explains the key parameters/macros used by the Phase 1 flow.

### A) PicoRV32 integration parameters

- `ENABLE_MUL`
  - `1`: enable multiply instruction handling in the internal PCPI multiply block.
  - `0`: disable multiply instruction handling.

- `ENABLE_FAST_MUL`
  - `0`: baseline iterative multiply path (`picorv32_pcpi_mul`) when `ENABLE_MUL=1`.
  - `1`: fast multiply path.
    - Baseline-B measurement uses native fast path via shim build.
    - Optimized measurement uses `pcpi_vedic_mul`.

- `ENABLE_FAST_ADD`
  - `0`: default ALU add/sub path.
  - `1`: use KSA-backed ALU add/sub fast path (`u_alu_add_ksa`, `u_alu_sub_ksa`).

- `ENABLE_PCPI`
  - Enables external PCPI coprocessor interface arbitration signals.
  - Not required for built-in mul path validation, but part of PCPI wait/ready mux logic.

- `BARREL_SHIFTER`
  - `1`: enable barrel shifter implementation for shift instructions.
  - Used in integration benches for deterministic, high-performance shift behavior.

### B) Root Makefile tool variables used by Phase 1

- `VERILATOR`: lint tool executable (default `verilator`).
- `IVERILOG`: compile tool executable (default `iverilog`).
- `VVP`: simulation runtime executable (default `vvp`).
- `PYTHON`: Python executable for helper scripts (default `python3`).
- `REPORT_DIR` (in `opt/Makefile`, default `synth/reports`): report output directory.

### C) Baseline measurement defines and knobs

- `BASELINE_CONFIG` (used by baseline PCPI bench)
  - `0`: iterative multiplier baseline path.
  - `1`: native fast multiplier baseline path.

- `FIRMWARE` (used by baseline integration bench)
  - Firmware hex path loaded into memory.
  - Default in this flow: `firmware/mul_test/mul_test.hex`.

### D) Frequently used command-line conventions

- `make -C opt ...`: run make in `opt/` subdirectory.
- `timeout --foreground N ...`: bound long runs while keeping output visible.

## 10. Complete Command List (Phase 1)

Run from repo root unless noted:

```bash
cd /mnt/toshiba4tb/workspace/projects/picorv32
```

### A) Environment/version checks

```bash
make --version | head -n 1
verilator --version
iverilog -V | head -n 1
vvp -V | head -n 1
python3 --version
```

### B) Root Makefile Phase 1 commands (canonical)

```bash
make lint
make sim_ksa
make sim_vedic
make all
```

### C) Optional `opt/` granular lint commands

```bash
make -C opt lint_ksa
make -C opt lint_vedic
make -C opt lint_pcpi
make -C opt lint_phase1
```

### D) Optional `opt/` granular sim commands

```bash
make -C opt sim_ksa
make -C opt sim_vedic
```

### E) Baseline measurement commands (Phase 1-focused)

```bash
make -C opt stage0_freeze

make -C opt area_baseline_A
make -C opt area_baseline_B
make -C opt area_baseline_C
make -C opt area_optimized
make -C opt stage2_area_capture

make -C opt quality_capture
make -C opt baseline_reports
make -C opt baseline_capture_all
```

### F) Quick pass/fail and report checks

```bash
grep -E "STATUS: ALL PASS|RESULTS:" opt/sim/logs/ksa.log
grep -E "STATUS: ALL PASS|RESULTS:" opt/sim/logs/vedic.log
ls -1 opt/synth/reports | sort
cat opt/synth/reports/phase1_area_summary.txt
cat opt/synth/reports/phase1_quality_metrics.txt
```

### G) Optional timeout-wrapped commands

```bash
timeout --foreground 300 make sim_ksa; echo EXIT:$?
timeout --foreground 300 make sim_vedic; echo EXIT:$?
timeout --foreground 900 make all; echo EXIT:$?
```
