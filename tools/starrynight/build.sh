#!/bin/bash
# STARRY NIGHT - builds the package into OUT:
#   Starry Night.prg  +  Starry Night.reu       (the same base name: the Octophonic browser loads the .reu first)
#   OctoPaint Pictures build N.d64              "starry night.oct" for OctoPaint (320 x 200, letterbox bars of colour 1)
#   About.txt, Starry Night build N.zip
#   tools/starrynight/build.sh SOURCE.jpg OUT   (SOURCE.jpg: the scan, 1920 x 1520; kept out of git)
# Needs acme, c1541 (VICE's), zip, python3 with numpy, PIL, scipy, scikit-learn, opencv. N is BUILD in starry.asm.
# Optional: DITHER=0.5 for gentle error diffusion (the default, none, was picked by looking: see README.md).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${1:?the scan (jpg)}
OUT=${2:?OUT folder}
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/starry.asm" | head -1)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"

python3 "$HERE/../octopaint/mkoct.py" check
python3 "$HERE/gen.py" "$SRC" "$W" ${DITHER:+--dither "$DITHER"}
acme -I "$W" -f cbm -o "$OUT/Starry Night.prg" -l "$W/starry.lbl" "$HERE/starry.asm"
cp "$W/Starry Night.reu" "$OUT/Starry Night.reu"

# the picture for OctoPaint: read back with mkoct.py (it must decode, and the checksum is the one OctoPaint's debug overlay shows)
python3 "$HERE/../octopaint/mkoct.py" to-png "$W/Starry Night.oct" "$W/check.png"
python3 "$HERE/../octopaint/mkoct.py" csum "$W/Starry Night.oct"
rm -f "$OUT/OctoPaint Pictures build $N.d64"
c1541 -format "octopaint pics,sn" d64 "$OUT/OctoPaint Pictures build $N.d64" -write "$W/Starry Night.oct" "starry night.oct,s" >/dev/null 2>&1
c1541 "$OUT/OctoPaint Pictures build $N.d64" -list | head -5

cp "$HERE/about.txt" "$OUT/About.txt"
rm -f "$OUT/Starry Night build $N.zip"
(cd "$OUT" && zip -q "Starry Night build $N.zip" "Starry Night.prg" "Starry Night.reu" "OctoPaint Pictures build $N.d64" About.txt)
ls -l "$OUT"
