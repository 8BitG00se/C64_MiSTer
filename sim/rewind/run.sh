#!/bin/sh
# REWIND (Fix 61) - the simulation: the whole C64 (GHDL's Verilog of it, sim/rewind/vhdl2v.sh) with the
# rewind unit in Verilator. Three runs: the test game, the test game with a small stack in a busy DDR3
# (the ring wraps, the oldest frames go), and the Octophonic KERNAL to READY. with a rewind there.
# Needs Verilator 5, python3 (numpy, pillow), ffmpeg for the clip; acme only to remake the test game.
#   sim/rewind/run.sh <dir with fpga64_synth.v>                                (c) 2026 Mong00se
set -e
cd "$(dirname "$0")/../.." && R=$PWD
O=${1:-/tmp/rewind}; S=$R/sim/rewind
[ -f "$O/fpga64_synth.v" ] || { echo "run.sh: no $O/fpga64_synth.v - run sim/rewind/vhdl2v.sh $O first"; exit 1; }
cd "$O"
ln -sf fpga64_synth.v fpga64_synth.v05   # (the netlist is Verilog 2005: it has signals called do and break)
if command -v acme >/dev/null 2>&1; then
	python3 $S/mkgame.py rwdata.asm
	acme -f plain -o rwgame.bin $S/rwgame.asm && acme -f plain -o rwrom.bin $S/rwrom.asm
	python3 $S/mif2hex.py rwgame.bin $S/rwgame.hex 65536 0x0810
	python3 $S/mif2hex.py rwrom.bin $S/rwrom.hex
fi
python3 $S/mif2hex.py $R/rtl/roms/octo_C64.mif octo.hex 16384
python3 $S/mif2hex.py $R/rtl/roms/chargen.mif chargen.hex 4096
python3 -c "open('zero.hex','w').write('00\n'*65536)"

build() {   # $1 the stack's address bits, $2 the folder
	verilator --cc --exe --build -j 4 -O3 --x-assign fast --x-initial fast -Wno-fatal --top-module tb_top -GAW=$1 \
	  +1364-2005ext+v05 $S/public.vlt $S/tb_top.sv fpga64_synth.v05 $R/rtl/mos6526.v $R/rtl/cartridge.v $R/rtl/am29f040.sv $R/rtl/rewind.sv $R/rtl/octovic/ovram.sv \
	  $R/rtl/octovic/ddram_arb2.sv $R/rtl/octovic/sid_fx.sv $R/rtl/octovic/octo_os.sv $S/tb.cpp \
	  -CFLAGS "-O2 -Wno-attributes" -o tb --Mdir $2 > $2.txt 2>&1 || { grep -E "%Error|error:" $2.txt | head -30; tail -5 $2.txt; exit 1; }
}
build 20 obj20
build 15 obj15
# the three runs side by side, each in its own folder (rom.hex, ram.hex and chargen.hex are read from there)
for d in r1 r2 r3; do mkdir -p $d; cp chargen.hex $d/; done
cp $S/rwrom.hex r1/rom.hex; cp $S/rwgame.hex r1/ram.hex
cp $S/rwrom.hex r2/rom.hex; cp $S/rwgame.hex r2/ram.hex
cp octo.hex r3/rom.hex; cp zero.hex r3/ram.hex
(set +e; cd r1 && ../obj20/tb game ../frames_game.bin 0 > ../game.txt 2>&1; echo $? > rc) &
(set +e; cd r2 && ../obj15/tb game "" 30 > ../small.txt 2>&1; echo $? > rc) &
(set +e; cd r3 && ../obj20/tb boot ../frames_boot.bin 10 > ../boot.txt 2>&1; echo $? > rc) &
wait
rc=0
echo "== 1: the test game (the stack: 1M words, the DDR3 answering in 60 clocks)"
cat game.txt; [ "$(cat r1/rc)" = 0 ] || rc=1
echo "== 2: the test game, a stack of 32768 words (it wraps; the oldest frames go), the DDR3 busy 30% of the time"
grep -v "^OK   step" small.txt; echo "   ($(grep -c "^OK   step" small.txt) rewind steps compared: all the same)"; [ "$(cat r2/rc)" = 0 ] || rc=1
echo "== 3: the Octophonic KERNAL (no OctoVIC in this core) to READY., then a rewind; the DDR3 busy 10% of the time"
grep -v "^OK   step" boot.txt; echo "   ($(grep -c "^OK   step" boot.txt) rewind steps compared: all the same)"; [ "$(cat r3/rc)" = 0 ] || rc=1
if [ -z "$NOCLIP" ]; then
	python3 $S/mkclip.py frames_game.bin rewind_game.mp4 rewind_game.png || true
	python3 $S/mkclip.py frames_boot.bin rewind_boot.mp4 rewind_boot.png || true
fi
rm -rf frames_game.bin frames_boot.bin zero.hex r1 r2 r3
[ $rc = 0 ] && echo "REWIND_SIMS_ALL_OK" || echo "REWIND_SIMS_FAILED"
exit $rc
