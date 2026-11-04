#!/bin/sh
# 020 - octophonic/os.ini.
#
# The point of this step: WITHOUT a startin= line, Octophonic Main starts on the NETWORK
# whenever a share is set up, and waits for it (Neal's os.log showed a 24-59 second stall on
# every boot). A release card must never do that, so startin=sd is written.
#
# It is careful with a card that already has an os.ini:
#   - no os.ini           -> writes the canonical one
#   - os.ini with startin= -> left completely alone (someone chose that on purpose)
#   - os.ini without startin= -> backed up, then startin=sd added. Nothing else is touched.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

IN="$OCTO_ROOT/octophonic/os.ini"
mkdir -p "$OCTO_ROOT/octophonic" || exit 1

write_canonical() {
    cat > "$IN" <<'OSINI'
; OCTOPHONIC OS - while this file is here, the MiSTer starts straight into Octophonic 64.
; Delete it (or set enabled=0) and the MiSTer starts as normal.
enabled=1
; what to start: the Octophonic 64 launcher (keeps your Octophonic settings)
boot=_Computer/Octophonic 64.mgl
; where the browser starts. sd = the SD card, always, with no waiting for a network.
; net = a network share. last = wherever you were last.
startin=sd
; the folder @ starts in - the Octophonic library on the SD card
start=/media/fat/games/C64/Octophonic
OSINI
}

if [ ! -e "$IN" ]; then
    octo_say "no os.ini - writing the canonical one"
    write_canonical || exit 1
elif grep -qE '^[[:space:]]*startin[[:space:]]*=' "$IN"; then
    octo_say "os.ini already has a startin= line - left alone:"
    grep -E '^[[:space:]]*startin[[:space:]]*=' "$IN" | sed 's/^/        /'
    octo_mark_done "os.ini already had startin="
    exit 0
else
    octo_say "os.ini has no startin= line - that is the network-wait bug. Adding startin=sd."
    octo_backup "$IN" || exit 1
    # keep everything that is there; add the line after boot= if we can, else at the end
    if grep -qE '^[[:space:]]*boot[[:space:]]*=' "$IN"; then
        awk '
            { print }
            !done && /^[[:space:]]*boot[[:space:]]*=/ {
                print "; where the browser starts. sd = the SD card, always, with no waiting for a network."
                print "; net = a network share. last = wherever you were last."
                print "startin=sd"
                done = 1
            }
        ' "$IN" > "$IN.new" && mv -f "$IN.new" "$IN" || exit 1
    else
        printf 'startin=sd\n' >> "$IN" || exit 1
    fi
fi
sync

octo_say "os.ini now reads:"
grep -v '^;' "$IN" | sed 's/^/        /'
grep -qE '^[[:space:]]*startin[[:space:]]*=[[:space:]]*sd' "$IN" || { echo "startin=sd did not take"; exit 1; }
octo_mark_done "os.ini ok, startin=sd"
