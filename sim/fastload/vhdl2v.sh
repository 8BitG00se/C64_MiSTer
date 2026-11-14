#!/bin/sh
# FAST LOAD (Fix 49) simulation: the VHDL the test needs, as Verilog (GHDL 4) - the C64 itself
# (sim/rewind/vhdl2v.sh: the 6510, the VIC-II, the bus logic with the fast loader's ROM bank) and the
# 1541's VIA (rtl/iec_drive/iecdrv_via6522.vhd). The drive's 6502 is the C64 netlist's T65.
#   sim/fastload/vhdl2v.sh <out dir>                                       (c) 2026 Mong00se
set -e
cd "$(dirname "$0")/../.." && R=$PWD
O=${1:-/tmp/fastload}; mkdir -p "$O"
sim/rewind/vhdl2v.sh "$O"
mkdir -p "$O/via" && cd "$O/via"
GF="--std=08 -frelaxed -fexplicit -fsynopsys --workdir=$O/via"
ghdl -a $GF $R/rtl/iec_drive/iecdrv_via6522.vhd
ghdl --synth $GF --out=verilog iecdrv_via6522 > ../via6522_synth.v 2> ../via_synth.log || { tail -40 ../via_synth.log; exit 1; }
python3 $R/sim/rewind/fixnet.py ../via6522_synth.v
grep -n "^module " ../via6522_synth.v
