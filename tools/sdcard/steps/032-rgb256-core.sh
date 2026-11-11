#!/bin/sh
# 032 - the C64RGB 256 core (Fix 60, docs/RGB256.md): the recolour core for old 16-colour games, hidden
# in _Computer as .C64RGB256_<date>.rbf (a dot name: the MiSTer menu never lists it). Octophonic Main
# starts it when a game with a <game>.rgb recolour pack beside it is picked; SHIFT+F1 held goes back.
# Payload wanted: files/C64RGB256_*.rbf (none: the step waits for an update that brings one).
# OCTO-RECHECK (a different C64RGB 256 core in the payload replaces the one on the card - not when the
# update is OLDER than the card: its core number decides, as for the Octophonic core)
#
# ONE C64RGB 256 core only: any other .C64RGB256_*.rbf in _Computer moves to _Octophonic/old cores
# (nothing is deleted), so Main's <rbf>_Computer/.C64RGB256</rbf> can only ever find this one.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
RBF=$(ls "$OCTO_PAYLOAD"/C64RGB256_*.rbf 2>/dev/null | head -1)
INCARD=$(ls "$OCTO_ROOT"/_Computer/.C64RGB256_*.rbf 2>/dev/null | head -1)
if [ -z "$RBF" ] && ! octo_is_done; then
    octo_say "this update has no C64RGB 256 core - nothing to do yet (the step runs again with the next update)"
    exit 0
fi
octo_skip_if_current "${RBF:-}|${INCARD:-$OCTO_ROOT/_Computer/.none}"
[ -n "$RBF" ] && [ -s "$RBF" ] || { echo "no C64RGB256_*.rbf in $OCTO_PAYLOAD"; exit 1; }
NAME=$(basename "$RBF")
octo_say "C64RGB 256 core: $NAME"
octo_say "md5:              $(octo_md5 "$RBF")"
mkdir -p "$OCTO_ROOT/_Computer" "$OCTO_ROOT/_Octophonic/old cores" || exit 1
T="$OCTO_ROOT/_Computer/.$NAME"
for o in "$OCTO_ROOT"/_Computer/.C64RGB256_*.rbf; do
    [ -e "$o" ] || continue
    [ "$o" = "$T" ] && [ "$(octo_md5 "$o")" = "$(octo_md5 "$RBF")" ] && continue
    octo_backup "$o"
    mv -f "$o" "$OCTO_ROOT/_Octophonic/old cores/$(basename "$o")" || exit 1
    octo_say "moved to _Octophonic/old cores: $(basename "$o")"
done
if [ -e "$T" ]; then
    octo_say "this exact C64RGB 256 core is already in place - nothing changed"
else
    cp -f "$RBF" "$T.tmp" && mv -f "$T.tmp" "$T" || exit 1
    octo_say "in place: _Computer/.$NAME"
fi
sync
NC=$(ls -A "$OCTO_ROOT/_Computer" | grep -c '^\.C64RGB256_.*\.rbf$')
[ "$NC" = 1 ] || { echo "there are $NC C64RGB 256 cores in _Computer - there must be exactly one"; exit 1; }
[ "$(octo_md5 "$T")" = "$(octo_md5 "$RBF")" ] || { echo "the C64RGB 256 core in _Computer is not this one"; exit 1; }
octo_mark_done "C64RGB 256 core $NAME"
