#!/bin/bash
# OCTOPHONIC FUSION - builds "Octophonic Fusion build N.img": one card image to flash from the PC.
#
# It is Mr. Fusion (MiSTer's own universal installer image, github.com/MiSTer-devel/mr-fusion)
# carrying an Octophonic MiSTer instead of the plain one: on the first power-on Mr. Fusion grows the
# card to its full size, puts everything on it and restarts - into Octophonic 64.
#
#   1. the official MiSTer base: Mr. Fusion's release image (its bootloader, Linux and installer),
#      and the newest MiSTer release from MiSTer-devel/SD-Installer-Win64_MiSTer
#   2. that release unpacked onto a fresh card tree
#   3. this recipe's steps run onto it - every step EXCEPT the -DEV- ones (OCTO_DEV is never set
#      here), so no SSH key, no network share, no CRT video settings can get in
#   4. the card packed back up as Mr. Fusion's release.7z, with the Octophonic install picture
#   5. the image written (tools/sdcard/image/octofat.py), then opened again and checked
#
#   OCTO_BUILD=1 tools/sdcard/build-image.sh [OUTDIR]
#
# Settings: OCTO_BUILD (the build number in the name, default 1), OCTO_WORK (scratch room, about
# 1.5 GB; default /dev/shm/octofusion when there is room, else $TMPDIR), MRFUSION (Mr. Fusion's
# release, default v2.10), MISTER_RELEASE (default: the newest), OCTO_CORE / OCTO_MAIN /
# OCTO_MENU (use these files instead of the built ones). Needs: git, curl, python3, acme, gcc+make
# (7-Zip is built from its own source if there is no 7zz/7z here). No Commodore ROMs are involved:
# the KERNAL is inside the core's FPGA image.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
BUILD=${OCTO_BUILD:-1}
OUT=${1:-$PWD}
MRF=${MRFUSION:-v2.10}
NAME="Octophonic Fusion build $BUILD"
if [ -z "${OCTO_WORK:-}" ]; then
    if [ -d /dev/shm ] && [ "$(df -Pk /dev/shm | awk 'NR==2{print $4}')" -gt 2500000 ]; then OCTO_WORK=/dev/shm/octofusion
    else OCTO_WORK=${TMPDIR:-/tmp}/octofusion; fi
fi
W=$OCTO_WORK
say() { printf '\n== %s\n' "$*"; }
die() { printf '\n!! %s\n' "$*" >&2; exit 1; }
mkdir -p "$W" "$OUT"
echo "building: $NAME"
echo "work:     $W"
echo "out:      $OUT"

# --------------------------------------------------------------------------------- tools
say "tools"
Z=$(command -v 7zz || command -v 7z || true)
if [ -z "$Z" ]; then
    Z="$W/7zip/CPP/7zip/Bundles/Alone2/b/g/7zz"
    if [ ! -x "$Z" ]; then
        echo "no 7-Zip here: building it from its source (github.com/ip7z/7zip)"
        rm -rf "$W/7zip"
        GIT_LFS_SKIP_SMUDGE=1 git clone -q --depth 1 https://github.com/ip7z/7zip "$W/7zip"
        (cd "$W/7zip/CPP/7zip/Bundles/Alone2" && make -s -j4 -f ../../cmpl_gcc.mak >/dev/null)
    fi
fi
[ -x "$Z" ] || die "no 7-Zip"
echo "7-Zip: $Z"
command -v acme >/dev/null || die "acme is needed to build SHELL.PRG"
command -v python3 >/dev/null || die "python3 is needed"

# --------------------------------------------------------------------- 1. the official base
say "1. the official MiSTer base"
mkdir -p "$W/dl"
MZ="$W/dl/mr-fusion-$MRF.img.zip"
if [ ! -s "$MZ" ]; then
    curl -fsSL --retry 3 -o "$MZ.part" "https://github.com/MiSTer-devel/mr-fusion/releases/download/$MRF/mr-fusion-$MRF.img.zip" \
        || die "could not fetch Mr. Fusion $MRF from github.com/MiSTer-devel/mr-fusion/releases"
    mv "$MZ.part" "$MZ"
fi
echo "Mr. Fusion $MRF: $(sha256sum "$MZ" | cut -c1-16)...  $(stat -c %s "$MZ") bytes"
rm -rf "$W/mrf"; mkdir -p "$W/mrf"
(cd "$W/mrf" && unzip -q "$MZ")
BASE=$(ls "$W"/mrf/*.img | head -1)
[ -s "$BASE" ] || die "no .img in the Mr. Fusion zip"
P1S=$(python3 -I -c "import struct,sys;d=open(sys.argv[1],'rb').read(512);print(*struct.unpack('<II',d[454:462]))" "$BASE")
dd if="$BASE" of="$W/mrf/p1.fat" bs=512 skip=${P1S% *} count=${P1S#* } status=none
mkdir -p "$W/mrf/p1"
"$Z" x -y -o"$W/mrf/p1" "$W/mrf/p1.fat" >/dev/null || die "could not open Mr. Fusion's data partition"
[ -s "$W/mrf/p1/zImage" ] && [ -s "$W/mrf/p1/release.7z" ] || die "Mr. Fusion's partition is not as expected"
echo "Mr. Fusion files: $(ls "$W/mrf/p1" | tr '\n' ' ')"
rm -f "$W/mrf/p1.fat" "$W/mrf/p1/release.7z"       # (its own older release is replaced; RAM is short)

SDI="$W/sdi"
if [ ! -d "$SDI/.git" ]; then
    rm -rf "$SDI"
    GIT_LFS_SKIP_SMUDGE=1 git clone -q --depth 1 --filter=blob:none --no-checkout \
        https://github.com/MiSTer-devel/SD-Installer-Win64_MiSTer "$SDI" || die "could not reach MiSTer-devel/SD-Installer-Win64_MiSTer"
fi
REL=${MISTER_RELEASE:-$(git -C "$SDI" ls-tree --name-only HEAD | sed -n 's/^\(release_[0-9]\{8\}\)\.7z.*/\1/p' | sort -u | tail -1)}
[ -n "$REL" ] || die "no release_*.7z in SD-Installer-Win64_MiSTer"
PARTS=$(git -C "$SDI" ls-tree --name-only HEAD | grep "^$REL\.7z" || true)
[ -n "$PARTS" ] || die "$REL is not in SD-Installer-Win64_MiSTer"
# only this release's blobs are fetched (the clone has none: --filter=blob:none), straight to files
mkdir -p "$W/relparts"
for p in $PARTS; do
    if [ ! -s "$W/relparts/$p" ]; then
        git -C "$SDI" show "HEAD:$p" > "$W/relparts/$p.part" && mv -f "$W/relparts/$p.part" "$W/relparts/$p"
    fi
    [ -s "$W/relparts/$p" ] || die "could not fetch $p"
done
FIRST=$(echo "$PARTS" | head -1)
echo "MiSTer release: $REL  ($(echo $PARTS | wc -w) part(s), SD-Installer-Win64_MiSTer $(git -C "$SDI" rev-parse --short HEAD))"

# --------------------------------------------------------------------- 2. the card tree
say "2. the release onto a fresh card"
rm -rf "$W/rel"; mkdir -p "$W/rel"
"$Z" x -y -o"$W/rel" "$W/relparts/$FIRST" >/dev/null || die "could not unpack $REL"
CARD="$W/rel/files"
[ -s "$CARD/MiSTer" ] && [ -s "$CARD/menu.rbf" ] && [ -s "$CARD/linux/linux.img" ] || die "$REL has no files/MiSTer, menu.rbf, linux/linux.img"
echo "card: $(du -sh "$CARD" | cut -f1), stock MiSTer $(md5sum < "$CARD/MiSTer" | cut -c1-8)"

# --------------------------------------------------------------------- 3. the payload
say "3. the payload and the recipe"
PAY="$W/payload"; rm -rf "$PAY"; mkdir -p "$PAY/_Computer"
for b in build-reports octoos-main-build octo-menu-build; do
    git -C "$REPO" fetch -q origin "+refs/heads/$b:refs/remotes/origin/$b" 2>/dev/null || echo "(no $b branch yet)"
done
HEADC=$(git -C "$REPO" rev-parse --short HEAD)

# a built thing is used only if it was built from a commit whose source for it is the same as here
same_src() {   # same_src <commit> <path>...  -> true when nothing under the paths differs from HEAD
    local c=$1; shift
    git -C "$REPO" cat-file -e "$c^{commit}" 2>/dev/null || return 1
    git -C "$REPO" diff --quiet "$c" HEAD -- "$@"
}
built_from() { git -C "$REPO" show "origin/$1:result.txt" 2>/dev/null | awk '{print $2}'; }
built_ok()   { git -C "$REPO" show "origin/$1:result.txt" 2>/dev/null | awk '{print $1}'; }

# the core: its KERNAL (rtl/roms/octo_C64.mif) must be this commit's, as SHELL.PRG calls into it
if [ -n "${OCTO_CORE:-}" ]; then cp "$OCTO_CORE" "$PAY/"
else
    C=$(built_from build-reports)
    RBF=$(git -C "$REPO" ls-tree --name-only origin/build-reports 2>/dev/null | grep '^C64_Octophonic_.*\.rbf$' | head -1 || true)
    [ "$(built_ok build-reports)" = success ] && [ -n "$RBF" ] || die "no successful core build on build-reports"
    same_src "$C" rtl c64.sv files.qip C64.qsf sys || die "the core on build-reports was built from $C, whose core source differs from $HEADC - wait for the core build of this commit (or set OCTO_CORE)"
    git -C "$REPO" show "origin/build-reports:$RBF" > "$PAY/$RBF"
    echo "core: $RBF (built from $C, same core source as $HEADC)"
fi
cp "$REPO/tools/install/core-number.txt" "$REPO/tools/install/install_core.sh" "$PAY/"
# Octophonic Main: built from the same tools/octoos/main as here
if [ -n "${OCTO_MAIN:-}" ]; then cp "$OCTO_MAIN" "$PAY/MiSTer"
else
    C=$(git -C "$REPO" show origin/octoos-main-build:result.txt 2>/dev/null | awk '{print $1}')
    [ -n "$C" ] || die "no Octophonic Main on octoos-main-build"
    same_src "$C" tools/octoos/main .github/workflows/octoos-main.yml || die "Octophonic Main on octoos-main-build was built from $C, whose patch differs from $HEADC - wait for its build (or set OCTO_MAIN)"
    git -C "$REPO" show origin/octoos-main-build:MiSTer > "$PAY/MiSTer"
    git -C "$REPO" show origin/octoos-main-build:acme > "$PAY/acme" || die "no acme on octoos-main-build (OCTOCODE's compiler)"
    echo "Main: built from $C (same patches as $HEADC), $(md5sum < "$PAY/MiSTer" | cut -c1-8)"
fi
grep -q 'Octophonic OS' "$PAY/MiSTer" || die "that MiSTer is not Octophonic Main"
[ -s "$PAY/acme" ] || { [ -n "${OCTO_ACME:-}" ] && cp "$OCTO_ACME" "$PAY/acme"; }
[ -s "$PAY/acme" ] || die "no acme for step 055 (set OCTO_ACME)"
grep -q 'COMPILE' "$PAY/MiSTer" || die "that Main has no COMPILE (octophonic-compile.patch)"
# the front-screen cards (step 085)
if [ -d "$HERE/files/tty2oled" ]; then cp -r "$HERE/files/tty2oled" "$PAY/"; else echo "no front-screen cards here (step 085 skips: a fresh card has no tty2oled)"; fi
# OCTOCODE, the code editor, from this commit's source (step 055 puts it in Apps)
acme -f cbm -o "$PAY/OCTOCODE.PRG" "$REPO/tools/octoos/octocode/octocode.asm"
echo "OCTOCODE.PRG: $(stat -c %s "$PAY/OCTOCODE.PRG") bytes"
# no menu core in the payload: since build 4 the stock (white noise) menu.rbf stays; step 095 puts
# it back on a card that had the navy one
rm -f "$PAY/menu.rbf"
# SHELL.PRG from this commit's source
acme -f cbm -o "$PAY/SHELL.PRG" "$REPO/tools/octoos/kernal/shell.asm"
echo "SHELL.PRG: $(stat -c %s "$PAY/SHELL.PRG") bytes"
# the example set for step 015 (something in every games/C64 folder, and the demos with their
# .reu files): OCTO_EXAMPLES=<a folder with MANIFEST.txt and games/>, else the sdcard-examples
# branch (binaries live there, not in this branch). OCTO_EXAMPLES=none leaves the folders empty.
if [ "${OCTO_EXAMPLES:-}" = none ]; then echo "example set: none (OCTO_EXAMPLES=none) - the games/C64 folders stay empty"
elif [ -n "${OCTO_EXAMPLES:-}" ]; then
    [ -s "$OCTO_EXAMPLES/MANIFEST.txt" ] || die "OCTO_EXAMPLES=$OCTO_EXAMPLES has no MANIFEST.txt"
    mkdir -p "$PAY/examples"; cp -r "$OCTO_EXAMPLES"/. "$PAY/examples/"
    echo "example set: $(wc -l < "$PAY/examples/MANIFEST.txt") files from $OCTO_EXAMPLES"
else
    git -C "$REPO" fetch -q origin "+refs/heads/sdcard-examples:refs/remotes/origin/sdcard-examples" \
        || die "no sdcard-examples branch to fetch (or set OCTO_EXAMPLES=<folder>, or =none)"
    git -C "$REPO" archive origin/sdcard-examples examples | tar -x -C "$PAY" || die "could not unpack the example set"
    [ -s "$PAY/examples/MANIFEST.txt" ] || die "the sdcard-examples branch has no examples/MANIFEST.txt"
    (cd "$PAY/examples" && md5sum -c --quiet MANIFEST.txt) || die "the example set does not match its MANIFEST.txt"
    echo "example set: $(wc -l < "$PAY/examples/MANIFEST.txt") files, $(du -sh "$PAY/examples" | cut -f1), sdcard-examples $(git -C "$REPO" rev-parse --short origin/sdcard-examples)"
fi
# the launcher (the plain one: its chip presets need chip files, which are not part of the image)
cat > "$PAY/_Computer/Octophonic 64.mgl" <<'MGL'
<mistergamedescription>
    <rbf>_Computer/.C64_Octophonic</rbf>
    <setname same_dir="1">Octophonic64</setname>
</mistergamedescription>
MGL

# the recipe: every step but the DEV ones, onto the card
rm -rf "$W/recipe"; mkdir -p "$W/recipe"
cp -r "$HERE/run-steps.sh" "$HERE/octo-step-lib.sh" "$HERE/steps" "$W/recipe/"
env -u OCTO_DEV -u OCTO_FORCE -u OCTO_ONLY -u OCTO_LIST OCTO_ROOT="$CARD" OCTO_PAYLOAD="$PAY" \
    sh "$W/recipe/run-steps.sh" | tee "$W/recipe.log"
grep -q '^RECIPE_OK' "$W/recipe.log" || die "the recipe did not finish"
grep -q -- '-DEV-' "$CARD/octophonic/steps-done.txt" && die "a DEV step ran"
# the recipe itself goes on the card, so the updater can carry on from here
mkdir -p "$CARD/octophonic/recipe"
cp -r "$HERE/run-steps.sh" "$HERE/octo-step-lib.sh" "$CARD/octophonic/recipe/"
mkdir -p "$CARD/octophonic/recipe/steps"
for s in "$HERE"/steps/*.sh; do case "$(basename "$s")" in *-DEV-*) ;; *) cp "$s" "$CARD/octophonic/recipe/steps/" ;; esac; done
# the build's own leftovers: its backups of the stock files stay (MiSTer.orig, menu.rbf.stock are
# the way back), the run's backup folder is renamed so no build-machine time is in the name
for d in "$CARD"/octophonic/backups/run-*; do [ -d "$d" ] && mv "$d" "$CARD/octophonic/backups/image-build-$BUILD"; done
printf 'Octophonic Fusion build %s\nMiSTer %s, Mr. Fusion %s, source %s\n' "$BUILD" "$REL" "$MRF" "$HEADC" > "$CARD/octophonic/fusion-build.txt"

# --------------------------------------------------------------------- 4. release.7z + picture
say "4. Mr. Fusion's release.7z"
rm -rf "$W/fat"; cp -r "$W/mrf/p1" "$W/fat"
rm -f "$W/fat/release.7z"
# LZMA2, 64 MB dictionary, two threads: within this machine's RAM, and Mr. Fusion's 7zr (p7zip
# 16.02) unpacks it in well under 100 MB on the DE10-Nano. No BCJ filters (-mf=off).
(cd "$W/rel" && "$Z" a -t7z -m0=LZMA2:d=64m -mx=7 -mf=off -mmt=2 "$W/fat/release.7z" files >/dev/null) || die "could not pack release.7z"
"$Z" t "$W/fat/release.7z" >/dev/null || die "release.7z does not test good"
echo "release.7z: $(stat -c %s "$W/fat/release.7z") bytes"
python3 -I "$HERE/image/splash.py" "$W/fat/splash.png" 1920 1080

# --------------------------------------------------------------------- 5. the image
say "5. the image"
IMG="$OUT/$NAME.img"
SOURCE_DATE_EPOCH=$(git -C "$REPO" log -1 --format=%ct) python3 -I "$HERE/image/octofat.py" "$BASE" "$W/fat" "$IMG" OCTOFUSION
sed "s/@BUILD@/$BUILD/g; s/@REL@/$REL/g; s/@MRF@/$MRF/g" "$HERE/image/How to flash.txt" > "$OUT/How to flash.txt"
cp "$HERE/image/Check card.bat" "$OUT/"
echo "$(stat -c %s "$IMG") bytes: $IMG"

say "checking the image"
OFFICIAL_7Z="$W/relparts/$FIRST" bash "$HERE/image/check-image.sh" "$IMG" "$Z" "$W/check"
