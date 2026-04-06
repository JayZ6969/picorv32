# =============================================================================
# Makefile — Phase 1 & 2: RTL simulation and formal verification
#
# Targets:
#   make all          — run all unit testbenches + formal check
#   make tb_ksa       — compile & simulate KSA testbench
#   make tb_vedic     — compile & simulate Vedic multiplier testbench
#   make formal       — run GF(2) Python formal verification
#   make formal_full  — formal with --bits 8 --signed (extended, ~60s)
#   make waves_ksa    — open KSA waveform in GTKWave
#   make waves_vedic  — open Vedic multiplier waveform in GTKWave
#   make synth_ksa    — Yosys synthesis of KSA (LUT/timing report)
#   make synth_vedic  — Yosys synthesis of Vedic multiplier
#   make synth_core   — Yosys synthesis of full picorv32 (baseline)
#   make synth_ksa_core   — Yosys synthesis with USE_KSA=1
#   make synth_vedic_core — Yosys synthesis with ENABLE_VEDIC_MUL=1
#   make synth_both_core  — Yosys synthesis with USE_KSA=1 ENABLE_VEDIC_MUL=1
#   make clean        — remove all build artifacts
#
# Requirements:
#   iverilog, gtkwave, python3, sympy, yosys
# =============================================================================

TOP      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
# picorv32 repository root (parent of opt/)
ROOT     := $(abspath $(TOP)/..)
RTL      := $(TOP)/rtl
TB       := $(TOP)/tb
FORMAL   := $(TOP)/formal
BUILD    := $(TOP)/build

IVERILOG := iverilog
IVFLAGS  := -Wall -Wno-portbind
VVP      := vvp
GTKWAVE  := gtkwave
PYTHON   := $(ROOT)/.venv/bin/python3
YOSYS    := yosys
PYTHON_CLEAN := env -u PYTHONPATH -u PYTHONHOME

.PHONY: all clean tb_ksa tb_vedic formal formal_full waves_ksa waves_vedic \
        synth_ksa synth_vedic synth_core synth_ksa_core synth_vedic_core synth_both_core \
	tb_pcpi_compare report \
	phase3_precheck phase3_fpga_sim phase3_fpga_build phase3_program phase3_collect phase3 \
		phase4_precheck phase4_collect phase4 \
		phase5_precheck phase5_collect phase5 \
	phase3_tools_check_sim phase3_tools_check_build phase3_tools_check_program \
	_phase3_require_iceprog _phase3_require_icesprog \
	baseline_capture baseline_check

all: tb_ksa tb_vedic formal
	@echo ""
	@echo "============================================"
	@echo "  Phase 1 & 2 complete. Check results above."
	@echo "============================================"

# ---------------------------------------------------------------------------
# Build directory
# ---------------------------------------------------------------------------
$(BUILD):
	mkdir -p $(BUILD)

# ---------------------------------------------------------------------------
# [Unit TB 1] Kogge-Stone Adder
# ---------------------------------------------------------------------------
$(BUILD)/tb_ksa: $(TB)/tb_ksa.v $(RTL)/ksa.v | $(BUILD)
	$(IVERILOG) $(IVFLAGS) -o $@ $^

tb_ksa: $(BUILD)/tb_ksa
	@echo ""
	@echo "--- Running KSA testbench ---"
	cd $(BUILD) && $(VVP) tb_ksa
	@echo ""

waves_ksa: tb_ksa
	$(GTKWAVE) $(BUILD)/dump_ksa.vcd $(TOP)/wave_ksa.gtkw &

# ---------------------------------------------------------------------------
# [Unit TB 2] Vedic Multiplier (all hierarchy levels in one file)
# ---------------------------------------------------------------------------
$(BUILD)/tb_vedic_mul: $(TB)/tb_vedic_mul.v $(RTL)/vedic_mul_32.v | $(BUILD)
	$(IVERILOG) $(IVFLAGS) -o $@ $^

tb_vedic: $(BUILD)/tb_vedic_mul
	@echo ""
	@echo "--- Running Vedic Multiplier testbench ---"
	cd $(BUILD) && $(VVP) tb_vedic_mul
	@echo ""

waves_vedic: tb_vedic
	$(GTKWAVE) $(BUILD)/dump_vedic_mul.vcd $(TOP)/wave_vedic.gtkw &

# ---------------------------------------------------------------------------
# [Formal] GF(2) algebraic verification
# ---------------------------------------------------------------------------
formal:
	@echo ""
	@echo "--- GF(2) Formal Verification (4-bit, fast) ---"
	$(PYTHON_CLEAN) $(PYTHON) $(FORMAL)/gf2_verify.py --bits 4
	@echo ""

formal_full:
	@echo ""
	@echo "--- GF(2) Formal Verification (8-bit, exhaustive, signed) ---"
	$(PYTHON_CLEAN) $(PYTHON) $(FORMAL)/gf2_verify.py --bits 8 --exhaustive --signed
	@echo ""

# ---------------------------------------------------------------------------
# [Synthesis] Yosys — LUT count and combinational depth reports
# ---------------------------------------------------------------------------
YOSYS_SYNTH_OPTS := synth -flatten -nofsm

$(BUILD)/ksa.json: $(RTL)/ksa.v | $(BUILD)
	$(YOSYS) -p "read_verilog $<; $(YOSYS_SYNTH_OPTS); write_json $@; stat" 2>&1 | tee $(BUILD)/ksa_synth.log

synth_ksa: $(BUILD)/ksa.json
	@echo ""
	@echo "=== KSA synthesis: LUT count and cell summary ==="
	@grep -E "Cells|LUT|DFF|carry" $(BUILD)/ksa_synth.log || true

$(BUILD)/vedic_mul_32.json: $(RTL)/vedic_mul_32.v | $(BUILD)
	$(YOSYS) -p "read_verilog $<; $(YOSYS_SYNTH_OPTS); write_json $@; stat" 2>&1 | tee $(BUILD)/vedic_synth.log

synth_vedic: $(BUILD)/vedic_mul_32.json
	@echo ""
	@echo "=== Vedic multiplier synthesis: LUT count and cell summary ==="
	@grep -E "Cells|LUT|DFF|carry" $(BUILD)/vedic_synth.log || true

# Synthesis macros for the four core variants
# Each variant writes a separate JSON for area comparison
define SYNTH_CORE_RULE
$(BUILD)/picorv32_$(1).json: $(ROOT)/picorv32.v $(RTL)/ksa.v $(RTL)/vedic_mul_32.v $(RTL)/picorv32_pcpi_vedic_mul.v | $(BUILD)
	$(YOSYS) -p "read_verilog -sv $(ROOT)/picorv32.v $(RTL)/ksa.v $(RTL)/vedic_mul_32.v $(RTL)/picorv32_pcpi_vedic_mul.v; \
	             chparam -set ENABLE_MUL $(2) -set ENABLE_VEDIC_MUL $(3) -set USE_KSA $(4) picorv32; \
	             $(YOSYS_SYNTH_OPTS); \
	             write_json $$@; stat" 2>&1 | tee $(BUILD)/picorv32_$(1)_synth.log

synth_$(1)_core: $(BUILD)/picorv32_$(1).json
	@echo ""
	@echo "=== PicoRV32 $(1) synthesis summary ==="
	@grep -E "Cells|LUT|DFF|Number" $(BUILD)/picorv32_$(1)_synth.log | head -20 || true
endef

# Variant: baseline (ENABLE_MUL=1, USE_KSA=0, ENABLE_VEDIC_MUL=0)
$(eval $(call SYNTH_CORE_RULE,baseline,1,0,0))
# Variant: +KSA
$(eval $(call SYNTH_CORE_RULE,ksa,1,0,1))
# Variant: +Vedic
$(eval $(call SYNTH_CORE_RULE,vedic,0,1,0))
# Variant: +Both
$(eval $(call SYNTH_CORE_RULE,both,0,1,1))

synth_core: synth_baseline_core
synth_ksa_core: synth_ksa_core
synth_vedic_core: synth_vedic_core
synth_both_core: synth_both_core

synth_all_variants: synth_baseline_core synth_ksa_core synth_vedic_core synth_both_core
	@echo ""
	@echo "=== Area comparison across all 4 variants ==="
	@for v in baseline ksa vedic both; do \
	  echo "--- $$v ---"; \
	  grep "Number of cells" $(BUILD)/picorv32_$${v}_synth.log 2>/dev/null || echo "(run synth first)"; \
	done

REPORTS := $(TOP)/results
PHASE1_RESULTS := $(REPORTS)/phase1
PHASE2_RESULTS := $(REPORTS)/phase2
PHASE3  := $(TOP)/phase3
PHASE4  := $(TOP)/phase4
PHASE5  := $(TOP)/phase5
PHASE3_RESULTS := $(REPORTS)/phase3
PHASE4_RESULTS := $(REPORTS)/phase4
PHASE5_RESULTS := $(REPORTS)/phase5
PICOSOC := $(ROOT)/picosoc
BOARD ?= icebreaker
TARGET_MHZ ?= 12
PHASE3_PROFILE ?= fit
PROGRAMMER ?= auto
BASELINE_METRICS := $(PHASE2_RESULTS)/pcpi_summary.csv
BASELINE_METRICS_LEGACY := $(REPORTS)/pcpi_summary.csv
PHASE3_ARTIFACT_PREFIX := $(BOARD)
PHASE5_NETLIST_JSON ?= $(PHASE3_RESULTS)/$(BOARD)/$(PHASE3_ARTIFACT_PREFIX).json
ifeq ($(BOARD),icebreaker)
ifeq ($(PHASE3_PROFILE),fit)
PHASE3_ARTIFACT_PREFIX := icebreaker_fit
endif
endif

$(REPORTS):
	mkdir -p $(REPORTS)

$(PHASE1_RESULTS) $(PHASE2_RESULTS) $(PHASE3_RESULTS) $(PHASE4_RESULTS) $(PHASE5_RESULTS):
	mkdir -p $@

# ---------------------------------------------------------------------------
# [PCPI Compare] Baseline sequential MUL vs Vedic pipeline latency
# ---------------------------------------------------------------------------
$(BUILD)/tb_pcpi_compare: $(TB)/tb_pcpi_compare.v $(ROOT)/picorv32.v \
						   $(RTL)/vedic_mul_32.v $(RTL)/picorv32_pcpi_vedic_mul.v | $(BUILD) $(REPORTS) $(PHASE2_RESULTS)
	$(IVERILOG) -Wno-portbind -g2001 -o $@ $^

tb_pcpi_compare: $(BUILD)/tb_pcpi_compare
	@echo ""
	@echo "--- Running PCPI MUL Latency Comparison ---"
	cd $(BUILD) && $(VVP) tb_pcpi_compare
	@echo ""

baseline_capture: tb_pcpi_compare
	@echo ""
	@echo "=== Baseline capture complete ==="
	@echo "Baseline metrics file: $(BASELINE_METRICS)"

baseline_check:
	@metrics_file="$(BASELINE_METRICS)"; \
	if [ ! -f "$$metrics_file" ] && [ -f "$(BASELINE_METRICS_LEGACY)" ]; then \
		metrics_file="$(BASELINE_METRICS_LEGACY)"; \
	fi; \
	if [ ! -f "$$metrics_file" ]; then \
		echo "Missing baseline metrics: $(BASELINE_METRICS)"; \
		echo "Run: make baseline_capture"; \
		exit 2; \
	fi; \
	if ! grep -q '^avg_cycles,' "$$metrics_file"; then \
		echo "Baseline metrics exists but format is invalid: $$metrics_file"; \
		echo "Run: make baseline_capture"; \
		exit 2; \
	fi; \
	echo "Baseline gate: PASS ($$metrics_file)"

# ---------------------------------------------------------------------------
# [Report] Generate all charts and tables from simulation results
# ---------------------------------------------------------------------------
report: tb_ksa tb_vedic tb_pcpi_compare
	@echo ""
	@echo "--- Generating report figures and tables ---"
	$(PYTHON_CLEAN) $(PYTHON) $(REPORTS)/generate_report.py
	@echo ""
	@echo "=== Report artifacts in $(PHASE2_RESULTS)/ ==="
	@ls -1 $(PHASE2_RESULTS)/*.png $(PHASE2_RESULTS)/*.csv $(PHASE2_RESULTS)/*.tex 2>/dev/null

# ---------------------------------------------------------------------------
# [Phase 3] FPGA synthesis + functional verification workflow
# ---------------------------------------------------------------------------
define CHECK_BOARD
	@if [ "$(BOARD)" != "icebreaker" ] && [ "$(BOARD)" != "hx8kdemo" ]; then \
		echo "Unsupported BOARD='$(BOARD)'. Use BOARD=icebreaker or BOARD=hx8kdemo"; \
		exit 2; \
	fi
endef

define REQUIRE_TOOL
	@if ! command -v $(1) >/dev/null 2>&1; then \
		echo "Missing required tool: $(1)"; \
		echo "Please install it and re-run the Phase 3 target."; \
		exit 2; \
	fi
endef

phase3_tools_check_sim:
	$(call REQUIRE_TOOL,iverilog)
	$(call REQUIRE_TOOL,vvp)
	@if command -v yosys-config >/dev/null 2>&1; then \
		echo "Found yosys-config"; \
	elif [ -f /usr/share/yosys/ice40/cells_sim.v ]; then \
		echo "yosys-config not found; using /usr/share/yosys/ice40/cells_sim.v"; \
	else \
		echo "Missing yosys-config and missing /usr/share/yosys/ice40/cells_sim.v"; \
		echo "Install yosys package with iCE40 simulation cells."; \
		exit 2; \
	fi

phase3_tools_check_build:
	$(call REQUIRE_TOOL,yosys)
	$(call REQUIRE_TOOL,nextpnr-ice40)
	$(call REQUIRE_TOOL,icetime)
	$(call REQUIRE_TOOL,icepack)
	$(call REQUIRE_TOOL,riscv32-unknown-elf-gcc)
	$(call REQUIRE_TOOL,riscv32-unknown-elf-objcopy)

phase3_tools_check_program:
	@if [ "$(PROGRAMMER)" = "iceprog" ]; then \
		$(MAKE) --no-print-directory _phase3_require_iceprog; \
	elif [ "$(PROGRAMMER)" = "icesprog" ]; then \
		$(MAKE) --no-print-directory _phase3_require_icesprog; \
	elif [ "$(PROGRAMMER)" = "auto" ]; then \
		if [ "$(BOARD)" = "icebreaker" ]; then \
			if command -v iceprog >/dev/null 2>&1 || command -v icesprog >/dev/null 2>&1; then \
				echo "Found programmer backend for icebreaker (iceprog/icesprog)."; \
			else \
				echo "Missing programmer: install iceprog or icesprog for BOARD=$(BOARD)."; \
				exit 2; \
			fi; \
		else \
			$(MAKE) --no-print-directory _phase3_require_iceprog; \
		fi; \
	else \
		echo "Unsupported PROGRAMMER='$(PROGRAMMER)'. Use auto, iceprog, or icesprog."; \
		exit 2; \
	fi

_phase3_require_iceprog:
	$(call REQUIRE_TOOL,iceprog)

_phase3_require_icesprog:
	$(call REQUIRE_TOOL,icesprog)

phase3_precheck: tb_ksa tb_vedic formal baseline_capture baseline_check
	@echo ""
	@echo "=== Phase 3 precheck complete ==="
	@echo "All local simulation/formal gates passed."
	@echo "Baseline-vs-optimized gate passed (compulsory)."

phase3_fpga_sim: phase3_tools_check_sim
	$(CHECK_BOARD)
	@echo ""
	@echo "--- Phase 3 board-level simulation ($(BOARD)) ---"
	@if [ "$(BOARD)" = "icebreaker" ]; then \
		$(MAKE) -C $(PICOSOC) icebsim; \
	else \
		$(MAKE) -C $(PICOSOC) hx8ksim; \
	fi

phase3_fpga_build: phase3_tools_check_build
	$(CHECK_BOARD)
	@if [ "$(PHASE3_PROFILE)" != "fit" ] && [ "$(PHASE3_PROFILE)" != "full" ]; then \
		echo "Unsupported PHASE3_PROFILE='$(PHASE3_PROFILE)'. Use fit or full."; \
		exit 2; \
	fi
	@echo ""
	@echo "--- Phase 3 FPGA synthesis + P&R ($(BOARD), profile=$(PHASE3_PROFILE)) ---"
	@if [ "$(BOARD)" = "icebreaker" ]; then \
		if [ "$(PHASE3_PROFILE)" = "fit" ]; then \
			$(MAKE) -C $(PICOSOC) icebreaker_fit.bin icebreaker_fw.elf icebreaker_fw.hex icebreaker_fw.bin; \
		else \
			$(MAKE) -C $(PICOSOC) icebreaker.bin icebreaker_fw.elf icebreaker_fw.hex icebreaker_fw.bin; \
		fi; \
	else \
		$(MAKE) -C $(PICOSOC) hx8kdemo.bin hx8kdemo_fw.elf hx8kdemo_fw.hex hx8kdemo_fw.bin; \
	fi

phase3_program: phase3_tools_check_program
	$(CHECK_BOARD)
	@if [ "$(PHASE3_PROFILE)" != "fit" ] && [ "$(PHASE3_PROFILE)" != "full" ]; then \
		echo "Unsupported PHASE3_PROFILE='$(PHASE3_PROFILE)'. Use fit or full."; \
		exit 2; \
	fi
	@echo ""
	@echo "--- Phase 3 board programming ($(BOARD), profile=$(PHASE3_PROFILE), programmer=$(PROGRAMMER)) ---"
	@if [ "$(BOARD)" = "icebreaker" ]; then \
		if [ "$(PROGRAMMER)" = "icesprog" ]; then \
			if [ "$(PHASE3_PROFILE)" = "fit" ]; then \
				icesprog $(PICOSOC)/icebreaker_fit.bin; \
			else \
				icesprog $(PICOSOC)/icebreaker.bin; \
			fi; \
			icesprog -o 0x100000 $(PICOSOC)/icebreaker_fw.bin; \
		elif [ "$(PROGRAMMER)" = "iceprog" ]; then \
			if [ "$(PHASE3_PROFILE)" = "fit" ]; then \
				$(MAKE) -C $(PICOSOC) icebfitprog; \
			else \
				$(MAKE) -C $(PICOSOC) icebprog; \
			fi; \
		elif [ "$(PROGRAMMER)" = "auto" ]; then \
			if command -v iceprog >/dev/null 2>&1; then \
				if [ "$(PHASE3_PROFILE)" = "fit" ]; then \
					if ! $(MAKE) -C $(PICOSOC) icebfitprog; then \
						if command -v icesprog >/dev/null 2>&1; then \
							echo "iceprog failed; retrying with icesprog"; \
							icesprog $(PICOSOC)/icebreaker_fit.bin; \
							icesprog -o 0x100000 $(PICOSOC)/icebreaker_fw.bin; \
						else \
							exit 2; \
						fi; \
					fi; \
				else \
					if ! $(MAKE) -C $(PICOSOC) icebprog; then \
						if command -v icesprog >/dev/null 2>&1; then \
							echo "iceprog failed; retrying with icesprog"; \
							icesprog $(PICOSOC)/icebreaker.bin; \
							icesprog -o 0x100000 $(PICOSOC)/icebreaker_fw.bin; \
						else \
							exit 2; \
						fi; \
					fi; \
				fi; \
			elif command -v icesprog >/dev/null 2>&1; then \
				echo "iceprog unavailable/unsupported, falling back to icesprog"; \
				if [ "$(PHASE3_PROFILE)" = "fit" ]; then \
					icesprog $(PICOSOC)/icebreaker_fit.bin; \
				else \
					icesprog $(PICOSOC)/icebreaker.bin; \
				fi; \
				icesprog -o 0x100000 $(PICOSOC)/icebreaker_fw.bin; \
			else \
				echo "No supported programmer found for BOARD=$(BOARD)."; \
				exit 2; \
			fi; \
		else \
			echo "Unsupported PROGRAMMER='$(PROGRAMMER)' for BOARD=$(BOARD)."; \
			exit 2; \
		fi; \
	else \
		if [ "$(PROGRAMMER)" = "icesprog" ]; then \
			echo "PROGRAMMER=icesprog is not supported for BOARD=$(BOARD). Use iceprog."; \
			exit 2; \
		fi; \
		$(MAKE) -C $(PICOSOC) hx8kprog; \
	fi

phase3_collect:
	$(CHECK_BOARD)
	@if [ "$(PHASE3_PROFILE)" != "fit" ] && [ "$(PHASE3_PROFILE)" != "full" ]; then \
		echo "Unsupported PHASE3_PROFILE='$(PHASE3_PROFILE)'. Use fit or full."; \
		exit 2; \
	fi
	@$(MAKE) baseline_check
	@mkdir -p $(PHASE3_RESULTS)/$(BOARD)
	@echo ""
	@echo "--- Collecting Phase 3 artifacts ($(BOARD), profile=$(PHASE3_PROFILE)) ---"
	@cp -f $(BASELINE_METRICS) $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true
	@if [ "$(BOARD)" = "icebreaker" ] && [ "$(PHASE3_PROFILE)" = "fit" ]; then \
		$(MAKE) -C $(PICOSOC) icebreaker.json >/dev/null; \
		cp -f $(PICOSOC)/icebreaker_fit.log $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true; \
		cp -f $(PICOSOC)/icebreaker_fit.rpt $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true; \
		cp -f $(PICOSOC)/icebreaker_fit.json $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true; \
		cp -f $(PICOSOC)/icebreaker_fit.asc $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true; \
		cp -f $(PICOSOC)/icebreaker_fit.bin $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true; \
	fi
	@cp -f $(PICOSOC)/$(BOARD).log $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true
	@cp -f $(PICOSOC)/$(BOARD).rpt $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true
	@cp -f $(PICOSOC)/$(BOARD).json $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true
	@cp -f $(PICOSOC)/$(BOARD).asc $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true
	@cp -f $(PICOSOC)/$(BOARD).bin $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true
	@cp -f $(PICOSOC)/$(BOARD)_fw.elf $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true
	@cp -f $(PICOSOC)/$(BOARD)_fw.hex $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true
	@cp -f $(PICOSOC)/$(BOARD)_fw.bin $(PHASE3_RESULTS)/$(BOARD)/ 2>/dev/null || true
	@$(PYTHON_CLEAN) $(PYTHON) $(PHASE3)/summarize_phase3.py \
		--board $(BOARD) \
		--artifact-prefix $(PHASE3_ARTIFACT_PREFIX) \
		--picosoc-dir $(PICOSOC) \
		--out-dir $(PHASE3_RESULTS)/$(BOARD) \
		--target-mhz $(TARGET_MHZ)
	@$(PYTHON_CLEAN) $(PYTHON) $(PHASE3)/plot_phase3.py \
		--metrics-csv $(PHASE3_RESULTS)/$(BOARD)/phase3_metrics.csv \
		--out-dir $(PHASE3_RESULTS)/$(BOARD)
	@echo ""
	@echo "Phase 3 summary: $(PHASE3_RESULTS)/$(BOARD)/phase3_summary.md"
	@echo "Phase 3 metrics: $(PHASE3_RESULTS)/$(BOARD)/phase3_metrics.csv"
	@echo "Phase 3 graphs:  $(PHASE3_RESULTS)/$(BOARD)/phase3_timing.png"
	@echo "                $(PHASE3_RESULTS)/$(BOARD)/phase3_resources.png"
	@echo "                $(PHASE3_RESULTS)/$(BOARD)/phase3_baseline_compare.png"

phase3: phase3_precheck phase3_fpga_sim phase3_fpga_build phase3_collect
	@echo ""
	@echo "============================================"
	@echo "  Phase 3 flow complete for BOARD=$(BOARD)"
	@echo "  Next step: make phase3_program BOARD=$(BOARD)"
	@echo "============================================"

# ---------------------------------------------------------------------------
# [Phase 4] Pre-ASIC logical sign-off readiness workflow
# ---------------------------------------------------------------------------
phase4_precheck:
	@$(MAKE) baseline_check
	@echo ""
	@echo "=== Phase 4 precheck complete ==="
	@echo "Baseline gate passed. Ready for Phase 4 metrics collection."

phase4_collect:
	@$(MAKE) baseline_check
	@mkdir -p $(PHASE4_RESULTS)
	@echo ""
	@echo "--- Collecting Phase 4 artifacts ---"
	@cp -f $(BASELINE_METRICS) $(PHASE4_RESULTS)/ 2>/dev/null || true
	@$(PYTHON_CLEAN) $(PYTHON) $(PHASE4)/summarize_phase4.py \
		--baseline-csv $(BASELINE_METRICS) \
		--root $(ROOT) \
		--out-dir $(PHASE4_RESULTS)
	@$(PYTHON_CLEAN) $(PYTHON) $(PHASE4)/plot_phase4.py \
		--metrics-csv $(PHASE4_RESULTS)/phase4_metrics.csv \
		--out-dir $(PHASE4_RESULTS)
	@echo ""
	@echo "Phase 4 summary: $(PHASE4_RESULTS)/phase4_summary.md"
	@echo "Phase 4 metrics: $(PHASE4_RESULTS)/phase4_metrics.csv"
	@echo "Phase 4 graphs:  $(PHASE4_RESULTS)/phase4_signoff_status.png"
	@echo "                $(PHASE4_RESULTS)/phase4_baseline_delta.png"

phase4: phase4_precheck phase4_collect
	@echo ""
	@echo "============================================"
	@echo "  Phase 4 preparation flow complete"
	@echo "============================================"

# ---------------------------------------------------------------------------
# [Phase 5] ASIC physical-design readiness workflow
# ---------------------------------------------------------------------------
phase5_precheck:
	@$(MAKE) baseline_check
	@echo ""
	@echo "=== Phase 5 precheck complete ==="
	@echo "Baseline gate passed. Ready for Phase 5 metrics collection."

phase5_collect:
	@$(MAKE) baseline_check
	@mkdir -p $(PHASE5_RESULTS)
	@echo ""
	@echo "--- Collecting Phase 5 artifacts ---"
	@cp -f $(BASELINE_METRICS) $(PHASE5_RESULTS)/ 2>/dev/null || true
	@$(PYTHON_CLEAN) $(PYTHON) $(PHASE5)/summarize_phase5.py \
		--baseline-csv $(BASELINE_METRICS) \
		--phase3-metrics-csv $(PHASE3_RESULTS)/$(BOARD)/phase3_metrics.csv \
		--netlist-json $(PHASE5_NETLIST_JSON) \
		--root $(ROOT) \
		--out-dir $(PHASE5_RESULTS)
	@$(PYTHON_CLEAN) $(PYTHON) $(PHASE5)/plot_phase5.py \
		--metrics-csv $(PHASE5_RESULTS)/phase5_metrics.csv \
		--out-dir $(PHASE5_RESULTS)
	@echo ""
	@echo "Phase 5 summary: $(PHASE5_RESULTS)/phase5_summary.md"
	@echo "Phase 5 metrics: $(PHASE5_RESULTS)/phase5_metrics.csv"
	@echo "Phase 5 baseline metrics:  $(PHASE5_RESULTS)/phase5_baseline_metrics.csv"
	@echo "Phase 5 optimized metrics: $(PHASE5_RESULTS)/phase5_optimized_metrics.csv"
	@echo "Phase 5 compare table:     $(PHASE5_RESULTS)/phase5_ppa_compare.csv"
	@echo "Phase 5 unblock: $(PHASE5_RESULTS)/phase5_unblock_checklist.md"
	@echo "Phase 5 GDS:     $(PHASE5_RESULTS)/phase5_chip_preview.gds"
	@echo "Phase 5 GDS PNG: $(PHASE5_RESULTS)/phase5_chip_gds_render.png"
	@echo "Phase 5 graphs:  $(PHASE5_RESULTS)/phase5_signoff_status.png"
	@echo "                $(PHASE5_RESULTS)/phase5_ppa_overview.png"
	@echo "                $(PHASE5_RESULTS)/phase5_chip_preview.png"
	@echo "                $(PHASE5_RESULTS)/phase5_chip_photo.png"

phase5: phase5_precheck phase5_collect
	@echo ""
	@echo "============================================"
	@echo "  Phase 5 preparation flow complete"
	@echo "============================================"

# ---------------------------------------------------------------------------
# Waveform config stubs (user can customise)
# ---------------------------------------------------------------------------
$(TOP)/wave_ksa.gtkw:
	@echo "[dumpfile] $(BUILD)/dump_ksa.vcd" > $@
	@echo "[savefile] $@" >> $@

$(TOP)/wave_vedic.gtkw:
	@echo "[dumpfile] $(BUILD)/dump_vedic_mul.vcd" > $@
	@echo "[savefile] $@" >> $@

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
help:
	@echo "Available targets:"
	@echo "  all               — tb_ksa + tb_vedic + formal (fast)"
	@echo "  tb_ksa            — compile & run KSA unit testbench"
	@echo "  tb_vedic          — compile & run Vedic multiplier testbench"
	@echo "  formal            — GF(2) algebraic check (4-bit, fast)"
	@echo "  formal_full       — GF(2) check (8-bit exhaustive + signed)"
	@echo "  waves_ksa         — open KSA waveform in GTKWave"
	@echo "  waves_vedic       — open Vedic multiplier waveform in GTKWave"
	@echo "  tb_pcpi_compare   — baseline vs Vedic MUL latency (cycles)"
	@echo "  report            — run all sims then generate all charts+tables"
	@echo "  baseline_capture  — mandatory baseline measurement (original picorv32)"
	@echo "  baseline_check    — validate baseline metrics gate for all phases"
	@echo "  phase3            — end-to-end Phase 3 flow (precheck+sim+build+collect)"
	@echo "  phase3_precheck   — run simulation/formal gates before FPGA build"
	@echo "  phase3_fpga_sim   — board-level picosoc simulation (set BOARD=...)"
	@echo "  phase3_fpga_build — FPGA synth+P&R+bitstream for BOARD"
	@echo "  phase3_program    — program FPGA+flash for BOARD"
	@echo "  phase3_collect    — collect reports and generate phase3 summary"
	@echo "                     (vars: BOARD=icebreaker|hx8kdemo, TARGET_MHZ=12, PHASE3_PROFILE=fit|full, PROGRAMMER=auto|iceprog|icesprog)"
	@echo "  phase4            — Phase 4 precheck + collect (sign-off templates)"
	@echo "  phase4_precheck   — baseline gate before Phase 4"
	@echo "  phase4_collect    — generate Phase 4 metrics/summary/graphs"
	@echo "  phase5            — Phase 5 precheck + collect (PPA templates)"
	@echo "  phase5_precheck   — baseline gate before Phase 5"
	@echo "  phase5_collect    — generate Phase 5 metrics/summary/graphs"
	@echo "  synth_ksa         — Yosys synth of ksa.v module"
	@echo "  synth_vedic       — Yosys synth of vedic_mul_32.v module"
	@echo "  synth_all_variants— Yosys synth all 4 core variants"
	@echo "  clean             — remove build dir"

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
clean:
	rm -rf $(BUILD)
	@echo "Build artifacts removed."
