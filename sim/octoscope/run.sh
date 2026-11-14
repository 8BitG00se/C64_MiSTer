#!/bin/sh
# OCTOSCOPE (Fix 55): the core's scope against the emulator's code - every capture sample for sample, every shown
# capture at every latch, every pixel of every line (copper bands, a tall scope over a sprite), the trace unbroken,
# no late lines (see tb.cpp). Needs Verilator 5. FAILs (exit 1) on any mismatch.
#   sim/octoscope/run.sh [frames seed busy% latmin latmax]
set -e
cd "$(dirname "$0")/../.." && R=$PWD && T=/tmp/octoscope && rm -rf $T && mkdir -p $T
# Verilator-only copies of three SID files (Quartus takes forms Verilator doesn't: "wire" function ports and
# initialised wire arrays, procedural writes to a wire array) - the logic is untouched
sed -e 's/(wire signed/(input signed/g' -e 's/(wire \[/(input [/g' \
    -e 's/^wire \(\[[0-9:]*\]\) \([A-Za-z_0-9]*\)\(\[[0-9:]*\]\) *= *$/localparam logic \1 \2\3 =/' $R/rtl/sid/sid_envelope.sv > $T/sid_envelope.sv
sed -e 's/^wire  \[7:0\] \(_st_out\|p_t_out\|ps__out\|pst_out\)\[/reg   [7:0] \1[/' $R/rtl/sid/sid_top.sv > $T/sid_top.sv
verilator --cc --exe -O3 -Wno-fatal -Wno-WIDTH -Wno-SELRANGE -Wno-PINMISSING -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT --public-flat-rw \
  --top-module tb_top $R/sim/octoscope/tb_top.sv $T/sid_top.sv $R/rtl/sid/sid_voice.sv $T/sid_envelope.sv $R/rtl/sid/sid_dac.sv \
  $R/sim/octoscope/sid_tables_stub.sv $R/sim/octoscope/sid_filter_stub.sv \
  $R/rtl/octovic/octovic.sv $R/rtl/octovic/ovram.sv $R/rtl/octovic/octoscope.sv $R/rtl/octovic/scope_screen.sv \
  $R/sim/octoscope/tb.cpp -o tb --Mdir $T/obj >$T/build.txt 2>&1 \
  && make -s -j4 -C $T/obj -f Vtb_top.mk >>$T/build.txt 2>&1 || { tail -30 $T/build.txt; echo "OCTOSCOPE: FAIL (build)"; exit 1; }
$T/obj/tb ${1:-13} ${2:-1} ${3:-20} ${4:-6} ${5:-30} ${6:-0} | tee $T/result.txt
grep -q "OCTOSCOPE: PASS" $T/result.txt
# and again with the DDR3 busy half the time, round trips of 20-80 clocks, and the port held a whole raster line
# (63 us) once a frame: still every sample, no word lost, no late line
$T/obj/tb 13 2 50 20 80 2016 | tee $T/result_busy.txt
grep -q "OCTOSCOPE: PASS" $T/result_busy.txt
