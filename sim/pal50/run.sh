#!/bin/sh
# EXACT 50 Hz (Fix 48) checks: the PLL writes, the VIC frame length, the TOD, the 1541/RTC enables, a
# fast-loader style handshake and tape timing; check.py turns it into real time and verdicts.
# Needs Verilator 5, GHDL and python3.   sim/pal50/run.sh       (c) 2026 Mong00se
set -e
cd "$(dirname "$0")/../.." && R=$PWD && T=/tmp/pal50 && rm -rf $T && mkdir -p $T
cd $T
verilator --cc --exe --build -O3 -j 4 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY \
  --top-module top $R/sim/pal50/top.sv $R/rtl/pal50.sv $R/rtl/c1530.sv $R/sim/pal50/scfifo_stub.sv \
  $R/sim/pal50/tb.cpp -o tb >$T/build.txt 2>&1 || { tail -30 $T/build.txt; exit 1; }
./obj_dir/tb | tee $T/tb.txt
G="ghdl"; GF="--std=93c -fexplicit"
$G -a $GF $R/rtl/video_vicII_656x.vhd $R/rtl/cia_tod_clk.vhd $R/sim/pal50/tb_vic.vhd $R/sim/pal50/tb_tod.vhd
$G -e $GF tb_vic
$G -e $GF tb_tod
$G -r $GF tb_vic -gNTSC=0 | grep -E "LINE|FRAME" > $T/vic_pal.txt;  cat $T/vic_pal.txt
$G -r $GF tb_vic -gNTSC=1 | grep -E "LINE|FRAME" > $T/vic_ntsc.txt; cat $T/vic_ntsc.txt
$G -r $GF tb_tod -gNTSC=0 -gEXACT=0 | grep TOD > $T/tod_pal.txt
$G -r $GF tb_tod -gNTSC=0 -gEXACT=1 | grep TOD > $T/tod_exact.txt
$G -r $GF tb_tod -gNTSC=1 -gEXACT=0 | grep TOD > $T/tod_ntsc.txt
cat $T/tod_*.txt
python3 $R/sim/pal50/check.py $T/tb.txt $T/vic_pal.txt $T/vic_ntsc.txt $T/tod_pal.txt $T/tod_exact.txt $T/tod_ntsc.txt | tee $T/result.txt
