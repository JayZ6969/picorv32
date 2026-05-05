# Phase 4 - Formal Verification Plan (Repo Aligned)

This plan matches the existing formal infrastructure under opt/formal and the
current toolchain on this machine (SBY v0.64 + z3). It replaces the external
plan text with paths and commands that already exist in the repo.

## Working directory (required)

SymbiYosys resolves every path in `[files]` blocks **relative to the shell’s
current working directory**, not relative to the `.sby` file. **Run all
commands below from the repository root** (the directory that contains `opt/`,
`picorv32.v`, etc.). If you `cd` into `opt/formal/...` first, `sby` will look for
nested paths like `opt/formal/ksa/opt/formal/ksa/...` and fail with
`FileNotFoundError`.

## Prerequisites

```bash
sby --version
z3 --version
```

### Live console output

**`complete_phase4.sh`** passes **`--live csv`** to **`sby`** so you see property status lines during F1 / small Vedic. Disable with **`SBY_LIVE=0`**.

**Parallelism:** **`sby -j`** is set from **`SBY_JOBS`** (default **`$(nproc)`**) for F1 KSA and F2 small Vedic. How much that speeds things up depends on each `.sby` job (multiple engines or tasks can use more cores; a single smtbmc step is still often one solver at a time). Full F5 RVFI uses **`make -j`** via **`RVFI_FULL_JOBS`**; MUL-only F5 uses **`RVFI_MUL_JOBS`** (both default **`$(nproc)`**). If RAM is tight, lower **`SBY_JOBS`**, **`RVFI_FULL_JOBS`**, or **`RVFI_MUL_JOBS`**.

**`run_smtbmc.sh`** (F3 PCPI, F4 arithmetic, optional large Vedic) streams **yosys** and **yosys-smtbmc** to the terminal: **`## …`**, step skips, **`waiting for solver`**, etc., while still writing **`opt/formal/_work_<name>/basecase.log`** and **`induction.log`**. For less smtbmc chatter use **`SMTBMC_NOPROGRESS=1`**. For Yosys console-only-via-log use **`FORMAL_YOSYS_QUIET=1`**.

You can also **`tail -f opt/formal/_work_<name>/basecase.log`** in a second shell while a long job runs.

If SBY v0.64 has hierarchy issues, use the fallback runner:
**`opt/scripts/formal/run_smtbmc.sh`**.

### SBY 0.64: `sby` often crashes on larger smtbmc jobs

With YosysHQ SBY **0.64**, the `smtbmc` engine can raise
`AttributeError: 'NoneType' object has no attribute 'hierarchy'` while parsing
solver output. **F1 (KSA) and small Vedic (2×2–8×8) usually work with `sby`.**
For **Vedic 16×16 / 32×32, F3 (PCPI), and F4 (arithmetic equiv)**, run the
wrapper from the repository root (same depths as the `.sby` files):

**Vedic 16×16** (depth 5, top `vedic_16x16_formal`):

```bash
bash opt/scripts/formal/run_smtbmc.sh vedic_16x16 vedic_16x16_formal 5 \
  opt/rtl/vedic/vedic_mul_2x2.v opt/rtl/vedic/vedic_mul_4x4.v \
  opt/rtl/vedic/vedic_mul_8x8.v opt/rtl/vedic/vedic_mul_16x16.v \
  opt/rtl/ksa/ksa_adder.v opt/rtl/csa/csa_cell.v \
  opt/formal/vedic/vedic_NxN_formal.sv \
  2>&1 | tee opt/formal/vedic/logs/vedic_16x16.log
```

**Vedic 32×32** (depth 8, top `vedic_32x32_formal`):

```bash
bash opt/scripts/formal/run_smtbmc.sh vedic_32x32 vedic_32x32_formal 8 \
  opt/rtl/vedic/vedic_mul_2x2.v opt/rtl/vedic/vedic_mul_4x4.v \
  opt/rtl/vedic/vedic_mul_8x8.v opt/rtl/vedic/vedic_mul_16x16.v \
  opt/rtl/vedic/vedic_mul_32x32.v opt/rtl/ksa/ksa_adder.v \
  opt/rtl/ksa/ksa_64bit_pipelined.v opt/rtl/csa/csa_cell.v \
  opt/formal/vedic/vedic_NxN_formal.sv \
  2>&1 | tee opt/formal/vedic/logs/vedic_32x32.log
```

**F3 PCPI** (depth 12, top `pcpi_formal`):

```bash
bash opt/scripts/formal/run_smtbmc.sh pcpi_protocol pcpi_formal 12 \
  opt/rtl/vedic/vedic_mul_2x2.v opt/rtl/vedic/vedic_mul_4x4.v \
  opt/rtl/vedic/vedic_mul_8x8.v opt/rtl/vedic/vedic_mul_16x16.v \
  opt/rtl/vedic/vedic_mul_32x32.v opt/rtl/ksa/ksa_adder.v \
  opt/rtl/ksa/ksa_64bit_pipelined.v opt/rtl/csa/csa_cell.v \
  opt/rtl/pcpi/pcpi_vedic_mul.v opt/formal/pcpi/pcpi_formal.sv \
  2>&1 | tee opt/formal/pcpi/logs/pcpi_formal.log
```

**F4 arithmetic equivalence** (default: **four** `run_smtbmc` legs with fixed `funct3`,
depth **`F4_SMTBMC_DEPTH`** default **10** — avoids one huge Z3 job with `anyconst` `funct3`).
From repo root:

```bash
bash opt/scripts/formal/run_arithmetic_formal_smtbmc.sh 2>&1 | tee opt/formal/equiv/logs/arithmetic_formal.log
```

Legacy single proof (slow): **`F4_LEGACY_COMBINED=1 F4_SMTBMC_DEPTH=12 bash opt/scripts/formal/run_arithmetic_formal_smtbmc.sh`**

Upgrading SymbiYosys / Yosys may allow using `sby` alone for these tasks again.

## Directory Layout (Existing)

- opt/formal/ksa
- opt/formal/vedic
- opt/formal/pcpi
- opt/formal/equiv
- opt/formal/rvfi (empty stub for future)

## Stage F1 - KSA Adder Properties

Files (already in repo):
- opt/formal/ksa/ksa_formal.sv
- opt/formal/ksa/ksa_formal.sby

Run (from repository root):
```bash
sby -f opt/formal/ksa/ksa_formal.sby 2>&1 | tee opt/formal/ksa/logs/ksa_formal.log
```

Pass condition: DONE (PASS)

## Stage F2 - Vedic Multiplier Properties

Files (already in repo):
- opt/formal/vedic/vedic_NxN_formal.sv
- opt/formal/vedic/vedic_2x2.sby
- opt/formal/vedic/vedic_4x4.sby
- opt/formal/vedic/vedic_8x8.sby
- opt/formal/vedic/vedic_16x16.sby
- opt/formal/vedic/vedic_32x32.sby

Run all sizes (2×2–8×8 work with `sby` on typical 0.64 installs; **16×16 and
32×32** often hit the smtbmc crash — use the wrapper commands in *SBY 0.64*
above instead of the last two `sby` iterations):

```bash
for lvl in 2x2 4x4 8x8; do
  echo "== Vedic ${lvl} =="
  sby -f opt/formal/vedic/vedic_${lvl}.sby 2>&1 | tee opt/formal/vedic/logs/vedic_${lvl}.log
  echo ""
done
```

For **16×16** and **32×32**, use the wrapper commands in *SBY 0.64* under
Prerequisites (same file list as `vedic_16x16.sby` / `vedic_32x32.sby`).

Generic wrapper form:

```bash
bash opt/scripts/formal/run_smtbmc.sh <name> <top> <depth> <verilog_files...>
```

## Stage F3 - PCPI Protocol Properties

Files (already in repo):
- opt/formal/pcpi/pcpi_formal.sv
- opt/formal/pcpi/pcpi_formal.sby

Run (from repository root). On **SBY 0.64**, `sby` commonly crashes on this
task; use the **F3 PCPI** `run_smtbmc.sh` command under *SBY 0.64* in
Prerequisites instead of:

```bash
sby -f opt/formal/pcpi/pcpi_formal.sby 2>&1 | tee opt/formal/pcpi/logs/pcpi_formal.log
```

Pass condition: `DONE (PASS)` from `sby`, or `DONE (PASS, rc=0)` / proof lines from the wrapper.

## Stage F4 - Arithmetic Equivalence

Files (already in repo):
- opt/formal/equiv/arithmetic_formal.sv
- opt/formal/equiv/arithmetic_formal.sby

Run (from repository root). **`complete_phase4.sh`** uses **`opt/scripts/formal/run_arithmetic_formal_smtbmc.sh`**
(four fixed-`funct3` **`run_smtbmc`** legs; writes **`opt/formal/equiv/arithmetic_formal/PASS`** on success).
On **SBY 0.64**, you can still use **`arithmetic_formal.sby`** instead:

```bash
sby -f opt/formal/equiv/arithmetic_formal.sby 2>&1 | tee opt/formal/equiv/logs/arithmetic_formal.log
```

Pass condition: **`opt/formal/equiv/arithmetic_formal/PASS`**, or **`DONE (PASS`** in the tee’d log / `sby` output.

## Skipping long-running proofs (optional)

### Waive only large Vedic (16×16 / 32×32) — **F4 still required**

This is the **default** for `opt/scripts/formal/complete_phase4.sh` when
`PHASE4_QUICK` is unset. That script finishes with **F5 (MUL-only RVFI)** and runs
the report with **`--skip-large-vedic --with-rvfi`**. Standalone report:

```bash
python3 opt/scripts/formal/gen_formal_report.py --skip-large-vedic --with-rvfi
# or without F5 rows: omit --with-rvfi
# or: PHASE4_SKIP_LARGE_VEDIC=1 python3 opt/scripts/formal/gen_formal_report.py --with-rvfi
```

### Waive large Vedic **and** F4 (fastest gate: F1, F2 small, F3 only)

```bash
python3 opt/scripts/formal/gen_formal_report.py --skip-slow
# or: PHASE4_SKIP_SLOW=1 python3 opt/scripts/formal/gen_formal_report.py
```

Required for “ALL PASS” in `--skip-slow` mode: **F1**, **F2 (2×2–8×8)**, **F3**, **F5 MUL RVFI**
(if you use **`--with-rvfi`**, as **`complete_phase4.sh`** does in minimal mode).

### One-shot Phase 4 script

**Standard (default)** — F1, F2 2×2–8×8, F3, **F4**, **F5** (RVFI MUL-only); skips Vedic 16×16 / 32×32;
report uses `--skip-large-vedic --with-rvfi`:

```bash
bash opt/scripts/formal/complete_phase4.sh
```

**Minimal** — also skips F4; still runs **F5** MUL-only; report uses `--skip-slow --with-rvfi`:

```bash
PHASE4_QUICK=1 bash opt/scripts/formal/complete_phase4.sh
```

**Full** F1–F5: **F4** + **full F5** (`make -C checks` after **`checks.cfg`** filters); **skips**
F2 Vedic 16×16 / 32×32 unless **`PHASE4_LARGE_VEDIC=1`** (those often exceed overnight).
Report **`--skip-large-vedic --with-rvfi-full`** by default, or **`--with-rvfi-full`**
if **`PHASE4_LARGE_VEDIC=1`**:

```bash
PHASE4_QUICK=0 bash opt/scripts/formal/complete_phase4.sh
# Optional: include F2 16×16 + 32×32 (may take days):
PHASE4_LARGE_VEDIC=1 PHASE4_QUICK=0 bash opt/scripts/formal/complete_phase4.sh
```

### After long jobs you started manually (e.g. separate terminal)

When **vedic_32×32** and/or **F4** `run_smtbmc` runs finish, refresh the report from
the repo root. Add **`--with-rvfi`** if you ran **`run_rvfi_mul_checks.sh`**, or
**`--with-rvfi-full`** if you ran **`run_rvfi_full_checks.sh`** / full Phase 4
(**`PHASE4_QUICK=0`**).

- If **F2 vedic_16×16** is also proved (or you do not care about it), after **MUL-only** F5:

  ```bash
  python3 opt/scripts/formal/gen_formal_report.py --with-rvfi
  ```

  After **full** F5 (`run_rvfi_full_checks.sh` or **`PHASE4_QUICK=0`**):

  ```bash
  python3 opt/scripts/formal/gen_formal_report.py --with-rvfi-full
  ```

- If **16×16** / **32×32** were never proved but **F4** was:

  ```bash
  python3 opt/scripts/formal/gen_formal_report.py --skip-large-vedic --with-rvfi
  ```

- If you also want to waive **F4**:

  ```bash
  python3 opt/scripts/formal/gen_formal_report.py --skip-slow --with-rvfi
  ```

Optional **full** RVFI beyond the MUL family: **`bash opt/scripts/formal/run_rvfi_full_checks.sh`** — see **`opt/docs/P5_RVFI_Formal.md`**.

## Stage F5 — RVFI (via `complete_phase4.sh`)

- **`PHASE4_QUICK=0`:** **`run_rvfi_full_checks.sh`** — **`make -C checks`** for makefile **`all`**
  after **`checks.cfg`** filters (slow whole-core RVFI checks removed). Report:
  **`--skip-large-vedic --with-rvfi-full`** unless **`PHASE4_LARGE_VEDIC=1`** was used
  (then **`--with-rvfi-full`**).
- **Standard (unset) or `PHASE4_QUICK=1`:** **`run_rvfi_mul_checks.sh`** — four MUL RVFI checks; report **`--with-rvfi`**.

**`checks.cfg`** filters **`reg_ch0`** for the generated suite. Details: **`opt/docs/P5_RVFI_Formal.md`**.

## Report

Generate a consolidated report (from repository root). **`complete_phase4.sh`**
selects **`--with-rvfi`** (MUL-only) vs **`--with-rvfi-full`** (full makefile **`all`**) from **`PHASE4_QUICK`**.

```bash
python3 opt/scripts/formal/gen_formal_report.py --skip-large-vedic --with-rvfi
python3 opt/scripts/formal/gen_formal_report.py --with-rvfi-full
```

Waivers: see **Skipping long-running proofs** above (`--skip-large-vedic`, `--skip-slow`).

Output:

- `opt/formal/phase4_report.txt`

---

## Phase 4 command cheat sheet (from repository root)

**Minimal Phase 4** — skips F4; **F5 MUL-only**; report **`--skip-slow --with-rvfi`**:

```bash
PHASE4_QUICK=1 bash opt/scripts/formal/complete_phase4.sh
cat opt/formal/phase4_report.txt
```

**Standard Phase 4** — skips Vedic 16×16 / 32×32; F4 + **F5 MUL-only**; report **`--skip-large-vedic --with-rvfi`**:

```bash
bash opt/scripts/formal/complete_phase4.sh
cat opt/formal/phase4_report.txt
```

**Full Phase 4** — **F4** + **full F5** (filtered **`make -C checks`**); **skips** F2 16×16 / 32×32
unless **`PHASE4_LARGE_VEDIC=1`**. Report **`--skip-large-vedic --with-rvfi-full`** by default.

```bash
PHASE4_QUICK=0 bash opt/scripts/formal/complete_phase4.sh
cat opt/formal/phase4_report.txt
```

**Optional — include F2 16×16 + 32×32** (often multi-day; not required for the default report):

```bash
PHASE4_LARGE_VEDIC=1 PHASE4_QUICK=0 bash opt/scripts/formal/complete_phase4.sh
cat opt/formal/phase4_report.txt
```

**Collect results:** summary **`opt/formal/phase4_report.txt`**; logs **`opt/formal/ksa/logs/`**, **`opt/formal/vedic/logs/`**, **`opt/formal/pcpi/logs/`**, **`opt/formal/equiv/logs/`**; F5 MUL **`opt/formal/rvfi/logs/mul_rvfi.log`**; full F5 **`opt/formal/rvfi/logs/full_rvfi_make.log`**; per-check **`opt/riscv-formal/cores/picorv32/checks/<name>/`**.

**F5 standalone — MUL only:**

```bash
bash opt/scripts/formal/run_rvfi_mul_checks.sh
```

**F5 standalone — full suite:**

```bash
bash opt/scripts/formal/run_rvfi_full_checks.sh
```

**Report only** (after manual F5): **`--with-rvfi`** for MUL-only; **`--with-rvfi-full`** after **`run_rvfi_full_checks.sh`**.

```bash
python3 opt/scripts/formal/gen_formal_report.py --skip-large-vedic --with-rvfi
python3 opt/scripts/formal/gen_formal_report.py --with-rvfi-full
```

Details: F5 setup and solver notes are in `opt/docs/P5_RVFI_Formal.md`.
