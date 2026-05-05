#!/usr/bin/env bash
set -euo pipefail

cd /mnt/toshiba4tb/workspace/projects/picorv32/opt

out="/tmp/native_fmax_sweep_$(date +%s)"
mkdir -p "$out"

cat > "$out/wrapper_template.v" <<'EOF'
`timescale 1ns/1ps
module picorv32_optimized_wrapper (
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
    .LATCHED_MEM_RDATA(1),
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

printf 'case,fa,bar,mul_params,seed,rc,lut4,fmax_mhz\n' > "$out/results.csv"

run_case() {
  local name="$1"
  local fa="$2"
  local bar="$3"
  local mul_params="$4"
  local seed="$5"

  local shim="$out/pcpi_${name}.v"
  local wrapper="$out/wrapper_${name}.v"
  local ys="$out/synth_${name}.ys"
  local json="$out/design_${name}.json"
  local asc="$out/design_${name}.asc"
  local rpt="$out/report_${name}.json"
  local ylog="$out/yosys_${name}.log"
  local plog="$out/pnr_${name}.log"
  local slog="$out/stat_${name}.log"

  cat > "$shim" <<'EOF'
`timescale 1ns/1ps
module pcpi_vedic_mul (
  input clk,
  input resetn,
  input pcpi_valid,
  input [31:0] pcpi_insn,
  input [31:0] pcpi_rs1,
  input [31:0] pcpi_rs2,
  output pcpi_wr,
  output [31:0] pcpi_rd,
  output pcpi_wait,
  output pcpi_ready
);
picorv32_pcpi_fast_mul __MUL_PARAMS__ u_fast_mul (
  .clk(clk),
  .resetn(resetn),
  .pcpi_valid(pcpi_valid),
  .pcpi_insn(pcpi_insn),
  .pcpi_rs1(pcpi_rs1),
  .pcpi_rs2(pcpi_rs2),
  .pcpi_wr(pcpi_wr),
  .pcpi_rd(pcpi_rd),
  .pcpi_wait(pcpi_wait),
  .pcpi_ready(pcpi_ready)
);
endmodule
EOF
  sed -i "s|__MUL_PARAMS__|$mul_params|" "$shim"

  cp "$out/wrapper_template.v" "$wrapper"
  sed -i "s/__FA__/$fa/; s/__BAR__/$bar/" "$wrapper"

  cat > "$ys" <<EOF
read_verilog -I.. ../picorv32.v
read_verilog rtl/ksa/ksa_adder.v
read_verilog rtl/ksa/ksa_32bit.v
read_verilog rtl/ksa/ksa_64bit_pipelined.v
read_verilog $shim
read_verilog $wrapper
hierarchy -check -top picorv32_optimized_wrapper
synth_ice40 -top picorv32_optimized_wrapper -json $json
tee -q -o $slog stat
EOF

  yosys -q -s "$ys" > "$ylog" 2>&1

  local lut4
  lut4=$(awk '/SB_LUT4/{print $2}' "$slog" | tail -n 1)

  local rc
  if nextpnr-ice40 --up5k --package sg48 --freq 20 --json "$json" --pcf constraints/picorv32_ice40up5k.pcf --asc "$asc" --report "$rpt" --timing-allow-fail --pcf-allow-unconstrained --seed "$seed" > "$plog" 2>&1; then
    rc=0
  else
    rc=$?
  fi

  local fmax
  fmax=$(grep -m1 "Max frequency for clock" "$plog" | sed 's/^.*: //; s/ (.*$//; s/ MHz$//' || true)
  if [[ -z "${fmax:-}" && -f "$rpt" ]]; then
    fmax=$(python3 - <<'PY' "$rpt"
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    f=d.get('fmax',{})
    if not f:
        print('')
    else:
        v=next(iter(f.values())).get('achieved','')
        print(v if v is not None else '')
except Exception:
    print('')
PY
)
  fi

  printf '%s,%s,%s,"%s",%s,%s,%s,%s\n' "$name" "$fa" "$bar" "$mul_params" "$seed" "$rc" "${lut4:-}" "${fmax:-}" >> "$out/results.csv"
  echo "[$name] fa=$fa bar=$bar seed=$seed rc=$rc LUT4=${lut4:-NA} Fmax=${fmax:-NA}"
}

# Baseline native fast-mul settings and timing-pipeline variants.
run_case native_fa1_bar0 1 0 "" 1
run_case native_fa0_bar0 0 0 "" 1
run_case native_xff_fa1_bar0 1 0 "#(.EXTRA_MUL_FFS(1), .EXTRA_INSN_FFS(1), .MUL_CLKGATE(1))" 1
run_case native_xff_fa0_bar0 0 0 "#(.EXTRA_MUL_FFS(1), .EXTRA_INSN_FFS(1), .MUL_CLKGATE(1))" 1

# Quick seed exploration for the best default native case.
for s in 1 2 3 4 5 6 7 8 9 10; do
  run_case native_fa1_bar0_seed${s} 1 0 "" "$s"
done

echo "OUT_DIR=$out"
cat "$out/results.csv"
