#!/bin/sh
# The updater's feedback loop: runs the recipe on a FAKE card folder (never a real card) five times and checks
#   1 first install            -> everything installs
#   2 same package again       -> nothing changes
#   3 a newer package          -> core, Main, SHELL.PRG update once (old core kept in _Octophonic/old cores)
#   4 the newer package again  -> nothing changes
#   5 the OLDER package again  -> nothing changes (no downgrade, Main/SHELL stay with the newer core)
#   sh tools/sdcard/test/recheck-test.sh [scratch folder]      prints RECHECK_TEST_OK at the end
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=${1:-${TMPDIR:-/tmp}/octo-recheck-test}
rm -rf "$T"; mkdir -p "$T"; cd "$T" || exit 1
mkpay() {
    P=$1; V=$2; mkdir -p "$P/_Computer" "$P/tty2oled"
    head -c 100000 /dev/urandom > "$P/C64_Octophonic_2026110${V}_core${V}.rbf"
    head -c 90000 /dev/urandom > "$P/Octophonic64RGB_2026110${V}.rbf"          # Fix 60: the Octophonic64RGB core (step 033)
    echo $((V + 2)) > "$P/core-number.txt"; cp "$R/tools/install/install_core.sh" "$P/"
    printf '<mistergamedescription>\n<rbf>_Computer/.C64_Octophonic</rbf>\n<setname same_dir="1">Octophonic64</setname>\n</mistergamedescription>\n' > "$P/_Computer/Octophonic 64.mgl"
    { echo "Octophonic OS COMPILE main v$V"; head -c 5000 /dev/urandom; } > "$P/MiSTer"
    { printf '\000\276'; echo "shell v$V"; } > "$P/SHELL.PRG"
    echo "acme" > "$P/acme"; echo "octocode" > "$P/OCTOCODE.PRG"; echo "spec" > "$P/SPEC.PRG"
    cp "$R/tools/oled/oled.sh" "$P/oled.sh"; cp "$R/tools/oled/tty2oled/"* "$P/tty2oled/"
}
mkpay old 7; mkpay new 8
mkdir -p card/linux; echo "stock main" > card/MiSTer; printf '[MiSTer]\nbootcore_timeout=10\n' > card/MiSTer_example.ini
FAIL=0
run() {   # run <payload> <name> <updated wanted> <older-kept wanted>
    OCTO_ROOT="$T/card" OCTO_PAYLOAD="$T/$1" sh "$R/tools/sdcard/run-steps.sh" > "$T/$2.log" 2>&1; RC=$?
    U=$(grep -c 'different version' "$T/$2.log"); O=$(grep -c 'OLDER than the card' "$T/$2.log")
    echo "$2 ($1 package): exit $RC, $U updated, $O kept as older, $(tail -1 "$T/$2.log")"
    [ "$RC" = 0 ] && [ "$U" = "$3" ] && [ "$O" = "$4" ] || { echo "   ^ NOT AS EXPECTED (wanted $3 updated, $4 older)"; FAIL=1; }
}
run old run1 0 0; run old run2 0 0; run new run3 4 0; run new run4 0 0; run old run5 0 5
same() { [ "$(md5sum < "$1")" = "$(md5sum < "$2")" ] && echo "   ok  $3" || { echo "   BAD $3"; FAIL=1; }; }
same card/MiSTer new/MiSTer "Main is the newer one"
same card/octophonic/SHELL.PRG new/SHELL.PRG "SHELL.PRG is the newer one"
same card/_Computer/.C64_Octophonic_20261108_core8.rbf new/C64_Octophonic_20261108_core8.rbf "Core 8 in _Computer"
N=$(ls -a card/_Computer | grep -c '^\.C64_Octophonic_.*\.rbf$'); [ "$N" = 1 ] && echo "   ok  exactly one core in _Computer" || { echo "   BAD $N cores in _Computer"; FAIL=1; }
same card/_Computer/.Octophonic64RGB_20261108.rbf new/Octophonic64RGB_20261108.rbf "the newer Octophonic64RGB core in _Computer"
N=$(ls -a card/_Computer | grep -c '^\.Octophonic64RGB_.*\.rbf$'); [ "$N" = 1 ] && echo "   ok  exactly one Octophonic64RGB core in _Computer" || { echo "   BAD $N Octophonic64RGB cores in _Computer"; FAIL=1; }
[ -e "card/_Octophonic/old cores/.Octophonic64RGB_20261107.rbf" ] && echo "   ok  the older Octophonic64RGB core kept in _Octophonic/old cores" || { echo "   BAD the older Octophonic64RGB core not kept"; FAIL=1; }
[ -e "card/_Octophonic/old cores/.C64_Octophonic_20261107_core7.rbf" ] && echo "   ok  Core 7 kept in _Octophonic/old cores" || { echo "   BAD Core 7 not kept"; FAIL=1; }
grep -q -- '-DEV-.*Z' card/octophonic/steps-done.txt && { echo "   BAD a DEV step ran"; FAIL=1; }
echo "update.log:"; sed 's/^/   /' card/octophonic/update.log
[ "$FAIL" = 0 ] && echo RECHECK_TEST_OK || { echo RECHECK_TEST_FAILED; exit 1; }
