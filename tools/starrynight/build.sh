#!/bin/bash
# STARRY NIGHT - builds the package into OUT:
#   Starry Night.prg  +  Starry Night.reu       (the same base name: the Octophonic browser loads the .reu first)
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

python3 "$HERE/gen.py" "$SRC" "$W" ${DITHER:+--dither "$DITHER"}
# the music (music.py -> 2520 frames x 256 bytes), appended to the .reu on a 64 KB boundary: R_MUS
python3 "$HERE/music.py" "$W/music.bin"
python3 - "$W" <<'PY'
import sys
w = sys.argv[1]; reu = open(w + '/Starry Night.reu', 'rb').read(); mus = open(w + '/music.bin', 'rb').read()
r = (len(reu) + 0xFFFF) & ~0xFFFF       # 64 KB boundary; every frame (256 bytes, 4 DMAs of 64) lies inside one 512 KB window
open(w + '/Starry Night.reu', 'wb').write(reu + bytes(r - len(reu)) + mus)
open(w + '/data.inc', 'a').write('R_MUS = $%06x\n' % r)
print('music at REU $%06x, %d bytes; the .reu is now %d bytes' % (r, len(mus), r + len(mus)))
PY
acme -I "$W" -f cbm -o "$OUT/Starry Night.prg" -l "$W/starry.lbl" "$HERE/starry.asm"
cp "$W/Starry Night.reu" "$OUT/Starry Night.reu"

cp "$HERE/about.txt" "$OUT/About.txt"
rm -f "$OUT/Starry Night build $N.zip"
(cd "$OUT" && zip -q "Starry Night build $N.zip" "Starry Night.prg" "Starry Night.reu" About.txt)
ls -l "$OUT"
