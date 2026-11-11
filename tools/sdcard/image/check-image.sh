#!/bin/bash
# OCTOPHONIC FUSION - opens a finished image again and proves what is in it:
#   the partitions are Mr. Fusion's; the data partition is a sound FAT (fsck.fat, when there is one);
#   release.7z tests good and holds the card; bootcore points at the Octophonic launcher with no
#   timeout; and nothing from the DEV steps or Neal's own setup is anywhere in what Octophonic added.
#   check-image.sh IMAGE 7ZZ WORKDIR
set -uo pipefail
IMG=$1; Z=$2; W=$3
FAIL=0
bad() { echo "  FAIL: $*"; FAIL=1; }
okk() { echo "  ok:   $*"; }
rm -rf "$W"; mkdir -p "$W"

echo "-- the partitions"
read -r T1 S1 N1 T2 S2 N2 < <(python3 -I -c "
import struct,sys;d=open(sys.argv[1],'rb').read(512)
e=lambda i:(d[446+16*i+4],)+struct.unpack('<II',d[446+16*i+8:446+16*i+16])
print(*e(0),*e(1))" "$IMG")
printf '  1: type %02x  start %s  sectors %s (%s MB)\n  2: type %02x  start %s  sectors %s\n' "$T1" "$S1" "$N1" $((N1/2048)) "$T2" "$S2" "$N2"
[ "$T1" = 11 ] && [ "$S1" = 10240 ] && okk "data partition: FAT, at 10240 (as Mr. Fusion's)" || bad "partition 1"
[ "$T2" = 162 ] && [ "$S2" = 2048 ] && [ "$N2" = 8192 ] && okk "bootloader partition: type a2 at 2048, 8192 sectors" || bad "partition 2"
dd if="$IMG" of="$W/p1" bs=512 skip="$S1" count="$N1" status=none

echo "-- the FAT"
FSCK=${FSCK_FAT:-$(command -v fsck.fat || true)}    # (FSCK_FAT: a fsck.fat built from dosfstools)
if [ -n "$FSCK" ]; then
    if "$FSCK" -n "$W/p1" > "$W/fsck.txt" 2>&1; then okk "fsck.fat: $(tail -1 "$W/fsck.txt")"; else bad "fsck.fat:"; cat "$W/fsck.txt"; fi
else echo "  (no fsck.fat here - 7-Zip's reading of it below is the check)"; fi
"$Z" l "$W/p1" | sed -n '/^---/,/^---/p' | sed 's/^/  /'
mkdir -p "$W/fat"; "$Z" x -y -o"$W/fat" "$W/p1" >/dev/null && okk "every file read back" || bad "7-Zip could not read the FAT"

echo "-- release.7z"
"$Z" t "$W/fat/release.7z" > "$W/t.txt" 2>&1 && okk "release.7z tests good ($(grep -m1 '^Files:' "$W/t.txt"))" || bad "release.7z test"
mkdir -p "$W/card"; "$Z" x -y -o"$W/card" "$W/fat/release.7z" >/dev/null || bad "release.7z will not unpack"
C="$W/card/files"

echo "-- the card Mr. Fusion will write (the parts that are Octophonic's or about to be used)"
( cd "$C" && find . -maxdepth 1 | sort | sed 's|^\./||;/^\.$/d;s/^/    /' )
echo "  games/C64:"; ( cd "$C/games/C64" && find . -mindepth 1 | sort | sed 's|^\./|    |' )
echo "  _Computer:"; ls -A "$C/_Computer" | sed 's/^/    /'
echo "  octophonic:"; ( cd "$C/octophonic" && find . -mindepth 1 | sort | sed 's|^\./|    |' )
echo "  games/C64 files (the example set, step 015): $(find "$C/games/C64" -type f | wc -l), $(du -sh "$C/games/C64" | cut -f1)"
if [ "${OCTO_EXAMPLES:-}" = none ]; then
    [ "$(find "$C/games/C64" -type f ! -path "*/Tools/OCTOCODE.PRG" ! -path "*/Tools/SPEC.PRG" ! -path "*/Tools/TESTCARD.PRG" | wc -l)" = 0 ] && okk "games/C64 is empty but Tools/OCTOCODE.PRG, Tools/SPEC.PRG and Tools/TESTCARD.PRG (OCTO_EXAMPLES=none)" || bad "files in games/C64"
    [ -s "$C/games/C64/Tools/OCTOCODE.PRG" ] && okk "Tools/OCTOCODE.PRG (step 055)" || bad "no Tools/OCTOCODE.PRG"
    [ -s "$C/octophonic/acme" ] && okk "octophonic/acme (F2 COMPILE on the MiSTer)" || bad "no octophonic/acme"
else
    grep -q '^015-examples.sh ' "$C/octophonic/steps-done.txt" && okk "step 015 put the example set in" || bad "step 015 (the example set) did not run"
fi
for d in Demos Games Tools Code Music SIDs Pictures "My Chips" Disks Screenshots Saves; do
    [ -d "$C/games/C64/$d" ] || bad "no games/C64/$d"
    # OCTO_EXAMPLES_PARTIAL=1: a set that fills only some folders (build 7: the four demos) - empty ones are fine
    [ "${OCTO_EXAMPLES:-}" = none ] || [ "${OCTO_EXAMPLES_PARTIAL:-0}" = 1 ] || [ -n "$(ls -A "$C/games/C64/$d")" ] || bad "games/C64/$d is empty"
done

echo "-- straight into Octophonic"
INI="$C/MiSTer.ini"
[ ! -e "$C/games/C64/Apps" ] && okk "no old games/C64/Apps (it is Tools now, Fix 45)" || bad "games/C64/Apps is on the card"
[ "$(grep -E '^[[:space:]]*vsync_adjust[[:space:]]*=' "$INI" | sed 's/;.*//' | tr -d ' \t\r' | sort -u)" = "vsync_adjust=2" ] \
    && okk "MiSTer.ini vsync_adjust=2 (HDMI follows the core's 50 Hz, step 065)" || bad "MiSTer.ini has no vsync_adjust=2 (step 065)"
BC=$(grep -E '^[[:space:]]*bootcore[[:space:]]*=' "$INI" | sed 's/[[:space:]]*;.*//')
echo "  MiSTer.ini: $BC"
grep -E '^[[:space:]]*;?[[:space:]]*bootcore_timeout' "$INI" | sed 's/^/  MiSTer.ini: /'
[ "$BC" = "bootcore=Octophonic 64.mgl" ] && okk "bootcore is the Octophonic launcher" || bad "bootcore is not 'Octophonic 64.mgl'"
grep -qE '^[[:space:]]*bootcore_timeout[[:space:]]*=' "$INI" && bad "a bootcore_timeout is active (it shows the menu)" || okk "no bootcore_timeout (the core loads before the menu draws anything)"
[ -s "$C/_Computer/Octophonic 64.mgl" ] && okk "_Computer/Octophonic 64.mgl is there" || bad "no launcher"
grep -q '<setname' "$C/_Computer/Octophonic 64.mgl" && okk "the launcher has its setname line" || bad "no setname"
ls "$C"/_Computer/.C64_Octophonic_*.rbf >/dev/null 2>&1 && okk "the hidden core: $(cd "$C/_Computer" && ls -A | grep '^\.C64_Octophonic')" || bad "no hidden core"
grep -q 'Octophonic OS' "$C/MiSTer" && okk "MiSTer is Octophonic Main (stock kept as MiSTer.orig: $([ -s "$C/MiSTer.orig" ] && echo yes || echo NO))" || bad "MiSTer is not Octophonic Main"
LA=$(od -A n -t x1 -N 2 "$C/octophonic/SHELL.PRG" | tr -d ' \n')
[ "$LA" = 00be ] || [ "$LA" = 00c0 ] && okk "octophonic/SHELL.PRG (loads at \$${LA#00}${LA%??})" || bad "SHELL.PRG load address $LA"
NC=$(ls -A "$C/_Computer" | grep -c '^\.C64_Octophonic_.*\.rbf$')
[ "$NC" = 1 ] && okk "exactly one Octophonic core in _Computer (no older core can be started by the launcher)" || bad "$NC Octophonic cores in _Computer"
echo "-- the front screen"
for f in tty2oled/tty2oled.sh tty2oled/S60tty2oled tty2oled/tty2oled-user.ini octophonic/oled.sh; do
    [ -s "$C/$f" ] && okk "$f" || bad "no $f"
done
grep -q 'tty2oled/S60tty2oled' "$C/linux/user-startup.sh" 2>/dev/null && okk "linux/user-startup.sh starts tty2oled at power-on (the logo at boot)" || bad "tty2oled is not started at power-on"
grep -q '^TTY2OLED_UPDATE="no"' "$C/tty2oled/tty2oled-user.ini" 2>/dev/null && okk "tty2oled's own updater off (it would flash the stock firmware)" || bad "tty2oled's updater is not off"
grep -q 'oled.sh' "$C/MiSTer" && okk "Main has the front screen (oled.sh)" || bad "Main has no front screen"
grep -q 'SHOWCASE' "$C/MiSTer" && okk "Main has the os-fixes (SHOWCASE)" || bad "Main has no os-fixes"
for o in "$C"/games/C64/Demos/*/*.oled; do [ -e "$o" ] && okk "demo animation: ${o#$C/}"; done
if [ -n "${OCTO_EXPECT:-}" ] && [ -s "$OCTO_EXPECT" ]; then
    echo "-- every expected file, by md5 ($(wc -l < "$OCTO_EXPECT"))"
    EB=0
    while IFS= read -r line; do
        sum=${line%%  *}; rel=${line#*  }
        [ "$(md5sum < "$C/$rel" 2>/dev/null | cut -c1-32)" = "$sum" ] || { bad "$rel is missing or not the right one"; EB=1; }
    done < "$OCTO_EXPECT"
    [ "$EB" = 0 ] && okk "all $(wc -l < "$OCTO_EXPECT") match"
fi
grep -E '^(enabled|boot|startin|start)=' "$C/octophonic/os.ini" | sed 's/^/  os.ini: /'
grep -qx 'start=/media/fat/games/C64' "$C/octophonic/os.ini" && okk "os.ini start=/media/fat/games/C64" || bad "os.ini start= is not /media/fat/games/C64"
grep -qx 'startin=sd' "$C/octophonic/os.ini" && okk "os.ini startin=sd (never waits for a network)" || bad "os.ini startin"
echo "  steps done:"; sed 's/^/    /' "$C/octophonic/steps-done.txt"
grep -q -- '-DEV-' "$C/octophonic/steps-done.txt" && bad "a DEV step is in steps-done.txt" || okk "no DEV step ran"
ls "$C/octophonic/recipe/steps" | grep -q -- '-DEV-' && bad "a DEV step is on the card" || okk "no DEV step on the card ($(ls "$C/octophonic/recipe/steps" | wc -l) steps)"
if [ -s "$C/menu.rbf.stock" ]; then okk "menu.rbf: the navy menu core (stock kept as menu.rbf.stock)"; else echo "  note: menu.rbf is the stock one (no navy menu core was built yet)"; fi

echo "-- nothing personal or DEV in what Octophonic added"
# the files that are not byte-for-byte the official release's: compare 7-Zip's CRCs
OFF=${OFFICIAL_7Z:-}
"$Z" l -slt "$W/fat/release.7z" | awk '/^Path = /{p=substr($0,8)} /^CRC = /{print $3"\t"p}' | LC_ALL=C sort > "$W/ours.crc"
if [ -n "$OFF" ] && [ -s "$OFF" ]; then
    "$Z" l -slt "$OFF" | awk '/^Path = /{p=substr($0,8)} /^CRC = /{print $3"\t"p}' | LC_ALL=C sort > "$W/off.crc"
    LC_ALL=C comm -23 "$W/ours.crc" "$W/off.crc" | cut -f2 | grep -v '^$' > "$W/added.txt"
else
    awk -F'\t' '{print $2}' "$W/ours.crc" > "$W/added.txt"     # (no official list: check everything)
fi
echo "  files Octophonic added or changed: $(wc -l < "$W/added.txt")"
sed 's/^/    /' "$W/added.txt"
# in every file (binaries too): a key, a share, an address. In text files also PC paths (C:\, \\server)
PATS='OCTOPHONIC SSH KEY|octophonic-key|ssh-rsa AAAA|ssh-ed25519 AAAA|BEGIN OPENSSH|MiSTerBridge|192\.168\.[0-9]|10\.0\.[0-9]+\.[0-9]|SERVER="?[A-Za-z0-9]'
TPATS='C:\\|\\\\[A-Za-z0-9]|cifs_mount'
HITS=0
while IFS= read -r f; do
    [ -f "$W/card/$f" ] || continue
    # PC-path patterns only for real text files: a .reu/.prg/.d64 is random bytes that can contain "\\x" by chance
    case "$f" in *.reu|*.REU|*.prg|*.PRG|*.d64|*.crt|*.CHP|*.chp|*.rbf|*.img) TP='';; *) TP="$TPATS";; esac
    if grep -a -q -E "$PATS" "$W/card/$f" 2>/dev/null || { [ -n "$TP" ] && grep -I -q -E "$TP" "$W/card/$f"; } 2>/dev/null; then
        echo "    HIT in $f:"; grep -a -o -E ".{0,30}($PATS).{0,30}" "$W/card/$f" | head -3 | sed 's/^/      /'
        { [ -n "$TP" ] && grep -I -o -E ".{0,30}($TP).{0,30}" "$W/card/$f"; } 2>/dev/null | head -3 | sed 's/^/      /'; HITS=1
    fi
done < "$W/added.txt"
[ "$HITS" = 0 ] && okk "no SSH key, share, IP address or PC path in any of them" || bad "personal strings found (above)"
# MiSTer.ini must be MiSTer's own example plus the bootcore lines and vsync_adjust=2 (step 065, Fix 43)
# and nothing else (so no one's video, share or other settings can be in it)
if diff <(grep -v -E 'bootcore|^[[:space:]]*vsync_adjust' "$C/MiSTer_example.ini") <(grep -v -E 'bootcore|^[[:space:]]*vsync_adjust' "$INI") > "$W/ini.diff"; then
    okk "MiSTer.ini is MiSTer's own example + the bootcore lines + vsync_adjust, nothing else"
else bad "MiSTer.ini differs from MiSTer_example.ini beyond bootcore and vsync_adjust:"; cat "$W/ini.diff"; fi
V=$(grep -E '^[[:space:]]*vsync_adjust' "$INI" | tr -d ' \r' | sort -u)
[ "$V" = "vsync_adjust=2" ] && okk "vsync_adjust=2 (Fix 43: HDMI follows the core's 50 Hz)" || bad "vsync_adjust is not 2 everywhere: $V"
[ -e "$C/linux/octophonic-key.pub" ] && bad "the SSH key file is on the card" || okk "no linux/octophonic-key.pub"
grep -q 'OCTOPHONIC SSH KEY' "$C/linux/user-startup.sh" 2>/dev/null && bad "the SSH block is in user-startup.sh" || okk "no SSH block in linux/user-startup.sh"
find "$W/card" "$W/fat" -iname '*kernal*' -o -iname '*basic*.bin' -o -iname '*chargen*' -o -iname '*.rom' 2>/dev/null | grep -v -i 'mt32\|soundfont' | sed 's/^/  rom-like name: /'

echo
echo "-- will it install (Mr. Fusion unpacks the whole card into RAM, /tmp, before writing it)"
# Build 2 (499 MB) ran the DE10-Nano out of RAM part way through the unpack; Mr. Fusion's
# installer does not check for that, so it wrote a half card (no menu.rbf: a black screen).
# MiSTer's own release alone unpacks to about 398 MB (linux.img is 375 MB of it) and installs;
# /tmp is a tmpfs, half the 1 GB RAM at most - so keep within about 50 MB of the official size.
LIMIT_MB=${OCTO_TREE_LIMIT_MB:-450}
TREE_MB=$(( $(du -sk "$C" | cut -f1) / 1024 ))
if [ "$TREE_MB" -le "$LIMIT_MB" ]; then okk "the card unpacks to $TREE_MB MB (limit $LIMIT_MB MB)"
else bad "the card unpacks to $TREE_MB MB - over the $LIMIT_MB MB limit, Mr. Fusion cannot install it"; fi
M=$(stat -c %s "$C/menu.rbf" 2>/dev/null || echo 0)
[ "$M" -gt 1048576 ] && okk "menu.rbf is there ($M bytes)" || bad "menu.rbf missing or too small ($M bytes)"
for f in linux/uboot.img octophonic/os.ini octophonic/SHELL.PRG octophonic/steps-done.txt; do
    [ -s "$C/$f" ] && okk "$f is there ($(stat -c %s "$C/$f") bytes)" || bad "$f missing or empty"
done
Z0=$(find "$C" -type f -size 0 | sed "s|^$C/||")
[ -z "$Z0" ] && okk "no empty (0-byte) file anywhere" || { bad "empty files:"; echo "$Z0" | sed 's/^/      /'; }

if [ "$FAIL" = 0 ]; then echo "IMAGE_OK"; else echo "IMAGE_FAILED"; exit 1; fi
