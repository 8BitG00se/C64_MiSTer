#!/bin/sh
# 050 - octophonic/SHELL.PRG: the F1 browser and the start jingle.
#
# IT MUST MATCH THE CORE'S KERNAL. SHELL.PRG is built from the same commit as the core's ROM
# (tools/octoos/kernal/shell.asm -> acme -f cbm), and it calls into the ROM at fixed addresses.
# An old SHELL.PRG with a new core is the classic way to get a browser that misbehaves.
# Payload wanted: files/SHELL.PRG
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

NEW=$(octo_payload SHELL.PRG) || { echo "no SHELL.PRG in $OCTO_PAYLOAD"; exit 1; }
CUR="$OCTO_ROOT/octophonic/SHELL.PRG"
mkdir -p "$OCTO_ROOT/octophonic" || exit 1
octo_say "new SHELL.PRG: $(octo_md5 "$NEW")  ($(wc -c < "$NEW") bytes)"

if [ -e "$CUR" ] && [ "$(octo_md5 "$CUR")" = "$(octo_md5 "$NEW")" ]; then
    octo_say "this exact SHELL.PRG is already in place - nothing changed"
    octo_mark_done "SHELL.PRG already $(octo_md5 "$NEW")"
    exit 0
fi

[ -e "$CUR" ] && { octo_say "the one in place: $(octo_md5 "$CUR")  ($(wc -c < "$CUR") bytes)"; octo_backup "$CUR"; }
cp -f "$NEW" "$CUR" || exit 1
sync
[ "$(octo_md5 "$CUR")" = "$(octo_md5 "$NEW")" ] || { echo "the copy does not match"; exit 1; }

# a .prg must start with its load address. SHELL.PRG loads at $C000, so 00 C0.
LOAD=$(od -A n -t x1 -N 2 "$CUR" | tr -d ' \n')
octo_say "load address bytes: $LOAD  (00c0 = \$C000, which is right)"
[ "$LOAD" = "00c0" ] || octo_say "WARNING: that is not \$C000 - is this really SHELL.PRG?"
octo_mark_done "SHELL.PRG $(octo_md5 "$CUR")"
