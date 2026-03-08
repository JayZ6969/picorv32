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

.PHONY: all clean tb_ksa tb_vedic formal formal_full waves_ksa waves_vedic \
        synth_ksa synth_vedic synth_core synth_ksa_core synth_vedic_core synth_both_core \
        tb_pcpi_compare report

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
	$(PYTHON) $(FORMAL)/gf2_verify.py --bits 4
	@echo ""

formal_full:
	@echo ""
	@echo "--- GF(2) Formal Verification (8-bit, exhaustive, signed) ---"
	$(PYTHON) $(FORMAL)/gf2_verify.py --bits 8 --exhaustive --signed
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

$(REPORTS):
	mkdir -p $(REPORTS)

# ---------------------------------------------------------------------------
# [PCPI Compare] Baseline sequential MUL vs Vedic pipeline latency
# ---------------------------------------------------------------------------
$(BUILD)/tb_pcpi_compare: $(TB)/tb_pcpi_compare.v $(ROOT)/picorv32.v \
                           $(RTL)/vedic_mul_32.v $(RTL)/picorv32_pcpi_vedic_mul.v | $(BUILD) $(REPORTS)
	$(IVERILOG) -Wno-portbind -g2001 -o $@ $^

tb_pcpi_compare: $(BUILD)/tb_pcpi_compare
	@echo ""
	@echo "--- Running PCPI MUL Latency Comparison ---"
	cd $(BUILD) && $(VVP) tb_pcpi_compare
	@echo ""

# ---------------------------------------------------------------------------
# [Report] Generate all charts and tables from simulation results
# ---------------------------------------------------------------------------
report: tb_ksa tb_vedic tb_pcpi_compare
	@echo ""
	@echo "--- Generating report figures and tables ---"
	$(PYTHON) $(REPORTS)/generate_report.py
	@echo ""
	@echo "=== Report artifacts in $(REPORTS)/ ==="
	@ls -1 $(REPORTS)/*.png $(REPORTS)/*.csv $(REPORTS)/*.tex 2>/dev/null

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
