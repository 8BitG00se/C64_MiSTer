#!/bin/sh
# 042 - Octophonic Main with the front screen (Fix 27 / Fix 20): a program's own .oled animation on the tty2oled
# screen while it runs, the Octophonic logo the rest of the time (tools/octoos/main/octophonic-oled.patch).
# The same job as 040 (040 is done on a card that already has an Octophonic Main, so a newer Main comes as a new
# step): the stock MiSTer program is kept as MiSTer.orig the first time only, the Main it replaces is backed up.
# The new Main runs from the next time Main starts - WILL RESTART MISTER MAIN: the installer restarts the MiSTer
# afterwards (and logs it), or it happens at the next power-on.
# Payload wanted: files/MiSTer (built by .github/workflows/octoos-main.yml)
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

NEW=$(octo_payload MiSTer) || { echo "no MiSTer in $OCTO_PAYLOAD"; exit 1; }
CUR="$OCTO_ROOT/MiSTer"
octo_say "new Main md5: $(octo_md5 "$NEW")"

if [ -e "$CUR" ] && [ "$(octo_md5 "$CUR")" = "$(octo_md5 "$NEW")" ]; then
    octo_say "this exact Main is already in place - nothing changed"
    octo_mark_done "Main already $(octo_md5 "$NEW")"
    exit 0
fi

if [ -e "$CUR" ]; then
    octo_say "Main in place md5: $(octo_md5 "$CUR")"
    if grep -q 'Octophonic OS' "$CUR" 2>/dev/null; then
        octo_say "the Main in place is already an Octophonic one - MiSTer.orig left alone"
    elif [ -e "$OCTO_ROOT/MiSTer.orig" ]; then
        octo_say "MiSTer.orig already exists - left alone"
    else
        cp -p "$CUR" "$OCTO_ROOT/MiSTer.orig" || exit 1
        octo_say "your stock MiSTer program kept as MiSTer.orig"
    fi
    octo_backup "$CUR"
fi

cp -f "$NEW" "$CUR.octo-new" || exit 1
chmod +x "$CUR.octo-new" || exit 1
mv -f "$CUR.octo-new" "$CUR" || exit 1
sync

[ "$(octo_md5 "$CUR")" = "$(octo_md5 "$NEW")" ] || { echo "the copy does not match"; exit 1; }
octo_say "in place: $(octo_md5 "$CUR")"
octo_say "Octophonic markers in it: $(grep -c 'Octophonic OS' "$CUR" 2>/dev/null)"
octo_mark_done "Main $(octo_md5 "$CUR")"
