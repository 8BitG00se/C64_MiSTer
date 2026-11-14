#!/bin/sh
# 059 - OctoPlay, the PSID player with the OctoScope: games/C64/Tools/OCTOPLAY.PRG,
#       games/C64/Disks/Octo Tunes.d64 (the player, its source and the tunes, so OctoPlay can
#       read them from drive 8), and the tunes on their own in games/C64/SIDs.
# Payload wanted: files/OCTOPLAY.PRG, files/Octo Tunes.d64 (optional), files/tunes/*.sid
#       (the image build makes them from tools/octoplay).
# OCTO-RECHECK (newer files in the payload replace the ones on the card)
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_skip_if_current "$OCTO_PAYLOAD/OCTOPLAY.PRG|$OCTO_ROOT/games/C64/Tools/OCTOPLAY.PRG" \
                     "$OCTO_PAYLOAD/Octo Tunes.d64|$OCTO_ROOT/games/C64/Disks/Octo Tunes.d64"

S=$(octo_payload OCTOPLAY.PRG) || { echo "no OCTOPLAY.PRG in $OCTO_PAYLOAD"; exit 1; }
mkdir -p "$OCTO_ROOT/games/C64/Tools" "$OCTO_ROOT/games/C64/Disks" "$OCTO_ROOT/games/C64/SIDs" || exit 1

octo_put() {   # SRC DST-under-the-card
    _s=$1; _d="$OCTO_ROOT/$2"
    if [ -e "$_d" ] && [ "$(octo_md5 "$_d")" = "$(octo_md5 "$_s")" ]; then
        octo_say "$2 already this one - nothing changed"
    else
        [ -e "$_d" ] && octo_backup "$_d"
        cp -f "$_s" "$_d" || return 1
        octo_say "$2: $(octo_md5 "$_d")  ($(wc -c < "$_d") bytes)"
    fi
}

octo_put "$S" "games/C64/Tools/OCTOPLAY.PRG" || exit 1

D="$OCTO_PAYLOAD/Octo Tunes.d64"
if [ -f "$D" ]; then
    octo_put "$D" "games/C64/Disks/Octo Tunes.d64" || exit 1
else
    octo_say "no Octo Tunes.d64 in the payload - the disk was not installed"
fi

n=0
if [ -d "$OCTO_PAYLOAD/tunes" ]; then
    for t in "$OCTO_PAYLOAD"/tunes/*.sid; do
        [ -f "$t" ] || continue
        octo_put "$t" "games/C64/SIDs/$(basename "$t")" || exit 1
        n=$((n + 1))
    done
fi
octo_say "$n tune(s) in games/C64/SIDs"

sync
octo_mark_done "OCTOPLAY $(octo_md5 "$OCTO_ROOT/games/C64/Tools/OCTOPLAY.PRG"), $n tunes"
