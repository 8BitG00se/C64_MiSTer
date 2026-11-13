#!/bin/sh
# 057 - games/C64/Tools/TESTCARD.PRG: the monitor test card (crosshatch, circles) for setting up a screen.
# Payload wanted: files/TESTCARD.PRG (the image build makes it from tools/testcard).
# OCTO-RECHECK (a newer TESTCARD.PRG in the payload replaces the one on the card)
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_skip_if_current "$OCTO_PAYLOAD/TESTCARD.PRG|$OCTO_ROOT/games/C64/Tools/TESTCARD.PRG"

S=$(octo_payload TESTCARD.PRG) || { echo "no TESTCARD.PRG in $OCTO_PAYLOAD"; exit 1; }
D="$OCTO_ROOT/games/C64/Tools/TESTCARD.PRG"
mkdir -p "$OCTO_ROOT/games/C64/Tools" || exit 1
if [ -e "$D" ] && [ "$(octo_md5 "$D")" = "$(octo_md5 "$S")" ]; then
    octo_say "Tools/TESTCARD.PRG already this one - nothing changed"
else
    [ -e "$D" ] && octo_backup "$D"
    cp -f "$S" "$D" || exit 1
    octo_say "Tools/TESTCARD.PRG: $(octo_md5 "$D")  ($(wc -c < "$D") bytes)"
fi
sync
octo_mark_done "TESTCARD $(octo_md5 "$D")"
