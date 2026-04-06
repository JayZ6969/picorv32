# Phase 5 — ASIC Physical Design Readiness

This folder contains the Phase 5 workflow scaffold for physical-design preparation and sign-off packaging.

## Goals
- Prepare placeholders for PPA and physical sign-off metrics.
- Track closure status for DRC/LVS/IR/EM and timing.
- Preserve baseline comparison in final phase package.

## Commands (from `opt/`)
- `make phase5_precheck` — baseline gate + prerequisites.
- `make phase5_collect` — generate Phase 5 metrics, summary, and graphs.
- `make phase5` — run precheck + collect.

## Artifacts
- `opt/results/phase5/phase5_metrics.csv`
- `opt/results/phase5/phase5_summary.md`
- `opt/results/phase5/phase5_baseline_metrics.csv` (baseline PicoRV32 phase5 proxy metrics)
- `opt/results/phase5/phase5_optimized_metrics.csv` (optimized phase5 proxy metrics)
- `opt/results/phase5/phase5_ppa_compare.csv` (baseline vs optimized comparison table)
- `opt/results/phase5/phase5_signoff_status.png`
- `opt/results/phase5/phase5_ppa_overview.png`
- `opt/results/phase5/phase5_chip_preview.png` (conceptual netlist-based preview)
- `opt/results/phase5/phase5_chip_photo.png` (same conceptual preview with requested photo name)
- `opt/results/phase5/phase5_yosys_cmos.log`
- `opt/results/phase5/phase5_yosys_cmos_baseline.log`
- `opt/results/phase5/phase5_yosys_cmos_optimized.log`
- `opt/results/phase5/phase5_tool_inventory.csv`
- `opt/results/phase5/phase5_chip_blocks.csv` (module cell counts for preview)
- `opt/results/phase5/phase5_unblock_checklist.md` (actionable host/docker steps when physical tools are missing)
- `opt/results/phase5/phase5_chip_preview.gds` (conceptual floorplan GDS artifact)
- `opt/results/phase5/phase5_chip_gds_render.png` (render generated from the GDS artifact)

## Notes
- Full RTL→GDSII sign-off requires additional physical tools (`openroad`, `magic`, `netgen`, `klayout`) and a PDK.
- Phase 5 reports numeric PPA proxies (`setup_slack_ns`, `hold_slack_ns`, `total_power_mw`, `core_area_um2`) and explicit blockers.

## Recommended tool install path (no root): Nix
- Install/fetch required physical tools into Nix store and run Phase 5 in one command:

```bash
cd /mnt/toshiba4tb/workspace/projects/picorv32
nix-shell -p yosys nextpnr icestorm verilator iverilog openroad magic-vlsi netgen klayout \
	--run 'cd opt && make phase5'
```

- Validate tool availability recorded by Phase 5:

```bash
cat /mnt/toshiba4tb/workspace/projects/picorv32/opt/results/phase5/phase5_tool_inventory.csv
```
