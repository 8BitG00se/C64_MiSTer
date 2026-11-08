#!/bin/bash
# SIGNAL TEST - builds Signal Test.prg + .reu, About.txt, Install to MiSTer.bat and "Signal Test build N.zip" into OUT
#   tools/signaltest/build.sh OUT        (needs acme, zip, python3 with numpy and PIL; N is BUILD in signal.asm)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); OUT=${1:?OUT folder}
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/signal.asm" | head -1)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; mkdir -p "$OUT"
python3 "$HERE/gen.py" "$W"
acme -I "$W" -f cbm -o "$OUT/Signal Test.prg" "$HERE/signal.asm"
cp "$W/Signal Test.reu" "$OUT/"; [ -f "$HERE/about.txt" ] && cp "$HERE/about.txt" "$OUT/About.txt"
printf '@echo off\r\nrem Copies Signal Test into the MiSTer share, so the MiSTer can load it over the network.\r\nset "DST=C:\\MiSTerBridge\\Games\\C64\\Octophonic\\Signal Test build %s"\r\nif not exist "%%DST%%" mkdir "%%DST%%"\r\ncopy /Y "%%~dp0Signal Test.prg" "%%DST%%\\" >nul\r\ncopy /Y "%%~dp0Signal Test.reu" "%%DST%%\\" >nul\r\necho Signal Test build %s is in %%DST%%\r\npause\r\n' "$N" "$N" > "$OUT/Install to MiSTer.bat"
rm -f "$OUT/Signal Test build $N.zip"
(cd "$OUT" && zip -q "Signal Test build $N.zip" "Signal Test.prg" "Signal Test.reu" About.txt "Install to MiSTer.bat")
ls -l "$OUT"
