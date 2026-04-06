#!/usr/bin/env bash
set -euo pipefail

# Ubuntu 22 host setup for PicoRV32 Phase 3 + MuseLab iCESugar boards

sudo apt-get update
sudo apt-get install -y \
  git make build-essential pkg-config \
  cmake ninja-build \
  yosys nextpnr-ice40 fpga-icestorm \
  iverilog verilator gtkwave \
  gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf \
  libhidapi-dev libusb-1.0-0-dev \
  libftdi1-dev libudev-dev zlib1g-dev libjsoncpp-dev libevent-dev libboost-regex-dev

# Map expected riscv32-unknown-elf-* tool names
sudo ln -sf /usr/bin/riscv64-unknown-elf-gcc /usr/local/bin/riscv32-unknown-elf-gcc
sudo ln -sf /usr/bin/riscv64-unknown-elf-objcopy /usr/local/bin/riscv32-unknown-elf-objcopy
sudo ln -sf /usr/bin/riscv64-unknown-elf-cpp /usr/local/bin/riscv32-unknown-elf-cpp

# Install MuseLab iCELink programmer (icesprog)
if ! command -v icesprog >/dev/null 2>&1; then
  tmpdir=$(mktemp -d)
  git clone --depth 1 https://github.com/wuxx/icesugar.git "$tmpdir/icesugar"
  make -C "$tmpdir/icesugar/tools/src"
  sudo install -m 0755 "$tmpdir/icesugar/tools/src/icesprog" /usr/local/bin/icesprog
  sudo install -Dm0644 "$tmpdir/icesugar/tools/src/60-icesugar.rules" /etc/udev/rules.d/60-icesugar.rules
  rm -rf "$tmpdir"
fi

# Optional universal programmer for non-FTDI boards
# Ubuntu 22 repositories may not include openfpgaloader package.
if ! command -v openFPGALoader >/dev/null 2>&1; then
  if sudo apt-get install -y openfpgaloader; then
    echo "[INFO] Installed openFPGALoader from apt"
  else
    echo "[INFO] openfpgaloader package not found in apt; building from source..."
    tmpdir=$(mktemp -d)
    git clone --depth 1 https://github.com/trabucayre/openFPGALoader.git "$tmpdir/openFPGALoader"
    cmake -S "$tmpdir/openFPGALoader" -B "$tmpdir/openFPGALoader/build" -DCMAKE_BUILD_TYPE=Release
    cmake --build "$tmpdir/openFPGALoader/build" -j"$(nproc)"
    sudo cmake --install "$tmpdir/openFPGALoader/build"
    if [ -f "$tmpdir/openFPGALoader/99-openfpgaloader.rules" ]; then
      sudo install -Dm0644 "$tmpdir/openFPGALoader/99-openfpgaloader.rules" /etc/udev/rules.d/99-openfpgaloader.rules
    fi
    rm -rf "$tmpdir"
  fi
fi

sudo udevadm control --reload-rules
sudo udevadm trigger
sudo usermod -aG plugdev "$USER" || true

echo
echo "Host setup complete. Log out/in, unplug/replug FPGA board, then run:"
echo "  bash opt/phase3/scripts/host_preflight.sh"
