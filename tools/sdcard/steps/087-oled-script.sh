#!/bin/sh
# 087 - the front screen's helper for Octophonic Main: octophonic/oled.sh (tools/oled/oled.sh).
# Main starts it to show a program's own animation (NAME.oled beside the program) and to bring the Octophonic logo
# back. It finds the screen itself and does nothing when there is none, so it is safe on any card.
# Payload wanted: files/oled.sh
# OCTO-RECHECK (a newer oled.sh in the payload replaces the one on the card)
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_skip_if_current "$OCTO_PAYLOAD/oled.sh|$OCTO_STATE/oled.sh"

NEW=$(octo_payload oled.sh) || { echo "no oled.sh in $OCTO_PAYLOAD"; exit 1; }
sh -n "$NEW" || { echo "oled.sh has a syntax error"; exit 1; }
CUR="$OCTO_STATE/oled.sh"
mkdir -p "$OCTO_STATE" || exit 1
if [ -e "$CUR" ] && [ "$(octo_md5 "$CUR")" = "$(octo_md5 "$NEW")" ]; then
    octo_say "this oled.sh is in place already"
else
    octo_backup "$CUR" || exit 1
    cp -f "$NEW" "$CUR" || exit 1
    chmod +x "$CUR"
    sync
    [ "$(octo_md5 "$CUR")" = "$(octo_md5 "$NEW")" ] || { echo "the copy does not match"; exit 1; }
    octo_say "in place: octophonic/oled.sh"
fi
octo_mark_done "oled.sh $(octo_md5 "$CUR")"
