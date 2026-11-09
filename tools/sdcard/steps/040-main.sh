#!/bin/sh
# 040 - Octophonic Main (the MiSTer program).
# The stock MiSTer program is kept as MiSTer.orig the FIRST time only, so it is never
# overwritten with an Octophonic one. Same test Neal's own installer uses.
# Payload wanted: files/MiSTer
# OCTO-RECHECK (a newer Main in the payload replaces the one on the card, even when this step is done)
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
CUR="$OCTO_ROOT/MiSTer"
octo_skip_if_current "$OCTO_PAYLOAD/MiSTer|$CUR"
NEW=$(octo_payload MiSTer) || { echo "no MiSTer in $OCTO_PAYLOAD"; exit 1; }
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
