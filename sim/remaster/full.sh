#!/bin/sh
# LEVEL 2 REMASTER behind the real VIC-II: the whole C64 (GHDL's Verilog of it, as sim/rewind) runs the test game
# with the remaster and recolour units behind it.                                    (c) 2026 Mong00se
#   run 1 (no pack): what the VIC gives the unit is written as frames (.l2f) and checked against the char ROM and
#          the sprites' data; a pack is made for those frames;
#   run 2 (that pack): the picture out of the units must be the model's, every pixel (and the frames the same).
#   sim/remaster/full.sh <dir with fpga64_synth.v and the rewind sim's obj20 (sim/rewind/run.sh builds it)>
set -e
cd "$(dirname "$0")/../.." && R=$PWD
O=${1:-/tmp/rewind}; S=$R/sim/remaster
cd "$O"
[ -x obj20/tb ] || { echo "full.sh: no $O/obj20/tb - sim/rewind/run.sh builds it"; exit 1; }
mkdir -p rmf; cp $R/sim/rewind/rwrom.hex rmf/rom.hex; cp $R/sim/rewind/rwgame.hex rmf/ram.hex; cp chargen.hex rmf/
cd rmf
../obj20/tb remaster p1 10 "" ${RM_FIRST:-70} ${RM_FRAMES:-3} | tail -3
python3 $S/fullpack.py p1.l2f chargen.hex full.rgb
../obj20/tb remaster p2 10 full.rgb ${RM_FIRST:-70} ${RM_FRAMES:-3} | tail -3
cmp p1.l2f p2.l2f && echo "the frames of both runs are the same"
python3 $S/check.py full.rgb p2.l2f p2.rgb 0 1 "${REMASTER_FULL_PNG:-full.png}"
# run 3: the rewind test again with the remaster unit at work beside it (learn mode on: it writes to the DDR3 too)
RM_PACK=full.rgb ../obj20/tb game "" 20 > rewind_with_remaster.txt 2>&1 || { tail -5 rewind_with_remaster.txt; exit 1; }
grep -E "^INFO the remaster|REWIND_SIM" rewind_with_remaster.txt
grep -q "REWIND_SIM_OK" rewind_with_remaster.txt
echo "REMASTER_FULL_OK"
