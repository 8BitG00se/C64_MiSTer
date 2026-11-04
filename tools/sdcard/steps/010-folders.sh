#!/bin/sh
# 010 - the folder tree from docs/SDCARD.md.
# Creates only what is missing. Deletes nothing. Safe to run any number of times.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

MADE=0
for p in \
    "_Computer" \
    "_Octophonic" \
    "_Octophonic/old cores" \
    "octophonic" \
    "games/C64" \
    "games/C64/Octophonic" \
    "games/C64/Octophonic/Stock64" \
    "games/C64/My Chips" \
    "screenshots/Octophonic" \
    "Scripts"
do
    if [ -d "$OCTO_ROOT/$p" ]; then
        octo_say "already there: $p"
    else
        mkdir -p "$OCTO_ROOT/$p" || { echo "could not create $p"; exit 1; }
        octo_say "created:       $p"
        MADE=$((MADE+1))
    fi
done
sync
octo_say "$MADE folder(s) created"
octo_mark_done "folders ok ($MADE created)"
