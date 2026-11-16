# ------------------------------------------------------------------------------
#  make lint        - lint the RTL with Verilator and Icarus (pure Verilog-2005)
#  make sim         - build + run the SystemVerilog testbench with Verilator
#  make wave        - same, with VCD dump (view: gtkwave code_converter.vcd)
#  make questa      - run with Questa/ModelSim   (if vsim is installed)
#  make vcs         - run with Synopsys VCS      (if vcs is installed)
#  make xrun        - run with Cadence Xcelium   (if xrun is installed)
#  make clean
#
#  Verilator build directory can be overridden:  make sim MDIR=/tmp/obj
# ------------------------------------------------------------------------------
TOP  := tb_code_converter
MDIR ?= obj_dir

VFLAGS := --binary --timing --assert -Wno-fatal -Wno-lint -Wno-style --top-module $(TOP)

lint:
	verilator --lint-only -Wall -f filelist_rtl.f --top-module code_converter_top
	iverilog -g2005 -Wall -I../rtl -o /dev/null ../rtl/code_converter_top.v ../rtl/conv_control.v ../rtl/conv_datapath.v
	@echo "LINT CLEAN"

sim:
	verilator $(VFLAGS) -Mdir $(MDIR) -f filelist_rtl.f -f filelist_tb.f
	$(abspath $(MDIR))/V$(TOP) | tee sim.log
	@grep -q "TEST PASSED" sim.log && echo "==> PASS" || (echo "==> FAIL"; exit 1)

wave:
	verilator $(VFLAGS) --trace -DDUMP_VCD -Mdir $(MDIR)_wave -f filelist_rtl.f -f filelist_tb.f
	$(abspath $(MDIR)_wave)/V$(TOP) | tee sim.log

questa:
	vlib work
	vlog -sv -f filelist_rtl.f -f filelist_tb.f
	vsim -c -do "run -all; quit" $(TOP) | tee sim.log

vcs:
	vcs -sverilog -timescale=1ns/1ps -full64 -f filelist_rtl.f -f filelist_tb.f -top $(TOP) -o simv
	./simv | tee sim.log

xrun:
	xrun -sv -access +r -f filelist_rtl.f -f filelist_tb.f -top $(TOP) | tee sim.log

clean:
	rm -rf obj_dir obj_dir_wave work simv* csrc xcelium.d sim.log *.vcd *.wlf transcript
