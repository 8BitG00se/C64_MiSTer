#!/bin/sh
# 065 - MiSTer.ini: vsync_adjust=2 (Fix 43). The HDMI output follows the core's own rate - PAL 50 Hz
# (about 50.12) - instead of MiSTer's fixed 60 Hz, which shows every 5th frame twice (judder). Smooth
# scrolling and a capture card recording every frame exactly once need this. A release step (not DEV):
# it suits every HDMI user of a 50 Hz machine; a TV that won't take 50 Hz can set vsync_adjust=0 again.
#   - only the vsync_adjust lines change: every active one (any section, so no core section overrides
#     it), or one is added under [MiSTer]; everything else in the file stays as it is
#   - MiSTer.ini is backed up first; already 2 everywhere = nothing touched
# Takes effect when the MiSTer next starts (the runner's restart, or the next power-on).
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

INI="$OCTO_ROOT/MiSTer.ini"
[ -e "$INI" ] || { echo "no MiSTer.ini - run step 060 first"; exit 1; }

ACTIVE=$(grep -E '^[[:space:]]*vsync_adjust[[:space:]]*=' "$INI" | sed 's/;.*//' | tr -d ' \t\r' | sort -u)
if [ "$ACTIVE" = "vsync_adjust=2" ]; then
    octo_say "vsync_adjust=2 already set"
else
    octo_backup "$INI" || exit 1
    if [ -n "$ACTIVE" ]; then
        sed -i -E 's/^[[:space:]]*vsync_adjust[[:space:]]*=[^;\r]*/vsync_adjust=2 /' "$INI" || exit 1
        octo_say "vsync_adjust set to 2 (was: $(echo $ACTIVE))"
    elif grep -q '^\[MiSTer\]' "$INI"; then
        sed -i '0,/^\[MiSTer\]/s/^\[MiSTer\].*/&\nvsync_adjust=2/' "$INI" || exit 1
        octo_say "vsync_adjust=2 added under [MiSTer]"
    else
        { printf '[MiSTer]\nvsync_adjust=2\n'; cat "$INI"; } > "$INI.new" && mv -f "$INI.new" "$INI" || exit 1
        octo_say "no [MiSTer] section - added one with vsync_adjust=2"
    fi
    sync
fi
octo_say "now:"
grep -n 'vsync_adjust' "$INI" | sed 's/^/        /'
octo_mark_done "vsync_adjust=2 (HDMI follows the core's 50 Hz)"
