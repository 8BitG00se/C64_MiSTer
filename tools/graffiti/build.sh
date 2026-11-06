#!/bin/bash
# GRAFFITI WALL - builds the package into OUT: "Graffiti Wall.prg", "Graffiti Wall.reu", About.txt, "Graffiti Wall build N.zip"
#   tools/graffiti/build.sh OUT PHOTO [N]       (PHOTO: the brick wall photo, a jpg)
# Needs acme, zip, python3 with numpy, PIL, opencv (cv2) and scipy. N is BUILD in graffiti.asm.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?OUT folder}; PHOTO=${2:?the wall photo}
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/graffiti.asm" | head -1)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
python3 "$HERE/gen.py" "$W" "$PHOTO" ${CHECK:+--check "$CHECK"}
acme -I "$W" -f cbm -o "$OUT/Graffiti Wall.prg" -l "$W/graffiti.lbl" "$HERE/graffiti.asm"
cp "$W/Graffiti Wall.reu" "$OUT/Graffiti Wall.reu"
cp "$HERE/about.txt" "$OUT/About.txt"
rm -f "$OUT/Graffiti Wall build $N.zip"
(cd "$OUT" && zip -q "Graffiti Wall build $N.zip" "Graffiti Wall.prg" "Graffiti Wall.reu" About.txt)
cp "$W/graffiti.lbl" "$OUT/graffiti.lbl" 2>/dev/null || true
ls -l "$OUT"
