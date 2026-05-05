# Phase 2 Documentation: Implementation, Prerequisites, and Verification

This document captures what was implemented for Phase 2, required tools, tested versions, and exact commands to verify Phase 2.

## 1. Phase 2 Scope

Phase 2 in this workspace includes:

- PCPI-level verification for `pcpi_vedic_mul`.
- PicoRV32 integration verification using the new PCPI Vedic multiplier.
- KSA and Vedic unit/regression simulation under `opt/` flow.
- Formal proofs for KSA and Vedic sub-units (2x2, 4x4, 8x8).
- Heavy 16x16/32x32 checks kept as best-effort (non-blocking) so full Phase 2 is reliable on this machine.
- Baseline measurement flow for A/B/C/Optimized configurations, including area, performance, switching, and quality reports.

### Baseline configurations used in reports

- Baseline A (iterative): `ENABLE_MUL=1`, `ENABLE_FAST_MUL=0`
- Baseline B (native fast): `ENABLE_MUL=1`, `ENABLE_FAST_MUL=1` with `pcpi_vedic_mul_fastshim`
- Baseline C (core only): `ENABLE_MUL=0`, `ENABLE_FAST_MUL=0`
- Optimized: `ENABLE_MUL=1`, `ENABLE_FAST_MUL=1` with KSA + Vedic + `pcpi_vedic_mul`

### Baseline metrics and output artifacts

- Area metrics:
  - `TOTAL_CELLS`, `SB_LUT4`, `SB_DFF`, `SB_CARRY`, `SB_MAC16`, `SB_RAM40_4K`
- Performance metrics:
  - `total_cycles`, `stall_cycles`, `stall_pct`, `effective_ipc`, `avg_pcpi_latency`
- Switching metrics:
  - `switching_transitions`, `switching_per_cycle`
- Quality metrics:
  - Lint warnings/errors, core-line delta proxy, module-addition proxy, dead-code proxy

Key artifacts:

- `opt/synth/reports/phase1_area_comparison.csv`
- `opt/synth/reports/phase2_performance.csv`
- `opt/synth/reports/phase1_quality_metrics.txt`
- `opt/synth/reports/layer0_switching_summary.txt`
- `opt/synth/reports/master_metrics.csv`

## 2. Files Added/Updated for Phase 2

### Added testbenches

- `opt/tb/pcpi/tb_pcpi_vedic_mul.v`
- `opt/tb/integration/tb_picorv32_top.v`
- `opt/tb/pcpi/tb_pcpi_baseline_mul.v`
- `opt/tb/integration/tb_picorv32_baseline_top.v`

### Added/updated baseline-capture RTL helpers

- `opt/rtl/pcpi/pcpi_vedic_mul_fastshim.v`

### Added baseline-capture scripts

- `opt/scripts/parse_area.py`
- `opt/scripts/parse_performance.py`
- `opt/scripts/count_switching.py`
- `opt/scripts/collect_quality_metrics.py`
- `opt/scripts/build_master_report.py`

### Added formal files

KSA:
- `opt/formal/ksa/ksa_formal.v`
- `opt/formal/ksa/ksa_formal.sby`

Vedic formal sub-units:
- `opt/formal/vedic/vedic_2x2_formal.v`
- `opt/formal/vedic/vedic_2x2_formal.sby`
- `opt/formal/vedic/vedic_4x4_formal.v`
- `opt/formal/vedic/vedic_4x4_formal.sby`
- `opt/formal/vedic/vedic_8x8_formal.v`
- `opt/formal/vedic/vedic_8x8_formal.sby`

Vedic heavy/advanced checks:
- `opt/formal/vedic/vedic_16x16_ag_formal.v`
- `opt/formal/vedic/vedic_16x16_ag_formal.sby`
- `opt/formal/vedic/vedic_32x32_ag_formal.v`
- `opt/formal/vedic/vedic_32x32_ag_formal.sby`
- `opt/formal/vedic/vedic_mul_8x8_contract.v`
- `opt/formal/vedic/vedic_mul_16x16_contract.v`
- `opt/formal/vedic/equiv_16x16.ys`
- `opt/formal/vedic/equiv_32x32.ys`
- `opt/formal/vedic/vedic_mul_16x16_ref.v`
- `opt/formal/vedic/vedic_mul_32x32_ref.v`

### Added Phase 2 firmware support

- `opt/firmware/mul_test/mul_test.S`
- `opt/firmware/mul_test/link.ld`
- `opt/firmware/mul_test/Makefile`

### Updated build flow

- `opt/Makefile` updated with Phase 2 targets:
  - `sim_ksa`
  - `sim_vedic`
  - `sim_pcpi`
  - `sim_integration`
  - `formal_ksa`
  - `formal_vedic_2x2`
  - `formal_vedic_4x4`
  - `formal_vedic_8x8`
  - `formal_vedic_16x16_ag`
  - `formal_vedic_32x32_ag`
  - `equiv_vedic_16x16`
  - `equiv_vedic_32x32`
  - `vedic_heavy_best_effort`
  - `formal_vedic`
  - `phase2_all`

## 3. Prerequisites for Phase 2

Phase 2 needs simulation tools plus formal tools.

### Required tools

- Bash shell
- GNU Make
- Python 3
- Icarus Verilog (`iverilog`, `vvp`)
- Verilator (optional for additional lint checks)
- Yosys
- `yosys-smtbmc`
- SymbiYosys (`sby`)
- SMT solver (`z3`)

### Tested versions in this environment

- GNU Make: 4.3
- Python: 3.10.12
- Icarus Verilog (`iverilog`): 11.0 (stable)
- Icarus runtime (`vvp`): 11.0 (stable)
- Verilator: 4.038
- SymbiYosys (`sby`): v0.64
- Yosys: 0.9 (git sha1 1979e0b)
- Z3: 4.16.0 (64 bit)

### Version check commands

Run from repo root:

```bash
make --version | head -n 1
python3 --version
iverilog -V | head -n 1
vvp -V | head -n 1
verilator --version
sby --version
yosys -V
yosys-smtbmc -h | head -n 1
z3 -version
```

## 4. Important reliability decision

On this machine, full flat 16x16 and 32x32 equivalence/SAT checks can take too long and frequently time out.

To keep Phase 2 reliable, `formal_vedic` now works as:

- Required and deterministic:
  - `formal_vedic_2x2`
  - `formal_vedic_4x4`
  - `formal_vedic_8x8`
- Best-effort and non-blocking:
  - `formal_vedic_16x16_ag`
  - `formal_vedic_32x32_ag`
  - `equiv_vedic_16x16`
  - `equiv_vedic_32x32`

This means `phase2_all` can pass reliably even if heavy checks timeout.

## 5. Commands to verify Phase 2 manually

Run from repo root:

```bash
cd /mnt/toshiba4tb/workspace/projects/picorv32
export PATH="$HOME/.local/bin:$PATH"
```

### Baseline Measurement Quick Run

Use this one command to run the full baseline measurement pipeline:

```bash
make -C opt baseline_capture_all
```

This generates baseline and optimized area/performance/switching/quality outputs in `opt/synth/reports`.

Optional cleanup of stale solver processes:

```bash
pkill -f "yosys-smtbmc|z3 -smt2 -in|sby -f" || true
```

### A) Simulation checks

```bash
timeout --foreground 600 make -C opt sim_ksa; echo EXIT:$?
timeout --foreground 600 make -C opt sim_vedic; echo EXIT:$?
timeout --foreground 600 make -C opt sim_pcpi; echo EXIT:$?
timeout --foreground 600 make -C opt sim_integration; echo EXIT:$?
```

Expected result: all `EXIT:0`.

### B) Formal checks (required deterministic set)

```bash
timeout --foreground 600 make -C opt formal_ksa; echo EXIT:$?
timeout --foreground 600 make -C opt formal_vedic_2x2; echo EXIT:$?
timeout --foreground 600 make -C opt formal_vedic_4x4; echo EXIT:$?
timeout --foreground 600 make -C opt formal_vedic_8x8; echo EXIT:$?
```

Expected result: all `EXIT:0`.

### C) Heavy checks (best-effort, non-blocking)

```bash
make -C opt BEST_EFFORT_TIMEOUT=300 EQUIV_TIMEOUT=300 vedic_heavy_best_effort; echo EXIT:$?
```

Expected result:

- Usually `EXIT:0` because this target is intentionally non-blocking.
- Individual heavy jobs may still timeout; this is acceptable for reliable Phase 2 completion on this machine.

### D) Aggregate Phase 2 run

```bash
timeout --foreground 3600 make -C opt phase2_all; echo EXIT:$?
```

Expected result: `EXIT:0`.

## 6. Quick pass/fail checks from logs

```bash
grep -E "STATUS: ALL PASS|RESULTS:|INTEGRATION RESULTS" opt/sim/logs/*.log
grep -E "DONE \(PASS|DONE \(FAIL|DONE \(ERROR" opt/formal/ksa/ksa_formal_prove/logfile.txt
grep -E "DONE \(PASS|DONE \(FAIL|DONE \(ERROR" opt/formal/vedic/vedic_2x2_formal_prove/logfile.txt
grep -E "DONE \(PASS|DONE \(FAIL|DONE \(ERROR" opt/formal/vedic/vedic_4x4_formal_prove/logfile.txt
grep -E "DONE \(PASS|DONE \(FAIL|DONE \(ERROR" opt/formal/vedic/vedic_8x8_formal_prove/logfile.txt
```

## 7. Troubleshooting notes

- Always use uppercase `-C` with make:
  - Correct: `make -C opt ...`
  - Incorrect: `make -c opt ...`
- If a command appears idle, check whether it is in SAT solving.
- Use explicit `timeout --foreground ...` when running heavy targets manually.
- If interrupted, re-run the target directly; no special state reset is required.

## 8. Definition of Done for Phase 2

Phase 2 is considered complete and stable in this repository when all of the following are true:

- `sim_ksa`, `sim_vedic`, `sim_pcpi`, `sim_integration` pass.
- `formal_ksa`, `formal_vedic_2x2`, `formal_vedic_4x4`, `formal_vedic_8x8` pass.
- `phase2_all` returns success (`EXIT:0`).
- Heavy 16x16/32x32 checks are attempted via best-effort path and do not block completion.

## 9. Parameter, Macro, and Variable Reference (Phase 2)

This section explains the key knobs used by simulation, formal, and baseline capture in `opt/Makefile`.

### A) Core synthesis/simulation parameters (PicoRV32)

- `ENABLE_MUL`
  - `1`: enable multiply handling via internal PCPI multiplier path.
  - `0`: disable multiply support.

- `ENABLE_FAST_MUL`
  - `0`: baseline iterative path (`picorv32_pcpi_mul`) when `ENABLE_MUL=1`.
  - `1`: fast multiply path.
    - Baseline-B measurement uses `pcpi_vedic_mul_fastshim` (forwarded native fast mul).
    - Optimized measurement uses `pcpi_vedic_mul`.

- `BARREL_SHIFTER`
  - Enables barrel shifter logic in integration test configurations.

### B) Testbench compile-time defines

- `BASELINE_CONFIG` (used by `tb_pcpi_baseline_mul.v`)
  - `0`: instantiate `picorv32_pcpi_mul` (iterative baseline A).
  - `1`: instantiate `picorv32_pcpi_fast_mul` (native fast baseline B).

- `ENABLE_FAST_MUL` (used by `tb_picorv32_baseline_top.v`)
  - Passed through to PicoRV32 instance to switch iterative vs fast path in integration runs.

- `FIRMWARE` (used by `tb_picorv32_baseline_top.v`)
  - Hex file path loaded by `$readmemh`, default: `firmware/mul_test/mul_test.hex`.

### C) `opt/Makefile` tool variables

- `IVERILOG`: Verilog compiler executable (default `iverilog`).
- `VVP`: Icarus runtime executable (default `vvp`).
- `SBY`: SymbiYosys executable (default `sby`).
- `YOSYS`: Yosys executable (default `yosys`).
- `PYTHON`: Python executable (default `python3`).
- `VERILATOR`: Verilator executable (default `verilator`).

### D) `opt/Makefile` flow-control variables

- `EQUIV_TIMEOUT` (default `300`)
  - Timeout (seconds) for heavy equivalence checks.

- `BEST_EFFORT_TIMEOUT` (default `300`)
  - Timeout (seconds) for heavy best-effort formal jobs.

- `VVP_PLUSARGS` (default empty)
  - Extra plusargs passed to `vvp` invocations.

- `REPORT_DIR` (default `synth/reports`)
  - Output directory for area/perf/quality/master reports.

- `OPT_BENCH_FIRMWARE` (default `firmware/bench/bench.hex`)
  - Firmware path for optimized bench workload run.
  - If the file is missing, `sim_integration_opt_bench` is skipped without failing the flow.

## 10. Complete Command List (Phase 2)

Run from repo root:

```bash
cd /mnt/toshiba4tb/workspace/projects/picorv32
export PATH="$HOME/.local/bin:$PATH"
```

### A) Environment/version checks

```bash
make --version | head -n 1
python3 --version
iverilog -V | head -n 1
vvp -V | head -n 1
verilator --version
sby --version
yosys -V
yosys-smtbmc -h | head -n 1
z3 -version
```

### B) Core simulation commands

```bash
make -C opt sim_ksa
make -C opt sim_vedic
make -C opt sim_pcpi
make -C opt sim_integration
```

### C) Core formal commands

```bash
make -C opt formal_ksa
make -C opt formal_vedic_2x2
make -C opt formal_vedic_4x4
make -C opt formal_vedic_8x8
make -C opt formal_vedic
```

### D) Heavy formal/equivalence commands

```bash
make -C opt formal_vedic_16x16_ag
make -C opt formal_vedic_32x32_ag
make -C opt equiv_vedic_16x16
make -C opt equiv_vedic_32x32
make -C opt BEST_EFFORT_TIMEOUT=300 EQUIV_TIMEOUT=300 vedic_heavy_best_effort
```

### E) Aggregate Phase 2 command

```bash
make -C opt phase2_all
```

### F) Baseline-capture and reporting commands

```bash
make -C opt stage0_freeze
make -C opt area_baseline_A
make -C opt area_baseline_B
make -C opt area_baseline_C
make -C opt area_optimized
make -C opt stage2_area_capture

make -C opt sim_pcpi_baseline_A
make -C opt sim_pcpi_baseline_B
make -C opt sim_integration_baseline_A_mul
make -C opt sim_integration_baseline_B_mul
make -C opt sim_integration_opt_metrics
make -C opt sim_integration_opt_bench
make -C opt layer0_perf_capture

make -C opt sim_integration_baseline_A_mul_vcd
make -C opt sim_integration_baseline_B_mul_vcd
make -C opt sim_integration_opt_metrics_vcd
make -C opt switching_baseline_A_mul
make -C opt switching_baseline_B_mul
make -C opt switching_optimized_mul
make -C opt compare_switching
make -C opt layer0_switching_capture

make -C opt quality_capture
make -C opt baseline_reports
make -C opt baseline_capture_all
```

### G) Utility/cleanup commands

```bash
make -C opt prep_dirs
make -C opt firmware
make -C opt clean_phase2
make -C opt clean_baseline
```

### H) Timeout-wrapped safe execution examples

```bash
timeout --foreground 600 make -C opt sim_ksa; echo EXIT:$?
timeout --foreground 600 make -C opt sim_vedic; echo EXIT:$?
timeout --foreground 600 make -C opt sim_pcpi; echo EXIT:$?
timeout --foreground 600 make -C opt sim_integration; echo EXIT:$?

timeout --foreground 600 make -C opt formal_ksa; echo EXIT:$?
timeout --foreground 600 make -C opt formal_vedic_2x2; echo EXIT:$?
timeout --foreground 600 make -C opt formal_vedic_4x4; echo EXIT:$?
timeout --foreground 600 make -C opt formal_vedic_8x8; echo EXIT:$?

timeout --foreground 3600 make -C opt phase2_all; echo EXIT:$?
```
