#!/bin/sh
# 015 - the example set: something in every games/C64 folder, and the demos.
#
#   Demos/        every Octophonic demo build (a folder each: its .prg and the .reu it needs),
#                 Demos/Stock64/ the stock one-SID versions
#   Games/ Apps/ Code/ Music/ SIDs/ Pictures/ My Chips/ Disks/ Screenshots/ Saves/
#                 one or more examples each, all original 6502 work (no Commodore ROMs, no
#                 third-party games or tunes). Code/ has the OCTOCODE examples' .asm sources and
#                 their programs; Disks/ the same examples as .d64s (each runs from its disk).
#
# Payload wanted: files/examples/games/C64/... and files/examples/MANIFEST.txt
# (build-image.sh puts them there from the sdcard-examples branch, or OCTO_EXAMPLES=<dir>).
# MANIFEST.txt: one line a file, "<md5>  games/C64/<path>".
#
# Rules: copies only what is missing or different; a file it replaces is backed up first
# (octophonic/backups/<run>/); it deletes nothing, and nothing of the user's that isn't in the
# set is touched. Run twice: the second run finds every file already in place.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

EX="$OCTO_PAYLOAD/examples"
MAN="$EX/MANIFEST.txt"
if [ ! -s "$MAN" ]; then
    # a card with no example set (build-image.sh OCTO_EXAMPLES=none): the folders stay empty, to be
    # filled by the user (FileZilla, the updater)
    octo_say "no example set in this payload - the games/C64 folders stay empty"
    octo_mark_done "no example set (folders left empty)"
    exit 0
fi

NEW=0; SAME=0; REPL=0; BAD=0
# (read from a file, not a pipe, so the counters survive the loop; names have spaces)
while IFS= read -r line; do
    sum=${line%%  *}; rel=${line#*  }
    [ -n "$rel" ] && [ "$sum" != "$line" ] || continue
    src="$EX/$rel"; dst="$OCTO_ROOT/$rel"
    [ -f "$src" ] || { echo "the payload has no $rel"; exit 1; }
    if [ -f "$dst" ] && [ "$(octo_md5 "$dst")" = "$sum" ]; then SAME=$((SAME+1)); continue; fi
    mkdir -p "$(dirname "$dst")" || exit 1
    if [ -e "$dst" ]; then octo_backup "$dst" || exit 1; REPL=$((REPL+1)); else NEW=$((NEW+1)); fi
    cp -f "$src" "$dst.octonew" && mv -f "$dst.octonew" "$dst" || { echo "could not write $rel"; exit 1; }
    [ "$(octo_md5 "$dst")" = "$sum" ] || { echo "the copy of $rel does not match"; BAD=$((BAD+1)); }
done < "$MAN"
sync
[ "$BAD" = 0 ] || exit 1
octo_say "example set: $NEW new, $REPL replaced (backed up), $SAME already in place"
octo_mark_done "examples ok ($(wc -l < "$MAN") files: $NEW new, $REPL replaced, $SAME there)"
