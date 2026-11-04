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
echo "  games/C64 files (should be none - the tree is empty):  $(find "$C/games/C64" -type f | wc -l)"
[ "$(find "$C/games/C64" -type f | wc -l)" = 0 ] && okk "games/C64 is an empty tree" || bad "files in games/C64"
for d in Demos Games Apps Code Music SIDs Pictures "My Chips" Disks Screenshots Saves; do
    [ -d "$C/games/C64/$d" ] || bad "no games/C64/$d"
done

echo "-- straight into Octophonic"
INI="$C/MiSTer.ini"
BC=$(grep -E '^[[:space:]]*bootcore[[:space:]]*=' "$INI" | sed 's/[[:space:]]*;.*//')
echo "  MiSTer.ini: $BC"
grep -E '^[[:space:]]*;?[[:space:]]*bootcore_timeout' "$INI" | sed 's/^/  MiSTer.ini: /'
[ "$BC" = "bootcore=Octophonic 64.mgl" ] && okk "bootcore is the Octophonic launcher" || bad "bootcore is not 'Octophonic 64.mgl'"
grep -qE '^[[:space:]]*bootcore_timeout[[:space:]]*=' "$INI" && bad "a bootcore_timeout is active (it shows the menu)" || okk "no bootcore_timeout (the core loads before the menu draws anything)"
[ -s "$C/_Computer/Octophonic 64.mgl" ] && okk "_Computer/Octophonic 64.mgl is there" || bad "no launcher"
grep -q '<setname' "$C/_Computer/Octophonic 64.mgl" && okk "the launcher has its setname line" || bad "no setname"
ls "$C"/_Computer/.C64_Octophonic_*.rbf >/dev/null 2>&1 && okk "the hidden core: $(cd "$C/_Computer" && ls -A | grep '^\.C64_Octophonic')" || bad "no hidden core"
grep -q 'Octophonic OS' "$C/MiSTer" && okk "MiSTer is Octophonic Main (stock kept as MiSTer.orig: $([ -s "$C/MiSTer.orig" ] && echo yes || echo NO))" || bad "MiSTer is not Octophonic Main"
[ "$(od -A n -t x1 -N 2 "$C/octophonic/SHELL.PRG" | tr -d ' \n')" = 00c0 ] && okk "octophonic/SHELL.PRG (loads at \$C000)" || bad "SHELL.PRG"
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
PATS='OCTOPHONIC SSH KEY|octophonic-key|ssh-rsa AAAA|ssh-ed25519 AAAA|BEGIN OPENSSH|MiSTerBridge|SIDWeaver|192\.168\.[0-9]|10\.0\.[0-9]+\.[0-9]|SERVER="?[A-Za-z0-9]'
TPATS='C:\\|\\\\[A-Za-z0-9]|cifs_mount'
HITS=0
while IFS= read -r f; do
    [ -f "$W/card/$f" ] || continue
    if grep -a -q -E "$PATS" "$W/card/$f" 2>/dev/null || grep -I -q -E "$TPATS" "$W/card/$f" 2>/dev/null; then
        echo "    HIT in $f:"; grep -a -o -E ".{0,30}($PATS).{0,30}" "$W/card/$f" | head -3 | sed 's/^/      /'
        grep -I -o -E ".{0,30}($TPATS).{0,30}" "$W/card/$f" 2>/dev/null | head -3 | sed 's/^/      /'; HITS=1
    fi
done < "$W/added.txt"
[ "$HITS" = 0 ] && okk "no SSH key, share, IP address or PC path in any of them" || bad "personal strings found (above)"
# MiSTer.ini must be MiSTer's own example plus the bootcore lines and nothing else (so no one's video,
# share or other settings can be in it)
if diff <(grep -v -E 'bootcore' "$C/MiSTer_example.ini") <(grep -v -E 'bootcore' "$INI") > "$W/ini.diff"; then
    okk "MiSTer.ini is MiSTer's own example + the bootcore lines, nothing else (video: MiSTer's defaults)"
else bad "MiSTer.ini differs from MiSTer_example.ini beyond bootcore:"; cat "$W/ini.diff"; fi
[ -e "$C/linux/octophonic-key.pub" ] && bad "the SSH key file is on the card" || okk "no linux/octophonic-key.pub"
grep -q 'OCTOPHONIC SSH KEY' "$C/linux/user-startup.sh" 2>/dev/null && bad "the SSH block is in user-startup.sh" || okk "no SSH block in linux/user-startup.sh"
find "$W/card" "$W/fat" -iname '*kernal*' -o -iname '*basic*.bin' -o -iname '*chargen*' -o -iname '*.rom' 2>/dev/null | grep -v -i 'mt32\|soundfont' | sed 's/^/  rom-like name: /'

echo
if [ "$FAIL" = 0 ]; then echo "IMAGE_OK"; else echo "IMAGE_FAILED"; exit 1; fi
