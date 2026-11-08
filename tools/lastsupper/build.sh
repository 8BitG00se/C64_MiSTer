#!/bin/bash
# THE LAST SUPPER - builds the package into OUT:  The Last Supper.prg + The Last Supper.reu, About.txt, Install to MiSTer.bat, The Last Supper build N.zip
#   tools/monalisa/build.sh PAINTING.jpg OUT
#     PAINTING.jpg: the photograph of the painting (Wikimedia Commons, "The Last Supper - Leonardo Da Vinci - High Resolution 32x16";
#     kept out of git). Needs acme, zip, python3 with numpy, PIL, scipy, scikit-learn. N is BUILD in supper.asm.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${1:?the photograph of the painting (jpg)}
OUT=${2:?OUT folder}
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/supper.asm" | head -1)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
python3 "$HERE/gen.py" "$SRC" "$W"
NM=$(python3 "$HERE/music.py" "$W/music.bin")
grep -q "^NMUS    = $NM\$" "$HERE/supper.asm" || { echo "the music is $NM frames: set NMUS in supper.asm (and the camera path) to match"; exit 1; }
python3 - "$W" <<'PY'
import sys
w = sys.argv[1]; reu = open(w + '/The Last Supper.reu', 'rb').read(); mus = open(w + '/music.bin', 'rb').read()
r = (len(reu) + 0xFFFF) & ~0xFFFF
open(w + '/The Last Supper.reu', 'wb').write(reu + bytes(r - len(reu)) + mus)
open(w + '/data.inc', 'a').write('R_MUS = $%06x\n' % r)
print('music at REU $%06x, %d bytes; the .reu is now %d bytes' % (r, len(mus), r + len(mus)))
PY
acme -I "$W" -f cbm -o "$OUT/The Last Supper.prg" -l "$W/supper.lbl" "$HERE/supper.asm"
cp "$W/The Last Supper.reu" "$OUT/The Last Supper.reu"
cp "$HERE/about.txt" "$OUT/About.txt"
printf '@echo off\r\nrem Copies The Last Supper into the MiSTer share, so the MiSTer can load it over the network.\r\nset "DST=C:\\MiSTerBridge\\Games\\C64\\Octophonic\\The Last Supper build %s"\r\nif not exist "%%DST%%" mkdir "%%DST%%"\r\ncopy /Y "%%~dp0The Last Supper.prg" "%%DST%%\\" >nul\r\ncopy /Y "%%~dp0The Last Supper.reu" "%%DST%%\\" >nul\r\necho The Last Supper build %s is in %%DST%%\r\npause\r\n' "$N" "$N" > "$OUT/Install to MiSTer.bat"
rm -f "$OUT/The Last Supper build $N.zip"
(cd "$OUT" && zip -q "The Last Supper build $N.zip" "The Last Supper.prg" "The Last Supper.reu" About.txt "Install to MiSTer.bat")
ls -l "$OUT"
