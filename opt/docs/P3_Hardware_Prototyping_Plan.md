# Part B: Hardware Prototyping Plan (Stage 6)

This document turns Stage 6 into executable commands in this workspace.

## Prerequisites Before Stage 6

1. Optimized PnR succeeds (`pnr/optimized/design.asc` exists).
2. Routed Fmax is validated in reports.
3. Programmer is visible over USB (`1d50:602b` / iCELink / CMSIS-DAP / DAPLink).
4. Tools installed: `icepack`, `icesprog`, `lsusb` (`usbutils`), `python3`.

Board detection check:

```bash
cd opt
bash scripts/hw/check_board.sh
```

## Stage 6.1: Generate Bitstreams

Pack all routed designs (A, C, optimized):

```bash
cd opt
bash scripts/hw/pack_bitstreams.sh
```

Outputs:

- `hw/bitstreams/baseline_A.bin`
- `hw/bitstreams/baseline_C.bin`
- `hw/bitstreams/optimized.bin`
- `hw/logs/icepack_<config>.log`

The pack script enforces expected iCE40UP5K bitstream size (`104090` bytes by default).
Override with `EXPECTED_BIN_SIZE=<bytes>` if needed.

## Stage 6.2: Flash and Verify

Flash one configuration:

```bash
cd opt
bash scripts/hw/flash_and_verify.sh optimized
```

Repeat for each config:

```bash
bash scripts/hw/flash_and_verify.sh baseline_A
bash scripts/hw/flash_and_verify.sh baseline_C
bash scripts/hw/flash_and_verify.sh optimized
```

The script checks:

1. `icesprog` write succeeds.
2. Readback bytes match the bitstream file (byte-for-byte compare).

Logs:

- `hw/logs/flash_<config>.log`
- `hw/logs/verify_<config>.log`

Optional:

- Set `ICESPROG_OFFSET=<addr>` if your board expects the bitstream at a non-zero flash offset.

## Stage 6.3: Power-On Sanity (Heartbeat LED)

Current opt flow does not include a board-specific top module or LED pin assignment.

- RTL directories currently include only arithmetic/PCPI blocks under `rtl/`.
- Constraint file currently maps `clk`, `resetn`, `trap`, `uart_tx`, `uart_rx` only.

Before LED heartbeat can be validated, add a board top-level module and LED pin mapping in:

- `rtl/top/<board_top>.v`
- `constraints/picorv32_ice40up5k.pcf`

Suggested heartbeat logic:

```verilog
reg [25:0] hb_ctr;
always @(posedge clk) hb_ctr <= hb_ctr + 1;
assign LED = hb_ctr[25];
```

## Stage 6 Exit Gate

1. `icesprog` write succeeds.
2. Readback bytes match the bitstream file.
3. Heartbeat LED visible (after top-level + PCF LED integration).
4. All three configs (`baseline_A`, `baseline_C`, `optimized`) flashed and verified.
