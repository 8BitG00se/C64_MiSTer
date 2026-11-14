#!/bin/sh
# 090 - files over the network (Fix 19): FileZilla from the PC straight into games/C64.   © 2026 Mong00se
#
# NOTHING IS ADDED AND NOTHING IS SWITCHED ON HERE. MiSTer's own Linux (linux/linux.img, which this card
# carries untouched) already runs two file servers at every power-on:
#     FTP   port 21   ProFTPD   (/etc/init.d/S50proftpd)
#     SFTP  port 22   sshd      (/etc/init.d/S50sshd, the same server ssh uses)
# So a freshly flashed card takes files the moment it is on the network - no keyboard, no setup.
# What this step is for: it PROVES that on every card and every image build, and says it in plain words:
#   - image build: looks inside linux.img for the two start scripts. A MiSTer release that dropped or
#     switched off its FTP server FAILS the build here, so a card can never go out without file transfer.
#   - a card in a MiSTer (the updater): looks at the running machine - are the servers set to start, are
#     they running, what name and address to type into FileZilla - and writes one line to update.log.
#     It only looks. A server someone switched off (MiSTer's ftp_off / ssh_off scripts) is left off.
#
# WHAT THAT MEANS FOR SECURITY - read this, the card goes out to the public:
#   - user root, password 1. That is MiSTer's standard login, the same on every MiSTer in the world and
#     printed in MiSTer's own documentation. It is NOT a secret.
#   - that login can read, change and delete EVERY file on the card, and over ssh it is a full root shell.
#   - anyone on the same network can use it. It is not offered to the internet unless the router is told
#     to forward ports 21/22 to the MiSTer - never do that.
#   - FTP also lets "anonymous" in with no password, but only into an empty folder inside the read-only
#     linux.img: it cannot see the card and cannot write anything.
#   - FTP sends the password and the files in the clear; SFTP (port 22) is encrypted - same user, same password.
#   - no Samba share: that stays off (it needs linux/samba.sh, which the release card does not have - the
#     image check makes sure).
#   - your own password: MiSTer's own security_fixes.sh (github.com/MiSTer-devel/Scripts_MiSTer) sets one.
# This step puts no key, no address, no share name and no password of anyone's on the card.
set -u
. "$(dirname "$0")/../octo-step-lib.sh"
octo_is_done && { octo_say "already done"; exit 0; }
[ "${OCTO_LIST:-0}" = 1 ] && { octo_say "WOULD CHECK MiSTer's own FTP and SFTP servers (changes nothing)"; exit 0; }

# OCTO_SYSROOT: where the running MiSTer's /etc is (empty = this machine). Only the test sets it.
SYS="${OCTO_SYSROOT:-}"
INITD="$SYS/etc/init.d"
IMG="$OCTO_ROOT/linux/linux.img"

# is <name> in /etc/init.d of linux.img, as a start script (S50xxx) or switched off (_S50xxx)?
# With debugfs (e2fsprogs - any Linux build machine has it) the folder is read properly. Without it, the
# raw bytes are searched: an ext4 folder entry is ... <type byte 01 = a file> <the name>, so the name
# right after a 01 byte is a file's name (the same words in a script's own text have no 01 in front).
# The raw search is right for an untouched MiSTer release; it could be fooled by a linux.img someone
# renamed files in by hand (an old entry's bytes can stay behind), which is why debugfs is used first.
INITLIST=""
if [ -s "$IMG" ] && command -v debugfs >/dev/null 2>&1; then
    INITLIST=$(debugfs -R "ls -p /etc/init.d" "$IMG" 2>/dev/null | cut -d/ -f6)
fi
img_has() {
    if [ -n "$INITLIST" ]; then printf '%s\n' "$INITLIST" | grep -qx "$1"
    else LC_ALL=C grep -a -q "$(printf '\001%s' "$1")" "$IMG" 2>/dev/null; fi
}

FTP=missing; SFTP=missing
if [ -n "$SYS" ] || { [ "$OCTO_ROOT" = /media/fat ] && [ -d /etc/init.d ]; }; then
    # ---------------------------------------------------------------- a card in a running MiSTer
    WHERE="this MiSTer"
    [ -e "$INITD/_S50proftpd" ] && FTP=off
    [ -e "$INITD/S50proftpd" ] && FTP=on
    [ -e "$INITD/_S50sshd" ] && SFTP=off
    [ -e "$INITD/S50sshd" ] && SFTP=on
    if [ -z "$SYS" ]; then
        pidof proftpd >/dev/null 2>&1 && octo_say "FTP server (ProFTPD): running now" || octo_say "FTP server (ProFTPD): NOT running right now"
        pidof sshd >/dev/null 2>&1 && octo_say "SFTP/ssh server (sshd): running now" || octo_say "SFTP/ssh server (sshd): NOT running right now"
        # the name and address to type into FileZilla - said on screen only, never written to the card
        NAME=$(hostname 2>/dev/null)
        ADDR=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ')
        octo_say "in FileZilla, Host:  ${NAME:-MiSTer}   (or the address: ${ADDR:-none yet - no network})"
    fi
    [ -e "$OCTO_ROOT/linux/samba.sh" ] && octo_say "a Samba share is switched on too (linux/samba.sh) - that is this card's own choice, left alone"
elif [ -s "$IMG" ]; then
    # ---------------------------------------------------------------- a card being built (the image)
    WHERE="linux.img"
    [ -n "$INITLIST" ] && octo_say "linux.img's /etc/init.d read with debugfs" || octo_say "no debugfs here: linux.img searched for its start scripts' folder entries"
    img_has _S50proftpd && FTP=off
    img_has S50proftpd && FTP=on
    img_has _S50sshd && SFTP=off
    img_has S50sshd && SFTP=on
    [ -e "$OCTO_ROOT/linux/samba.sh" ] && octo_say "linux/samba.sh is on this card: a Samba share is switched on too (the image check refuses that on a release card)"
else
    # ---------------------------------------------------------------- a test folder: no MiSTer Linux at all
    octo_say "no linux/linux.img here (a test folder, not a card) - nothing to check"
    octo_mark_done "no MiSTer Linux on this card to check"
    exit 0
fi

case "$FTP" in
    on)      octo_say "FTP   port 21: ON at every power-on (MiSTer's own ProFTPD, $WHERE)" ;;
    off)     octo_say "FTP   port 21: SWITCHED OFF in $WHERE (MiSTer's ftp_off script) - left off; ftp_on puts it back" ;;
    missing) octo_say "FTP   port 21: this MiSTer Linux has NO FTP server ($WHERE)" ;;
esac
case "$SFTP" in
    on)      octo_say "SFTP  port 22: ON at every power-on (MiSTer's own sshd, $WHERE)" ;;
    off)     octo_say "SFTP  port 22: SWITCHED OFF in $WHERE (MiSTer's ssh_off script) - left off; ssh_on puts it back" ;;
    missing) octo_say "SFTP  port 22: this MiSTer Linux has NO ssh server ($WHERE)" ;;
esac

if [ "$WHERE" = linux.img ] && [ "$FTP" != on ]; then
    # the release image: FileZilla over FTP is the whole point of Fix 19 - do not build a card without it
    echo "this MiSTer release does not start an FTP server (it is $FTP in linux.img)."
    echo "A release card must take files over the network: not building one that cannot."
    exit 1
fi

if [ "$FTP" = on ] || [ "$SFTP" = on ]; then
    octo_say "login: root, with MiSTer's standard password (1) - it can change EVERY file on the card,"
    octo_say "       from any machine on the same network. Files for the browser go in games/C64/..."
    octo_say "       (the card is /media/fat on the MiSTer). See the top of this step for the whole picture."
fi
octo_say "nothing was added or changed - these are MiSTer's own servers."
octo_mark_done "MiSTer's own file servers: FTP (21) $FTP, SFTP (22) $SFTP - nothing added or changed"
