#!/bin/sh
# Step 090's feedback loop (Fix 19): runs it on FAKE cards (never a real one, never a MiSTer) and checks   © 2026 Mong00se
#   1 a test folder with no linux.img        -> passes, changes nothing
#   2 a card whose linux.img starts FTP+sshd -> passes, says both are ON; the second run says "already done";
#                                               a forced third run changes nothing either (same files, same sums)
#   3 linux.img with FTP switched off        -> the image build is REFUSED (exit 1), nothing marked done
#   4 linux.img with no FTP server at all    -> refused too
#   5 a card in a "running MiSTer" (a fake /etc/init.d) with FTP on / switched off -> reported, never changed
#   6 nothing personal: the step file passes the image check's own personal-string patterns
#   sh tools/sdcard/test/network-test.sh [scratch folder]      prints NETWORK_TEST_OK at the end
# With OCTO_LINUX_IMG=<a real MiSTer linux/linux.img> it also runs case 2 on the real thing.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
S="$R/tools/sdcard/steps/090-network-file-transfer.sh"
T=${1:-${TMPDIR:-/tmp}/octo-network-test}
rm -rf "$T"; mkdir -p "$T"; cd "$T" || exit 1
FAIL=0
ok()  { echo "   ok  $*"; }
bad() { echo "   BAD $*"; FAIL=1; }
# a pretend linux.img: just the folder entries the step looks for (a 01 type byte, then the name)
# (and the name inside a script's own text, with no 01 in front, which must NOT count)
mkimg() {
    D=$1; shift; mkdir -p "$D/linux"
    { head -c 4096 /dev/zero; for n in "$@"; do printf '\014\000\012\001%s' "$n"; done
      printf 'Usage: /etc/init.d/S50proftpd {start|stop}'; head -c 4096 /dev/zero; } > "$D/linux/linux.img"
}
sums() { (cd "$1" && find . -type f ! -name update.log ! -name steps-done.txt | LC_ALL=C sort | xargs md5sum 2>/dev/null | md5sum | cut -c1-32); }
run() { OCTO_ROOT="$T/$1" OCTO_PAYLOAD="$T/nopayload" OCTO_RUNSTAMP=test sh "$S" > "$T/$2.log" 2>&1; echo $?; }

echo "1 a test folder, no linux.img"
mkdir -p c1/linux; RC=$(run c1 r1)
[ "$RC" = 0 ] && grep -q 'nothing to check' r1.log && ok "passes and says so" || bad "exit $RC"

echo "2 a card whose linux.img starts FTP and sshd"
mkimg c2 S50proftpd S50sshd; B=$(sums c2); RC=$(run c2 r2a)
[ "$RC" = 0 ] && grep -q 'FTP   port 21: ON' r2a.log && grep -q 'SFTP  port 22: ON' r2a.log && ok "first run: both ON" || bad "first run (exit $RC)"
[ "$(grep -c '^090-network-file-transfer.sh ' c2/octophonic/steps-done.txt)" = 1 ] && ok "one line in steps-done.txt: $(cut -d' ' -f3- c2/octophonic/steps-done.txt)" || bad "steps-done.txt"
RC=$(run c2 r2b); [ "$RC" = 0 ] && grep -q 'already done' r2b.log && ok "second run: already done" || bad "second run (exit $RC)"
RC=$(OCTO_FORCE=1 OCTO_ROOT="$T/c2" OCTO_PAYLOAD="$T/nopayload" sh "$S" > r2c.log 2>&1; echo $?)
[ "$RC" = 0 ] && [ "$(grep -c '^090-' c2/octophonic/steps-done.txt)" = 1 ] && ok "forced third run: still one line" || bad "forced run (exit $RC)"
[ "$(sums c2)" = "$B" ] && ok "no file on the card added or changed by three runs" || bad "the card changed"
[ ! -d c2/octophonic/backups ] && ok "nothing replaced, so nothing to back up" || bad "a backup appeared"

echo "3 linux.img with FTP switched off (_S50proftpd)"
mkimg c3 _S50proftpd S50sshd; RC=$(run c3 r3)
[ "$RC" = 1 ] && ! grep -q '^090-' c3/octophonic/steps-done.txt 2>/dev/null && ok "refused, not marked done" || bad "exit $RC"

echo "4 linux.img with no FTP server"
mkimg c4 S50sshd; RC=$(run c4 r4)
[ "$RC" = 1 ] && grep -q 'NO FTP server' r4.log && ok "refused" || bad "exit $RC"

echo "5 a card in a running MiSTer (fake /etc/init.d)"
mkdir -p c5/linux sys5/etc/init.d; : > sys5/etc/init.d/S50proftpd; : > sys5/etc/init.d/S50sshd
RC=$(OCTO_SYSROOT="$T/sys5" run c5 r5); [ "$RC" = 0 ] && grep -q 'FTP   port 21: ON' r5.log && ok "FTP on: reported" || bad "exit $RC"
mkdir -p c6/linux sys6/etc/init.d; : > sys6/etc/init.d/_S50proftpd; : > sys6/etc/init.d/S50sshd; B=$(ls sys6/etc/init.d)
RC=$(OCTO_SYSROOT="$T/sys6" run c6 r6)
[ "$RC" = 0 ] && grep -q 'SWITCHED OFF' r6.log && [ "$(ls sys6/etc/init.d)" = "$B" ] && ok "FTP switched off by its owner: reported, left off" || bad "exit $RC"

echo "6 nothing personal in the step (the image check's own patterns)"
PATS=$(sed -n "s/^PATS='\(.*\)'$/\1/p" "$R/tools/sdcard/image/check-image.sh"); TPATS=$(sed -n "s/^TPATS='\(.*\)'$/\1/p" "$R/tools/sdcard/image/check-image.sh")
[ -n "$PATS" ] && [ -n "$TPATS" ] || bad "could not read the patterns from check-image.sh"
if grep -a -q -E "$PATS" "$S" || grep -I -q -E "$TPATS" "$S"; then bad "a personal-string pattern matches the step"; grep -a -n -E "$PATS" "$S"; grep -I -n -E "$TPATS" "$S"
else ok "no key, share, address or PC path pattern matches"; fi
printf 'SERVER="nas"\n' | grep -q -E "$PATS" && ok "(the patterns do catch a planted one)" || bad "the patterns caught nothing"

if [ -n "${OCTO_LINUX_IMG:-}" ]; then
    echo "7 a real MiSTer linux.img: $OCTO_LINUX_IMG"
    mkdir -p c7/linux; ln -s "$OCTO_LINUX_IMG" c7/linux/linux.img; RC=$(run c7 r7); sed 's/^/     /' r7.log
    [ "$RC" = 0 ] && grep -q 'FTP   port 21: ON' r7.log && grep -q 'SFTP  port 22: ON' r7.log && ok "the real linux.img: both ON" || bad "exit $RC"
fi
[ "$FAIL" = 0 ] && echo "NETWORK_TEST_OK" || { echo "NETWORK_TEST_FAILED"; exit 1; }
