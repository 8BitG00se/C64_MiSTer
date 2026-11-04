#!/bin/sh
# 900 DEV - Neal's own machine only. NOT part of the release image.
#
# Puts the PC's SSH public key in /root/.ssh so ssh never asks for a password, and adds a
# guarded block to /media/fat/linux/user-startup.sh that puts it back after a MiSTer Linux
# update (an update replaces linux.img, which is where /root lives, so the key would vanish).
#
# The root filesystem is read-only on a MiSTer (/ is linux.img on a loop device), so it is
# remounted read-write for a moment. The remount BACK to read-only is deferred into a
# background job, because doing it in a live ssh session wedges that session.
#
# Payload wanted: files/dev/octophonic-key.pub
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }

PUBF=$(octo_payload dev/octophonic-key.pub) || {
    octo_say "no files/dev/octophonic-key.pub - nothing to install, skipping"
    octo_mark_done "skipped, no key in the payload"
    exit 0
}
PUB=$(cat "$PUBF")
[ -n "$PUB" ] || { echo "the key file is empty"; exit 1; }

FATL="$OCTO_ROOT/linux"
[ -d "$FATL" ] || { echo "no $FATL on this card"; exit 1; }
cp -f "$PUBF" "$FATL/octophonic-key.pub" || exit 1
octo_say "key kept on the FAT partition: linux/octophonic-key.pub"

# 1. into /root/.ssh now
if grep -qxF "$PUB" /root/.ssh/authorized_keys 2>/dev/null; then
    octo_say "the key is already in /root/.ssh/authorized_keys"
else
    WASRO=no
    octo_root_is_ro && WASRO=yes
    if [ "$WASRO" = yes ]; then
        mount -o remount,rw / || { echo "could not make / writable"; exit 1; }
        octo_say "/ remounted read-write"
    fi
    mkdir -p /root/.ssh && chmod 700 /root/.ssh || exit 1
    printf '%s\n' "$PUB" >> /root/.ssh/authorized_keys || exit 1
    chmod 600 /root/.ssh/authorized_keys
    sync
    octo_say "key appended to /root/.ssh/authorized_keys"
    if [ "$WASRO" = yes ]; then
        octo_say "/ goes back to read-only in 5 seconds, in the background"
        (sleep 5; sync; mount -o remount,ro /) >/dev/null 2>&1 &
    fi
fi

# 2. the startup hook, so a Linux update cannot lose it
US="$FATL/user-startup.sh"
if grep -qF 'OCTOPHONIC SSH KEY' "$US" 2>/dev/null; then
    octo_say "the startup block is already in user-startup.sh"
else
    if [ -e "$US" ]; then
        [ -e "$US.before-octophonic" ] || cp -p "$US" "$US.before-octophonic"
        octo_say "user-startup.sh backed up as user-startup.sh.before-octophonic"
    else
        printf '#!/bin/sh\n' > "$US" || exit 1
        octo_say "created user-startup.sh"
    fi
    cat >> "$US" <<'OCTOEOF'

# --- OCTOPHONIC SSH KEY (added by the Octophonic project) ---
# Puts the PC's SSH key back into /root/.ssh after a MiSTer Linux update replaces linux.img.
# Reads it from the FAT partition, which updates never touch. Does nothing if it is there.
if [ -s /media/fat/linux/octophonic-key.pub ]; then
    OCTOPUB=$(cat /media/fat/linux/octophonic-key.pub)
    if ! grep -qxF "$OCTOPUB" /root/.ssh/authorized_keys 2>/dev/null; then
        OCTORO=no
        mount | grep ' / ' | grep -q 'ro,' && OCTORO=yes
        [ "$OCTORO" = yes ] && mount -o remount,rw /
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        printf '%s\n' "$OCTOPUB" >> /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        sync
        [ "$OCTORO" = yes ] && mount -o remount,ro /
        echo "$(date -u) octophonic: ssh key re-installed into /root/.ssh" >> /media/fat/linux/octophonic-key.log
    fi
fi
# --- end OCTOPHONIC SSH KEY ---
OCTOEOF
    chmod +x "$US" 2>/dev/null
    sync
    octo_say "block appended to user-startup.sh"
fi

sh -n "$US" || { echo "user-startup.sh now has a syntax error - that could stop the MiSTer booting"; exit 1; }
octo_say "user-startup.sh syntax OK"
octo_mark_done "DEV ssh key + startup hook"
