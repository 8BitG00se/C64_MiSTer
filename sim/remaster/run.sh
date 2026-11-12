#!/bin/sh
# LEVEL 2 REMASTER (Build 14): rtl/remaster.sv + rtl/rgb256.sv in Verilator against the model (model.py), every
# pixel. Needs Verilator 5, numpy, Pillow.                                              (c) 2026 Mong00se
#   sim/remaster/run.sh                         made-up frames (gen.py): every case, three DDR3 speeds, learn mode
#   sim/remaster/run.sh PACK.rgb FRAMES.l2f [MODEL.rgb]   real frames (rgb256.py grab); MODEL.rgb: the pack tool's
#                                               own answer (palette 1), checked as well
set -e
cd "$(dirname "$0")/../.." && R=$PWD
T=${REMASTER_SIM_DIR:-/tmp/remastersim}; mkdir -p $T
VERILATOR=${VERILATOR:-verilator}
$VERILATOR --cc --exe -O3 -Wno-WIDTH -Wno-fatal --top-module tb_rm $R/sim/remaster/tb_rm.sv $R/rtl/remaster.sv $R/rtl/rgb256.sv \
  $R/rtl/octovic/ovram.sv $R/sim/remaster/tb.cpp -o tb --Mdir $T/obj >$T/build.txt 2>&1 \
  && make -s -j4 -C $T/obj -f Vtb_rm.mk >>$T/build.txt 2>&1 || { grep -E "%Error|error" -A4 $T/build.txt | head -40; tail -5 $T/build.txt; exit 1; }
S=$R/sim/remaster
if [ -n "$2" ]; then
	$T/obj/tb "$1" "$2" $T/rtl.rgb 0 1 0 30 10
	python3 $S/check.py "$1" "$2" $T/rtl.rgb 0 1 "${REMASTER_SIM_PNG:-$T/rtl.png}" "$3"
	$T/obj/tb "$1" "$2" $T/rtl0.rgb 0 0 0 30 10
	python3 $S/check.py "$1" "$2" $T/rtl0.rgb 0 0 | sed 's/^/   Level 2 off: /'
	exit 0
fi
python3 $S/gen.py $T
rc=0
echo "== 1: Level 2 on, the DDR3 answering in 12 clocks"
$T/obj/tb $T/test.rgb $T/test.l2f $T/rtl.rgb 0 1 0 12 0 && python3 $S/check.py $T/test.rgb $T/test.l2f $T/rtl.rgb 0 1 "${REMASTER_SIM_PNG:-$T/rtl.png}" || rc=1
echo "== 2: Level 2 on, palette 2, a slow and busy DDR3 (60 clocks and more, busy 30% of the time)"
$T/obj/tb $T/test.rgb $T/test.l2f $T/rtl2.rgb 1 1 0 60 30 && python3 $S/check.py $T/test.rgb $T/test.l2f $T/rtl2.rgb 1 1 || rc=1
echo "== 3: Level 2 off (WIN+F4): Level 1's picture exactly"
$T/obj/tb $T/test.rgb $T/test.l2f $T/rtl3.rgb 0 0 0 12 0 && python3 $S/check.py $T/test.rgb $T/test.l2f $T/rtl3.rgb 0 0 || rc=1
echo "== 4: learn mode: the picture the same, the log holds each missing key once"
$T/obj/tb $T/test.rgb $T/test.l2f $T/rtl4.rgb 0 1 1 12 0 $T/learn.bin && python3 $S/check.py $T/test.rgb $T/test.l2f $T/rtl4.rgb 0 1 \
  && python3 $S/checklearn.py $T/test.rgb $T/test.l2f $T/learn.bin || rc=1
[ $rc = 0 ] && echo "REMASTER_SIMS_ALL_OK" || echo "REMASTER_SIMS_FAILED"
exit $rc
