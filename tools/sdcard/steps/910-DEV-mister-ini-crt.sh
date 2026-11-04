#!/bin/sh
# 910 DEV - Neal's own video setup. NOT part of the release image.
# His MiSTer drives HDMI to a monitor AND 15 kHz RGB to a JVC production monitor over
# VGA-to-5-BNC at the same time, which needs vga_scaler=0 and forced_scandoubler=0.
# A release image must not carry this: a user with only HDMI should get MiSTer's defaults.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

INI="$OCTO_ROOT/MiSTer.ini"
[ -e "$INI" ] || { echo "no MiSTer.ini - run step 060 first"; exit 1; }

want() {  # want <key> <value>
    K=$1; V=$2
    if grep -qE "^[[:space:]]*$K[[:space:]]*=[[:space:]]*$V([[:space:]]|$)" "$INI"; then
        octo_say "$K=$V already set"
        return 0
    fi
    octo_backup "$INI"
    if grep -qE "^[[:space:]]*;?[[:space:]]*$K[[:space:]]*=" "$INI"; then
        sed -i "0,/^[[:space:]]*;\?[[:space:]]*$K[[:space:]]*=.*/s|^[[:space:]]*;\?[[:space:]]*$K[[:space:]]*=.*|$K=$V|" "$INI" || return 1
        octo_say "$K set to $V"
    else
        sed -i "0,/^\[MiSTer\]/s/^\[MiSTer\]/[MiSTer]\n$K=$V/" "$INI" || return 1
        octo_say "$K=$V added"
    fi
}
want vga_scaler 0 || exit 1
want forced_scandoubler 0 || exit 1
sync
octo_say "now:"
grep -E '^[[:space:]]*(vga_scaler|forced_scandoubler|vga_mode|video_mode)[[:space:]]*=' "$INI" | sed 's/^/        /'
octo_mark_done "DEV CRT video settings"
