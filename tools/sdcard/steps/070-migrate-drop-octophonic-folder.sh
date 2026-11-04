#!/bin/sh
# 070 - migration: drop games/C64/Octophonic and games/C64/Octophonic/Stock64.
#
# WHY: those two came from an earlier idea of the library layout and were created on Neal's
# card on 4 Nov 2026. The tree is now games/C64/{Demos,Games,SIDs,My Chips,Disks} (step 010 and
# docs/SDCARD.md), with no Octophonic folder, and os.ini's start= is games/C64 itself.
#
# ONLY EMPTY FOLDERS ARE REMOVED. rmdir is used on purpose: it refuses to touch a folder with
# anything in it, so "only if empty" is enforced by the tool and not by a test that could be
# wrong. A folder that is NOT empty is backed up and LEFT WHERE IT IS, and this step says so -
# it will not quietly move someone's demos.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

LEFT=0

# deepest first, so Stock64 goes before its parent
for p in "games/C64/Octophonic/Stock64" "games/C64/Octophonic"; do
    T="$OCTO_ROOT/$p"
    if [ ! -e "$T" ]; then
        octo_say "not there (nothing to do): $p"
        continue
    fi
    if [ ! -d "$T" ]; then
        octo_say "NOT A FOLDER, left alone: $p"
        LEFT=$((LEFT+1))
        continue
    fi
    N=$(ls -A "$T" 2>/dev/null | wc -l)
    if [ "$N" -eq 0 ]; then
        if rmdir "$T" 2>/dev/null; then
            octo_say "removed (it was empty): $p"
        else
            octo_say "could not remove $p - left alone"
            LEFT=$((LEFT+1))
        fi
    else
        octo_say "NOT EMPTY ($N item(s)) - backing it up and LEAVING IT: $p"
        B="$OCTO_BACKUPS/$OCTO_RUNSTAMP/$(printf '%s' "$p" | tr '/' '~')"
        mkdir -p "$B" 2>/dev/null
        if cp -a "$T/." "$B/" 2>/dev/null; then
            octo_say "  copied to octophonic/backups/$OCTO_RUNSTAMP/$(printf '%s' "$p" | tr '/' '~')/"
        else
            octo_say "  COULD NOT BACK IT UP - nothing was removed"
        fi
        octo_say "  move what is in it where you want it, then run this step again"
        LEFT=$((LEFT+1))
    fi
done
sync

octo_say "games/C64 now holds:"
ls -A "$OCTO_ROOT/games/C64" 2>/dev/null | sed 's/^/        /' || octo_say "        (no games/C64)"

if [ "$LEFT" -gt 0 ]; then
    octo_say "$LEFT folder(s) still there because they were not empty - not marking this done,"
    octo_say "so it runs again once they have been dealt with."
    exit 0
fi
octo_mark_done "old Octophonic library folders gone"
