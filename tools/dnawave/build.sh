#!/bin/bash
# DNA WAVE - builds DNA Wave.prg + .reu, About.txt, Install to MiSTer.bat and "DNA Wave build N.zip" into OUT
#   tools/pendulumwave/build.sh OUT        (needs acme, zip, python3 with numpy and PIL; N is BUILD in dna.asm)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); OUT=${1:?OUT folder}
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/dna.asm" | head -1)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; mkdir -p "$OUT"
python3 "$HERE/gen.py" "$W"
acme -I "$W" -f cbm -o "$OUT/DNA Wave.prg" "$HERE/dna.asm"
cp "$W/DNA Wave.reu" "$OUT/"; cp "$HERE/about.txt" "$OUT/About.txt"
printf '@echo off\r\nrem Copies DNA Wave into the MiSTer share, so the MiSTer can load it over the network.\r\nset "DST=C:\\MiSTerBridge\\Games\\C64\\Octophonic\\DNA Wave build %s"\r\nif not exist "%%DST%%" mkdir "%%DST%%"\r\ncopy /Y "%%~dp0DNA Wave.prg" "%%DST%%\\" >nul\r\ncopy /Y "%%~dp0DNA Wave.reu" "%%DST%%\\" >nul\r\necho DNA Wave build %s is in %%DST%%\r\npause\r\n' "$N" "$N" > "$OUT/Install to MiSTer.bat"
rm -f "$OUT/DNA Wave build $N.zip"
(cd "$OUT" && zip -q "DNA Wave build $N.zip" "DNA Wave.prg" "DNA Wave.reu" About.txt "Install to MiSTer.bat")
ls -l "$OUT"
