#!/bin/sh
# 010 - the folder tree from docs/SDCARD.md.
# Creates only what is missing. Deletes nothing. Safe to run any number of times.
# The browser's SD CARD drive is games/C64: Demos, Games, Tools, Code, Music, SIDs, Pictures,
# My Chips, Disks, Screenshots, Saves, Textures (build 6's tree). os.ini's start= is /media/fat/games/C64
# (step 020). Step 015 fills them with the example set - this step only makes folders.
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
    "games/C64/Demos" \
    "games/C64/Games" \
    "games/C64/Tools" \
    "games/C64/Code" \
    "games/C64/Music" \
    "games/C64/SIDs" \
    "games/C64/Pictures" \
    "games/C64/My Chips" \
    "games/C64/Disks" \
    "games/C64/Screenshots" \
    "games/C64/Textures" \
    "games/C64/Saves" \
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
