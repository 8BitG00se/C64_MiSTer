# The Octophonic SD card

One folder tree for both machines. On the MiSTer it is the SD card, `/media/fat`. The Octophonic 64
Emulator has the same tree as its `SD card` folder, next to the emulator. A file put where the MiSTer
has it is where the emulator finds it.

Every folder outside `games/C64` is one that something already uses:
- Octophonic Main: `tools/octoos/main/octophonic-main.patch`, which has `OS_DIR`, `OS_TOP`, `CHIP_DIR`,
  `NET_SEEN`, `OS_LAST` and the boot code.
- The core install: `tools/install/install_core.sh`.
- MiSTer itself: `menu.rbf`, `Scripts/`, `screenshots/`.

The eleven folders in `games/C64` (build 6, Neal's list) are the browser's SD CARD drive: Demos,
Games, Apps, Code, Music, SIDs, Pictures, My Chips, Disks, Screenshots, Saves. os.ini's `start=` is
`/media/fat/games/C64`.

```
/media/fat/                                  the SD card (MiSTer)  =  "SD card/" (the emulator)
|
+-- menu.rbf                                 MiSTer's own menu core (C=+F1 goes here: MENU, $12)
|
+-- _Computer/
|   +-- .C64_Octophonic_<date>_<tag>.rbf     the core, hidden (install_core.sh puts it here;
|   |                                         one at a time, the newest by core number)
|   +-- Octophonic 64.mgl                    the launcher: os.ini's boot= (default)
|   +-- Octophonic 64 <preset>.mgl           chip presets (F8 CHIP PRESET lists "Octophonic 64*.mgl")
|
+-- _Octophonic/
|   +-- core.txt                             the core in place: NAME=, ORDER= (install_core.sh)
|   +-- old cores/                           every core replaced, kept (nothing is deleted)
|
+-- octophonic/                              Octophonic OS (Main's OS_DIR)
|   +-- os.ini                               enabled=1, boot=, startin=, start= (docs/OCTOOS.md);
|   |                                         without it Main is the stock Main
|   +-- SHELL.PRG                            the browser (F1) and the start jingle; built by
|   |                                         tools/octoos/kernal/build.sh (missing: no browser, silence)
|   +-- os.log, os.log.1                     Main's log (written by Main)
|   +-- net.seen                             a network share has been seen (written by Main)
|   +-- last.txt                             the last folder, for START IN: LAST USED (Main)
|
+-- games/
|   +-- C64/                                 the browser's SD CARD drive (F1, then SD CARD)
|       +-- Demos/                           one folder per demo build: its .prg and its .reu
|       |   +-- <demo name> build <N>/        (the browser runs the .prg; the .reu of the same
|       |       +-- <demo>.prg                 name, or the folder's only one, goes in first)
|       |       +-- <demo>.reu
|       +-- Games/                           games: .prg .crt .d64 ..., a folder each if you like
|       +-- Apps/                            programs that make things: OCTOCODE.PRG (the code
|       |                                     editor); later SIDWeaver Lite, OctoPaint
|       +-- Code/                            your source code (.asm) and what it makes
|       +-- Music/                           music programs and tunes as .prg
|       +-- SIDs/                            SID tunes (the browser runs .prg; a raw .sid is not
|       |                                     one of the core's file types, so it isn't listed)
|       +-- Pictures/                        pictures (viewers as .prg)
|       +-- My Chips/                        your own measured chips: *.CHP (F8 MY CHIP LEFT / RIGHT)
|       +-- Disks/                           loose disk and cartridge images: .d64 .g64 .t64 .d81 .crt
|       +-- Screenshots/                     SHOT's pictures when there is no network share
|       +-- Saves/                           saved games and the files programs write
|
|                                            All eleven are EMPTY on a fresh card: you fill them.
|                                            (An all-in-one image may bake apps into Apps/: a later
|                                            recipe step, not 010.)
|
+-- Scripts/                                 MiSTer's scripts (Main reads cifs_mount.ini / .sh for
|                                             a network share; the Octophonic updater goes here)
|
+-- screenshots/                            MiSTer's own (Win+PrtScn)
```

The network share is the browser's NETWORK drive, not part of the card. On the MiSTer it is
`games/00-NETWORK/C64` or `/media/network/C64` (os.ini `start=`). On Neal's PC it is
`C:\MiSTerBridge\Games\C64`. The emulator uses that same share by default (F12 > Octophonic 64 >
Games folder). Demos on the share go in `Octophonic/<demo name> build <N>/` (where the
demos' Install .bats put them); on the card they go in `Demos/`.

## The emulator

The emulator's runtime folder (`rt/` in its tree, and the Windows package) has:

| Path | What |
|---|---|
| `x64sc` (`x64sc.exe`) | the emulator |
| `ROMs/` | your own C64 ROMs (checked by CRC; the Octophonic KERNAL is made from them) |
| `SD card/` | **the SD card above, the same tree**: `games/C64` is its SD CARD drive (Demos, Games, SIDs, My Chips, Disks - empty), `octophonic/SHELL.PRG` its browser. `.CHP` files in `games/C64/My Chips` join the emulator's own `Chips/` |
| `MiSTerBridge/Games/C64` (test runtime only) | a stand-in for the network share |

An older emulator folder with `octophonic/SHELL.PRG` beside the emulator still works: the emulator
uses that file when `SD card/octophonic/SHELL.PRG` is missing. The emulator never reads
`_Computer`, `_Octophonic` or `Scripts`. They are there so that one tree, or one SD image, fits both
machines.

The emulator is not a MiSTer. Its Main model leaves NET b5 clear, so it never offers the MiSTer's
menu (C=+F1). `OCTO_MISTER=1` sets the bit, for testing only; MENU is then logged and shown as a
banner.

## Making the card (the updater, the SD image)

Steps 1-3 are what the Install .bats already do. Step 4 is new. Steps 5-6 cover the demos and the card.

1. Put the core in `_Computer/` with `install_core.sh <rbf> <core number>` (`tools/install`). It
   records `_Octophonic/core.txt` and never replaces a newer core without asking.
2. Put the launcher `_Computer/Octophonic 64.mgl` in place, if it is missing.
3. Copy `octophonic/SHELL.PRG` and write `octophonic/os.ini` (keep the user's own, if there is one).
4. A new KERNAL gets onto the MiSTer only inside a new core (`.rbf`): the ROM is in the FPGA image
   (`rtl/roms/octo_C64.mif`). A new SHELL.PRG is a plain file copy.
5. Put demos in `games/C64/Demos/<demo name> build <N>/`, with their `.reu`.
6. Leave `Scripts/`, `screenshots/` and `menu.rbf` as MiSTer has them.

For the emulator, the same `SD card/` folder goes next to `x64sc.exe` (step 3's SHELL.PRG and step 5's
demos; steps 1, 2 and 4 don't apply).
