#!/bin/sh
# 056 - games/C64/Tools/SPEC.PRG: the spec page (Fix 59) - core, OctoVIC, SIDs, SDRAM size, REU, PAL/NTSC.
# Payload wanted: files/SPEC.PRG (the image build makes it from tools/spec).
# OCTO-RECHECK (a newer SPEC.PRG in the payload replaces the one on the card)
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_skip_if_current "$OCTO_PAYLOAD/SPEC.PRG|$OCTO_ROOT/games/C64/Tools/SPEC.PRG"

S=$(octo_payload SPEC.PRG) || { echo "no SPEC.PRG in $OCTO_PAYLOAD"; exit 1; }
D="$OCTO_ROOT/games/C64/Tools/SPEC.PRG"
mkdir -p "$OCTO_ROOT/games/C64/Tools" || exit 1
if [ -e "$D" ] && [ "$(octo_md5 "$D")" = "$(octo_md5 "$S")" ]; then
    octo_say "Tools/SPEC.PRG already this one - nothing changed"
else
    [ -e "$D" ] && octo_backup "$D"
    cp -f "$S" "$D" || exit 1
    octo_say "Tools/SPEC.PRG: $(octo_md5 "$D")  ($(wc -c < "$D") bytes)"
fi
sync
octo_mark_done "SPEC $(octo_md5 "$D")"
