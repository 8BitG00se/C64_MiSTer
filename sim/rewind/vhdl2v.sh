#!/bin/sh
# REWIND (Fix 61): the C64 itself (rtl/fpga64_sid_iec.vhd with the 6510, the VIC-II and the bus logic) turned
# into Verilog with GHDL, so the whole machine can run in Verilator beside the rewind unit.
# Needs GHDL 4.   sim/rewind/vhdl2v.sh <out dir>            (c) 2026 Mong00se
set -e
cd "$(dirname "$0")/../.." && R=$PWD
O=${1:-/tmp/rewind}; mkdir -p "$O"; cd "$O"
GF="--std=08 -frelaxed -fexplicit -fsynopsys --workdir=$O"
ghdl -a $GF $R/rtl/t65/T65_Pack.vhd $R/rtl/t65/T65_ALU.vhd $R/rtl/t65/T65_MCode.vhd $R/rtl/t65/T65.vhd \
  $R/rtl/cpu_6510.vhd $R/rtl/dprom.vhd $R/rtl/spram.vhd $R/rtl/video_vicII_656x.vhd $R/sim/rewind/stubs.vhd \
  $R/rtl/fpga64_keyboard.vhd $R/rtl/fpga64_buslogic.vhd $R/rtl/sid_mix.vhd $R/rtl/cia_tod_clk.vhd $R/rtl/fpga64_sid_iec.vhd
ghdl --synth $GF --out=verilog -gREWIND=1 fpga64_sid_iec > fpga64_synth.v 2> synth.log || { tail -40 synth.log; exit 1; }
python3 $R/sim/rewind/fixnet.py fpga64_synth.v
tail -5 synth.log
wc -l fpga64_synth.v
grep -n "^module " fpga64_synth.v | head -60
