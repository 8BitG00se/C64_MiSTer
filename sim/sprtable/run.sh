#!/bin/sh
# THE SPRITE TABLE CHECK: the sprite table OctoVIC's RTL draws with, frame by frame, against the emulator's
# model (copied from VRAM at SATBASE as line 0 is started), for the two ways programs feed it - uploaded by
# REU in the vertical blank (the shooter engine) and double-buffered with SATBASE flipped (Code/sprites) -
# with the DDR3 idle, busy, very busy, and held for 1,500 clocks in the middle of the upload (no VDATA byte
# may be lost: LOST $D6B2 stays 0). Needs Verilator 5, python3 + numpy.   sim/sprtable/run.sh
set -e
cd "$(dirname "$0")/../.." && R=$PWD && T=/tmp/sprtable && rm -rf $T && mkdir -p $T
cd $R/sim/sprtable
verilator --cc --exe -O3 -Wno-WIDTH -Wno-fatal --public-flat-rw --top-module octovic \
  $R/rtl/octovic/octovic.sv $R/rtl/octovic/ovram.sv $R/rtl/octovic/octoscope.sv tb.cpp -o tb --Mdir obj >$T/build.txt 2>&1 \
  && make -s -j4 -C obj -f Voctovic.mk >>$T/build.txt 2>&1 || { tail -20 $T/build.txt; exit 1; }
fail=0
for mode in vblank flip; do
  python3 gen.py $mode $T/$mode.log 12
  for m in "0 6 30" "80 40 120" "90 60 160"; do
    SATN=48 python3 replay.py $T/$mode 0 12 $T/out $m 1 | tail -1 | sed "s/^/$mode: /" | tee $T/r.txt
    grep -q "^$mode: PASS.*lost: 0$" $T/r.txt || fail=1
  done
done
STALL=304:1500 SATN=48 python3 replay.py $T/vblank 0 12 $T/out 30 6 40 1 | tail -1 | sed "s/^/vblank: /" | tee $T/r.txt
grep -q "PASS.*lost: 0$" $T/r.txt || fail=1
# the limit (63 bytes queued): held for 4,000 clocks the queue overflows - LOST must say so
STALL=304:4000 SATN=48 python3 replay.py $T/vblank 0 12 $T/out 30 6 40 1 | tail -1 | sed "s/^/vblank (over the limit, LOST must count): /" | tee $T/r.txt || true
grep -q "lost: [1-9]" $T/r.txt || fail=1
[ $fail = 0 ] && echo "SPRTABLE: PASS" || { echo "SPRTABLE: FAIL"; exit 1; }
