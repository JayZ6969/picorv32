# Baseline Measurement Policy (Compulsory for Phases 3, 4, 5)

## Rule
Every phase must include a baseline comparison against the original PicoRV32 implementation.

## Baseline source of truth
- `opt/results/phase2/pcpi_summary.csv`
- Produced by `make baseline_capture` in `opt/`.

## Enforcement
- `make baseline_check` must pass before phase completion.
- Any phase report without baseline deltas is considered incomplete.

## Required reporting fields per phase
1. Absolute metrics for current phase implementation.
2. Corresponding baseline metrics.
3. Delta (absolute and percentage where applicable).
4. Pass/fail gate decision with justification.

## Phase-specific minimums
- Phase 3: cycle latency, board timing/fmax, key functional pass rates.
- Phase 4: lint/CDC/formal closure metrics and deltas vs baseline quality targets.
- Phase 5: timing/power/area (PPA) and physical sign-off deltas vs baseline.
