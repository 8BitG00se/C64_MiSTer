#!/bin/sh
# 055 - the coding tools: octophonic/acme (the assembler Main runs for OCTOCODE's F2 COMPILE) and
# games/C64/Apps/OCTOCODE.PRG (the editor: F3 load, edit, F2 compile and run, F5 save to the disk).
# Payload wanted: files/acme (ARM, static - built with Main on octoos-main-build), files/OCTOCODE.PRG
# Nothing else goes in Apps or the other games/C64 folders: they are filled by the user.
# OCTO-RECHECK (a newer acme / OCTOCODE.PRG in the payload replaces the one on the card)
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_skip_if_current "$OCTO_PAYLOAD/acme|$OCTO_ROOT/octophonic/acme" "$OCTO_PAYLOAD/OCTOCODE.PRG|$OCTO_ROOT/games/C64/Apps/OCTOCODE.PRG"

A=$(octo_payload acme) || { echo "no acme in $OCTO_PAYLOAD"; exit 1; }
O=$(octo_payload OCTOCODE.PRG) || { echo "no OCTOCODE.PRG in $OCTO_PAYLOAD"; exit 1; }
mkdir -p "$OCTO_ROOT/octophonic" "$OCTO_ROOT/games/C64/Apps" || exit 1
for pair in "$A:octophonic/acme" "$O:games/C64/Apps/OCTOCODE.PRG"; do
    SRC=${pair%%:*}; DST="$OCTO_ROOT/${pair#*:}"
    if [ -e "$DST" ] && [ "$(octo_md5 "$DST")" = "$(octo_md5 "$SRC")" ]; then
        octo_say "${pair#*:} already this one - nothing changed"
        continue
    fi
    [ -e "$DST" ] && octo_backup "$DST"
    cp -f "$SRC" "$DST" || exit 1
    octo_say "${pair#*:}: $(octo_md5 "$DST")  ($(wc -c < "$DST") bytes)"
done
chmod 755 "$OCTO_ROOT/octophonic/acme" 2>/dev/null || :
sync
octo_mark_done "acme $(octo_md5 "$OCTO_ROOT/octophonic/acme"), OCTOCODE $(octo_md5 "$OCTO_ROOT/games/C64/Apps/OCTOCODE.PRG")"
