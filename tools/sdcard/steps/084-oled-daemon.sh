#!/bin/sh
# 084 - the front screen at power-on (Fix 20): tty2oled's own daemon, so the screen gets the Octophonic logo the
# moment the core starts (and every other core's picture/name when Neal goes to the MiSTer menu).
#
# A card without tty2oled (a fresh card, the release image) gets venice1200's MiSTer scripts from the payload
# (GPL-3, see CREDITS.md): tty2oled/tty2oled.sh (the daemon), S60tty2oled (starts it), the two .ini files, and the
# line in linux/user-startup.sh that starts it at power-on - exactly what tty2oled's own installer puts there,
# without its downloads. A card that has tty2oled already keeps its own scripts.
# Either way tty2oled's own updater is switched off in tty2oled-user.ini (TTY2OLED_UPDATE="no"): it would offer to
# flash the stock screen firmware, which has no Octophonic logo. Pictures: tty2oled's picture pack is not needed -
# the Octophonic firmware plays the logo for any core name with "Octophonic" in it.
# With a screen plugged in, the daemon is started now too (no MiSTer restart).
# Payload wanted: files/tty2oled/{tty2oled.sh,S60tty2oled,tty2oled-system.ini,tty2oled-user.ini}
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

SRC="$OCTO_PAYLOAD/tty2oled"
DST="$OCTO_ROOT/tty2oled"
for F in tty2oled.sh S60tty2oled tty2oled-system.ini tty2oled-user.ini; do
    [ -s "$SRC/$F" ] || { echo "no $F in $SRC"; exit 1; }
done
mkdir -p "$DST/pics_pri" || exit 1

if [ -e "$DST/S60tty2oled" ] || [ -e "$DST/_S60tty2oled" ]; then
    octo_say "tty2oled is on this card already - its own scripts are kept"
    for F in tty2oled-system.ini tty2oled-user.ini; do
        [ -e "$DST/$F" ] || { cp -f "$SRC/$F" "$DST/$F" || exit 1; octo_say "added the missing $F"; }
    done
else
    for F in tty2oled.sh S60tty2oled tty2oled-system.ini tty2oled-user.ini; do
        octo_backup "$DST/$F" || exit 1
        cp -f "$SRC/$F" "$DST/$F" || exit 1
    done
    chmod +x "$DST/tty2oled.sh" "$DST/S60tty2oled"
    octo_say "tty2oled's daemon put on the card (tty2oled/)"
fi

# tty2oled's own updater off (it would flash the stock firmware over the Octophonic logo)
U="$DST/tty2oled-user.ini"
if grep -q '^TTY2OLED_UPDATE="no"' "$U" && grep -q '^SCRIPT_UPDATE="no"' "$U"; then
    octo_say "tty2oled's own updater is already off"
else
    octo_backup "$U" || exit 1
    grep -v '^TTY2OLED_UPDATE=\|^SCRIPT_UPDATE=\|^AUTOUPDATE=' "$U" > "$U.new"
    printf '%s\n' '# Octophonic: tty2oled'"'"'s own updater off - it would flash the stock screen firmware over the Octophonic logo' \
        'TTY2OLED_UPDATE="no"' 'SCRIPT_UPDATE="no"' 'AUTOUPDATE="no"' >> "$U.new"
    mv -f "$U.new" "$U" || exit 1
    octo_say "tty2oled's own updater switched off in tty2oled-user.ini"
fi

# started at power-on, as tty2oled's installer does it
US="$OCTO_ROOT/linux/user-startup.sh"
mkdir -p "$OCTO_ROOT/linux"
if [ -e "$US" ] && grep -q 'tty2oled' "$US"; then
    octo_say "user-startup.sh starts tty2oled already"
else
    if [ -e "$US" ]; then octo_backup "$US" || exit 1
    else printf '#!/bin/sh\n\necho "***" $1 "***"\n' > "$US"; fi
    printf '\n# Startup tty2oled\n[[ -e /media/fat/tty2oled/S60tty2oled ]] && /media/fat/tty2oled/S60tty2oled $1\n' >> "$US"
    octo_say "user-startup.sh now starts tty2oled at power-on"
fi
sh -n "$US" 2>/dev/null || bash -n "$US" || { echo "user-startup.sh has a syntax error - that could stop the MiSTer booting"; exit 1; }
sync

# start it now, if this is the MiSTer itself with the screen plugged in (not while building an image)
if [ "$OCTO_ROOT" = /media/fat ] && [ -x "$DST/S60tty2oled" ]; then
    TTYD=$(sed -n 's/^TTYDEV="\([^"]*\)".*/\1/p' "$DST/tty2oled-system.ini" "$DST/tty2oled-user.ini" | tail -1)
    if [ -c "${TTYD:-/dev/ttyUSB0}" ]; then
        if [ -e /run/tty2oled-daemon.pid ] && [ -d "/proc/$(cat /run/tty2oled-daemon.pid)" ]; then
            octo_say "the daemon is running already"
        else
            "$DST/S60tty2oled" start >/dev/null 2>&1 && octo_say "the daemon started - the screen shows the Octophonic logo"
        fi
    else
        octo_say "no screen on ${TTYD:-/dev/ttyUSB0} right now - the daemon starts at the next power-on"
    fi
fi
octo_mark_done "tty2oled daemon, its updater off"
