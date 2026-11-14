#!/bin/sh
# FAST LOAD (Fix 49) - the simulation: the whole C64 and its 1541 (GHDL's Verilog of the VHDL, sim/fastload/
# vhdl2v.sh) in Verilator. Three runs of LOAD"*",8,1 from the Octophonic KERNAL's READY prompt, the same file
# on the same disk: the fast loader on (the default), switched off, and on with the parallel port disabled.
# Each must leave the file in memory byte for byte; the times are printed side by side.
# Needs Verilator 5 and python3.   sim/fastload/run.sh <dir with fpga64_synth.v and via6522_synth.v> [blocks]
#                                                                                   (c) 2026 Mong00se
set -e
cd "$(dirname "$0")/../.." && R=$PWD
O=${1:-/tmp/fastload}; S=$R/sim/fastload; B=${2:-12}
[ -f "$O/fpga64_synth.v" ] && [ -f "$O/via6522_synth.v" ] || { echo "run.sh: no netlists in $O - run sim/fastload/vhdl2v.sh $O first"; exit 1; }
cd "$O"
ln -sf fpga64_synth.v fpga64_synth.v05     # (the netlists are Verilog 2005: they have signals called do and break)
ln -sf via6522_synth.v via6522_synth.v05
M=$R/sim/rewind/mif2hex.py
python3 $M $R/rtl/roms/octo_C64.mif octo.hex 16384
python3 $M $R/rtl/roms/std_C64.mif std.hex 16384
python3 $M $R/rtl/roms/octo_fastload.mif fastload.hex 4096
python3 $M $R/rtl/roms/chargen.mif chargen.hex 4096
python3 $M $R/rtl/iec_drive/c1541_rom.mif c1541.hex 16384
python3 $M $R/rtl/iec_drive/c1541_fastload.mif fastdrive.hex 512
python3 -c "open('zero.hex','w').write('00\n'*65536)"
python3 $S/mkdisk.py $B test.prg test.d64 g64.hex
# (Verilator will not take "wire [..] name[n] = '{...};": the same with an assign, in a copy for the simulation)
for f in c1541_direct_gcr; do
	python3 - $R/rtl/iec_drive/$f.sv $f.sim.sv <<'P'
import re, sys
s = open(sys.argv[1]).read()
s = re.sub(r"wire\s*(\[[^\]]+\])\s*(\w+)\s*(\[\d+\])\s*=\s*'\{", r"wire \1 \2\3; assign \2 = '{", s)
open(sys.argv[2], 'w').write(s)
P
done
${VERILATOR:-verilator} --cc --exe --build -j 4 -O3 --x-assign fast --x-initial fast -Wno-fatal --top-module tb_top \
  +1364-2005ext+v05 $S/public.vlt $S/tb_top.sv fpga64_synth.v05 via6522_synth.v05 \
  $R/rtl/mos6526.v $R/rtl/cartridge.v $R/rtl/am29f040.sv $R/rtl/octovic/octo_os.sv $R/rtl/octovic/sid_fx.sv $R/rtl/octovic/ovram.sv $R/rtl/pal50.sv \
  $R/rtl/iec_drive/c1541_multi.sv $R/rtl/iec_drive/c1541_drv.sv $R/rtl/iec_drive/c1541_logic.sv \
  c1541_direct_gcr.sim.sv $R/rtl/iec_drive/c1541_track.sv $R/rtl/iec_drive/iecdrv_misc.sv $R/rtl/iec_drive/lfsr.v \
  $S/tb.cpp -CFLAGS "-O2 -Wno-attributes" -o tb --Mdir obj > build.txt 2>&1 || { grep -E "%Error|error:" build.txt | head -30; tail -5 build.txt; exit 1; }
rc=0
for m in fast slow noport; do (./obj/tb $m test.prg > $m.txt 2>&1; echo $? > $m.rc) & done
wait
for m in fast slow noport; do
	case $m in fast) echo "== 1: Fast loader On (the default)";; slow) echo "== 2: Fast loader Off";; noport) echo "== 3: Fast loader On, Parallel port Disabled";; esac
	cat $m.txt; [ "$(cat $m.rc)" = 0 ] || rc=1
done
f=$(sed -n 's/^TIME fast [0-9]* blocks: \([0-9.]*\) s.*/\1/p' fast.txt); s=$(sed -n 's/^TIME slow [0-9]* blocks: \([0-9.]*\) s.*/\1/p' slow.txt)
[ -n "$f" ] && [ -n "$s" ] && python3 -c "print('== the same $B-block file: %.2f s the slow way, %.2f s with the fast loader: %.1f times faster' % ($s, $f, $s / $f))"
[ $rc = 0 ] && echo "FASTLOAD_SIMS_ALL_OK" || echo "FASTLOAD_SIMS_FAILED"
exit $rc
