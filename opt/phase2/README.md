# Phase 2 — Formal and Comparative Verification

This folder documents the Phase 2 objective: algebraic/formal correctness and baseline-versus-optimized latency comparison.

## Scope
- GF(2) formal checks (`formal`, `formal_full`)
- PCPI latency comparison baseline (`tb_pcpi_compare`)
- Baseline metrics capture gate for downstream phases

## Commands (from `opt/`)
- `make formal`
- `make formal_full`
- `make tb_pcpi_compare`
- `make baseline_capture`
- `make baseline_check`

## Artifacts
- Baseline metrics: `opt/results/phase2/pcpi_summary.csv`
- Optional consolidated report: `make report` → `opt/results/phase2/*.png`, `*.csv`, `*.tex`

## Completion criteria
- Formal checks pass for selected mode.
- Baseline metrics file is generated and valid.
- `make baseline_check` reports `PASS`.
