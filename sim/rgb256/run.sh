#!/bin/sh
# C64RGB 256 (Fix 60): the recolour unit (rtl/rgb256.sv) in Verilator against the model
# (tools/rgb256/rgb256.py), every pixel of tagged VIC-II frames, every palette. Needs Verilator 5, numpy, Pillow.
#   sim/rgb256/run.sh                       made-up frames, tools/rgb256/example.txt
#   sim/rgb256/run.sh PACK.rgb FRAMES.tags  your own (frames from tools/rgb256/rgb256.py grab)
set -e
cd "$(dirname "$0")/../.." && R=$PWD
T=${RGB256_SIM_DIR:-/tmp/rgb256sim}; rm -rf $T; mkdir -p $T
VERILATOR=${VERILATOR:-verilator}
$VERILATOR --cc --exe -O3 -Wno-WIDTH -Wno-fatal --top-module rgb256 $R/rtl/rgb256.sv $R/sim/rgb256/tb.cpp -o tb --Mdir $T/obj >$T/build.txt 2>&1 \
  && make -s -j4 -C $T/obj -f Vrgb256.mk >>$T/build.txt 2>&1 || { tail -30 $T/build.txt; exit 1; }
if [ -n "$2" ]; then PACK=$1; TAGS=$2; else
  python3 $R/sim/rgb256/gen.py $T/test.tags
  python3 $R/tools/rgb256/rgb256.py make $R/tools/rgb256/example.txt -o $T/example.rgb
  PACK=$T/example.rgb; TAGS=$T/test.tags
fi
$T/obj/tb $PACK $TAGS $T/rtl.rgb
python3 $R/sim/rgb256/check.py $PACK $TAGS $T/rtl.rgb ${RGB256_SIM_PNG:-$T/rtl.png}
