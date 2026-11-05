#!/bin/bash
# THE EXAMPLE SET - builds every example in games/C64 (all but Demos, which come from the demos'
# own build packages) into OUT/games/C64, the payload of SD recipe step 015.
#   tools/examples/build.sh OUT [OCTOCODE.PRG]
# Needs acme, c1541 (VICE's), python3 with PIL. Everything here is original Octophonic 64 / Mong00se
# work: no Commodore ROMs, no third-party code, pictures or tunes (the tunes are SIDWeaver's,
# Mong00se's own program; the chips are his own measured SIDs).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=${1:?OUT folder}
G="$OUT/games/C64"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$G"/{Demos,Games,Apps,Code,Music,SIDs,Pictures,"My Chips",Disks,Screenshots,Saves}

# Apps: OCTOCODE, the code editor
OC=${2:-}
if [ -z "$OC" ]; then acme -f cbm -o "$W/octocode.prg" "$REPO/tools/octoos/octocode/octocode.asm" 2>/dev/null; OC="$W/octocode.prg"; fi
cp "$OC" "$G/Apps/OCTOCODE.PRG"

# Code: the OCTOCODE examples - each .asm (as OCTOCODE's F2 leaves it in Code) and its program
# Disks: the same, a .d64 each - the program first (LOAD"*",8,1 and RUN), its source as a SEQ file
#        (OCTOCODE's F3 loads it from the disk in drive 8)
declare -A DISK=( [raster]="Raster Bars" [scroll]="Big Scroller" [sprites]="64 Sprites" [plasma]="Plasma"
                  [bounce]="Bouncing Logo" [split]="Split Screens" [parallax]="Parallax" )
for a in hello stock raster scroll sprites plasma bounce split parallax; do
    cp "$HERE/code/$a.asm" "$G/Code/$a.asm"
    acme -f cbm -o "$G/Code/$a.prg" "$HERE/code/$a.asm"
    if [ -n "${DISK[$a]:-}" ]; then
        python3 -I "$REPO/tools/octoos/octocode/a2p.py" "$HERE/code/$a.asm" "$W/$a.seq"
        n=$(printf '%s' "${DISK[$a]}" | tr 'A-Z' 'a-z')
        c1541 -format "${n:0:16},oc" d64 "$W/d.d64" -write "$G/Code/$a.prg" "$a" -write "$W/$a.seq" "$a.asm,s" >/dev/null 2>&1
        cp "$W/d.d64" "$G/Disks/${DISK[$a]}.d64"
    fi
done
# OCTOCODE Examples.d64: OCTOCODE first (RETURN on the disk starts it, and it opens HELLO.ASM from
# the disk), then every example's source for its F3
ARGS=(-write "$OC" "octocode")
for a in hello stock raster scroll sprites plasma bounce split parallax; do
    python3 -I "$REPO/tools/octoos/octocode/a2p.py" "$HERE/code/$a.asm" "$W/$a.seq"
    ARGS+=(-write "$W/$a.seq" "$a.asm,s")
done
c1541 -format "octocode examples,oc" d64 "$G/Disks/OCTOCODE Examples.d64" "${ARGS[@]}" >/dev/null 2>&1
# a cartridge and a plain BASIC disk
acme -f plain -o "$W/cart.bin" "$HERE/misc/cart.asm"
python3 -I - "$W/cart.bin" "$G/Disks/Hello Cart.crt" <<'PY'
import sys, struct
b = open(sys.argv[1], 'rb').read(); assert len(b) == 8192
h = b'C64 CARTRIDGE   ' + struct.pack('>IHHBB', 0x40, 0x0100, 0, 0, 1) + b'\0' * 6 + b'HELLO CART'.ljust(32, b'\0')
open(sys.argv[2], 'wb').write(h + b'CHIP' + struct.pack('>IHHHH', 0x2010, 0, 0, 0x8000, 0x2000) + b)
PY
printf '10 print "hello from the disk!"\n20 print "a basic program on a .d64,"\n30 print "picked in the browser: it went"\n40 print "into drive 8, and load and run"\n50 print "were typed for you."\n' > "$W/hello.bas"
petcat -w2 -o "$W/hello.prg" -- "$W/hello.bas" >/dev/null 2>&1
c1541 -format "hello disk,hd" d64 "$G/Disks/Hello Disk.d64" -write "$W/hello.prg" "hello" >/dev/null 2>&1

# Games and Saves: NOTE CATCHER, and its save disk (the game and its best score, HISCORE)
acme -f cbm -o "$G/Games/Note Catcher.prg" "$HERE/game/notecatcher.asm"
printf '\x0c' > "$W/hiscore"
c1541 -format "note catcher,nc" d64 "$G/Saves/Note Catcher Save Disk.d64" -write "$G/Games/Note Catcher.prg" "note catcher" -write "$W/hiscore" "hiscore,s" >/dev/null 2>&1
c1541 -format "blank disk,bd" d64 "$G/Saves/Blank Disk.d64" >/dev/null 2>&1

# Pictures
(cd "$HERE/picture" && acme -f cbm -o "$G/Pictures/Sunset.prg" viewer.asm)

# Music and SIDs: SIDWeaver tunes in a player (a raw .sid is not one of the browser's file types)
mkplayer() {   # out init play fx tune lines...
    local out=$1 init=$2 play=$3 fx=$4 tune=$5; shift 5
    python3 -I - "$@" > "$W/text.inc" <<'PY'
import sys
rows = [l.center(40)[:40] for l in sys.argv[1:]] + [' ' * 40] * 12
print('\n'.join('        !scr "%s"' % r.replace('"', "'") for r in rows[:12]))
PY
    sed "s/INIT/$init/; s/PLAY/$play/; s/FX\*3/$((fx * 3))/; s|TUNE|\"$HERE/music/$tune\"|; s|!source \"text.inc\"|!source \"$W/text.inc\"|" \
        "$HERE/music/player.asm" > "$W/player.asm"
    acme -f cbm -o "$out" "$W/player.asm"
}
mkplayer "$G/Music/Crystal Harbour.prg" '$1006' '$1003' 1 harbour.bin "crystal harbour" "" "a sidweaver tune" "octophonic 64 / mong00se" "" "" "octosid fx: chorus and echo" "spread over four sids, in stereo"
mkplayer "$G/SIDs/Neal Plays.prg" '$1000' '$1013' 0 nealplays.bin "neal plays" "" "by mong00se" "made with sidweaver, 2026" "" "" "one sid, as a stock c64 has it"

# My Chips: Mong00se's own measured SIDs
cp "$REPO"/chips/*.CHP "$G/My Chips/"

# Screenshots: the SHOT example, and a screenshot
acme -f cbm -o "$G/Screenshots/Take a Screenshot.prg" "$HERE/misc/shot.asm"
cp "$HERE/picture/sunset.png" "$G/Screenshots/Sunset.png"

echo "example set: $(find "$G" -type f | wc -l) files in $G"
