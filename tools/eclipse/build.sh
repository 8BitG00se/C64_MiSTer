#!/bin/bash
# ECLIPSE BEACH - builds the package into OUT:
#   Eclipse Beach.prg  +  Eclipse Beach.reu     (the same base name: the Octophonic browser loads the .reu first)
#   Eclipse Beach build N.d64                   the program, its source (PETSCII text, for the OCTOCODE editor) and the OctoPaint pictures
#   About.txt, Eclipse Beach build N.zip        (with "Install to MiSTer.bat")
#   tools/eclipse/build.sh OUT
# Needs acme, c1541 (VICE's), zip, python3 with numpy and PIL. N is BUILD in eclipse.asm.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?OUT folder}
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/eclipse.asm" | head -1)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
python3 "$HERE/../octopaint/mkoct.py" check
python3 "$HERE/gen.py" "$W" ${PREVIEW:+--preview="$PREVIEW"}
acme -I "$W" -f cbm -o "$OUT/Eclipse Beach.prg" -l "$W/eclipse.lbl" "$HERE/eclipse.asm"
cp "$W/Eclipse Beach.reu" "$OUT/Eclipse Beach.reu"
[ -n "${PREVIEW:-}" ] && cp "$W"/preview_*.png "$OUT/" || true
for f in sky sea beach "sun frames" "corona frames"; do
  python3 "$HERE/../octopaint/mkoct.py" to-png "$W/$f.oct" "$W/check_$f.png"
  python3 "$HERE/../octopaint/mkoct.py" csum "$W/$f.oct"
done
python3 "$HERE/../octoos/octocode/a2p.py" "$HERE/eclipse.asm" "$W/eclipse.seq"
D="$OUT/Eclipse Beach build $N.d64"
rm -f "$D"
c1541 -format "eclipse beach,eb" d64 "$D" -write "$OUT/Eclipse Beach.prg" "eclipse beach" -write "$W/eclipse.seq" "eclipse.asm,s" \
  -write "$W/sky.oct" "sky.oct,s" -write "$W/sea.oct" "sea.oct,s" -write "$W/beach.oct" "beach.oct,s" \
  -write "$W/sun frames.oct" "sun frames.oct,s" -write "$W/corona frames.oct" "corona.oct,s" >/dev/null 2>&1
c1541 "$D" -list 2>/dev/null | sed -n 1,12p
cp "$HERE/about.txt" "$OUT/About.txt"
printf '@echo off\r\nrem Copies this folder to the Octophonic games folder on the PC (copies only, deletes nothing).\r\nset "DEST=C:\\MiSTerBridge\\Games\\C64\\Octophonic\\Eclipse Beach"\r\nif not exist "%%DEST%%" mkdir "%%DEST%%"\r\nxcopy "%%~dp0*" "%%DEST%%\\" /E /I /Y /Q\r\necho Copied to %%DEST%%\r\npause\r\n' > "$OUT/Install to MiSTer.bat"
rm -f "$OUT/Eclipse Beach build $N.zip"
(cd "$OUT" && zip -q "Eclipse Beach build $N.zip" "Eclipse Beach.prg" "Eclipse Beach.reu" "Eclipse Beach build $N.d64" About.txt "Install to MiSTer.bat")
ls -l "$OUT"
