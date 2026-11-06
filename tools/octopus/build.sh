#!/bin/bash
# OCTOPUS - builds the package into OUT: Octopus.prg, Octopus.reu, About.txt, "Octopus build N.zip"
#   tools/octopus/build.sh OUT
# Needs acme, zip, python3 with numpy and PIL. N is BUILD in octopus.asm.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?OUT folder}
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/octopus.asm" | head -1)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
python3 "$HERE/gen.py" "$W"
acme -I "$W" -f cbm -o "$OUT/Octopus.prg" -l "$W/octopus.lbl" "$HERE/octopus.asm"
cp "$W/Octopus.reu" "$OUT/Octopus.reu"
cp "$HERE/about.txt" "$OUT/About.txt"
rm -f "$OUT/Octopus build $N.zip"
(cd "$OUT" && zip -q "Octopus build $N.zip" Octopus.prg Octopus.reu About.txt)
ls -l "$OUT"
