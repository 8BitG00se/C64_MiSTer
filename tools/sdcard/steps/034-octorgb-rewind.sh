#!/bin/sh
# 034 - REWIND (Fix 61, Build 13): the companion core Octophonic64RGB with the rewind unit (rtl/rewind.sv) -
# hold WIN+F2 (or the pad button set as Rewind) in a game and it runs backwards, up to about 30 seconds.
# This companion has no OctoVIC and SIDs 1 and 2 only (their room went to the rewind); Octophonic programs
# run in the main core as before. It takes the place of the companion core on the card (step 033's), in
# _Computer as .Octophonic64RGB_<date>.rbf.                                        (c) 2026 Mong00se
# Payload wanted: files/Octophonic64RGB_*.rbf (none: the step waits for an update that brings one).
# OCTO-RECHECK (a different companion core in the payload replaces the one on the card)
#
# The core it replaces is kept once in octophonic/backups/before-build13/ (for "Undo Build 13") and moved to
# _Octophonic/old cores - nothing is deleted. ONE companion core only stays in _Computer. Restarts nothing.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
RBF=$(ls "$OCTO_PAYLOAD"/Octophonic64RGB_*.rbf 2>/dev/null | head -1)
INCARD=$(ls "$OCTO_ROOT"/_Computer/.Octophonic64RGB_*.rbf 2>/dev/null | head -1)
if [ -z "$RBF" ] && ! octo_is_done; then
    octo_say "this update has no Octophonic64RGB core - nothing to do yet (the step runs again with the next update)"
    exit 0
fi
octo_skip_if_current "${RBF:-}|${INCARD:-$OCTO_ROOT/_Computer/.none}"
[ -n "$RBF" ] && [ -s "$RBF" ] || { echo "no Octophonic64RGB_*.rbf in $OCTO_PAYLOAD"; exit 1; }
NAME=$(basename "$RBF")
NEW=$(octo_md5 "$RBF")
octo_say "Octophonic64RGB core with REWIND: $NAME"
octo_say "md5:                              $NEW"
OLD="$OCTO_ROOT/_Octophonic/old cores"
KEEP="$OCTO_BACKUPS/before-build13"
mkdir -p "$OCTO_ROOT/_Computer" "$OLD" || exit 1
T="$OCTO_ROOT/_Computer/.$NAME"
for o in "$OCTO_ROOT"/_Computer/.Octophonic64RGB_*.rbf "$OCTO_ROOT"/_Computer/.C64RGB256_*.rbf; do
    [ -e "$o" ] || continue
    [ "$o" = "$T" ] && [ "$(octo_md5 "$o")" = "$NEW" ] && continue
    if ! ls "$KEEP"/.Octophonic64RGB_*.rbf >/dev/null 2>&1; then      # the first core replaced: Undo's
        mkdir -p "$KEEP" && cp -p "$o" "$KEEP/" || exit 1
        octo_say "kept for Undo: octophonic/backups/before-build13/$(basename "$o")"
    fi
    octo_backup "$o"
    D="$OLD/$(basename "$o")"
    [ -e "$D" ] && [ "$(octo_md5 "$D")" != "$(octo_md5 "$o")" ] && D="$D.$(octo_md5 "$o" | cut -c1-8)"
    mv -f "$o" "$D" || exit 1
    octo_say "moved to _Octophonic/old cores: $(basename "$D")"
done
if [ -e "$T" ]; then
    octo_say "this exact Octophonic64RGB core is already in place - nothing changed"
else
    cp -f "$RBF" "$T.tmp" && mv -f "$T.tmp" "$T" || exit 1
    octo_say "in place: _Computer/.$NAME"
fi
sync
NC=$(ls -A "$OCTO_ROOT/_Computer" | grep -c '^\.Octophonic64RGB_.*\.rbf$')
[ "$NC" = 1 ] || { echo "there are $NC Octophonic64RGB cores in _Computer - there must be exactly one"; exit 1; }
[ "$(octo_md5 "$T")" = "$NEW" ] || { echo "the Octophonic64RGB core in _Computer is not this one"; exit 1; }
octo_mark_done "Octophonic64RGB core with REWIND $NAME md5 $NEW"
