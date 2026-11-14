#!/bin/sh
# © 2026 Mong00se
# MY CHIPS, PER SID (Fix 81): each of the eight SIDs really plays the chip its menu line says - its model, its
# filter curve and its combined waveforms - in every arrangement tried (see tb.cpp). Needs Verilator 5.
# FAILs (exit 1) on any mismatch.      sim/perslot/run.sh [random arrangements, default 24]
set -e
cd "$(dirname "$0")/../.." && R=$PWD && T=${TMPDIR:-/tmp}/perslot && rm -rf $T && mkdir -p $T
# Verilator-only copies of four SID files (Quartus takes forms Verilator doesn't: "wire" function ports and
# initialised wire arrays, procedural writes to a wire array) - the logic is untouched
W='s/(wire signed/(input signed/g;s/(wire \[/(input [/g;s/(wire x_neg, wire signed/(input x_neg, input signed/g'
sed -e "$W" -e 's/^wire \(\[[0-9:]*\]\) \([A-Za-z_0-9]*\)\(\[[0-9:]*\]\) *= *$/localparam logic \1 \2\3 =/' $R/rtl/sid/sid_envelope.sv > $T/sid_envelope.sv
sed -e "$W" -e 's/^wire \(\[[0-9:]*\]\) \([A-Za-z_0-9]*\)\(\[[0-9:]*\]\) *= *$/localparam logic \1 \2\3 =/' \
    -e 's/^\(\treg signed \[[0-9:]*\] v[id]\) = 0;/\1;/' $R/rtl/sid/sid_filter.sv > $T/sid_filter.sv   # (and two block-local "= 0"s)
sed -e "$W" -e 's/^wire \(\[[0-9:]*\]\) \([A-Za-z_0-9]*\)\(\[[0-9:]*\]\) *= *$/localparam logic \1 \2\3 =/' $R/rtl/sid/sid_tables.sv > $T/sid_tables.sv
sed -e 's/^wire  \[7:0\] \(_st_out\|p_t_out\|ps__out\|pst_out\)\[/reg   [7:0] \1[/' $R/rtl/sid/sid_top.sv > $T/sid_top.sv
verilator --cc --exe -O2 -Wno-fatal -Wno-WIDTH -Wno-SELRANGE -Wno-PINMISSING -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT \
  --top-module tb_top $R/sim/perslot/tb_top.sv $R/rtl/sid/chip_slots.sv $R/rtl/sid/chip_bank.sv \
  $T/sid_top.sv $R/rtl/sid/sid_voice.sv $T/sid_envelope.sv $R/rtl/sid/sid_dac.sv $T/sid_tables.sv $T/sid_filter.sv \
  $R/sim/perslot/tb.cpp -o tb --Mdir $T/obj >$T/build.txt 2>&1 \
  && make -s -j4 -C $T/obj -f Vtb_top.mk >>$T/build.txt 2>&1 || { tail -30 $T/build.txt; echo "PERSLOT: FAIL (build)"; exit 1; }
$T/obj/tb $R/chips/MOS_6581_5084.CHP $R/chips/CSG_8580R5_3591.CHP $R/chips/MOS_6581_3184.CHP $R/chips/MOS_8580R5_4687.CHP ${1:-24} | tee $T/result.txt
grep -q "PERSLOT: PASS" $T/result.txt
