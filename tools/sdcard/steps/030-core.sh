#!/bin/sh
# 030 - the Octophonic core, hidden in _Computer as .C64_Octophonic_<date>_<tag>.rbf,
# plus the Octophonic 64.mgl launcher and the chip-preset launchers.
#
# Uses the documented tools/install/install_core.sh, so: the core that was there moves to
# _Octophonic/old cores (nothing is deleted), _Octophonic/core.txt records what is in place,
# and a NEWER core is never replaced by an older one without force.
# Payload wanted: files/C64_Octophonic_*.rbf, files/core-number.txt, files/install_core.sh,
#                 files/_Computer/*.mgl
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

RBF=$(ls "$OCTO_PAYLOAD"/C64_Octophonic_*.rbf 2>/dev/null | head -1)
[ -n "$RBF" ] && [ -s "$RBF" ] || { echo "no C64_Octophonic_*.rbf in $OCTO_PAYLOAD"; exit 1; }
NAME=$(basename "$RBF")
INST=$(octo_payload install_core.sh) || { echo "no install_core.sh in $OCTO_PAYLOAD"; exit 1; }
NUMF=$(octo_payload core-number.txt) || { echo "no core-number.txt in $OCTO_PAYLOAD"; exit 1; }
ORDER=$(tr -dc '0-9' < "$NUMF")
[ -n "$ORDER" ] || { echo "core-number.txt has no number in it"; exit 1; }
octo_say "core:        $NAME"
octo_say "core number: $ORDER"
octo_say "md5:         $(octo_md5 "$RBF")"

# already in place, same bytes? then there is nothing to do.
CUR="$OCTO_ROOT/_Computer/.$NAME"
if [ -e "$CUR" ] && [ "$(octo_md5 "$CUR")" = "$(octo_md5 "$RBF")" ]; then
    octo_say "this exact core is already in place - nothing changed"
else
    mkdir -p "$OCTO_ROOT/_Computer" "$OCTO_ROOT/_Octophonic/old cores" || exit 1
    cp -f "$RBF" "/tmp/$NAME" || exit 1
    cp -f "$INST" /tmp/octo_install_core.sh || exit 1
    set +e
    OCTO_ROOT="$OCTO_ROOT" sh /tmp/octo_install_core.sh "$NAME" "$ORDER"
    RC=$?
    set -e
    rm -f /tmp/octo_install_core.sh "/tmp/$NAME"
    if [ "$RC" = 3 ]; then
        echo "a NEWER core is already on this card - it was NOT replaced."
        echo "that is deliberate. Re-run this step with OCTO_FORCE=1 only if you mean it."
        exit 3
    fi
    [ "$RC" = 0 ] || { echo "install_core.sh failed ($RC)"; exit "$RC"; }
fi

# the launchers. The <setname> line is what makes the tty2oled front screen show the
# Octophonic logo instead of the C64 one, so every launcher must carry it.
if [ -d "$OCTO_PAYLOAD/_Computer" ]; then
    for m in "$OCTO_PAYLOAD/_Computer"/*.mgl; do
        [ -e "$m" ] || continue
        T="$OCTO_ROOT/_Computer/$(basename "$m")"
        if [ -e "$T" ] && cmp -s "$m" "$T"; then
            octo_say "launcher already identical: $(basename "$m")"
        else
            [ -e "$T" ] && octo_backup "$T"
            cp -f "$m" "$T" || exit 1
            octo_say "launcher in place: $(basename "$m")"
        fi
        grep -q 'setname' "$T" || octo_say "WARNING: $(basename "$m") has no <setname> line - the OLED will show the C64 picture"
    done
fi
sync

octo_say "core.txt: $(cat "$OCTO_ROOT/_Octophonic/core.txt" 2>/dev/null | tr '\n' ' ')"
octo_say "old cores kept: $(ls -A "$OCTO_ROOT/_Octophonic/old cores" 2>/dev/null | wc -l)"
octo_mark_done "core $NAME (number $ORDER)"
