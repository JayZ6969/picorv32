DEVICE      := up5k
PACKAGE     := sg48
FREQ        := 12
PCF         := ../constraints/picorv32_ice40up5k.pcf
NEXTPNR     := nextpnr-ice40
ICETIME     := icetime
ICEPACK     := icepack
CONFIGS     := baseline_A baseline_B baseline_C baseline_C_ksa optimized

.PHONY: all $(CONFIGS) timing_all packs clean

all: $(CONFIGS) timing_all

define PNR_RULE
$(1): ../synth/$(1)/design.json
	@mkdir -p $(1) ../pnr/reports
	@echo "-- PnR: $(1) --------------------------------------"
	@if $(NEXTPNR) \
		--$(DEVICE) \
		--package $(PACKAGE) \
		--freq $(FREQ) \
		--json ../synth/$(1)/design.json \
		--pcf $(PCF) \
		--asc $(1)/design.asc \
		--report ../pnr/reports/$(1)_report.json \
		--log ../pnr/reports/$(1)_pnr.log \
		--seed 1 \
		--timing-allow-fail \
		--pcf-allow-unconstrained; then rc=0; else rc=1; fi; \
	echo $$$$rc > ../pnr/reports/$(1)_pnr.exit; \
	cp -f ../pnr/reports/$(1)_pnr.log ../pnr/reports/$(1)_pnr_stdout.log 2>/dev/null || true; \
	if [ "$$$$rc" != "0" ]; then \
		echo "-- PnR failed: $(1) (rc=$$$$rc)"; \
		rm -f $(1)/design.asc; \
	else \
		echo "-- PnR done: $(1)"; \
	fi; \
	exit 0
endef
$(foreach cfg,$(CONFIGS),$(eval $(call PNR_RULE,$(cfg))))

define TIMING_RULE
timing_$(1): $(1)
	@if [ -f $(1)/design.asc ]; then \
		$(ICETIME) \
			-d $(DEVICE) \
			-m \
			-t \
			-r ../pnr/reports/$(1)_timing.rpt \
			$(1)/design.asc \
			> ../pnr/reports/$(1)_icetime.log 2>&1 || true; \
		grep "Max frequency" ../pnr/reports/$(1)_timing.rpt || true; \
	else \
		echo "No ASC for $(1); skipping icetime." > ../pnr/reports/$(1)_icetime.log; \
		: > ../pnr/reports/$(1)_timing.rpt; \
	fi
endef
$(foreach cfg,$(CONFIGS),$(eval $(call TIMING_RULE,$(cfg))))

timing_all: $(foreach cfg,$(CONFIGS),timing_$(cfg))

define PACK_RULE
pack_$(1): $(1)/design.asc
	$(ICEPACK) $(1)/design.asc $(1)/design.bin
	@echo "Bitstream: $(1)/design.bin"
endef
$(foreach cfg,$(CONFIGS),$(eval $(call PACK_RULE,$(cfg))))

packs: $(foreach cfg,$(CONFIGS),pack_$(cfg))

clean:
	rm -rf $(foreach cfg,$(CONFIGS),$(cfg))
	rm -rf ../pnr/reports
