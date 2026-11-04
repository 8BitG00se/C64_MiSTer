#!/bin/sh
# 080 - MiSTer.ini: power-on goes straight into Octophonic 64, with no MiSTer menu, even when the
# MiSTer program in place is a stock one (a MiSTer update replaces Octophonic Main with stock Main,
# and then os.ini does nothing - this keeps "straight to Octophonic" true anyway).
#
# WHAT THE MAIN_MISTER SOURCE SAYS (at tools/octoos/main/UPSTREAM; cfg.cpp, bootcore.cpp, user_io.cpp):
#   - bootcore=<exact file name> loads that file the first time Main starts with the menu core and
#     no core asked for. "Octophonic 64.mgl" is an exact name (it ends .mgl), and findCore() looks
#     for it in every _ folder, so it finds _Computer/Octophonic 64.mgl and xml_load()s it.
#   - bootcore_timeout is read with a MINIMUM OF 2 (cfg.cpp: BOOTCORE_TIMEOUT, INT16, 2, 30):
#     bootcore_timeout=0 is NOT "no wait" - it is clamped to 2 seconds, and those 2 seconds are the
#     MiSTer menu on screen with a "Bootcore -> ..." countdown (menu.cpp). Only with NO
#     bootcore_timeout line at all is the timeout 0, and then the core is loaded at once, inside
#     user_io_init(), before video_init() - so the menu never draws a thing.
#   - MiSTer_example.ini (which step 060 starts a MiSTer.ini from) has bootcore_timeout=10 ACTIVE.
#     So this step comments every active bootcore_timeout line out.
#   - C=+F1 (the MiSTer menu) still works: Main loads menu.rbf with the path "menu.rbf", and
#     bootcore only fires when the path is empty (a real power-on).
#   - With Octophonic Main and os.ini, Main's own octo_os_boot() runs first (right after
#     cfg_parse(), before bootcore_init()) and does the same thing, so this line is the fallback.
#
# To start in the MiSTer menu as normal again: delete octophonic/os.ini AND put a ; in front of the
# bootcore= line this step wrote.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

INI="$OCTO_ROOT/MiSTer.ini"
WANT='Octophonic 64.mgl'
[ -e "$INI" ] || { echo "no MiSTer.ini - run step 060 first"; exit 1; }
[ -e "$OCTO_ROOT/_Computer/$WANT" ] || { echo "no _Computer/$WANT - run step 030 first (the launchers)"; exit 1; }

ACTIVE_TO=$(grep -cE '^[[:space:]]*bootcore_timeout[[:space:]]*=' "$INI")
OURS=$(grep -cxE "bootcore=$WANT[[:space:]]*(;.*)?" "$INI")
OTHER=$(grep -E '^[[:space:]]*bootcore[[:space:]]*=' "$INI" | grep -cvxE "bootcore=$WANT[[:space:]]*(;.*)?")

if [ "$ACTIVE_TO" = 0 ] && [ "$OURS" = 1 ] && [ "$OTHER" = 0 ]; then
    octo_say "MiSTer.ini already boots straight into $WANT - nothing changed"
    octo_mark_done "bootcore already $WANT, no timeout"
    exit 0
fi

octo_backup "$INI" || exit 1
TMP="$INI.octo-new"
# 1) every active bootcore_timeout and every other active bootcore line gets a ; (kept, readable)
# 2) our bootcore line goes right under [MiSTer] (or at the top, if there is no [MiSTer] line)
awk -v want="$WANT" '
    BEGIN { placed = 0 }
    /^[ \t]*bootcore_timeout[ \t]*=/ {
        print ";" $0 "   ; (Octophonic: off - any timeout, even 0, shows the MiSTer menu first)"; next }
    /^[ \t]*bootcore[ \t]*=/ {
        if ($0 ~ ("^bootcore=" want "[ \t]*(;.*)?$") && !placed) { print; placed = 1; next }
        print ";" $0 "   ; (Octophonic: replaced by bootcore=" want ")"; next }
    { print }
' "$INI" > "$TMP" || exit 1
if ! grep -qxE "bootcore=$WANT[[:space:]]*(;.*)?" "$TMP"; then
    LINE="bootcore=$WANT       ; OCTOPHONIC: power-on goes straight into Octophonic 64 (no bootcore_timeout line: no menu at all)"
    if grep -q '^\[MiSTer\]' "$TMP"; then
        awk -v l="$LINE" '{ print } !d && /^\[MiSTer\]/ { print l; d = 1 }' "$TMP" > "$TMP.2" && mv -f "$TMP.2" "$TMP" || exit 1
    else
        { printf '[MiSTer]\n%s\n' "$LINE"; cat "$TMP"; } > "$TMP.2" && mv -f "$TMP.2" "$TMP" || exit 1
    fi
fi
mv -f "$TMP" "$INI" || exit 1
sync

octo_say "MiSTer.ini now:"
grep -nE '^[[:space:]]*;?[[:space:]]*bootcore' "$INI" | sed 's/^/        /'
[ "$(grep -cE '^[[:space:]]*bootcore_timeout[[:space:]]*=' "$INI")" = 0 ] || { echo "a bootcore_timeout line is still active"; exit 1; }
[ "$(grep -cE '^[[:space:]]*bootcore[[:space:]]*=' "$INI")" = 1 ] || { echo "not exactly one active bootcore line"; exit 1; }
octo_mark_done "bootcore=$WANT, no bootcore_timeout"
