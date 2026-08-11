TOP      ?= pmc_smoke_tb
VCS      ?= vcs
VCS_OPTS ?= -full64 -sverilog -timescale=1ns/1ps -debug_access+all
IVERILOG ?= iverilog

.PHONY: compile smoke compile_iverilog smoke_iverilog static clean list

list:
	@cat filelist.f

static:
	python3 scripts/static_check.py
	python3 scripts/interface_check.py

compile:
	$(VCS) $(VCS_OPTS) -f tb/filelist_tb.f -top $(TOP) -o simv

smoke: compile
	./simv

compile_iverilog:
	$(IVERILOG) -g2012 -f tb/filelist_tb.f -s $(TOP) -o simv_iverilog

smoke_iverilog: compile_iverilog
	vvp simv_iverilog

clean:
	rm -rf simv simv_iverilog simv.daidir csrc ucli.key *.vpd *.vcd *.fsdb *.log DVEfiles verdiLog
