# Phase 1 — Unit RTL Verification

This folder documents the Phase 1 objective: module-level simulation sanity for arithmetic blocks.

## Scope
- Kogge-Stone adder unit testbench (`tb_ksa`)
- Vedic multiplier unit testbench (`tb_vedic`)

## Commands (from `opt/`)
- `make tb_ksa`
- `make tb_vedic`
- `make all` (includes Phase 1 + Phase 2 fast checks)

## Artifacts
- Build outputs: `opt/build/`
- Waveforms: `opt/build/dump_ksa.vcd`, `opt/build/dump_vedic_mul.vcd`

## Completion criteria
- Both unit testbenches pass without assertion/error.
- Waveforms are inspectable if needed.
