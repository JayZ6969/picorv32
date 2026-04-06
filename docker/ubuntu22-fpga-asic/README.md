# Ubuntu 22 FPGA/ASIC Dev Container

This environment is designed for PicoRV32 Phase 3 work and general open-source FPGA/ASIC RTL flow.

## Why Ubuntu 22
- Yes, Ubuntu is fully fine for this flow.
- You do **not** need Arch Linux.
- Ubuntu has stable packages for `yosys`, `nextpnr-ice40`, `icestorm`, `iverilog`, `verilator` and RISC-V cross tools.

## Included tools
- FPGA: `yosys`, `yosys-config`, `nextpnr-ice40`, `icepack`, `icetime`, `iceprog`
- Simulator: `iverilog`, `vvp`, `verilator`, `gtkwave`
- MuseLab programmer: `icesprog` (built from `wuxx/icesugar`)
- RISC-V: `riscv32-unknown-elf-gcc/objcopy/cpp` (symlinked to Ubuntu `riscv64-unknown-elf-*`)
- ASIC-front-end: `opensta` + RTL toolchain dependencies

## Build image
From this directory:

```bash
docker compose build
```

## Run shell (with USB access)

```bash
docker compose run --rm fpga-asic-dev
```

Your repo is mounted at `/workspace`.

## Tool sanity check inside container

```bash
which yosys yosys-config nextpnr-ice40 icepack icetime iceprog icesprog \
      iverilog vvp riscv32-unknown-elf-gcc riscv32-unknown-elf-objcopy riscv32-unknown-elf-cpp
```

## Run your existing flow inside container

```bash
cd /workspace/opt
make baseline_capture
make baseline_check
make phase3_precheck BOARD=icebreaker
make phase3_fpga_build BOARD=icebreaker
make phase3_collect BOARD=icebreaker TARGET_MHZ=12
```

## Standalone Docker usage (optional path)

Docker is provided as a standalone environment. You can either:
- run flows natively on host OS (existing `opt/Makefile`), or
- open the container and run the same `make` commands inside it.

Build and open shell:

```bash
cd docker/ubuntu22-fpga-asic
docker compose build
docker compose run --rm fpga-asic-dev
```

Inside container (`/workspace` is your repo), run any phase explicitly:

```bash
cd /workspace/opt
make all
make baseline_capture
make report
make phase3 BOARD=icebreaker PHASE3_PROFILE=fit TARGET_MHZ=12
make phase4
make phase5 BOARD=icebreaker
```

Notes:
- USB programming from container (`phase3_program`) requires host daemon permissions for `/dev/bus/usb` mapping.
- Container runs write artifacts into the same mounted workspace paths under `opt/results/phase*`.

## iCESugar / MuseLab board note
- If board USB appears as `1d50:602b` (FPGALink/iCELink), use `icesprog`, not `iceprog`.
- Example:

```bash
icesprog your_bitstream.bin
icesprog -o 0x100000 your_firmware.bin
```

## ASIC note
This image covers open-source RTL/frontend + STA workflows.
For full RTL-to-GDS with OpenLane/Sky130, use dedicated OpenLane container stack separately (large image + PDK volume) to keep this dev image lightweight.
