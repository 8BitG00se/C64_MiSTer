#!/bin/sh
# THE KERNAL, ONE SOURCE, TWO TARGETS - the one command after any change in here:
#   1 assembles octo.asm (the start screen), wedge.asm, wedge2.asm (Octophonic OS's commands)
#   2 patches them into Commodore's BASIC and KERNAL (patch.py) -> octo64.bin
#   3 the core's ROM: rtl/roms/octo_C64.mif (mkmif.py) - what the next core build carries
#   4 the Octophonic 64 Emulator's ROM: its octo_rompatch.h (the emulator's tools/mkpatch.py, made
#     from that same .mif), its SHELL.PRG (rt/SD card/octophonic) and, if built there, its headless
#     x64sc (copied into rt/, the runtime, beside its SD card)
#   5 SHELL.PRG (the browser)
#   6 romtest: the new ROM against the stock ROMs, side by side (../test/romtest.cpp)
# so a KERNAL change can never be in one and not the other.
#   OCTO_EMU      the emulator's tree (tools/mkpatch.py, src/vice/src/octophonic, rt/) - needed
#   OCTO_MACHINE  a folder with C64Machine.h (SIDWeaver's Source/Emulation, with Source above it) - romtest
#   VICE_DATA     VICE's data (default /usr/local/share/vice): the stock ROMs, for std.bin and romtest
#   OCTO_NOTEST=1 skip romtest (it takes about five minutes)
# Never committed: std.bin, octo64.bin and every other .bin (Commodore's ROMs) - see .git/info/exclude.
set -e
cd "$(dirname "$0")"
K=$(pwd); R=$(cd ../../.. && pwd); V=${VICE_DATA:-/usr/local/share/vice}
[ -n "$OCTO_EMU" ] && [ -f "$OCTO_EMU/tools/mkpatch.py" ] || { echo "build.sh: set OCTO_EMU to the emulator's tree (so its ROM stays the core's)"; exit 1; }
T=${TMPDIR:-/tmp}/octokernal; mkdir -p "$T/roms"
[ -f std.bin ] || cat "$V/C64/basic-901226-01.bin" "$V/C64/kernal-901227-03.bin" > std.bin
acme -f plain -o octo.bin -l octo.lbl octo.asm
acme -f plain -o wedge.bin -l wedge.lbl wedge.asm
acme -f plain -o wedge2.bin -l wedge2.lbl wedge2.asm
python3 patch.py "$T/roms"
python3 refscan.py                                  # no piece over stock code something still calls
cp "$V/C64/chargen-901225-01.bin" "$T/roms/"
python3 mkmif.py "$R/rtl/roms/octo_C64.mif"
P="$OCTO_EMU/src/vice/src/octophonic/octo_rompatch.h"
python3 "$OCTO_EMU/tools/mkpatch.py" "$OCTO_EMU/tools" "$R/rtl/roms/octo_C64.mif" "$R/rtl/roms/std_C64.mif" \
    "$T/octo_rompatch.h" "$R/rtl/iec_drive/c1541_rom.mif" "$V/DRIVES/dos1541-325302-01+901229-05.bin"
cmp -s "$T/octo_rompatch.h" "$P" || cp "$T/octo_rompatch.h" "$P"          # (only when it changed: no needless rebuild)
acme -f cbm -o shell.prg shell.asm 2>&1 | grep -v "Output file already chosen" || true
[ -d "$OCTO_EMU/rt/SD card/octophonic" ] && cp shell.prg "$OCTO_EMU/rt/SD card/octophonic/SHELL.PRG"
if [ -f "$OCTO_EMU/src/build-headless/Makefile" ]; then
    make -k -s -j8 -C "$OCTO_EMU/src/build-headless" > "$T/emu-build.log" 2>&1 || true   # (other VICE tools there may not link)
    [ ! "$P" -nt "$OCTO_EMU/src/build-headless/src/x64sc" ] || { echo "build.sh: the emulator's x64sc did not rebuild ($T/emu-build.log)"; exit 1; }
    [ -d "$OCTO_EMU/rt" ] && cp "$OCTO_EMU/src/build-headless/src/x64sc" "$OCTO_EMU/rt/x64sc"   # the runtime (rt/: its SD card)
fi
ls -la octo64.bin shell.prg
[ -n "$OCTO_NOTEST" ] && exit 0
[ -n "$OCTO_MACHINE" ] && [ -f "$OCTO_MACHINE/C64Machine.h" ] || { echo "build.sh: set OCTO_MACHINE for romtest (or OCTO_NOTEST=1)"; exit 1; }
S=$(cd "$OCTO_MACHINE/.." && pwd)
g++ -O2 -std=c++17 -I"$OCTO_MACHINE" -I"$S" -o "$T/romtest" ../test/romtest.cpp "$OCTO_MACHINE/C64Machine.cpp" "$OCTO_MACHINE/Mos6510.cpp" "$OCTO_MACHINE/SidTune.cpp" "$S/SidChip.cpp"
sh ../test/mktest.sh "$T/data" > /dev/null
REFDIR=${REFDIR:-$K/../test} "$T/romtest" "$V/C64" "$T/roms" "$V/DRIVES/dos1541-325302-01+901229-05.bin" "$T/data/test.d64" "$T/data/folder" "$K/shell.prg" $ROMTEST_FILTER
