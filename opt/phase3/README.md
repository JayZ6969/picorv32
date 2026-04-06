# Phase 3 — FPGA Synthesis and Functional Verification

This directory contains the runnable workflow for Phase 3.

## Mandatory baseline policy
- Baseline measurement against original PicoRV32 is compulsory.
- The workflow enforces this gate via:
	- `make baseline_capture` (captures baseline-vs-optimized metrics)
	- `make baseline_check` (must pass before Phase 3 collection/execution)
- Baseline artifact: `opt/results/phase2/pcpi_summary.csv` (copied into `opt/results/phase3/<board>/`).

## Supported boards
- `icebreaker`
- `hx8kdemo`

## Build profiles
- `PHASE3_PROFILE=fit` (default): reduced-resource profile for iCE40UP5K bring-up.
- `PHASE3_PROFILE=full`: regular board configuration.

## Programmer backend
- `PROGRAMMER=auto` (default): for `icebreaker`, try `iceprog` first, then `icesprog`.
- `PROGRAMMER=iceprog`: force FTDI-based programming.
- `PROGRAMMER=icesprog`: force iCELink/FPGALink programming (recommended for `1d50:602b`).

For `BOARD=icebreaker` and `PHASE3_PROFILE=fit`, generated FPGA artifacts use the `icebreaker_fit.*` prefix.

## Main commands (from `opt/`)
- `make baseline_capture` — mandatory baseline measurement before any phase execution.
- `make baseline_check` — verify baseline gate is satisfied.
- `make phase3_precheck` — run local simulation/formal gates before FPGA flow.
- `make phase3_fpga_sim BOARD=icebreaker` — board-level RTL simulation from `picosoc`.
- `make phase3_fpga_build BOARD=icebreaker PHASE3_PROFILE=fit` — synth + P&R + bitstream generation.
- `make phase3_collect BOARD=icebreaker PHASE3_PROFILE=fit TARGET_MHZ=12` — gather logs/reports + generate summary artifacts.
- `make phase3_program BOARD=icebreaker PHASE3_PROFILE=fit` — program board and flash firmware (auto programmer selection).
- `make phase3_program BOARD=icebreaker PHASE3_PROFILE=fit PROGRAMMER=icesprog` — force iCELink/FPGALink programming.
- `make phase3 BOARD=icebreaker` — precheck + board sim + build + collect (uses default profile).

## Host-machine setup helpers
- `bash opt/phase3/scripts/host_setup_ubuntu22.sh` — install host dependencies for Ubuntu 22.
- `bash opt/phase3/scripts/host_preflight.sh` — verify tools and USB programmer visibility.

## MuseLab iCE40UP5K (iCELink/FPGALink) note
- If USB shows `1d50:602b` (FPGALink), use `icesprog` for programming.
- `iceprog` is FTDI-specific and may not work on iCELink-based boards.
- Typical commands:
	- `icesprog <bitstream.bin>`
	- `icesprog -o 0x100000 <firmware.bin>`

## Generated artifacts
`opt/results/phase3/<board>/`
- `phase3_metrics.csv` — key metrics (delay, fmax, timing met, resource indicators).
- `phase3_summary.md` — human-readable phase summary + hardware checklist.
- `phase3_timing.png` — target-vs-fmax timing graph.
- `phase3_resources.png` — netlist resource graph (baseline vs optimized for fit profile when baseline artifacts are present).
- `phase3_baseline_compare.png` — baseline-vs-optimized latency comparison (from copied `pcpi_summary.csv`).
- `*.log`, `*.rpt`, `*.json`, `*.asc`, `*.bin`, `*_fw.elf`, `*_fw.hex`, `*_fw.bin` (if present).
- For `icebreaker + fit`, copied files include both `icebreaker_fit.*` and `icebreaker_fw.*` artifacts.

## Typical run sequence
1. `make baseline_capture`
2. `make phase3_fpga_build BOARD=icebreaker PHASE3_PROFILE=fit`
3. `make phase3_collect BOARD=icebreaker PHASE3_PROFILE=fit TARGET_MHZ=12`
4. Review `opt/results/phase3/icebreaker/phase3_summary.md`
5. `make phase3_program BOARD=icebreaker PHASE3_PROFILE=fit`
6. Execute hardware checklist in `opt/phase3/hardware_checklist.md`

## Quick success criteria
- Baseline gate prints `PASS`.
- `phase3_summary.md` reports timing `PASS` versus target.
- Hardware checklist items are completed on board.
