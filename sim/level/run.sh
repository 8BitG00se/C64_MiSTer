#!/bin/bash
# Fix 28's level loop: the test programs in the Octophonic 64 emulator and in "stock VICE" (VICE's own
# reSID / reSID-fp with VICE 3.10's defaults, fed the same SID writes), then the table.
#   sim/level/run.sh OUT            (needs acme, g++, python3 with numpy; the emulator's VICE tree and build
#                                    for vref's libraries, and /home/claude/emu - the current-KERNAL emulator)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); OUT=$(mkdir -p "$1" && cd "$1" && pwd)
V=${VICE_SRC:-/home/claude/octophonic-backgrounds/emulator/src/vice/src}; B=${VICE_BUILD:-/home/claude/emu/build/src}
g++ -O2 -std=c++17 -o "$OUT/vref" "$HERE/vref.cc" -I$V -I$B -I$V/resid -I$B/resid -I$V/lib/libresidfp/src -I$B/lib/libresidfp/src \
    $B/resid/libresid.a $B/lib/libresidfp/src/.libs/libresidfp.a -lpthread
python3 "$HERE/gen.py" "$OUT/tests" >/dev/null
mkdir -p "$OUT/vice"
for t in "$OUT"/tests/*/; do
  n=$(basename "$t")
  ${EMUSND:-/home/claude/emu/emusnd.sh} "$t" "$OUT/$n" 600 >/dev/null
  ns=$(case $n in *1) echo 1;; *2) echo 2;; *4) echo 4;; *) echo 8;; esac)
  "$OUT/vref" resid 6581 $ns "$OUT/$n.sidw" "$OUT/vice/$n.resid.pcm" 14
  "$OUT/vref" residfp 6581 $ns "$OUT/$n.sidw" "$OUT/vice/$n.fp.pcm" 14
done
python3 "$HERE/table.py" "$OUT" chord1 tune1 chord2 tune2 tune4 chord8 tune8 uneven8 uneven8b
