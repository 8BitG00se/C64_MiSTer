#!/bin/sh
# rtl/sid_mix.vhd (the eight-SID mix, Fix 28) in GHDL against the integer model the emulator uses.
# Needs ghdl and python3.
set -e
cd "$(dirname "$0")/../.." && R=$PWD && mkdir -p /tmp/mixtest && cd /tmp/mixtest
python3 "$R/sim/level/mixvec.py" gen vec.txt exp.txt
ghdl -a --std=93c -fexplicit "$R/rtl/sid_mix.vhd" "$R/sim/level/tb_sid_mix.vhd"
ghdl -e --std=93c -fexplicit tb_sid_mix
ghdl -r --std=93c -fexplicit tb_sid_mix --ieee-asserts=disable
python3 "$R/sim/level/mixvec.py" check exp.txt out.txt
