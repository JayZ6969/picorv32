#!/usr/bin/env python3
"""Phase 4 Formal Verification Report Generator

Waive only the large Vedic multipliers (still require F4 arithmetic):

  python3 opt/scripts/formal/gen_formal_report.py --skip-large-vedic
  PHASE4_SKIP_LARGE_VEDIC=1 python3 opt/scripts/formal/gen_formal_report.py

Waive large Vedic **and** F4 (fastest gate — F1, F2 small, F3 only):

  python3 opt/scripts/formal/gen_formal_report.py --skip-slow
  PHASE4_SKIP_SLOW=1 python3 opt/scripts/formal/gen_formal_report.py

F5 (riscv-formal): use --with-rvfi for MUL-only rows, or --with-rvfi-full after a
full `make -C opt/riscv-formal/cores/picorv32/checks` (see run_rvfi_full_checks.sh).

  python3 opt/scripts/formal/gen_formal_report.py --skip-large-vedic --with-rvfi
  python3 opt/scripts/formal/gen_formal_report.py --with-rvfi-full
"""

import os
import sys

SKIP_SLOW = os.environ.get("PHASE4_SKIP_SLOW", "").lower() in ("1", "yes", "true") or "--skip-slow" in sys.argv
SKIP_LARGE_VEDIC = (
    os.environ.get("PHASE4_SKIP_LARGE_VEDIC", "").lower() in ("1", "yes", "true")
    or "--skip-large-vedic" in sys.argv
)
# --skip-slow implies large Vedic waived too; takes precedence for messaging
if SKIP_SLOW:
    SKIP_LARGE_VEDIC = True

WITH_RVFI_FULL = "--with-rvfi-full" in sys.argv
WITH_RVFI = "--with-rvfi" in sys.argv
SKIP_F5 = os.environ.get("PHASE4_SKIP_F5", "").lower() in ("1", "yes", "true") or "--skip-f5" in sys.argv
SKIP_F3 = os.environ.get("PHASE4_SKIP_F3", "").lower() in ("1", "yes", "true") or "--skip-f3" in sys.argv

RVFI_CHECKS_MAKEFILE = "opt/riscv-formal/cores/picorv32/checks/makefile"


def rvfi_makefile_all_targets():
    """Targets from the generated `all:` rule (same as `make -C checks` default)."""
    path = RVFI_CHECKS_MAKEFILE
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if line.startswith("all:"):
                return [t for t in line.split()[1:] if t not in ("\\", "|")]
    return []

# riscv-formal picorv32 checks (channel 0) — optional report rows (see opt/docs/P5_RVFI_Formal.md)
F5_CHECKS = [
    ("F5_insn_mul_ch0", "opt/riscv-formal/cores/picorv32/checks/insn_mul_ch0/PASS", "opt/riscv-formal/cores/picorv32/checks/insn_mul_ch0/logfile.txt"),
    ("F5_insn_mulh_ch0", "opt/riscv-formal/cores/picorv32/checks/insn_mulh_ch0/PASS", "opt/riscv-formal/cores/picorv32/checks/insn_mulh_ch0/logfile.txt"),
    ("F5_insn_mulhsu_ch0", "opt/riscv-formal/cores/picorv32/checks/insn_mulhsu_ch0/PASS", "opt/riscv-formal/cores/picorv32/checks/insn_mulhsu_ch0/logfile.txt"),
    ("F5_insn_mulhu_ch0", "opt/riscv-formal/cores/picorv32/checks/insn_mulhu_ch0/PASS", "opt/riscv-formal/cores/picorv32/checks/insn_mulhu_ch0/logfile.txt"),
]


def classify_log(pass_marker: str, logfile: str) -> str:
    if os.path.exists(pass_marker):
        return "✅ PASS"
    if os.path.exists(logfile):
        content = open(logfile).read()
        if (
            "DONE (PASS" in content
            or "PROVED by k-induction" in content
            or "successful proof by k-induction" in content
        ):
            return "✅ PASS"
        if "DONE (FAIL" in content or "PROOF FAILED" in content:
            return "❌ FAIL"
        if "Traceback (most recent call last)" in content or "FileNotFoundError" in content:
            return "⚠️  ERROR"
        if "ERROR" in content:
            return "⚠️  ERROR"
        return "🔄 RUNNING/UNKNOWN"
    return "⬜ NOT RUN"

# Large Vedic only (F4 still required unless --skip-slow).
LARGE_VEDIC_CHECKS = frozenset({"F2_vedic_16x16", "F2_vedic_32x32"})
# Full "slow" waive: large Vedic + F4.
SLOW_CHECKS = frozenset({"F2_vedic_16x16", "F2_vedic_32x32", "F4_arithmetic_equiv"})

checks = {
    "F1_ksa_formal":       "opt/formal/ksa/ksa_formal/PASS",
    "F2_vedic_2x2":        "opt/formal/vedic/vedic_2x2/PASS",
    "F2_vedic_4x4":        "opt/formal/vedic/vedic_4x4/PASS",
    "F2_vedic_8x8":        "opt/formal/vedic/vedic_8x8/PASS",
    "F2_vedic_16x16":      "opt/formal/vedic/vedic_16x16/PASS",
    "F2_vedic_32x32":      "opt/formal/vedic/vedic_32x32/PASS",
    "F3_pcpi_protocol":    "opt/formal/pcpi/pcpi_formal/PASS",
    "F4_arithmetic_equiv": "opt/formal/equiv/arithmetic_formal/PASS",
}

# Also check log files for status
log_files = {
    "F1_ksa_formal":       "opt/formal/ksa/logs/ksa_formal.log",
    "F2_vedic_2x2":        "opt/formal/vedic/logs/vedic_2x2.log",
    "F2_vedic_4x4":        "opt/formal/vedic/logs/vedic_4x4.log",
    "F2_vedic_8x8":        "opt/formal/vedic/logs/vedic_8x8.log",
    "F2_vedic_16x16":      "opt/formal/vedic/logs/vedic_16x16.log",
    "F2_vedic_32x32":      "opt/formal/vedic/logs/vedic_32x32.log",
    "F3_pcpi_protocol":    "opt/formal/pcpi/logs/pcpi_formal.log",
    "F4_arithmetic_equiv": "opt/formal/equiv/logs/arithmetic_formal.log",
}

print("=" * 65)
print("  PHASE 4 — FORMAL VERIFICATION REPORT")
if SKIP_SLOW:
    print("  (mode: slow checks waived — F2 16×16, F2 32×32, F4)")
elif SKIP_LARGE_VEDIC:
    print("  (mode: large Vedic waived — F2 16×16, F2 32×32 only; F4 required)")
if WITH_RVFI_FULL:
    print("  (includes F5 RVFI — makefile `all` after checks.cfg filters)")
elif WITH_RVFI:
    print("  (includes F5 RVFI — riscv-formal MUL family)")
if SKIP_F5:
    print("  (F5 RVFI omitted from this report — PHASE4_SKIP_F5=1 or --skip-f5)")
if SKIP_F3:
    print("  (F3 PCPI omitted — PHASE4_SKIP_F3=1 or --skip-f3)")
print("=" * 65)

all_pass = True
results = []
f4_mul_waived = False
F4_MUL_WAIVE_MARK = "opt/formal/equiv/arithmetic_formal/MUL_LEG_WAIVED"
for name in checks:
    pass_marker = checks[name]
    logfile = log_files[name]

    if SKIP_SLOW and name in SLOW_CHECKS:
        status = "⏭️  WAIVED (slow formal skipped)"
        print(f"  {name:<30} {status}")
        results.append((name, status))
        continue
    if SKIP_F3 and name == "F3_pcpi_protocol":
        status = "⏭️  WAIVED (F3 PCPI not run — PHASE4_SKIP_F3=1)"
        print(f"  {name:<30} {status}")
        results.append((name, status))
        continue
    if (not SKIP_SLOW) and SKIP_LARGE_VEDIC and name in LARGE_VEDIC_CHECKS:
        status = "⏭️  WAIVED (large Vedic skipped)"
        print(f"  {name:<30} {status}")
        results.append((name, status))
        continue

    status = classify_log(pass_marker, logfile)
    if (
        name == "F4_arithmetic_equiv"
        and status == "✅ PASS"
        and os.path.isfile(F4_MUL_WAIVE_MARK)
    ):
        status = "✅ PASS (F4 MUL leg waived — F4_SKIP_MUL_LEG=1)"
        f4_mul_waived = True
    if status != "✅ PASS":
        all_pass = False

    print(f"  {name:<30} {status}")
    results.append((name, status))

if f4_mul_waived:
    print("  (F4 MUL opcode leg waived — F4_SKIP_MUL_LEG=1)")

if WITH_RVFI_FULL:
    print("-" * 65)
    print("  F5 — RVFI (makefile `all` targets; heavy checks filtered in checks.cfg)")
    print("-" * 65)
    targets = rvfi_makefile_all_targets()
    if not targets:
        print("  (no makefile or empty `all:` — run genchecks in cores/picorv32)")
        all_pass = False
        results.append(("F5_rvfi_full", "⬜ NOT RUN (missing checks/makefile)"))
    else:
        for t in targets:
            pass_marker = f"opt/riscv-formal/cores/picorv32/checks/{t}/PASS"
            logfile = f"opt/riscv-formal/cores/picorv32/checks/{t}/logfile.txt"
            label = f"F5_{t}"
            status = classify_log(pass_marker, logfile)
            if status != "✅ PASS":
                all_pass = False
            print(f"  {label:<30} {status}")
            results.append((label, status))
elif WITH_RVFI:
    print("-" * 65)
    print("  F5 — RVFI (riscv-formal, MUL family)")
    print("-" * 65)
    for name, pass_marker, logfile in F5_CHECKS:
        status = classify_log(pass_marker, logfile)
        if status != "✅ PASS":
            all_pass = False
        print(f"  {name:<30} {status}")
        results.append((name, status))

print("=" * 65)
if all_pass and SKIP_SLOW and SKIP_F5 and SKIP_F3:
    overall = "ALL PASS (F1–F2 small; F3/F4/F5 skipped this run) ✅"
elif all_pass and SKIP_SLOW and SKIP_F3:
    overall = "ALL PASS (F1–F2 small; F3 skipped + slow checks waived) ✅"
elif all_pass and SKIP_SLOW and WITH_RVFI:
    overall = "ALL PASS (F1–F3 + waived slow F2/F4 + F5 RVFI) ✅"
elif all_pass and SKIP_SLOW and WITH_RVFI_FULL:
    overall = "ALL PASS (F1–F3 + waived slow F2/F4 + full F5 RVFI) ✅"
elif all_pass and SKIP_SLOW:
    overall = "ALL PASS (required subset; slow checks waived) ✅"
elif all_pass and SKIP_LARGE_VEDIC and not SKIP_SLOW and WITH_RVFI_FULL and f4_mul_waived:
    overall = "ALL PASS (large Vedic waived + F4 partial MUL waived + full F5 RVFI) ✅"
elif all_pass and SKIP_LARGE_VEDIC and not SKIP_SLOW and WITH_RVFI_FULL:
    overall = "ALL PASS (large Vedic waived + F4 + full F5 RVFI) ✅"
elif all_pass and SKIP_LARGE_VEDIC and not SKIP_SLOW and WITH_RVFI and f4_mul_waived:
    overall = "ALL PASS (large Vedic waived + F4 partial MUL waived + F5 RVFI) ✅"
elif all_pass and SKIP_LARGE_VEDIC and not SKIP_SLOW and WITH_RVFI:
    overall = "ALL PASS (large Vedic waived + F5 RVFI) ✅"
elif all_pass and SKIP_LARGE_VEDIC and not SKIP_SLOW and f4_mul_waived:
    overall = "ALL PASS (large Vedic waived; F4 partial — MUL leg waived) ✅"
elif all_pass and SKIP_LARGE_VEDIC and not SKIP_SLOW:
    overall = "ALL PASS (large Vedic waived; F4 proved) ✅"
elif all_pass and WITH_RVFI_FULL and not SKIP_SLOW and not SKIP_LARGE_VEDIC and f4_mul_waived:
    overall = "ALL PASS (F1–F5: F4 MUL leg waived + full RVFI) ✅"
elif all_pass and WITH_RVFI_FULL and not SKIP_SLOW and not SKIP_LARGE_VEDIC:
    overall = "ALL PASS (F1–F5: full RTL formal + full RVFI) ✅"
elif all_pass and WITH_RVFI and not SKIP_SLOW and not SKIP_LARGE_VEDIC and f4_mul_waived:
    overall = "ALL PASS (F1–F5: F4 MUL leg waived + RVFI MUL) ✅"
elif all_pass and WITH_RVFI and not SKIP_SLOW and not SKIP_LARGE_VEDIC:
    overall = "ALL PASS (F1–F5: full RTL formal + RVFI MUL) ✅"
elif all_pass and f4_mul_waived:
    overall = "ALL PASS (F4 partial — MUL leg waived; other gates proved) ✅"
elif all_pass:
    overall = "ALL PASS ✅"
else:
    overall = "INCOMPLETE / FAILURES ❌"
print(f"  Overall: {overall}")
print("=" * 65)

# Save report
os.makedirs("opt/formal", exist_ok=True)
with open("opt/formal/phase4_report.txt", "w") as f:
    f.write("PHASE 4 FORMAL VERIFICATION RESULTS\n")
    if SKIP_SLOW:
        f.write("(slow checks waived: F2 16x16, F2 32x32, F4)\n")
    elif SKIP_LARGE_VEDIC:
        f.write("(large Vedic waived: F2 16x16, F2 32x32)\n")
    if WITH_RVFI_FULL:
        f.write("(includes F5 RVFI — makefile all after checks.cfg filters)\n")
    elif WITH_RVFI:
        f.write("(includes F5 RVFI MUL checks)\n")
    if SKIP_F5:
        f.write("(F5 RVFI omitted — not run / not in report)\n")
    if SKIP_F3:
        f.write("(F3 PCPI omitted — PHASE4_SKIP_F3=1)\n")
    if f4_mul_waived:
        f.write("(F4 MUL funct3 leg waived — F4_SKIP_MUL_LEG=1)\n")
    f.write("=" * 50 + "\n")
    for name, status in results:
        f.write(f"{name}: {status}\n")
    f.write("=" * 50 + "\n")
    f.write(f"Overall: {overall}\n")

print(f"\n  Saved → opt/formal/phase4_report.txt")
