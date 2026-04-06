# Phase 3 Hardware Bring-up & Functional Verification Checklist

## Stage 1 — Bring-up
- [ ] Board powers up and enumerates over USB/JTAG.
- [ ] Programmer tool can access FPGA (`iceprog` for iCE40 flow).
- [ ] Correct board profile selected (`BOARD=icebreaker` or `BOARD=hx8kdemo`).
- [ ] Clock/reset behavior checked (design leaves reset, UART active).

## Stage 2 — First bitstream + heartbeat
- [ ] Run `make phase3_program BOARD=<board>` successfully.
- [ ] UART baud configured to expected value.
- [ ] Boot banner / heartbeat text observed on UART.
- [ ] LED/GPIO activity observed (if implemented in selected board top).

## Stage 3 — Functional verification on hardware
- [ ] Core instruction smoke test passes.
- [ ] MUL operation result samples match expected values.
- [ ] MULH/MULHU/MULHSU result samples match expected values.
- [ ] No hangs/crashes during repeated command loop.

## Stage 4 — Stability and performance capture
- [ ] 30-minute burn-in loop passes without failure.
- [ ] At least 3 repeated runs show consistent behavior.
- [ ] Measured cycle/latency aligns with simulation expectations (within accepted tolerance).

## Artifacts to archive
- [ ] `opt/results/phase3/<board>/phase3_summary.md`
- [ ] `opt/results/phase3/<board>/phase3_metrics.csv`
- [ ] Programming and UART logs
- [ ] Any wave captures / logic analyzer snapshots for debug incidents
