#!/bin/bash
# GREAT WAVE - builds the package into OUT:
#   Great Wave.prg  +  Great Wave.reu           (the same base name: the Octophonic browser loads the .reu first)
#   OctoPaint Pictures build 2.d64              "starry night.oct" and "great wave.oct" for OctoPaint (320 x 200, letterbox bars of colour 1)
#   About.txt, Great Wave build N.zip
#   tools/greatwave/build.sh WAVE.jpg OUT [STARRY]
#     WAVE.jpg: the scan of the print, 1920 x 1315 (kept out of git); STARRY: the Starry Night scan (jpg, 1920 x 1520) or a
#     finished "Starry Night.oct" (default: the scan next to WAVE.jpg called starry-night-source.jpg, else the env STARRY)
# Needs acme, c1541 (VICE's), zip, python3 with numpy, PIL, scipy, scikit-learn, opencv. N is BUILD in wave.asm.
# Optional: DITHER=0.5 for gentle error diffusion (the default, none, was picked by looking: see README.md).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${1:?the scan of the print (jpg)}
OUT=${2:?OUT folder}
STARRY=${3:-${STARRY:-$(dirname "$SRC")/starry-night-source.jpg}}
PICS=2                                  # the OctoPaint Pictures disk: build 1 had the Starry Night only
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/wave.asm" | head -1)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"

python3 "$HERE/../octopaint/mkoct.py" check
python3 "$HERE/gen.py" "$SRC" "$W" ${DITHER:+--dither "$DITHER"}
acme -I "$W" -f cbm -o "$OUT/Great Wave.prg" -l "$W/wave.lbl" "$HERE/wave.asm"
cp "$W/Great Wave.reu" "$OUT/Great Wave.reu"

# the Starry Night picture: from its finished .oct, or made from the scan with tools/starrynight/gen.py (into the temp folder only)
case "$STARRY" in
  *.oct) cp "$STARRY" "$W/starry night.oct" ;;
  *) mkdir -p "$W/sn"; python3 "$HERE/../starrynight/gen.py" "$STARRY" "$W/sn" >/dev/null; cp "$W/sn/Starry Night.oct" "$W/starry night.oct" ;;
esac

# the pictures for OctoPaint: read back with mkoct.py (they must decode, and the checksum is the one OctoPaint's debug overlay shows)
for f in "starry night" "great wave"; do
  python3 "$HERE/../octopaint/mkoct.py" to-png "$W/$f.oct" "$W/check_$f.png"
  python3 "$HERE/../octopaint/mkoct.py" csum "$W/$f.oct"
done
rm -f "$OUT/OctoPaint Pictures build $PICS.d64"
c1541 -format "octopaint pics,sn" d64 "$OUT/OctoPaint Pictures build $PICS.d64" \
  -write "$W/starry night.oct" "starry night.oct,s" -write "$W/great wave.oct" "great wave.oct,s" >/dev/null 2>&1
c1541 "$OUT/OctoPaint Pictures build $PICS.d64" -list | head -6

cp "$HERE/about.txt" "$OUT/About.txt"
rm -f "$OUT/Great Wave build $N.zip"
(cd "$OUT" && zip -q "Great Wave build $N.zip" "Great Wave.prg" "Great Wave.reu" "OctoPaint Pictures build $PICS.d64" About.txt)
ls -l "$OUT"
