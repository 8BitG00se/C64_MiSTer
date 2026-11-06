#!/bin/bash
# OCTOPAINT - builds the package into OUT:
#   OCTOPAINT.PRG
#   OctoPaint Disk build N.d64      OCTOPAINT first (LOAD"*",8,1 and RUN), then the example pictures
#   OCTOPAINT build N.zip           the PRG, the d64 and "How to use.txt" (from docs/OCTOPAINT.md)
#   tools/octopaint/build.sh OUT
# Needs acme, c1541 (VICE's), zip, python3 with PIL. N is BUILD in octopaint.asm. Original work by Mong00se.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=${1:?OUT folder}
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/octopaint.asm" | head -1)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"

# the palette table must be the one mkpal.py makes
python3 "$HERE/mkpal.py" "$W/palette.inc"
cmp -s "$W/palette.inc" "$HERE/palette.inc" || { echo "palette.inc is out of date: run mkpal.py" >&2; exit 1; }
python3 "$HERE/mkoct.py" check

acme -I "$HERE" -f cbm -o "$OUT/OCTOPAINT.PRG" "$HERE/octopaint.asm"
python3 "$HERE/mkoct.py" examples "$W/ex"
c1541 -format "octopaint,op" d64 "$OUT/OctoPaint Disk build $N.d64" \
    -write "$OUT/OCTOPAINT.PRG" "octopaint" \
    -write "$W/ex/TESTCARD.OCT" "testcard.oct,s" \
    -write "$W/ex/PALETTE.OCT" "palette.oct,s" >/dev/null 2>&1
python3 "$HERE/md2txt.py" "$REPO/docs/OCTOPAINT.md" "$W/How to use.txt"
rm -f "$OUT/OCTOPAINT build $N.zip"
zip -q -j "$OUT/OCTOPAINT build $N.zip" "$OUT/OCTOPAINT.PRG" "$OUT/OctoPaint Disk build $N.d64" "$W/How to use.txt"
ls -l "$OUT"
