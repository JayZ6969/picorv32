#!/bin/bash
set -e
echo "Building uart_test..."
yosys -p "synth_ice40 -top uart_test -json uart_test.json" uart_test.v
nextpnr-ice40 --up5k --package sg48 --json uart_test.json --pcf icesugar_test.pcf --asc uart_test.asc
icepack uart_test.asc uart_test.bin
echo "Flashing uart_test..."
icesprog uart_test.bin
echo "Capturing UART..."
python3 opt/scripts/hw/capture_uart.py uart_test /dev/ttyACM0
