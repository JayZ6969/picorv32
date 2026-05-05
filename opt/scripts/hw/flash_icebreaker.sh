#!/bin/bash

# Script to program IceBreaker FPGA using OpenOCD with CMSIS-DAP

# Configuration
SCRIPT_DIR="$(dirname "$0")"
BITSTREAM_FILE="$(pwd)/opt/hw/bitstreams/optimized.bin"
OPENOCD_CFG="${SCRIPT_DIR}/openocd_icebreaker.cfg"

# Check if bitstream exists
if [ ! -f "$BITSTREAM_FILE" ]; then
    echo "❌ Error: Bitstream file not found at $BITSTREAM_FILE"
    echo "   Run 'make -C opt p3_bitstream' first to generate the bitstream."
    exit 1
fi

# Check if OpenOCD is installed
if ! command -v openocd &> /dev/null; then
    echo "❌ Error: OpenOCD not found. Please install it with:"
    echo "   sudo apt update && sudo apt install -y openocd"
    exit 1
fi

# Check if CMSIS-DAP device is connected
if ! lsusb | grep -q "1d50:602b"; then
    echo "❌ Error: IceBreaker board (CMSIS-DAP) not detected."
    echo "   Please ensure the board is connected and powered on."
    echo "   Device ID should be 1d50:602b (MuseLab DAPLink CMSIS-DAP)"
    exit 1
fi

# Start OpenOCD in background
openocd -f "$OPENOCD_CFG" -c "init" -c "targets" -c "halt" -c "program $BITSTREAM_FILE verify reset exit" 2>&1 | tee /tmp/openocd_log.txt

# Check result
if grep -q "Error" /tmp/openocd_log.txt; then
    echo "❌ Programming failed. Check /tmp/openocd_log.txt for details."
    exit 1
else
    echo "✅ Successfully programmed IceBreaker FPGA with $BITSTREAM_FILE"
    echo "   Board should now be running the PicoRV32 design."
fi

# Clean up
rm -f /tmp/openocd_log.txt