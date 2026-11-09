#!/bin/bash
# (C) 2026 Mong00se
# 2026: AN OCTOPHONIC ODYSSEY - builds the package into OUT:
#   Octophonic Odyssey.d64  ODYSSEY (the program, first: LOAD"*",8,1 and RUN), GALAXY (the stock show's galaxy),
#                           and the source as SEQ files for OCTOCODE (ODYSSEY.ASM and its 8 parts)
#   Octophonic Odyssey.prg  the same program (the Octophonic browser loads it with the .reu beside it, at once)
#   Octophonic Odyssey.reu  the Octophonic picture, camera path, sprites and the music for SIDs 3-8
#   odyssey.asm and the parts  the source as plain text beside the disk: where OCTOCODE's compile (ACME on the MiSTer)
#                           finds the parts
#   About.txt, Install to MiSTer.bat, Octophonic Odyssey build N.zip (N is BUILD in odyssey.asm)
#
#   tools/odyssey/build.sh PICTURE.jpg OUT
#     PICTURE.jpg: the Webb "Cosmic Cliffs" (NASA, ESA, CSA, STScI) - the full-size original if you have it, any size
#     works; kept out of git. Needs acme, c1541 (VICE), zip, python3 with numpy, PIL, scipy, scikit-learn.
#     song.py rewrites song.asm here (the notes are made from song.py).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${1:?the picture (jpg)}
OUT=${2:?OUT folder}
C1541=${C1541:-$(command -v c1541 || echo /home/claude/emu/build/src/c1541)}
N=$(sed -n 's/^BUILD *= *\([0-9][0-9]*\).*/\1/p' "$HERE/odyssey.asm" | head -1)
NAME="Octophonic Odyssey"
PARTS="odyssey player show fx iris galaxy octo octofx camera song"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
python3 "$HERE/song.py" "$W" > "$W/songlen.txt"
cp "$W/song.asm" "$HERE/song.asm"
SONGLEN=$(cat "$W/songlen.txt")
python3 "$HERE/galaxy.py" "$W" > /dev/null
python3 "$HERE/octopic.py" "$SRC" "$W/music8.bin" "$SONGLEN" "$W/$NAME.reu"
(cd "$HERE" && acme -v1 -f cbm -o "$W/odyssey.prg" -Wno-label-indent odyssey.asm) | grep -v '^Saving' || true
[ -f "$W/odyssey.prg" ]
# every part, compiled on its own as OCTOCODE would (its F2), must give the same program
for p in $PARTS; do
  (cd "$HERE" && acme -f cbm -o "$W/$p.prg" -Wno-label-indent $p.asm)
  cmp -s "$W/odyssey.prg" "$W/$p.prg" || { echo "F2 on $p.asm does not build the same program"; exit 1; }
done
D="$OUT/$NAME.d64"
rm -f "$D"
args=(-format "odyssey 2026,mg" d64 "$D" -write "$W/odyssey.prg" odyssey)
args+=(-write "$W/galaxy.bin" galaxy)
for p in $PARTS; do
  python3 "$HERE/petscii.py" "$HERE/$p.asm" "$W/$p.seq"
  args+=(-write "$W/$p.seq" "$p.asm,s")
done
"$C1541" "${args[@]}" > /dev/null
"$C1541" -attach "$D" -dir | grep -v "^Unit\|^D64" > "$W/dir.txt"
cp "$W/odyssey.prg" "$OUT/$NAME.prg"
cp "$W/$NAME.reu" "$OUT/$NAME.reu"
for p in $PARTS; do cp "$HERE/$p.asm" "$OUT/$p.asm"; done
sed "s/@N@/$N/g" "$HERE/about.txt" | sed 's/$/\r/' > "$OUT/About.txt"
printf '@echo off\r\nrem Copies 2026: An Octophonic Odyssey into the MiSTer share, so the MiSTer can load it over the network.\r\nset "DST=C:\\MiSTerBridge\\Games\\C64\\Octophonic\\%s build %s"\r\nif not exist "%%DST%%" mkdir "%%DST%%"\r\ncopy /Y "%%~dp0%s.prg" "%%DST%%\\" >nul\r\ncopy /Y "%%~dp0%s.reu" "%%DST%%\\" >nul\r\ncopy /Y "%%~dp0%s.d64" "%%DST%%\\" >nul\r\ncopy /Y "%%~dp0*.asm" "%%DST%%\\" >nul\r\ncopy /Y "%%~dp0About.txt" "%%DST%%\\" >nul\r\necho %s build %s is in %%DST%%\r\npause\r\n' \
  "$NAME" "$N" "$NAME" "$NAME" "$NAME" "$NAME" "$N" > "$OUT/Install to MiSTer.bat"
Z="$NAME build $N.zip"
rm -f "$OUT/$Z"
(cd "$OUT" && zip -q "$Z" "$NAME.d64" "$NAME.prg" "$NAME.reu" *.asm About.txt "Install to MiSTer.bat")
cat "$W/dir.txt"
ls -l "$OUT"
