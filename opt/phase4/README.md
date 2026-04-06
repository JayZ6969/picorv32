# Phase 4 — Pre-ASIC Logical Sign-off

This folder contains the Phase 4 pre-ASIC sign-off workflow (lint/structural checks + readiness dashboard).

## Goals
- Close critical RTL quality issues before physical design.
- Produce a repeatable sign-off readiness package.
- Keep baseline comparison compulsory for all reports.

## Commands (from `opt/`)
- `make phase4_precheck` — baseline gate + prerequisites.
- `make phase4_collect` — generate Phase 4 metrics, summary, and graphs.
- `make phase4` — run precheck + collect.

## Artifacts
- `opt/results/phase4/phase4_metrics.csv`
- `opt/results/phase4/phase4_summary.md`
- `opt/results/phase4/phase4_signoff_status.png`
- `opt/results/phase4/phase4_baseline_delta.png` (generated when baseline metrics are present)
- `opt/results/phase4/phase4_verilator_lint.log`
- `opt/results/phase4/phase4_yosys_check.log`

## Notes
- Current flow measures real host-available checks (Verilator lint and Yosys structural check/stat).
- CDC/formal use evidence-based proxy closure for Phase 4 gate:
	- CDC: single-clock proxy analysis from RTL clock-edge usage.
	- Formal: Phase 2 GF(2) proof table reference.
- Dedicated CDC/formal tool runs are still recommended before final ASIC sign-off.
