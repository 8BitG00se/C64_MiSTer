#!/bin/sh
# 061 - CHIP PRESET launchers: _Computer/Octophonic 64 - *.mgl
#
# The setup page's CHIP PRESET line lists every _Computer/Octophonic 64*.mgl on the card and
# RETURN restarts into the one picked (Octophonic Main: scan_presets / cmd_setapply). The image
# has only shipped the plain launcher, so the list had one entry and the line would not switch -
# which is what Neal saw. This adds three more, each with its own MiSTer setname, so each one
# remembers its OWN core settings and its own chips (Main stores those per core name).
#
# They start at the core's defaults: the names say what to set each to, they are not pre-filled.
# Nothing is overwritten - a launcher the user has already made or edited is left exactly as it is.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"

D="$OCTO_ROOT/_Computer"
mkdir -p "$D" || exit 1

# label (as the setup page shows it) : the MiSTer setname that keeps its settings
PRESETS="6581:Octophonic64_6581 8580:Octophonic64_8580 MIXED:Octophonic64_MIXED"

made=0; kept=0
for p in $PRESETS; do
    LABEL=${p%%:*}; SET=${p##*:}
    F="$D/Octophonic 64 - $LABEL.mgl"
    if [ -e "$F" ]; then
        octo_say "_Computer/Octophonic 64 - $LABEL.mgl already there - left alone"
        kept=$((kept + 1))
        continue
    fi
    cat > "$F" <<MGL || exit 1
<mistergamedescription>
    <rbf>_Computer/.C64_Octophonic</rbf>
    <setname same_dir="1">$SET</setname>
</mistergamedescription>
MGL
    octo_say "_Computer/Octophonic 64 - $LABEL.mgl"
    made=$((made + 1))
done

octo_say "CHIP PRESET: $((made + kept + 1)) launchers (PLAIN plus $((made + kept))) - each keeps its own settings and chips"
sync
octo_mark_done "presets $made new, $kept kept"
