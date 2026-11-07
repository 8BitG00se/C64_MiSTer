#!/bin/bash
# OCTO KARATE - builds the package into OUT:
#   Octo Karate.prg  +  Octo Karate.reu         (the same base name: the Octophonic browser loads the .reu first)
#   Octo Karate build N.d64                     the program, its source (PETSCII text, for the OCTOCODE editor) and two OctoPaint fighter sheets (the source takes most of the disk); the zip also has the fighter data files (fighters/*.okf)
#   About.txt, Octo Karate build N.zip          (with "Install to MiSTer.bat")
#   tools/octokarate/build.sh OUT
# Needs acme, c1541 (VICE's), zip, python3 with numpy and PIL. N is BUILD in octokarate.asm.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?OUT folder}
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/octokarate.asm" | head -1)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
python3 "$HERE/../octopaint/mkoct.py" check
python3 "$HERE/export.py" "$W"
# Neal's shouts (mkshouts.py), appended to the .reu on a 64 KB boundary: R_SHOUT and their lengths into data.inc
(cd "$HERE" && python3 mkshouts.py "$W") >> "$W/data.inc"
python3 - "$W" <<'PY'
import sys
w = sys.argv[1]; reu = open(w + '/Octo Karate.reu', 'rb').read(); sh = open(w + '/shouts.bin', 'rb').read()
r = (len(reu) + 0xFFFF) & ~0xFFFF
open(w + '/Octo Karate.reu', 'wb').write(reu + bytes(r - len(reu)) + sh)
open(w + '/data.inc', 'a').write('R_SHOUT = $%06x\n' % r)
print('shouts at REU $%06x' % r)
PY
acme -I "$W" -f cbm -o "$OUT/Octo Karate.prg" -l "$W/octokarate.lbl" "$HERE/octokarate.asm"
cp "$W/Octo Karate.reu" "$OUT/Octo Karate.reu"
for f in "$W"/sheets/*.oct; do python3 "$HERE/../octopaint/mkoct.py" csum "$f"; done
python3 "$HERE/../octoos/octocode/a2p.py" "$HERE/octokarate.asm" "$W/octokarate.seq"
D="$OUT/Octo Karate build $N.d64"
rm -f "$D"
c1541 -format "octo karate,ok" d64 "$D" -write "$OUT/Octo Karate.prg" "octo karate" -write "$W/octokarate.seq" "octokarate.asm,s" \
  -write "$W/sheets/vic 1.oct" "vic 1.oct,s" -write "$W/sheets/sid 1.oct" "sid 1.oct,s" >/dev/null 2>&1
c1541 "$D" -list 2>/dev/null | sed -n 1,12p || true
cp "$HERE/about.txt" "$OUT/About.txt"
printf '@echo off\r\nrem Copies this folder to the Octophonic games folder on the PC (copies only, deletes nothing).\r\nset "DEST=C:\\MiSTerBridge\\Games\\C64\\Octophonic\\Octo Karate"\r\nif not exist "%%DEST%%" mkdir "%%DEST%%"\r\nxcopy "%%~dp0*" "%%DEST%%\\" /E /I /Y /Q\r\necho Copied to %%DEST%%\r\npause\r\n' > "$OUT/Install to MiSTer.bat"
rm -rf "$OUT/sheets" "$OUT/fighters"; mkdir -p "$OUT/sheets" "$OUT/fighters"; cp "$W"/sheets/*.oct "$OUT/sheets/"; cp "$W"/fighters/*.okf "$OUT/fighters/"
rm -f "$OUT/Octo Karate build $N.zip"
(cd "$OUT" && zip -q -r "Octo Karate build $N.zip" "Octo Karate.prg" "Octo Karate.reu" "Octo Karate build $N.d64" About.txt "Install to MiSTer.bat" sheets fighters)
ls -l "$OUT"
