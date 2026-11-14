#!/bin/sh
# OCTOPLAY - build the payload pieces for the card.                        (c) 2026 Mong00se
#   tools/octoplay/build.sh OUTDIR
# Writes into OUTDIR:
#   OCTOPLAY.PRG      the player (games/C64/Tools)
#   Octo Tunes.d64    a disk OctoPlay can read: the player, its source for OCTOCODE, and the tunes
#   tunes/*.sid       the tunes on their own (games/C64/SIDs)
# The .prg and the tunes are kept beside this script as finished files; the disk is made here so
# the card always carries one that matches them. Needs c1541 (VICE) only for the disk: without it
# the step still gets the .prg and the tunes, and says the disk was skipped.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build.sh OUTDIR}
mkdir -p "$OUT/tunes" || exit 1

cp -f "$HERE/OCTOPLAY.PRG" "$OUT/OCTOPLAY.PRG" || exit 1
for t in "$HERE"/tunes/*.sid; do cp -f "$t" "$OUT/tunes/" || exit 1; done

C1541=${C1541:-$(command -v c1541 || true)}
D="$OUT/Octo Tunes.d64"
if [ -z "$C1541" ]; then
    echo "octoplay: no c1541 - the tunes disk was skipped (the .prg and the .sid files are in the payload)"
    rm -f "$D"
    exit 0
fi
rm -f "$D"
set -- -format "octo tunes,01" d64 "$D" \
       -write "$HERE/OCTOPLAY.PRG" "octoplay,p" \
       -write "$HERE/octoplay.asm.seq" "octoplay.asm,s"
for t in "$HERE"/tunes/*.sid; do
    n=$(basename "$t" .sid | tr 'a-z' 'A-Z')
    set -- "$@" -write "$t" "$n,p"
done
"$C1541" "$@" >/dev/null 2>&1 || { echo "octoplay: c1541 could not make the disk"; exit 1; }
echo "octoplay: $(basename "$D") $(wc -c < "$D") bytes, $(ls "$HERE"/tunes/*.sid | wc -l) tunes"
