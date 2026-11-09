#!/bin/sh
# OCTOPHONIC - runs ON THE MISTER, sent by "Update front screen firmware.bat" (never from the Scripts menu).
# Runs the card's own recipe (octophonic/recipe/run-steps.sh). On a freshly flashed Fusion card the only step not
# done yet is 088: the front screen's firmware goes to OCTO4 (the one that plays each demo's own animation), from
# the kit the image put in octophonic/files/tty2oled-firmware. The screen is DARK FOR ABOUT 4 MINUTES while it is
# written; its old firmware is read back and kept first, and put back if writing fails.
# The MiSTer is NOT restarted, Main is NOT restarted, the core is NOT reloaded. Run twice: the second run does nothing.
LOG=/media/fat/octophonic/update.log
R=/media/fat/octophonic/recipe/run-steps.sh
[ -e "$R" ] || { echo "no recipe on this card ($R) - is this an Octophonic Fusion card?"; exit 1; }
echo "$(date '+%Y-%m-%d %H:%M:%S') front screen firmware: recipe run started (no restart)" >> "$LOG"
sh "$R" > /tmp/octo-front-screen.txt 2>&1; RC=$?
grep -v '^steps-done\|^[0-9][0-9][0-9]-.*Z ' /tmp/octo-front-screen.txt
echo "$(date '+%Y-%m-%d %H:%M:%S') front screen firmware: recipe run finished (exit $RC, no restart)" >> "$LOG"
exit $RC
