#!/bin/sh
# 088 - the front screen's firmware: Octophonic tty2oled OCTO4 (8BitG00se/octophonic-tty2oled), which can hold and
# play a program's own animation (CMDOANI) as well as the Octophonic logo.
#
# Only a screen that ALREADY runs an Octophonic firmware (OCTO1-OCTO3) is updated: a stock tty2oled screen is left
# alone (it still shows each program's still picture), and so is one that is up to date. The screen restarts by
# itself after the update (a few seconds dark) - the MiSTer does not.
# The screen's program is read back first and kept in octophonic/backups/<run>/ (about 2 minutes); then the new one
# is written and checked (about 2 minutes), at 115200 baud - Antonio Villena's board (CH340G) garbles faster
# transfers. If writing fails, the backup is written back.
# esptool 3.3.3 (GPL-2) and pyserial 3.5 (BSD) come in the payload and run from there: nothing is installed.
# Not on an image build (the screen has to be there), and not marked done until it has run on the MiSTer.
# Payload wanted: files/tty2oled-firmware/{esptool.py, serial/, esp32de_octo.bin, lolin32_octo.bin, esp32s3_octo.bin}
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }
WANT=4

FW="$OCTO_PAYLOAD/tty2oled-firmware"
[ "$OCTO_ROOT" = /media/fat ] || { octo_say "not on the MiSTer itself - the screen is updated there (skipped, not marked done)"; exit 0; }
[ -s "$FW/esptool.py" ] && [ -d "$FW/serial" ] || { octo_say "no screen firmware kit in the payload (skipped, not marked done)"; exit 0; }
T2O="$OCTO_ROOT/tty2oled"
TTY=$(sed -n 's/^TTYDEV="\([^"]*\)".*/\1/p' "$T2O/tty2oled-system.ini" "$T2O/tty2oled-user.ini" 2>/dev/null | tail -1)
TTY=${TTY:-/dev/ttyUSB0}
[ -c "$TTY" ] || { octo_say "no screen on $TTY (skipped, not marked done)"; exit 0; }
PY=$(command -v python3 || command -v python) || { echo "no python on this MiSTer - esptool needs it"; exit 1; }

daemon_stop() { [ -x "$T2O/S60tty2oled" ] && "$T2O/S60tty2oled" stop >/dev/null 2>&1; sleep 0.5; }
daemon_start() { [ -x "$T2O/S60tty2oled" ] && "$T2O/S60tty2oled" start >/dev/null 2>&1; }
ask_fw() {
    stty -F "$TTY" 115200 cs8 raw -parenb -cstopb -hupcl -echo 2>/dev/null
    cat "$TTY" > /tmp/octo_fw.hw 2>/dev/null & P=$!
    sleep 0.3; printf 'CMDHWINF\n' > "$TTY"; sleep 1.5
    kill "$P" 2>/dev/null; wait "$P" 2>/dev/null
    tr -d '\r\n' < /tmp/octo_fw.hw | grep -o 'HW[A-Z0-9]*;[^;]*;' | tail -1
}

daemon_stop
rm -rf /tmp/octo_oled.lock
HWV=$(ask_fw)
octo_say "the screen says: ${HWV:-nothing}"
[ -n "$HWV" ] || { daemon_start; octo_say "no answer from the screen (skipped, not marked done)"; exit 0; }
LV=$(printf '%s' "$HWV" | sed -n 's/.*-OCTO\([0-9][0-9]*\).*/\1/p')
if [ -z "$LV" ]; then
    daemon_start
    octo_say "a stock tty2oled firmware - left alone (programs get their still picture on it)"
    octo_mark_done "left alone: $HWV"; exit 0
fi
if [ "$LV" -ge "$WANT" ]; then
    daemon_start
    octo_say "the screen has OCTO$LV already"
    octo_mark_done "already OCTO$LV"; exit 0
fi
case "$HWV" in
    HWESP32DE*) BIN=esp32de_octo.bin; CHIP=esp32 ;;
    HWLOLIN32*) BIN=lolin32_octo.bin; CHIP=esp32 ;;
    HWESP32S3*) BIN=esp32s3_octo.bin; CHIP=esp32s3 ;;
    *) daemon_start; octo_say "a board this step doesn't know ($HWV) - left alone"; octo_mark_done "left alone: $HWV"; exit 0 ;;
esac
[ -s "$FW/$BIN" ] || { daemon_start; octo_say "no $BIN in the payload (skipped, not marked done)"; exit 0; }

ESP() { PYTHONPATH="$FW" "$PY" "$FW/esptool.py" --chip "$CHIP" --port "$TTY" --baud 115200 --before default_reset --after hard_reset "$@"; }
B="$OCTO_BACKUPS/$OCTO_RUNSTAMP"; mkdir -p "$B" || exit 1
OLD="$B/tty2oled-screen-$(printf '%s' "$HWV" | tr -c 'A-Za-z0-9-' '_')app.bin"
SIZE=$(( ( $(wc -c < "$FW/$BIN") + 65535 ) / 65536 * 65536 ))
[ "$SIZE" -lt 1310720 ] && SIZE=1310720                     # the whole app partition (1.25 MB), whatever is in it
octo_say "reading the screen's program back first ($SIZE bytes, about 2 minutes) ..."
ESP read_flash 0x10000 "$SIZE" "$OLD" > "$B/tty2oled-read.log" 2>&1 || { daemon_start; echo "could not read the screen's program (see $B/tty2oled-read.log) - nothing was changed"; exit 1; }
octo_say "backed up: octophonic/backups/$OCTO_RUNSTAMP/$(basename "$OLD")"
octo_say "writing OCTO$WANT ($BIN, about 2 minutes) - the screen goes dark, then restarts ..."
if ! ESP write_flash -z --flash_mode keep --flash_freq keep --flash_size keep 0x10000 "$FW/$BIN" > "$B/tty2oled-write.log" 2>&1; then
    octo_say "writing failed (see $B/tty2oled-write.log) - putting the old program back ..."
    ESP write_flash -z --flash_mode keep --flash_freq keep --flash_size keep 0x10000 "$OLD" >> "$B/tty2oled-write.log" 2>&1 \
        && octo_say "the old program is back" || octo_say "the old program did not go back either - the screen may stay dark; run this step again"
    sleep 4; daemon_start; exit 1
fi
grep -q 'Hash of data verified' "$B/tty2oled-write.log" && octo_say "written and checked"
sleep 5
rm -f /tmp/octo_oled.fw /tmp/octo_oled.held /tmp/octo_oled.now
NOW=$(ask_fw)
octo_say "the screen now says: ${NOW:-nothing yet}"
daemon_start
[ -x "$OCTO_STATE/oled.sh" ] && sh "$OCTO_STATE/oled.sh" logo
case "$NOW" in *-OCTO$WANT*) octo_mark_done "OCTO$WANT on $HWV" ;; *) echo "the screen does not report OCTO$WANT yet - run the step again after a power-off"; exit 1 ;; esac
