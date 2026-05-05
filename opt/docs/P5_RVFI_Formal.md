# Phase 5 (F5) — RVFI / riscv-formal

**Phase 4** (`opt/scripts/formal/complete_phase4.sh`) runs F5 as:

- **`PHASE4_QUICK=0` (full Phase 4):** **`run_rvfi_full_checks.sh`** — **`make -C checks`**
  for every target still listed after **`checks.cfg`** **`[filter-checks]`** (slow
  whole-core checks removed; see **Filtered RVFI checks**). **F2 Vedic 16×16 / 32×32**
  are **not** run unless **`PHASE4_LARGE_VEDIC=1`**. Report: **`--skip-large-vedic --with-rvfi-full`**
  by default, or **`--with-rvfi-full`** if large Vedic was included.
- **Standard (unset) or `PHASE4_QUICK=1` (minimal):** MUL-only — **`bash opt/scripts/formal/run_rvfi_mul_checks.sh`**. Report uses **`--with-rvfi`**.

This doc covers prerequisites, **`checks.cfg`** tuning, and standalone commands for both paths.

This stage is **ISA-level** verification: the core (including your PCPI multiply
path) is checked against the RISC-V formal specification via
[YosysHQ/riscv-formal](https://github.com/YosysHQ/riscv-formal).

It complements repo Phase 4 (F1–F4): those prove local RTL and protocol
properties; F5 proves the **instruction semantics** the core exposes on the
RVFI interface.

**`PHASE4_QUICK=1`** still runs those four checks at the end of **`complete_phase4.sh`**.
**`PHASE4_QUICK=0`** runs the full **`run_rvfi_full_checks.sh`** flow instead.

## Prerequisites

Same tool stack as SymbiYosys formal (Yosys, `sby`, and an SMT solver). This
repo’s `checks.cfg` / `genchecks.py` are set to **`solver z3`** so you do **not**
need Boolector installed (upstream defaults to Boolector, which causes
`FileNotFoundError: 'boolector'` if it is missing).

See
[SBY installation](https://yosyshq.readthedocs.io/projects/sby/en/latest/install.html).

## Layout in this repo

- `opt/riscv-formal/` — vendored riscv-formal tree (already present).
- Core RTL copy: `opt/riscv-formal/cores/picorv32/picorv32.v` (overwrite from project root before proofs).

Formal check sources live under:

- `opt/riscv-formal/cores/picorv32/checks/`

Upstream makefile targets use the `_ch0` suffix (channel 0), e.g. `insn_mul_ch0`, **not** `insn_mul`.

## Quick path — MUL instruction family only

From the **repository root** (directory containing `picorv32.v` and `opt/`):

```bash
bash opt/scripts/formal/run_rvfi_mul_checks.sh
```

That script:

1. Copies `picorv32.v` into `opt/riscv-formal/cores/picorv32/`.
2. Runs **`genchecks.py`** in that directory (refreshes **`checks/`** from **`checks.cfg`**).
3. Runs `make` for `insn_mul_ch0`, `insn_mulh_ch0`, `insn_mulhsu_ch0`, `insn_mulhu_ch0` in parallel.
4. Logs everything to `opt/formal/rvfi/logs/mul_rvfi.log`.

By default **`make -j$(nproc)`** runs all four checks in parallel (four Z3 processes).
If the machine thrashes, use **`RVFI_MUL_JOBS=1`** for one job at a time.

To regenerate **`checks/`** alone (e.g. after editing **`checks.cfg`** without running proofs):

```bash
cd opt/riscv-formal/cores/picorv32
python3 ../../checks/genchecks.py
make -C checks
cd ../../..
```

## Full RVFI suite (`make -C checks` — filtered makefile `all`)

From **repository root** (recommended wrapper — does **not** use the upstream
**`Makefile`** target that **`wget`**s **`picorv32.v`**):

```bash
bash opt/scripts/formal/run_rvfi_full_checks.sh
```

Log: **`opt/formal/rvfi/logs/full_rvfi_make.log`**. Parallelism: **`RVFI_FULL_JOBS`**
(default **`nproc`**; set **`1`** to serialize heavy **`sby`** jobs).

**`[filter-checks]`** in **`checks.cfg`** drops **`reg_ch0`**, **`pc_fwd_ch0`**, **`pc_bwd_ch0`**,
**`liveness_ch0`**, **`unique_ch0`**, and **`cover`** — on this Vedic-augmented core each
can be **comparable to or worse than** overnight-scale **F2 16×16** for Z3. Delete
individual **`- …`** lines (or the whole block) only if you accept multi-day runs.

Consolidated report after a full F5 run (with F1–F4 already proved as you prefer):

```bash
# If F2 16×16 / 32×32 were not proved (default full Phase 4):
python3 opt/scripts/formal/gen_formal_report.py --skip-large-vedic --with-rvfi-full
# If you ran PHASE4_LARGE_VEDIC=1 and proved both large Vedic jobs:
python3 opt/scripts/formal/gen_formal_report.py --with-rvfi-full
```

## MUL checks (`insn_mul*_ch0`) and Z3 at the last BMC step

With **`insn 20`**, **`yosys-smtbmc`** spends most of its time on **“Checking
assumptions in step 20”** because the unrolled cone includes the full **32×32
Vedic** multiplier.

**`checks.cfg`** adds **`[depth]`** lines for **`insn_mul_ch0`**, **`insn_mulh_ch0`**,
**`insn_mulhu_ch0`**, and **`insn_mulhsu_ch0`** only (see that file). After any edit,
re-run **`genchecks.py`**. If a MUL check **FAIL**s, increase those four numbers
toward **20** until proofs pass again. If Z3 is still slow, run MUL checks one at
a time: **`RVFI_MUL_JOBS=1 bash opt/scripts/formal/run_rvfi_mul_checks.sh`**.

### Filtered RVFI checks (`[filter-checks]` in `checks.cfg`)

Whole-core **`reg`**, **`pc_fwd` / `pc_bwd`** (deep BMC), **`liveness`**, **`unique`**,
and **`cover`** are disabled so **`make -C checks`** stays closer to “overnight
feasible” than F2 16×16 often is. **`reg_ch0`** alone can stall Z3 for hours on the
last step; the PC and liveness family are similar. Remove lines from **`[filter-checks]`**
to restore upstream-style obligations (expect **much** longer wall time).

**F5 / MUL-only (when you only care about multiply):** you can still use:

```bash
bash opt/scripts/formal/run_rvfi_mul_checks.sh
```

**Faster solver:** installing **Boolector** and setting `solver boolector` under
`[options]` in `checks.cfg` (then `genchecks.py`) is usually much quicker than Z3
on these bit-vector problems, if Boolector is on your `PATH`.

## Report (optional)

After MUL checks complete, include F5 in the Phase 4 report file:

```bash
python3 opt/scripts/formal/gen_formal_report.py --skip-large-vedic --with-rvfi
```

After a **full** F5 run (`run_rvfi_full_checks.sh` or default **`PHASE4_QUICK=0 complete_phase4.sh`**, large Vedic not run):

```bash
python3 opt/scripts/formal/gen_formal_report.py --skip-large-vedic --with-rvfi-full
```

If you also ran **`PHASE4_LARGE_VEDIC=1`** and proved F2 16×16 / 32×32:

```bash
python3 opt/scripts/formal/gen_formal_report.py --with-rvfi-full
```

(`--skip-large-vedic` waives only F2 16×16 / 32×32; use `--skip-slow` if F4 is also waived.)

## Exit criteria (MUL-focused)

Each of `insn_mul_ch0`, `insn_mulh_ch0`, `insn_mulhsu_ch0`, `insn_mulhu_ch0` should end with `DONE (PASS` in its `logfile.txt`, or a `PASS` marker under the check directory, depending on SBY version.
