#!/bin/sh
# 060 - MiSTer.ini: makes sure one EXISTS, and nothing more.
#
# DELIBERATELY DOES NOT SET VIDEO. Neal's own card forces vga_scaler=0 and
# forced_scandoubler=0 for his JVC production monitor over VGA-to-BNC. That is his setup, not
# everyone's, and a release image should not ship one person's monitor configuration - a user
# with only HDMI should get MiSTer's own defaults and set their own.
# Neal's CRT settings live in the DEV step 910 instead, which the image build skips.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

INI="$OCTO_ROOT/MiSTer.ini"
EX="$OCTO_ROOT/MiSTer_example.ini"

if [ -e "$INI" ]; then
    octo_say "MiSTer.ini is already there ($(wc -c < "$INI") bytes) - left exactly as it is"
elif [ -e "$EX" ]; then
    cp -p "$EX" "$INI" || exit 1
    sync
    octo_say "no MiSTer.ini - started one from MiSTer_example.ini"
else
    printf '[MiSTer]\n' > "$INI" || exit 1
    sync
    octo_say "no MiSTer.ini and no example - wrote a bare [MiSTer] one"
fi
octo_mark_done "MiSTer.ini present, video left to the user"
