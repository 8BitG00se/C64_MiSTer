#!/bin/sh
# FINE SCROLL check (Fix 42): the new OctoVIC with and without the 4x clock against the OctoVIC from
# before Fix 42 (git $OLDREV, default 6bfa651), every sub-pixel of 15 frames. Needs Verilator 5, numpy.
#   sim/finescroll/run.sh
set -e
cd "$(dirname "$0")/../.." && R=$PWD && T=/tmp/finescroll && rm -rf $T && mkdir -p $T/old
git show ${OLDREV:-6bfa651}:rtl/octovic/octovic.sv > $T/old/octovic.sv
cd $R/sim/finescroll
python3 gen.py $T/vram.bin $T/script.txt
build () {  # build <dir> <rtl> [flags]
  verilator --cc --exe -O3 -Wno-WIDTH -Wno-fatal --top-module octovic $3 "$2" $R/rtl/octovic/ovram.sv $R/sim/finescroll/tb.cpp -o tb --Mdir $1 >$T/build.txt 2>&1 \
    && make -s -j4 -C $1 -f Voctovic.mk >>$T/build.txt 2>&1 || { tail -30 $T/build.txt; exit 1; }
}
build $T/obj_new $R/rtl/octovic/octovic.sv
build $T/obj_old $T/old/octovic.sv -CFLAGS\ -DNOQUARTER
QUARTER=1 $T/obj_new/tb $T/vram.bin $T/script.txt 15 $T/q1.rgb 3 25 6 40
QUARTER=0 $T/obj_new/tb $T/vram.bin $T/script.txt 15 $T/q0.rgb 3 25 6 40
$T/obj_old/tb $T/vram.bin $T/script.txt 15 $T/old.rgb 3 25 6 40
python3 check.py $T/q1.rgb $T/q0.rgb $T/old.rgb
python3 pics.py $T/q1.rgb $T/old.rgb $T 2>/dev/null || true
