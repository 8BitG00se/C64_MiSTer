#!/bin/bash
# MONA LISA - builds the package into OUT:  Mona Lisa.prg + Mona Lisa.reu, About.txt, Install to MiSTer.bat, Mona Lisa build N.zip
#   tools/monalisa/build.sh PAINTING.jpg OUT
#     PAINTING.jpg: the photograph of the painting (Wikimedia Commons, "Mona Lisa, by Leonardo da Vinci, from C2RMF retouched";
#     kept out of git). Needs acme, zip, python3 with numpy, PIL, scipy, scikit-learn. N is BUILD in mona.asm.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${1:?the photograph of the painting (jpg)}
OUT=${2:?OUT folder}
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/mona.asm" | head -1)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
python3 "$HERE/gen.py" "$SRC" "$W"
NM=$(python3 "$HERE/music.py" "$W/music.bin")
grep -q "^NMUS    = $NM\$" "$HERE/mona.asm" || { echo "the music is $NM frames: set NMUS in mona.asm (and the camera path) to match"; exit 1; }
python3 - "$W" <<'PY'
import sys
w = sys.argv[1]; reu = open(w + '/Mona Lisa.reu', 'rb').read(); mus = open(w + '/music.bin', 'rb').read()
r = (len(reu) + 0xFFFF) & ~0xFFFF
open(w + '/Mona Lisa.reu', 'wb').write(reu + bytes(r - len(reu)) + mus)
open(w + '/data.inc', 'a').write('R_MUS = $%06x\n' % r)
print('music at REU $%06x, %d bytes; the .reu is now %d bytes' % (r, len(mus), r + len(mus)))
PY
acme -I "$W" -f cbm -o "$OUT/Mona Lisa.prg" -l "$W/mona.lbl" "$HERE/mona.asm"
cp "$W/Mona Lisa.reu" "$OUT/Mona Lisa.reu"
cp "$HERE/about.txt" "$OUT/About.txt"
printf '@echo off\r\nrem Copies Mona Lisa into the MiSTer share, so the MiSTer can load it over the network.\r\nset "DST=C:\\MiSTerBridge\\Games\\C64\\Octophonic\\Mona Lisa build %s"\r\nif not exist "%%DST%%" mkdir "%%DST%%"\r\ncopy /Y "%%~dp0Mona Lisa.prg" "%%DST%%\\" >nul\r\ncopy /Y "%%~dp0Mona Lisa.reu" "%%DST%%\\" >nul\r\necho Mona Lisa build %s is in %%DST%%\r\npause\r\n' "$N" "$N" > "$OUT/Install to MiSTer.bat"
rm -f "$OUT/Mona Lisa build $N.zip"
(cd "$OUT" && zip -q "Mona Lisa build $N.zip" "Mona Lisa.prg" "Mona Lisa.reu" About.txt "Install to MiSTer.bat")
ls -l "$OUT"
