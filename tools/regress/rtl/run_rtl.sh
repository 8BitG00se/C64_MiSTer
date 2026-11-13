#!/bin/bash
# OCTOPHONIC 64 - OLD-SOFTWARE REGRESSION TEST (Fix 69): the whole-C64 Verilator part, one side.  (c) 2026 Mong00se
#
# Builds the C64 of one core source tree (the last core's or the new core's) as sim/rewind does - GHDL turns
# rtl/fpga64_sid_iec.vhd into Verilog, Verilator builds it with the real CIAs and the SDRAM model - and runs the
# RTL list below through tools/regress/rtl/tb_regress.cpp. The testbench and the programs come from the HARNESS
# checkout (the same for both sides), the core from TREE.
#
#   run_rtl.sh TREE OUT [FRAMES]       needs ghdl 4, verilator 5, python3, acme (for the programs)
#   RTL_KERNAL_POKE=ADDR:VAL           (proof runs only) change one byte of TREE's BASIC+KERNAL image, e.g.
#                                      3981:0E = the start screen's background colour (LDA #$06 / STA $D021
#                                      at $F980) -> #$0E
#
# What runs (stock VIC only: this sim has no OctoVIC, no SID sound and no REU):
#   boot           the Octophonic KERNAL from power-on to READY. and on
#   code-stock     Code example: stock C64 raster bars (tools/examples/code/stock.asm)
#   disk-starfield Disks: Starfield (tools/examples/disks/starfield.asm)
#   disk-logo      Disks: Colour Logo (tools/examples/disks/logo.asm)
set -e
H=$(cd "$(dirname "$0")/../../.." && pwd)          # the harness checkout
TREE=$(cd "${1:?TREE}" && pwd); OUT=${2:?OUT}; FR=${3:-320}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
echo "== RTL regression side: core tree $TREE ($(git -C "$TREE" rev-parse --short HEAD 2>/dev/null || echo '?')), harness $H"
R=$TREE; S=$H/sim/rewind
if [ -n "$RTL_REUSE_TB" ]; then     # the same core already built (a proof run only changes rom.hex)
	cd "$OUT"; mkdir -p obj; cp "$RTL_REUSE_TB" obj/tb_regress
	echo "reusing the testbench already built: $RTL_REUSE_TB"
else
[ -x "$TREE/sim/rewind/vhdl2v.sh" ] || { echo "RTL_SIDE_UNBUILDABLE: $TREE has no sim/rewind/vhdl2v.sh (the whole-C64 sim came in with build 13)"; exit 3; }
"$TREE/sim/rewind/vhdl2v.sh" "$OUT/net" > "$OUT/vhdl2v.txt" 2>&1 || { tail -20 "$OUT/vhdl2v.txt"; echo "RTL_SIDE_UNBUILDABLE: GHDL"; exit 3; }
cd "$OUT"; ln -sf net/fpga64_synth.v fpga64_synth.v05
SRC="$H/tools/regress/rtl/public.vlt $S/tb_top.sv fpga64_synth.v05 $R/rtl/mos6526.v $R/rtl/cartridge.v $R/rtl/am29f040.sv $R/rtl/rewind.sv $R/rtl/remaster.sv $R/rtl/rgb256.sv $R/rtl/octovic/ovram.sv $R/rtl/octovic/ddram_arb2.sv $R/rtl/octovic/sid_fx.sv $R/rtl/octovic/octo_os.sv"
for f in $SRC; do [ -f "$f" ] || { echo "RTL_SIDE_UNBUILDABLE: $f is missing in this tree"; exit 3; }; done
verilator --cc --exe --build -j 2 -O3 --x-assign fast --x-initial fast -Wno-fatal --top-module tb_top -GAW=20 \
  +1364-2005ext+v05 $SRC $H/tools/regress/rtl/tb_regress.cpp \
  -CFLAGS "-O2 -Wno-attributes" -o tb_regress --Mdir obj > verilator.txt 2>&1 || { grep -E "%Error|error:" verilator.txt | head -30; echo "RTL_SIDE_UNBUILDABLE: Verilator"; exit 3; }
fi
python3 $S/mif2hex.py $R/rtl/roms/octo_C64.mif rom.hex 16384
python3 $S/mif2hex.py $R/rtl/roms/chargen.mif chargen.hex 4096
python3 -c "open('ram.hex','w').write('00\n'*65536)"
if [ -n "$RTL_KERNAL_POKE" ]; then
	python3 - "$RTL_KERNAL_POKE" <<'PY'
import sys
a, v = sys.argv[1].split(':'); a = int(a, 16)
L = open('rom.hex').read().split('\n'); old = L[a]; L[a] = '%02x' % int(v, 16)
open('rom.hex', 'w').write('\n'.join(L))
print('PROOF RUN: rom.hex byte $%04X changed %s -> %s (a deliberate one-byte change)' % (a, old, L[a]))
PY
fi
md5sum rom.hex chargen.hex | tee roms.md5
mkdir -p prg
if command -v acme >/dev/null; then
	for p in code/stock:code-stock disks/starfield:disk-starfield disks/logo:disk-logo; do
		(cd $H/tools/examples/$(dirname ${p%%:*}) && acme -f cbm -o "$OUT/prg/${p##*:}.prg" $(basename ${p%%:*}).asm)
	done
else echo "NOTE: no acme - only the KERNAL boot runs"; fi
run() {   # $1 name, $2 program or ""
	mkdir -p "run_$1"; cp rom.hex chargen.hex ram.hex "run_$1/"
	(cd "run_$1"; rc=0; ../obj/tb_regress $FR "../$1" "$2" 180 > "../$1.log" 2>&1 || rc=$?; echo $rc > "../$1.rc")
}
run boot "" &
for p in prg/*.prg; do [ -f "$p" ] && { n=$(basename "$p" .prg); run "$n" "$OUT/$p" & }; done
wait
for f in *.log; do echo "-- ${f%.log}: rc $(cat ${f%.log}.rc)"; tail -3 "$f"; done
rm -rf run_* fpga64_synth.v05 obj/*.o obj/*.cpp obj/*.h obj/*.d
echo "RTL_SIDE_DONE"
