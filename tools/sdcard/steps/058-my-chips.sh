#!/bin/sh
# 058 - games/C64/Chips: Neal's own measured SID chips (.CHP) for the core menu's "Load My Chip" lines and
# OctoPlay's F3/F5 (MOS 6581 5084, MOS 6581 3184, CSG 8580R5 3591, MOS 8580R5 4687 - docs/CHIPS.md).
# Payload wanted: files/chips/*.CHP (the image build copies them from chips/).
# OCTO-RECHECK (a changed .CHP in the payload replaces the one on the card)
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
set --
for S in "$OCTO_PAYLOAD"/chips/*.CHP; do set -- "$@" "$S|$OCTO_ROOT/games/C64/Chips/$(basename "$S")"; done
octo_skip_if_current "$@"
D="$OCTO_ROOT/games/C64/Chips"
mkdir -p "$D" || exit 1
n=0
for S in "$OCTO_PAYLOAD"/chips/*.CHP; do
    [ -e "$S" ] || { echo "no chips/*.CHP in $OCTO_PAYLOAD"; exit 1; }
    T="$D/$(basename "$S")"
    if [ -e "$T" ] && [ "$(octo_md5 "$T")" = "$(octo_md5 "$S")" ]; then :; else
        [ -e "$T" ] && octo_backup "$T"
        cp -f "$S" "$T" || exit 1
        octo_say "Chips/$(basename "$S"): $(octo_md5 "$T")"
    fi
    n=$((n + 1))
done
sync
octo_mark_done "MYCHIPS $n"
