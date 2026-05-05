IVERILOG ?= iverilog
VVP      ?= vvp
SBY      ?= sby
YOSYS    ?= yosys
PYTHON   ?= python3
VERILATOR ?= verilator
EQUIV_TIMEOUT ?= 300
BEST_EFFORT_TIMEOUT ?= 300
EQUIV_MAKE_JOBS ?= $(shell nproc 2>/dev/null || echo 4)
RUN_VEDIC_HEAVY ?= 0
RUN_FULL_VEDIC ?= 0
HAS_SBY ?= $(shell command -v $(SBY) >/dev/null 2>&1 && echo 1 || echo 0)
VVP_LINEBUF ?= $(shell command -v stdbuf >/dev/null 2>&1 && echo "stdbuf -oL" || echo "")
VVP_PLUSARGS ?=
PCPI_DEFAULT_PLUSARGS ?= +stress20 +reset_midop +rand1k +rand_groups=1000
PCPI_RAND1K_PLUSARGS ?= +stress20 +reset_midop +rand1k +rand_groups=1000
REPORT_DIR ?= synth/reports
BENCH_FW ?= firmware/bench/bench.hex
OPT_BENCH_FIRMWARE ?= $(BENCH_FW)

KSA_RTL = rtl/ksa/ksa_adder.v rtl/ksa/ksa_32bit.v rtl/ksa/ksa_64bit_pipelined.v
CSA_RTL = rtl/csa/csa_cell.v
VEDIC_TREE_RTL = $(CSA_RTL) rtl/vedic/vedic_mul_2x2.v rtl/vedic/vedic_mul_4x4.v rtl/vedic/vedic_mul_8x8.v rtl/vedic/vedic_mul_16x16.v rtl/vedic/vedic_mul_32x32.v
VEDIC_RTL = $(KSA_RTL) $(VEDIC_TREE_RTL)
PCPI_VEDIC_RTL = rtl/pcpi/pcpi_vedic_mul.v
PCPI_FAST_SHIM_RTL = rtl/pcpi/pcpi_vedic_mul_fastshim.v

.PHONY: all prep_dirs firmware lint_ksa lint_vedic lint_pcpi lint_phase1 sim_ksa sim_vedic sim_vedic_quick sim_pcpi sim_pcpi_rand1k sim_integration sim_pcpi_baseline_A sim_pcpi_baseline_B sim_integration_baseline_A_mul sim_integration_baseline_B_mul sim_integration_baseline_A_bench sim_integration_baseline_B_bench sim_integration_opt_metrics sim_integration_opt_bench sim_integration_baseline_A_mul_vcd sim_integration_baseline_B_mul_vcd sim_integration_opt_metrics_vcd switching_baseline_A_mul switching_baseline_B_mul switching_optimized_mul compare_switching formal_ksa formal_vedic formal_vedic_fast formal_vedic_full formal_vedic_2x2 formal_vedic_4x4 formal_vedic_8x8 formal_vedic_16x16_ag formal_vedic_32x32_ag equiv_vedic_16x16 equiv_vedic_32x32 equiv_vedic_parallel vedic_heavy_optional vedic_heavy_best_effort stage0_freeze area_baseline_A area_baseline_B area_baseline_C area_optimized stage2_area_capture layer0_perf_capture layer0_switching_capture quality_capture baseline_reports baseline_capture_all p3_check p3_synth p3_area p3_pnr p3_timing p3_composites p3_report phase3 phase5 report_figures phase2_refresh_perf phase2_all phase2_all_full hw_check_board hw_pack_bitstreams hw_flash_baseline_A hw_flash_baseline_C hw_flash_optimized hw_stage6 clean_phase2 clean_baseline

all: phase2_all

prep_dirs:
	mkdir -p sim sim/logs sim/vcd $(REPORT_DIR)

firmware:
	$(MAKE) -C firmware/mul_test all
	$(MAKE) -C firmware/bench all

lint_ksa: prep_dirs
	$(VERILATOR) --lint-only -Wall $(KSA_RTL) 2>&1 | tee sim/logs/lint_ksa.log

lint_vedic: prep_dirs
	$(VERILATOR) --lint-only -Wall $(VEDIC_RTL) 2>&1 | tee sim/logs/lint_vedic.log

lint_pcpi: prep_dirs
	$(VERILATOR) --lint-only -Wall --top-module pcpi_vedic_mul $(VEDIC_RTL) $(PCPI_VEDIC_RTL) 2>&1 | tee sim/logs/lint_pcpi.log

lint_phase1: lint_ksa lint_vedic lint_pcpi

sim_ksa: prep_dirs
	$(IVERILOG) -o sim/ksa_sim \
		$(KSA_RTL) \
		tb/unit/tb_ksa_32bit.v
		$(VVP) sim/ksa_sim $(VVP_PLUSARGS) | tee sim/logs/ksa.log

sim_vedic: prep_dirs
	$(IVERILOG) -o sim/vedic_sim \
		$(VEDIC_RTL) \
		tb/unit/tb_vedic_mul_32x32.v
		$(VVP_LINEBUF) $(VVP) sim/vedic_sim $(VVP_PLUSARGS) | tee sim/logs/vedic.log

sim_vedic_quick: prep_dirs
	$(IVERILOG) -o sim/vedic_sim \
		$(VEDIC_RTL) \
		tb/unit/tb_vedic_mul_32x32.v
	$(VVP_LINEBUF) $(VVP) sim/vedic_sim +quick $(VVP_PLUSARGS) | tee sim/logs/vedic_quick.log

sim_pcpi: prep_dirs
	$(IVERILOG) -o sim/pcpi_sim \
		$(VEDIC_RTL) \
		$(PCPI_VEDIC_RTL) \
		tb/pcpi/tb_pcpi_vedic_mul.v
		$(VVP) sim/pcpi_sim $(PCPI_DEFAULT_PLUSARGS) $(VVP_PLUSARGS) | tee sim/logs/pcpi.log sim/logs/pcpi_optimized.log

sim_pcpi_rand1k: prep_dirs
	$(IVERILOG) -o sim/pcpi_sim \
		$(VEDIC_RTL) \
		$(PCPI_VEDIC_RTL) \
		tb/pcpi/tb_pcpi_vedic_mul.v
	$(VVP) sim/pcpi_sim $(PCPI_RAND1K_PLUSARGS) $(VVP_PLUSARGS) | tee sim/logs/pcpi_rand1k.log

sim_pcpi_baseline_A: prep_dirs
	$(IVERILOG) -o sim/pcpi_baseline_A_sim \
		-DBASELINE_CONFIG=0 \
		../picorv32.v \
		tb/pcpi/tb_pcpi_baseline_mul.v
	$(VVP) sim/pcpi_baseline_A_sim $(VVP_PLUSARGS) | tee sim/logs/pcpi_baseline_A.log

sim_pcpi_baseline_B: prep_dirs
	$(IVERILOG) -o sim/pcpi_baseline_B_sim \
		-DBASELINE_CONFIG=1 \
		../picorv32.v \
		tb/pcpi/tb_pcpi_baseline_mul.v
	$(VVP) sim/pcpi_baseline_B_sim $(VVP_PLUSARGS) | tee sim/logs/pcpi_baseline_B.log

sim_integration: prep_dirs firmware
	$(IVERILOG) -o sim/integration_sim \
		../picorv32.v \
		$(KSA_RTL) \
		$(VEDIC_TREE_RTL) \
		$(PCPI_VEDIC_RTL) \
		tb/integration/tb_picorv32_top.v
		$(VVP) sim/integration_sim $(VVP_PLUSARGS) | tee sim/logs/integration.log

sim_integration_baseline_A_mul: prep_dirs firmware
	$(IVERILOG) -o sim/integration_baseline_A_mul_sim \
		-DENABLE_FAST_MUL=0 \
		-DFIRMWARE='"firmware/mul_test/mul_test.hex"' \
		../picorv32.v \
		tb/integration/tb_picorv32_baseline_top.v
	$(VVP) sim/integration_baseline_A_mul_sim $(VVP_PLUSARGS) | tee sim/logs/integration_baseline_A_mul.log

sim_integration_baseline_B_mul: prep_dirs firmware
	$(IVERILOG) -o sim/integration_baseline_B_mul_sim \
		-DENABLE_FAST_MUL=1 \
		-DFIRMWARE='"firmware/mul_test/mul_test.hex"' \
		../picorv32.v \
		$(PCPI_FAST_SHIM_RTL) \
		tb/integration/tb_picorv32_baseline_top.v
	$(VVP) sim/integration_baseline_B_mul_sim $(VVP_PLUSARGS) | tee sim/logs/integration_baseline_B_mul.log

sim_integration_baseline_A_bench: prep_dirs firmware
	$(IVERILOG) -o sim/integration_baseline_A_bench_sim \
		-DENABLE_FAST_MUL=0 \
		-DFIRMWARE='"$(BENCH_FW)"' \
		../picorv32.v \
		tb/integration/tb_picorv32_baseline_top.v
	$(VVP) sim/integration_baseline_A_bench_sim $(VVP_PLUSARGS) | tee sim/logs/integration_baseline_A_bench.log

sim_integration_baseline_B_bench: prep_dirs firmware
	$(IVERILOG) -o sim/integration_baseline_B_bench_sim \
		-DENABLE_FAST_MUL=1 \
		-DFIRMWARE='"$(BENCH_FW)"' \
		../picorv32.v \
		$(PCPI_FAST_SHIM_RTL) \
		tb/integration/tb_picorv32_baseline_top.v
	$(VVP) sim/integration_baseline_B_bench_sim $(VVP_PLUSARGS) | tee sim/logs/integration_baseline_B_bench.log

sim_integration_opt_metrics: prep_dirs firmware
	$(IVERILOG) -o sim/integration_optimized_mul_sim \
		-DFIRMWARE='"firmware/mul_test/mul_test.hex"' \
		../picorv32.v \
		$(KSA_RTL) \
		$(VEDIC_TREE_RTL) \
		$(PCPI_VEDIC_RTL) \
		tb/integration/tb_picorv32_top.v
	$(VVP) sim/integration_optimized_mul_sim $(VVP_PLUSARGS) | tee sim/logs/integration_optimized_mul.log sim/logs/integration.log

sim_integration_opt_bench: prep_dirs firmware
	@if [ ! -f "$(OPT_BENCH_FIRMWARE)" ]; then \
		echo "[info] skipping optimized bench run: missing $(OPT_BENCH_FIRMWARE)"; \
		rm -f sim/logs/integration_optimized_bench.log; \
	else \
		$(IVERILOG) -o sim/integration_optimized_bench_sim \
			-DFIRMWARE='"$(OPT_BENCH_FIRMWARE)"' \
			../picorv32.v \
			$(KSA_RTL) \
			$(VEDIC_TREE_RTL) \
			$(PCPI_VEDIC_RTL) \
			tb/integration/tb_picorv32_top.v; \
		$(VVP) sim/integration_optimized_bench_sim $(VVP_PLUSARGS) | tee sim/logs/integration_optimized_bench.log; \
	fi

sim_integration_baseline_A_mul_vcd: prep_dirs firmware
	$(IVERILOG) -o sim/integration_baseline_A_mul_vcd_sim \
		-DENABLE_FAST_MUL=0 \
		-DFIRMWARE='"firmware/mul_test/mul_test.hex"' \
		../picorv32.v \
		tb/integration/tb_picorv32_baseline_top.v
	$(VVP) sim/integration_baseline_A_mul_vcd_sim +dump_vcd | tee sim/logs/integration_baseline_A_mul.log
	cp -f sim/vcd/picorv32_integration.vcd sim/vcd/integration_baseline_A_mul.vcd

sim_integration_baseline_B_mul_vcd: prep_dirs firmware
	$(IVERILOG) -o sim/integration_baseline_B_mul_vcd_sim \
		-DENABLE_FAST_MUL=1 \
		-DFIRMWARE='"firmware/mul_test/mul_test.hex"' \
		../picorv32.v \
		$(PCPI_FAST_SHIM_RTL) \
		tb/integration/tb_picorv32_baseline_top.v
	$(VVP) sim/integration_baseline_B_mul_vcd_sim +dump_vcd | tee sim/logs/integration_baseline_B_mul.log
	cp -f sim/vcd/picorv32_integration.vcd sim/vcd/integration_baseline_B_mul.vcd

sim_integration_opt_metrics_vcd: prep_dirs firmware
	$(IVERILOG) -o sim/integration_optimized_mul_vcd_sim \
		-DDUMP_VCD \
		-DFIRMWARE='"firmware/mul_test/mul_test.hex"' \
		../picorv32.v \
		$(KSA_RTL) \
		$(VEDIC_TREE_RTL) \
		$(PCPI_VEDIC_RTL) \
		tb/integration/tb_picorv32_top.v
	$(VVP) sim/integration_optimized_mul_vcd_sim $(VVP_PLUSARGS) | tee sim/logs/integration_optimized_mul.log
	cp -f sim/vcd/picorv32_integration.vcd sim/vcd/integration_optimized_mul.vcd

switching_baseline_A_mul: sim_integration_baseline_A_mul_vcd
	@cycles=$$(awk '/^METRIC total_cycles / {print $$3; exit}' sim/logs/integration_baseline_A_mul.log); \
	$(PYTHON) scripts/count_switching.py sim/vcd/integration_baseline_A_mul.vcd $${cycles:-0} | tee sim/logs/switching_baseline_A_mul.log $(REPORT_DIR)/baseline_A_switching.txt

switching_baseline_B_mul: sim_integration_baseline_B_mul_vcd
	@cycles=$$(awk '/^METRIC total_cycles / {print $$3; exit}' sim/logs/integration_baseline_B_mul.log); \
	$(PYTHON) scripts/count_switching.py sim/vcd/integration_baseline_B_mul.vcd $${cycles:-0} | tee sim/logs/switching_baseline_B_mul.log $(REPORT_DIR)/baseline_B_switching.txt

switching_optimized_mul: sim_integration_opt_metrics_vcd
	@cycles=$$(awk '/^METRIC total_cycles / {print $$3; exit}' sim/logs/integration_optimized_mul.log); \
	$(PYTHON) scripts/count_switching.py sim/vcd/integration_optimized_mul.vcd $${cycles:-0} | tee sim/logs/switching_optimized_mul.log $(REPORT_DIR)/optimized_switching.txt

compare_switching:
	$(PYTHON) scripts/compare_switching.py | tee $(REPORT_DIR)/switching_comparison.txt

formal_ksa:
	@if [ "$(HAS_SBY)" = "1" ]; then \
		$(SBY) -f formal/ksa/ksa_formal.sby; \
	else \
		echo "[fallback] $(SBY) not found; running direct yosys SAT for ksa_formal"; \
		$(YOSYS) -q -p 'read_verilog -formal formal/ksa/ksa_formal.v rtl/ksa/ksa_adder.v rtl/ksa/ksa_32bit.v; prep -top ksa_formal; flatten; opt -full; select -module ksa_formal; sat -verify -prove-asserts -set-def-inputs'; \
		echo "[ok] yosys SAT passed: ksa_formal"; \
	fi

formal_vedic_2x2:
	@if [ "$(HAS_SBY)" = "1" ]; then \
		$(SBY) -f formal/vedic/vedic_2x2_formal.sby; \
	else \
		echo "[fallback] $(SBY) not found; running direct yosys SAT for vedic_2x2_formal"; \
		$(YOSYS) -q -p 'read_verilog -formal formal/vedic/vedic_2x2_formal.v rtl/vedic/vedic_mul_2x2.v; prep -top vedic_2x2_formal; flatten; opt -full; select -module vedic_2x2_formal; sat -verify -prove-asserts -set-def-inputs'; \
		echo "[ok] yosys SAT passed: vedic_2x2_formal"; \
	fi

formal_vedic_4x4:
	@if [ "$(HAS_SBY)" = "1" ]; then \
		$(SBY) -f formal/vedic/vedic_4x4_formal.sby; \
	else \
		echo "[fallback] $(SBY) not found; running direct yosys SAT for vedic_4x4_formal"; \
		$(YOSYS) -q -p 'read_verilog -formal formal/vedic/vedic_4x4_formal.v rtl/vedic/vedic_mul_2x2.v rtl/vedic/vedic_mul_4x4.v; prep -top vedic_4x4_formal; flatten; opt -full; select -module vedic_4x4_formal; sat -verify -prove-asserts -set-def-inputs'; \
		echo "[ok] yosys SAT passed: vedic_4x4_formal"; \
	fi

formal_vedic_8x8:
	@if [ "$(HAS_SBY)" = "1" ]; then \
		$(SBY) -f formal/vedic/vedic_8x8_formal.sby; \
	else \
		echo "[fallback] $(SBY) not found; running direct yosys SAT for vedic_8x8_formal"; \
		$(YOSYS) -q -p 'read_verilog -formal formal/vedic/vedic_8x8_formal.v rtl/vedic/vedic_mul_2x2.v rtl/vedic/vedic_mul_4x4.v rtl/vedic/vedic_mul_8x8.v; prep -top vedic_8x8_formal; flatten; opt -full; select -module vedic_8x8_formal; sat -verify -prove-asserts -set-def-inputs'; \
		echo "[ok] yosys SAT passed: vedic_8x8_formal"; \
	fi

formal_vedic_16x16_ag:
	@if [ "$(HAS_SBY)" = "1" ]; then \
		$(SBY) -f formal/vedic/vedic_16x16_ag_formal.sby; \
	else \
		echo "[skip] $(SBY) not found; skipping formal/vedic/vedic_16x16_ag_formal.sby"; \
	fi

formal_vedic_32x32_ag:
	@if [ "$(HAS_SBY)" = "1" ]; then \
		$(SBY) -f formal/vedic/vedic_32x32_ag_formal.sby; \
	else \
		echo "[skip] $(SBY) not found; skipping formal/vedic/vedic_32x32_ag_formal.sby"; \
	fi

vedic_heavy_best_effort:
	@if [ "$(HAS_SBY)" = "1" ]; then \
		echo "[best-effort] trying formal_vedic_16x16_ag (timeout: $(BEST_EFFORT_TIMEOUT)s)"; \
		timeout --foreground $(BEST_EFFORT_TIMEOUT)s $(SBY) -f formal/vedic/vedic_16x16_ag_formal.sby || true; \
		echo "[best-effort] trying formal_vedic_32x32_ag (timeout: $(BEST_EFFORT_TIMEOUT)s)"; \
		timeout --foreground $(BEST_EFFORT_TIMEOUT)s $(SBY) -f formal/vedic/vedic_32x32_ag_formal.sby || true; \
	else \
		echo "[skip] $(SBY) not found; skipping AG formal_vedic_16x16/32x32"; \
	fi
	@echo "[best-effort] trying equiv_vedic_parallel (jobs: $(EQUIV_MAKE_JOBS), timeout per job: $(EQUIV_TIMEOUT)s)"
	@$(MAKE) --no-print-directory EQUIV_TIMEOUT=$(EQUIV_TIMEOUT) EQUIV_MAKE_JOBS=$(EQUIV_MAKE_JOBS) equiv_vedic_parallel || true

vedic_heavy_optional:
	@if [ "$(RUN_VEDIC_HEAVY)" = "1" ]; then \
		echo "[optional] RUN_VEDIC_HEAVY=1 -> running heavy 16x16/32x32 checks"; \
		$(MAKE) --no-print-directory BEST_EFFORT_TIMEOUT=$(BEST_EFFORT_TIMEOUT) EQUIV_TIMEOUT=$(EQUIV_TIMEOUT) vedic_heavy_best_effort; \
	else \
		echo "[optional] skipping heavy 16x16/32x32 checks (set RUN_VEDIC_HEAVY=1 to enable)"; \
	fi

equiv_vedic_16x16:
	@echo "[equiv_16x16] running yosys with live output (timeout: $(EQUIV_TIMEOUT)s)"
	@rc=0; \
	timeout --foreground $(EQUIV_TIMEOUT)s $(YOSYS) -l formal/vedic/equiv_16x16.log formal/vedic/equiv_16x16.ys || rc=$$?; \
	if [ $$rc -eq 124 ]; then \
		echo "[equiv_16x16] timed out after $(EQUIV_TIMEOUT)s"; \
		tail -n 80 formal/vedic/equiv_16x16.log; \
		exit $$rc; \
	fi; \
	exit $$rc

equiv_vedic_32x32:
	@echo "[equiv_32x32] running yosys with live output (timeout: $(EQUIV_TIMEOUT)s)"
	@rc=0; \
	timeout --foreground $(EQUIV_TIMEOUT)s $(YOSYS) -l formal/vedic/equiv_32x32.log formal/vedic/equiv_32x32.ys || rc=$$?; \
	if [ $$rc -eq 124 ]; then \
		echo "[equiv_32x32] timed out after $(EQUIV_TIMEOUT)s"; \
		tail -n 80 formal/vedic/equiv_32x32.log; \
		exit $$rc; \
	fi; \
	exit $$rc

equiv_vedic_parallel:
	@echo "[equiv_parallel] running 16x16 + 32x32 in parallel (jobs: $(EQUIV_MAKE_JOBS), timeout per job: $(EQUIV_TIMEOUT)s)"
	@$(MAKE) --no-print-directory -j$(EQUIV_MAKE_JOBS) EQUIV_TIMEOUT=$(EQUIV_TIMEOUT) equiv_vedic_16x16 equiv_vedic_32x32

formal_vedic_fast: formal_vedic_2x2 formal_vedic_4x4 formal_vedic_8x8

formal_vedic_full: formal_vedic_fast vedic_heavy_best_effort

formal_vedic: formal_vedic_fast vedic_heavy_optional

stage0_freeze: prep_dirs
	@echo "date_utc=$$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > $(REPORT_DIR)/baseline_stage0_env.txt
	@echo "git_head=$$(git -C .. rev-parse HEAD 2>/dev/null || echo unknown)" >> $(REPORT_DIR)/baseline_stage0_env.txt
	@echo "git_status=" > $(REPORT_DIR)/baseline_stage0_git_status.txt
	@git -C .. status --short >> $(REPORT_DIR)/baseline_stage0_git_status.txt || true
	@echo "tools:" > $(REPORT_DIR)/baseline_stage0_tools.txt
	@($(IVERILOG) -V | head -n 1) >> $(REPORT_DIR)/baseline_stage0_tools.txt 2>&1 || true
	@($(VVP) -V | head -n 1) >> $(REPORT_DIR)/baseline_stage0_tools.txt 2>&1 || true
	@($(YOSYS) -V) >> $(REPORT_DIR)/baseline_stage0_tools.txt 2>&1 || true
	@($(SBY) --version) >> $(REPORT_DIR)/baseline_stage0_tools.txt 2>&1 || true
	@($(PYTHON) --version) >> $(REPORT_DIR)/baseline_stage0_tools.txt 2>&1 || true

area_baseline_A: prep_dirs
	@if $(YOSYS) -Q -p 'help synth_ice40' >/dev/null 2>&1; then \
		$(YOSYS) -q -l $(REPORT_DIR)/baseline_A_stat.log -p 'read_verilog ../picorv32.v; chparam -set ENABLE_MUL 1 picorv32; chparam -set ENABLE_FAST_MUL 0 picorv32; hierarchy -top picorv32; synth_ice40 -top picorv32; stat'; \
	else \
		$(YOSYS) -q -l $(REPORT_DIR)/baseline_A_stat.log -p 'read_verilog ../picorv32.v; chparam -set ENABLE_MUL 1 picorv32; chparam -set ENABLE_FAST_MUL 0 picorv32; hierarchy -top picorv32; synth -top picorv32; stat'; \
	fi

area_baseline_B: prep_dirs
	@if $(YOSYS) -Q -p 'help synth_ice40' >/dev/null 2>&1; then \
		$(YOSYS) -q -l $(REPORT_DIR)/baseline_B_stat.log -p 'read_verilog ../picorv32.v $(PCPI_FAST_SHIM_RTL); chparam -set ENABLE_MUL 1 picorv32; chparam -set ENABLE_FAST_MUL 1 picorv32; hierarchy -top picorv32; synth_ice40 -top picorv32; stat'; \
	else \
		$(YOSYS) -q -l $(REPORT_DIR)/baseline_B_stat.log -p 'read_verilog ../picorv32.v $(PCPI_FAST_SHIM_RTL); chparam -set ENABLE_MUL 1 picorv32; chparam -set ENABLE_FAST_MUL 1 picorv32; hierarchy -top picorv32; synth -top picorv32; stat'; \
	fi

area_baseline_C: prep_dirs
	@if $(YOSYS) -Q -p 'help synth_ice40' >/dev/null 2>&1; then \
		$(YOSYS) -q -l $(REPORT_DIR)/baseline_C_stat.log -p 'read_verilog ../picorv32.v; chparam -set ENABLE_MUL 0 picorv32; chparam -set ENABLE_FAST_MUL 0 picorv32; hierarchy -top picorv32; synth_ice40 -top picorv32; stat'; \
	else \
		$(YOSYS) -q -l $(REPORT_DIR)/baseline_C_stat.log -p 'read_verilog ../picorv32.v; chparam -set ENABLE_MUL 0 picorv32; chparam -set ENABLE_FAST_MUL 0 picorv32; hierarchy -top picorv32; synth -top picorv32; stat'; \
	fi

area_optimized: prep_dirs
	@if $(YOSYS) -Q -p 'help synth_ice40' >/dev/null 2>&1; then \
		$(YOSYS) -q -l $(REPORT_DIR)/optimized_stat.log -p 'read_verilog ../picorv32.v $(KSA_RTL) $(VEDIC_TREE_RTL) $(PCPI_VEDIC_RTL); chparam -set ENABLE_MUL 1 picorv32; chparam -set ENABLE_FAST_MUL 1 picorv32; hierarchy -top picorv32; synth_ice40 -top picorv32; stat'; \
	else \
		$(YOSYS) -q -l $(REPORT_DIR)/optimized_stat.log -p 'read_verilog ../picorv32.v $(KSA_RTL) $(VEDIC_TREE_RTL) $(PCPI_VEDIC_RTL); chparam -set ENABLE_MUL 1 picorv32; chparam -set ENABLE_FAST_MUL 1 picorv32; hierarchy -top picorv32; synth -top picorv32; stat'; \
	fi

stage2_area_capture: area_baseline_A area_baseline_B area_baseline_C area_optimized
	$(PYTHON) scripts/parse_area.py | tee $(REPORT_DIR)/phase1_area_summary.txt

layer0_perf_capture: sim_pcpi_baseline_A sim_pcpi_baseline_B sim_pcpi sim_integration_baseline_A_mul sim_integration_baseline_B_mul sim_integration_baseline_A_bench sim_integration_baseline_B_bench sim_integration_opt_metrics sim_integration_opt_bench
	$(PYTHON) scripts/parse_performance.py | tee $(REPORT_DIR)/phase2_performance_summary.txt

layer0_switching_capture: switching_baseline_A_mul switching_baseline_B_mul switching_optimized_mul compare_switching
	@echo "Switching logs:" > $(REPORT_DIR)/layer0_switching_summary.txt
	@cat sim/logs/switching_baseline_A_mul.log >> $(REPORT_DIR)/layer0_switching_summary.txt
	@cat sim/logs/switching_baseline_B_mul.log >> $(REPORT_DIR)/layer0_switching_summary.txt
	@cat sim/logs/switching_optimized_mul.log >> $(REPORT_DIR)/layer0_switching_summary.txt

quality_capture: lint_phase1
	$(PYTHON) scripts/collect_quality_metrics.py | tee $(REPORT_DIR)/phase1_quality_metrics.txt

baseline_reports: stage2_area_capture layer0_perf_capture quality_capture
	$(PYTHON) scripts/build_master_report.py | tee $(REPORT_DIR)/master_metrics_summary.txt

baseline_capture_all: stage0_freeze baseline_reports layer0_switching_capture

p3_check:
	bash scripts/check_prerequisites.sh

p3_synth: p3_check
	mkdir -p synth/baseline_A synth/baseline_B synth/baseline_C synth/baseline_C_ksa synth/optimized $(REPORT_DIR)
	$(YOSYS) -l $(REPORT_DIR)/baseline_A_yosys_full.log synth/synth_baseline_A.ys
	$(YOSYS) -l $(REPORT_DIR)/baseline_B_yosys_full.log synth/synth_baseline_B.ys
	$(YOSYS) -l $(REPORT_DIR)/baseline_C_yosys_full.log synth/synth_baseline_C.ys
	$(YOSYS) -l $(REPORT_DIR)/baseline_C_ksa_yosys_full.log synth/synth_baseline_C_ksa.ys
	$(YOSYS) -l $(REPORT_DIR)/optimized_yosys_full.log synth/synth_optimized.ys

p3_area: p3_synth
	$(PYTHON) scripts/parse_synth_area.py

p3_pnr: p3_area
	mkdir -p pnr/baseline_A pnr/baseline_B pnr/baseline_C pnr/optimized pnr/reports
	$(MAKE) -C pnr all

p3_timing: p3_pnr
	$(PYTHON) scripts/parse_timing.py

p3_composites: p3_timing
	$(PYTHON) scripts/compute_composites.py

p3_report: p3_composites
	$(PYTHON) scripts/gen_master_report.py
	$(PYTHON) scripts/phase3_summary.py

phase3: p3_report
	@echo ""
	@echo "============================================"
	@echo "  Phase 3 complete."
	@echo "  Master CSV:  $(REPORT_DIR)/master_metrics.csv"
	@echo "  Area CSV:    $(REPORT_DIR)/phase3_area_final.csv"
	@echo "  Timing CSV:  $(REPORT_DIR)/phase3_timing.csv"
	@echo "  Composites:  $(REPORT_DIR)/phase3_composites.csv"
	@echo "  Summary TXT: $(REPORT_DIR)/phase3_report_summary.txt"
	@echo "============================================"

# Phase 5: baseline -dsp vs -dsp -abc2 PnR + fast sim/lint gate + PHASE4_FAST formal (no F3/F4/F5).
phase5: prep_dirs
	bash scripts/phase5_measure.sh
	bash scripts/phase5_gate.sh
	bash scripts/phase5_collect.sh
	@echo ""
	@echo "Phase 5 artifacts: $(REPORT_DIR)/phase5_measure.json $(REPORT_DIR)/phase5_gate.txt $(REPORT_DIR)/phase5_complete.txt"

# PNG charts for opt/docs/PROJECT_REPORT_ALL_PHASES.md (Pillow + DejaVu).
report_figures: prep_dirs
	$(PYTHON) scripts/generate_report_figures.py

hw_check_board:
	bash scripts/hw/check_board.sh

hw_pack_bitstreams:
	bash scripts/hw/pack_bitstreams.sh baseline_A baseline_C optimized

hw_flash_baseline_A:
	bash scripts/hw/flash_and_verify.sh baseline_A

hw_flash_baseline_C:
	bash scripts/hw/flash_and_verify.sh baseline_C

hw_flash_optimized:
	bash scripts/hw/flash_and_verify.sh optimized

hw_stage6: hw_check_board hw_pack_bitstreams
	@echo ""
	@echo "Stage 6 prep complete."
	@echo "Flash targets:"
	@echo "  make -C opt hw_flash_baseline_A"
	@echo "  make -C opt hw_flash_baseline_C"
	@echo "  make -C opt hw_flash_optimized"

ifeq ($(RUN_FULL_VEDIC),1)
PHASE2_VEDIC_TARGET := sim_vedic
else
PHASE2_VEDIC_TARGET := sim_vedic_quick
endif

phase2_refresh_perf:
	$(PYTHON) scripts/parse_performance.py | tee $(REPORT_DIR)/phase2_performance_summary.txt

phase2_all: sim_ksa $(PHASE2_VEDIC_TARGET) sim_pcpi sim_integration_opt_metrics sim_integration_opt_bench formal_ksa formal_vedic phase2_refresh_perf

phase2_all_full:
	$(MAKE) --no-print-directory RUN_FULL_VEDIC=1 phase2_all
	$(MAKE) --no-print-directory sim_pcpi_rand1k

clean_phase2:
	rm -f sim/ksa_sim sim/vedic_sim sim/pcpi_sim sim/integration_sim
	rm -f sim/logs/ksa.log sim/logs/vedic.log sim/logs/pcpi.log sim/logs/integration.log
	rm -f sim/vcd/ksa_32bit.vcd sim/vcd/vedic_32x32.vcd sim/vcd/pcpi_vedic_mul.vcd sim/vcd/picorv32_integration.vcd
	$(MAKE) -C firmware/mul_test clean
	rm -rf formal/ksa/ksa_formal
	rm -rf formal/vedic/vedic_formal formal/vedic/vedic_formal_prove
	rm -rf formal/vedic/vedic_2x2_formal formal/vedic/vedic_2x2_formal_prove
	rm -rf formal/vedic/vedic_4x4_formal formal/vedic/vedic_4x4_formal_prove
	rm -rf formal/vedic/vedic_8x8_formal formal/vedic/vedic_8x8_formal_prove
	rm -rf formal/vedic/vedic_16x16_ag_formal formal/vedic/vedic_16x16_ag_formal_prove
	rm -rf formal/vedic/vedic_32x32_ag_formal formal/vedic/vedic_32x32_ag_formal_prove
	rm -f formal/vedic/equiv_16x16.log formal/vedic/equiv_32x32.log

clean_baseline:
	rm -f sim/pcpi_baseline_A_sim sim/pcpi_baseline_B_sim
	rm -f sim/integration_baseline_A_mul_sim sim/integration_baseline_B_mul_sim sim/integration_baseline_A_bench_sim sim/integration_baseline_B_bench_sim sim/integration_optimized_mul_sim sim/integration_optimized_bench_sim
	rm -f sim/integration_baseline_A_mul_vcd_sim sim/integration_baseline_B_mul_vcd_sim sim/integration_optimized_mul_vcd_sim
	rm -f sim/logs/pcpi_baseline_A.log sim/logs/pcpi_baseline_B.log sim/logs/pcpi_optimized.log
	rm -f sim/logs/integration_baseline_A_mul.log sim/logs/integration_baseline_B_mul.log sim/logs/integration_baseline_A_bench.log sim/logs/integration_baseline_B_bench.log sim/logs/integration_optimized_mul.log sim/logs/integration_optimized_bench.log
	rm -f sim/logs/switching_baseline_A_mul.log sim/logs/switching_baseline_B_mul.log sim/logs/switching_optimized_mul.log
	rm -f sim/logs/lint_ksa.log sim/logs/lint_vedic.log sim/logs/lint_pcpi.log
	rm -f sim/vcd/integration_baseline_A_mul.vcd sim/vcd/integration_baseline_B_mul.vcd sim/vcd/integration_optimized_mul.vcd
	rm -f $(REPORT_DIR)/baseline_A_stat.log $(REPORT_DIR)/baseline_B_stat.log $(REPORT_DIR)/baseline_C_stat.log $(REPORT_DIR)/optimized_stat.log
	rm -f $(REPORT_DIR)/baseline_A_synth_stat.log $(REPORT_DIR)/baseline_B_synth_stat.log $(REPORT_DIR)/baseline_C_synth_stat.log $(REPORT_DIR)/baseline_C_ksa_synth_stat.log $(REPORT_DIR)/optimized_synth_stat.log
	rm -f $(REPORT_DIR)/phase1_area_comparison.csv $(REPORT_DIR)/phase1_area_summary.txt
	rm -f $(REPORT_DIR)/phase2_performance.csv $(REPORT_DIR)/phase2_performance_summary.txt
	rm -f $(REPORT_DIR)/phase3_area_final.csv $(REPORT_DIR)/phase3_timing.csv $(REPORT_DIR)/phase3_composites.csv
	rm -f $(REPORT_DIR)/phase3_report_summary.txt
	rm -f $(REPORT_DIR)/phase1_quality_metrics.txt $(REPORT_DIR)/master_metrics.csv $(REPORT_DIR)/master_metrics_summary.txt
	rm -f $(REPORT_DIR)/baseline_A_switching.txt $(REPORT_DIR)/baseline_B_switching.txt $(REPORT_DIR)/optimized_switching.txt $(REPORT_DIR)/switching_comparison.txt
	rm -f $(REPORT_DIR)/layer0_switching_summary.txt $(REPORT_DIR)/baseline_stage0_env.txt $(REPORT_DIR)/baseline_stage0_tools.txt $(REPORT_DIR)/baseline_stage0_git_status.txt
