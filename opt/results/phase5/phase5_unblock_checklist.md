# Phase 5 Unblock Checklist

Missing physical tools detected:
- openroad magic netgen klayout

## Preferred Path (No Root): Nix
- cd /mnt/toshiba4tb/workspace/projects/picorv32
- nix-shell -p yosys nextpnr icestorm verilator iverilog openroad magic-vlsi netgen klayout --run 'cd opt && make phase5'
- Verify tools (inside nix-shell): command -v openroad magic netgen klayout

## Standalone Docker Path
- Build container: cd /mnt/toshiba4tb/workspace/projects/picorv32/docker/ubuntu22-fpga-asic && docker compose build
- Start shell: docker compose run --rm fpga-asic-dev
- Verify inside container: command -v openroad magic netgen klayout

## Native Host Path
- Install these tools using your distro package manager if available.
- Verify tools: command -v openroad magic netgen klayout

## Re-run Phase 5
- cd /mnt/toshiba4tb/workspace/projects/picorv32/opt && make phase5
