#!/bin/sh
# 089 - the front screen's firmware updates by itself (Fix 37): a guarded block in linux/user-startup.sh runs
# step 088 in the background at every power-on. Step 088 does nothing at all once the screen is up to date (or
# is a stock tty2oled screen, which it leaves alone), so after the first time this costs a fraction of a second.
# When it does update, the screen goes dark for about 4 minutes and comes back with the new logo; the MiSTer keeps
# running. Everything it does goes to octophonic/update.log. Runs on an image build too (it only writes the file).
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
TAG='# OCTOPHONIC-OLED-FIRMWARE'
US="$OCTO_ROOT/linux/user-startup.sh"
if [ -e "$US" ] && grep -q "^$TAG" "$US"; then
    octo_say "user-startup.sh runs the screen firmware step already"
    octo_is_done || octo_mark_done "user-startup.sh runs step 088 at power-on"
    exit 0
fi
[ "${OCTO_LIST:-0}" = 1 ] && { octo_say "WOULD ADD the screen firmware step to user-startup.sh"; exit 0; }
mkdir -p "$OCTO_ROOT/linux"
if [ -e "$US" ]; then octo_backup "$US" || exit 1
else printf '#!/bin/sh\n\necho "***" $1 "***"\n' > "$US"; fi
cat >> "$US" <<'EOS'

# OCTOPHONIC-OLED-FIRMWARE (Fix 37): the front screen's firmware, when it is due (octophonic step 088)
if [ "$1" = "start" ] && [ -f /media/fat/octophonic/recipe/steps/088-oled-firmware.sh ]; then
  ( sleep 25; cd /media/fat/octophonic/recipe && OCTO_ONLY=088 sh run-steps.sh >> /media/fat/octophonic/update.log 2>&1 ) &
fi
EOS
sh -n "$US" 2>/dev/null || bash -n "$US" || { echo "user-startup.sh has a syntax error - that could stop the MiSTer booting"; exit 1; }
sync
octo_say "user-startup.sh now runs the screen firmware step at power-on (step 088, in the background)"
octo_mark_done "user-startup.sh runs step 088 at power-on"
