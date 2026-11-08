#!/bin/sh
# 085 - the front screen's pictures: every demo's own title card for the tty2oled screen.
#
# tty2oled shows the picture named after the running core (/tmp/CORENAME) from tty2oled/pics_pri, as a
# 256 x 64 picture in 16 greys (a .gsc: 8192 bytes, two pixels a byte). The Octophonic launchers set the name with
# <setname>; the octopus animation itself lives in the screen's own firmware (8BitG00se/octophonic-tty2oled).
# This step puts each demo's card in pics_pri (GeometrySings.gsc, ...), backing up any it replaces.
# Once done the runner skips it, so a later batch of cards comes as a new step (086-oled-pics-2.sh, the same
# script) - or OCTO_ONLY=085 OCTO_FORCE=1 to lay this set down again.
# No tty2oled on the card: nothing to do (and not marked done, so it runs once tty2oled is put on).
# Payload wanted: files/tty2oled/pics_pri/*.gsc
set -u
. "$(dirname "$0")/../octo-step-lib.sh"

SRC="$OCTO_PAYLOAD/tty2oled/pics_pri"
DST="$OCTO_ROOT/tty2oled/pics_pri"
if [ ! -d "$OCTO_ROOT/tty2oled" ]; then
    octo_say "no tty2oled on this card - no front screen to give pictures to (skipped, not marked done)"
    exit 0
fi
ls "$SRC"/*.gsc >/dev/null 2>&1 || { echo "no .gsc cards in $SRC"; exit 1; }
mkdir -p "$DST" || exit 1
N=0; SAME=0
for NEW in "$SRC"/*.gsc; do
    F=$(basename "$NEW")
    [ "$(wc -c < "$NEW")" -eq 8192 ] || { echo "$F is not 8192 bytes - not a 256x64 16-grey card"; exit 1; }
    CUR="$DST/$F"
    if [ -e "$CUR" ] && [ "$(octo_md5 "$CUR")" = "$(octo_md5 "$NEW")" ]; then SAME=$((SAME + 1)); continue; fi
    octo_backup "$CUR" || exit 1
    cp -f "$NEW" "$CUR" || exit 1
    [ "$(octo_md5 "$CUR")" = "$(octo_md5 "$NEW")" ] || { echo "the copy of $F does not match"; exit 1; }
    octo_say "card in place: $F"
    N=$((N + 1))
done
sync
octo_say "$N new or changed, $SAME already in place"
octo_mark_done "cards: $(ls "$SRC"/*.gsc | wc -l)"
