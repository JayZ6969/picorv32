#!/usr/bin/env bash
set -euo pipefail

cd /mnt/toshiba4tb/workspace/projects/picorv32/opt

sweep_dir="/tmp/p3_opt_sweep_$(date +%s)"
mkdir -p "$sweep_dir"
printf 'cfg,latched_mem,fast_add,barrel,lut4,carry,dff,bram,pnr_rc,fmax_mhz\n' > "$sweep_dir/summary.csv"

cat > "$sweep_dir/configs.txt" <<'EOF'
base 1 1 1
fa0 1 0 1
lat0 0 1 1
bar0 1 1 0
fa0_lat0 0 0 1
fa0_bar0 1 0 0
EOF

while read -r name lat fa bar; do
  wrapper="$sweep_dir/wrapper_${name}.v"
  ys="$sweep_dir/synth_${name}.ys"
  json="$sweep_dir/design_${name}.json"
  blif="$sweep_dir/design_${name}.blif"
  statlog="$sweep_dir/stat_${name}.log"
  ylog="$sweep_dir/yosys_${name}.log"
  asc="$sweep_dir/design_${name}.asc"
  report="$sweep_dir/report_${name}.json"
  pnrlog="$sweep_dir/pnr_${name}.log"

  cat > "$wrapper" <<'EOF'
`timescale 1ns/1ps
module picorv32_optimized_sweep_wrapper (
    input  wire        clk,
    input  wire        resetn,
    output wire        trap,
    output wire        mem_valid,
    output wire        mem_instr,
    output wire [7:0]  mem_addr_lo,
    output wire [7:0]  mem_wdata_lo,
    output wire [3:0]  mem_wstrb
);
wire [31:0] mem_rdata = 32'b0;
wire        mem_ready = 1'b1;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0]  mem_wstrb_int;
assign mem_addr_lo = mem_addr[7:0];
assign mem_wdata_lo = mem_wdata[7:0];
assign mem_wstrb = mem_wstrb_int;
picorv32 #(
    .ENABLE_COUNTERS(0),
    .ENABLE_COUNTERS64(0),
    .LATCHED_MEM_RDATA(__LAT__),
    .ENABLE_MUL(1),
    .ENABLE_FAST_MUL(1),
    .ENABLE_FAST_ADD(__FA__),
    .BARREL_SHIFTER(__BAR__)
) u_core (
    .clk(clk),
    .resetn(resetn),
    .trap(trap),
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(mem_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb_int),
    .mem_rdata(mem_rdata),
    .irq(32'b0),
    .eoi(),
    .trace_valid(),
    .trace_data()
);
endmodule
EOF
  sed -i "s/__LAT__/$lat/; s/__FA__/$fa/; s/__BAR__/$bar/" "$wrapper"

  cat > "$ys" <<EOF
read_verilog -I.. ../picorv32.v
read_verilog rtl/ksa/ksa_adder.v
read_verilog rtl/ksa/ksa_32bit.v
read_verilog rtl/ksa/ksa_64bit_pipelined.v
read_verilog rtl/csa/csa_cell.v
read_verilog rtl/vedic/vedic_mul_2x2.v
read_verilog rtl/vedic/vedic_mul_4x4.v
read_verilog rtl/vedic/vedic_mul_8x8.v
read_verilog rtl/vedic/vedic_mul_16x16.v
read_verilog rtl/vedic/vedic_mul_32x32.v
read_verilog rtl/pcpi/pcpi_vedic_mul.v
read_verilog $wrapper
hierarchy -check -top picorv32_optimized_sweep_wrapper
synth_ice40 -top picorv32_optimized_sweep_wrapper -json $json -blif $blif -dsp
tee -q -o $statlog stat
EOF

  yosys -q -s "$ys" > "$ylog" 2>&1 || true

  lut4=$(awk '/SB_LUT4/{print $2}' "$statlog" | tail -n 1)
  carry=$(awk '/SB_CARRY/{print $2}' "$statlog" | tail -n 1)
  dff=$(awk '/SB_DFF/{sum+=$2} END{if (sum=="") sum=0; print sum}' "$statlog")
  bram=$(awk '/SB_RAM40_4K/{print $2}' "$statlog" | tail -n 1)

  if nextpnr-ice40 --up5k --package sg48 --freq 12 --json "$json" --pcf constraints/picorv32_ice40up5k.pcf --asc "$asc" --report "$report" --seed 1 --timing-allow-fail --pcf-allow-unconstrained > "$pnrlog" 2>&1; then
    pnr_rc=0
  else
    pnr_rc=1
  fi

  fmax=$(grep -m1 "Max frequency for clock" "$pnrlog" | sed "s/^.*: //; s/ (.*$//; s/ MHz$//" || true)
  if [[ -z "${fmax:-}" && -f "$report" ]]; then
    fmax=$(python3 - <<'PY' "$report"
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    fmax = data.get("fmax", {})
    if not fmax:
        print("")
    else:
        first = next(iter(fmax.values()))
        v = first.get("achieved", "")
        print(v if v is not None else "")
except Exception:
    print("")
PY
)
  fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$name" "$lat" "$fa" "$bar" "${lut4:-}" "${carry:-}" "${dff:-}" "${bram:-}" "$pnr_rc" "${fmax:-}" >> "$sweep_dir/summary.csv"
  echo "[$name] LUT4=${lut4:-NA} CARRY=${carry:-NA} pnr_rc=$pnr_rc fmax=${fmax:-NA}"
done < "$sweep_dir/configs.txt"

echo "SWEEP_DIR=$sweep_dir"
cat "$sweep_dir/summary.csv"
