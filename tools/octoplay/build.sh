#!/bin/sh
# OCTOPLAY - build the payload pieces for the card.                        (c) 2026 Mong00se
#   tools/octoplay/build.sh OUTDIR
# Writes into OUTDIR:
#   OCTOPLAY.PRG      the player (games/C64/Tools)
#   Octo Tunes.d64    a disk of tunes only, so OctoPlay's PICK A TUNE list is all tunes
#   tunes/*.sid       the tunes on their own (games/C64/SIDs)
# The player itself is NOT on the disk: OctoPlay lists every file on the mounted disk and says
# NOT A PSID FILE for anything else, so a .prg or a source .seq would sit in the tune list.
# The .prg and the tunes are kept beside this script as finished files; the disk is made here so
# the card always carries one that matches them. Needs c1541 (VICE) only for the disk: without it
# the step still gets the .prg and the tunes, and says the disk was skipped.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build.sh OUTDIR}
mkdir -p "$OUT/tunes" || exit 1

cp -f "$HERE/OCTOPLAY.PRG" "$OUT/OCTOPLAY.PRG" || exit 1
for t in "$HERE"/tunes/*.sid; do cp -f "$t" "$OUT/tunes/" || exit 1; done

# The disk is kept beside this script as a finished file, so a machine with no VICE (the GitHub
# builder, and this container) still puts it on the card. With c1541 here it is made again from
# the tunes, so the two can never drift apart.
C1541=${C1541:-$(command -v c1541 || true)}
D="$OUT/Octo Tunes.d64"
if [ -z "$C1541" ]; then
    if [ -s "$HERE/Octo Tunes.d64" ]; then
        cp -f "$HERE/Octo Tunes.d64" "$D" || exit 1
        echo "octoplay: no c1541 - the kept Octo Tunes.d64 ($(wc -c < "$D") bytes) goes on as it is"
        exit 0
    fi
    echo "octoplay: no c1541 and no kept disk - the tunes disk was skipped"
    rm -f "$D"
    exit 0
fi
rm -f "$D"
set -- -format "octo tunes,01" d64 "$D"
for t in "$HERE"/tunes/*.sid; do
    n=$(basename "$t" .sid | tr 'a-z' 'A-Z')
    set -- "$@" -write "$t" "$n,p"
done
"$C1541" "$@" >/dev/null 2>&1 || { echo "octoplay: c1541 could not make the disk"; exit 1; }
echo "octoplay: $(basename "$D") $(wc -c < "$D") bytes, $(ls "$HERE"/tunes/*.sid | wc -l) tunes"
# keep the copy beside this script in step, so a builder without VICE ships the same disk
cmp -s "$D" "$HERE/Octo Tunes.d64" || { cp -f "$D" "$HERE/Octo Tunes.d64"; echo "octoplay: the kept Octo Tunes.d64 was updated - commit it"; }
