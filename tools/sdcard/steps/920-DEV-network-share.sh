#!/bin/sh
# 920 DEV - Neal's network share. NOT part of the release image.
#
# The release card is share-free on purpose: everything lives on the SD card and no path to
# anyone's PC appears anywhere in the image. This step only reports what share this machine
# has, so the recipe records it without the image ever carrying it.
# It deliberately does NOT set a share up: MiSTer's own cifs_mount.ini / Scripts do that, and
# writing someone's server address into a script is exactly what must stay out of the image.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

octo_say "network shares mounted right now:"
mount | grep -iE 'cifs|smb|nfs' | sed 's/^/        /' || octo_say "        (none)"
octo_say "MiSTer's own share settings on this card:"
for f in "$OCTO_ROOT/Scripts/cifs_mount.ini" "$OCTO_ROOT/Scripts/cifs.sh" "$OCTO_ROOT/Scripts/mount-games.sh"; do
    [ -e "$f" ] && octo_say "        $f  ($(wc -c < "$f") bytes)"
done
octo_say "nothing was changed - this step only records what is here."
octo_mark_done "DEV share noted, not configured"
