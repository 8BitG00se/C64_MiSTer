#!/bin/sh
# 033 - Octophonic64RGB, the companion core (Octo Remaster, Build 12; Fix 60, docs/RGB256.md): the recolour
# core for old 16-colour games, hidden in _Computer as .Octophonic64RGB_<date>.rbf (a dot name: the MiSTer
# menu never lists it). Octophonic Main starts it when a game is picked in F1 (making the game a pack first
# if it has none); WIN+F1 or SHIFT+F1 held goes back to the Octophonic core.
# Payload wanted: files/Octophonic64RGB_*.rbf (none: the step waits for an update that brings one).
# OCTO-RECHECK (a different companion core in the payload replaces the one on the card)
#
# ONE companion core only: any other .Octophonic64RGB_*.rbf, and the old .C64RGB256_*.rbf (build 1's name),
# move to _Octophonic/old cores (nothing is deleted), so Main's <rbf>_Computer/.Octophonic64RGB</rbf> can
# only ever find this one. Restarts nothing.
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
octo_say "Octophonic64RGB core: $NAME"
octo_say "md5:                  $(octo_md5 "$RBF")"
mkdir -p "$OCTO_ROOT/_Computer" "$OCTO_ROOT/_Octophonic/old cores" || exit 1
T="$OCTO_ROOT/_Computer/.$NAME"
for o in "$OCTO_ROOT"/_Computer/.Octophonic64RGB_*.rbf "$OCTO_ROOT"/_Computer/.C64RGB256_*.rbf; do
    [ -e "$o" ] || continue
    [ "$o" = "$T" ] && [ "$(octo_md5 "$o")" = "$(octo_md5 "$RBF")" ] && continue
    octo_backup "$o"
    mv -f "$o" "$OCTO_ROOT/_Octophonic/old cores/$(basename "$o")" || exit 1
    octo_say "moved to _Octophonic/old cores: $(basename "$o")"
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
[ "$(octo_md5 "$T")" = "$(octo_md5 "$RBF")" ] || { echo "the Octophonic64RGB core in _Computer is not this one"; exit 1; }
octo_mark_done "Octophonic64RGB core $NAME"
