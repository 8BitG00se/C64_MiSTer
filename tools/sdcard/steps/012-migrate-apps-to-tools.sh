#!/bin/sh
# 012 - migration (Fix 45): games/C64/Apps is now games/C64/Tools - the home of OCTOCODE and, later,
# the disassembler, the cruncher, the cheats/trainer program, OctoPaint, OctoWeaver Lite and the like.
#
# On a card that has Apps: all of Apps is backed up first, then everything in it is moved into Tools.
# NOTHING IS OVERWRITTEN: if Tools already has something with the same name, the one from Apps is kept
# beside it as "<name> (Apps)" (a file with exactly the same bytes is not kept twice - it is in the
# backup). Then Apps, empty, is removed (rmdir: it refuses a folder with anything left in it).
# A fresh card has no Apps: nothing to do. Running it twice is harmless.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

A="$OCTO_ROOT/games/C64/Apps"
T="$OCTO_ROOT/games/C64/Tools"
mkdir -p "$T" || exit 1

if [ ! -e "$A" ]; then
    octo_say "no games/C64/Apps (nothing to move)"
    octo_mark_done "no Apps folder - Tools is the folder"
    exit 0
fi
[ -d "$A" ] || { octo_say "games/C64/Apps is not a folder - left alone"; exit 1; }

B="$OCTO_BACKUPS/$OCTO_RUNSTAMP/games~C64~Apps"
mkdir -p "$B" && cp -a "$A/." "$B/" || { octo_say "COULD NOT BACK UP Apps - nothing moved"; exit 1; }
octo_say "backed up: games/C64/Apps  ->  octophonic/backups/$OCTO_RUNSTAMP/games~C64~Apps/"

LEFT=0
for src in "$A"/* "$A"/.[!.]*; do
    [ -e "$src" ] || continue
    n=$(basename "$src")
    dst="$T/$n"
    if [ ! -e "$dst" ]; then
        mv "$src" "$dst" && octo_say "moved: Apps/$n -> Tools/$n" || { octo_say "could not move Apps/$n"; LEFT=$((LEFT+1)); }
    elif [ -f "$src" ] && [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        rm -f "$src" && octo_say "Tools/$n is already the same file - the Apps copy is only in the backup"
    else
        case "$n" in
            *.*) alt="${n%.*} (Apps).${n##*.}" ;;
            *)   alt="$n (Apps)" ;;
        esac
        i=2
        while [ -e "$T/$alt" ]; do
            case "$n" in *.*) alt="${n%.*} (Apps $i).${n##*.}" ;; *) alt="$n (Apps $i)" ;; esac
            i=$((i+1))
        done
        mv "$src" "$T/$alt" && octo_say "name clash: Apps/$n kept as Tools/$alt (Tools/$n untouched)" || { octo_say "could not move Apps/$n"; LEFT=$((LEFT+1)); }
    fi
done
sync
if [ "$LEFT" -gt 0 ] || ! rmdir "$A" 2>/dev/null; then
    octo_say "games/C64/Apps still has something in it - not marking this done, so it runs again"
    exit 0
fi
octo_say "games/C64/Apps removed (empty); games/C64/Tools now holds:"
ls -A "$T" | sed 's/^/        /'
octo_mark_done "Apps moved into Tools"
