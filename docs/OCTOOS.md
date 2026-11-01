# Octophonic OS (milestone 1, build 3)

The MiSTer starts straight into Octophonic 64, and the SD card is used from the READY prompt.
Nothing changes for a MiSTer without `/media/fat/octophonic/os.ini`.

## At READY

| Type | Does |
|---|---|
| `@` | the current folder, paged like a disk directory (any key: next page, RUN/STOP: stop) |
| `@NAME` | into folder NAME, then its directory (`@..` up) |
| `@/NAME` | the same, from the start folder; `@/` alone goes back to it; `@A/B` goes two down |
| `/NAME` | load and run NAME (.prg, or a .crt); a .d64/.g64/.d81 goes into drive 8 |

Names match whole, then without the extension, then by their start (`/HOR` finds `horizon.prg`).

Every request carries a number (SEQ) and waits up to 20 seconds for the answer with that number,
the border flickering while Main works (a folder on a network share can take a while); then
`?NO REPLY FROM OCTOPHONIC MAIN (CMD nn)`. In the browser, folder scans and loads show SCANNING... or
LOADING... and also wait 20 s; the settings wait 3 s.

## F1: the browser

F1 at READY (the editor waiting for a line, direct mode) clears the screen and types `@@`, which
loads `SHELL.PRG` from `/media/fat/octophonic` to `$C000` and runs it. F-keys and cursor keys only:

| Key | Does |
|---|---|
| cursor up/down, joystick 2 | move the bar |
| RETURN, fire | a folder: into it; a program or cartridge: load and run; a disk: into drive 8, then LOAD"*",8 and RUN |
| SHIFT+RETURN | a disk: into drive 8 only |
| F3, DEL, cursor left, joystick left | up a folder |
| F1 / F5 | page up / down |
| F2 | the start folder |
| HOME | the top of the folder |
| F8 | settings |
| F7, RUN/STOP | back to READY (the BASIC program is kept) |

RETURN on a `.reu` attaches it (as the menu does, no reset), then the list comes back with
`REU ATTACHED (16M)` on the status line and the bar on the `.prg` of the same name. RETURN on a
`.prg` attaches its `.reu` first (same name, or the only one in the folder) unless that very file is
attached already, so a 16 MB REU is never loaded twice. In each folder the `.prg` files come first
after the folders. `..` shows as `.. (UP A FOLDER)`; sizes are blocks under 1000, else K or M; a
name the C64 can't show comes out with `?`, never blank.

## Drives and the network

The top of the browser is the drives: **SD CARD** (`games/C64` on the card), **NETWORK** (the C64
folder of a network share) and **USB n** (`games/C64` on a stick). F3 from the top of a drive goes
up to them. NETWORK shows `OFF` while the share isn't connected (RETURN on it says so).

At power-on Main decides where to start (F8: START IN - NETWORK, SD CARD or LAST USED, saved as
`startin=` in os.ini; without it: the network if this MiSTer has a share set up, else the SD card).
A share is "set up" if one is mounted (cifs/smb/nfs in /proc/mounts), has been seen before on this
MiSTer, or MiSTer's cifs script has a SERVER. Both ways of mounting work: over `/media/fat/games`
(then `games/C64` is the share) and in a folder of its own (`games/00-NETWORK/C64`,
`/media/network/C64`); `start=` in os.ini, if it points at a folder on the share, is used.

While a share that is set up is still connecting, the start screen has a red dot at the end of the
title row (green once it is there; none at all without a share), and F1 shows
`PLEASE WAIT - CONNECTING TO NETWORK...` and opens the share's C64 folder the moment it mounts.
Any key, or 60 seconds, uses the SD card instead (`NO NETWORK - USING THE SD CARD`).

## Screenshots and reports (for the demos' self-tests)

`0C` SHOT takes a screenshot with MiSTer's own code (the scaler's picture, as Win+PrtScn) and saves
it as `<share C64 folder>/Octophonic/Screenshots/NAME.png` (no share: `/media/fat/screenshots/
Octophonic/NAME.png`). NAME may hold folders (`HORIZON/NIGHT-0351`); letters, digits, `- _ . /`.
Main answers at once and does the rest in the background: the picture is copied out of video memory
at the next vsync (NET bit 7 set from the request until that copy is done), then a worker thread
writes the PNG (NET bit 6) and Main copies it to the share. At most one a second; a SHOT while one
is under way is ignored. No message is put on the screen.

`0D` APPEND writes text for reports: VALUE `$FF` makes file ARG (0-3) the path NAME (under the same
Screenshots folder; folders are made); any other VALUE puts NAME's text (up to 32 characters,
PETSCII to ASCII) on the end of file ARG, with a new line unless VALUE bit 0 is set (a long line in
pieces). Not logged (there can be many).

CTRL+F11 (OS mode): a screenshot of whatever is running into `Screenshots/Manual`.

## Settings (F8)

Cursor up/down picks a line, left/right changes it, RETURN on CHIP PRESET starts it.
Lines: chip preset (the `_Computer/Octophonic 64*.mgl` launchers; the one started becomes `boot=` in
os.ini), my chip left/right (the `.CHP` files in `games/C64/My Chips`), START IN (network / SD card / last used), then the core's options:
Left/Right SIDs, My Chips, Octophonic, OctoSID FX, Split Screens, Turbo mode, Turbo speed.

## Same backend as the MiSTer menu

The C64 side is only a front end. Main lists folders with the menu's own `ScanDirectory` (the core's
file types `PRG CRT REU D64 G64 T64 D81`, the menu's sort, zips as folders), loads with
`c64_open_file` and the menu's indexes (PRG `0x01`, CRT `0x41`, REU `0x81`, chips `2`/`3` and their
remembered `.f2`/`.f3` like the menu's FC entries), mounts with `user_io_file_mount(path, 0)`, changes
options with `user_io_status_set` and saves with `user_io_status_save`, and starts a chip preset
with `xml_load`, as picking it in the menu does.

## The log

Main writes every request to `/media/fat/octophonic/os.log` (time, command, name, folder before and
after, the reply, how many ms it took; boot and errors too). It rolls over to `os.log.1` at 64 KB.

## Menu key, and out of a demo

Win+F12 (or the Menu key) opens the MiSTer menu; holding F12 for 2 seconds does too.

CTRL+F12 gets out of anything that is running - a demo that ignores RUN/STOP+RESTORE too: Main does
the menu's "Reset & Detach Cartridge" and the core starts again on the V1.1 start screen. The folder
is kept, so F1 opens the browser where it was. The REU keeps its contents (as with the menu's reset):
the next demo's own .reu goes in over it when it is run, the way the menu attaches a .reu.

## The pieces

- **The core** (`rtl/octovic/octo_os.sv`): the mailbox, 16 registers at `$D6F0-$D6FF` in OctoVIC's
  page (OctoVIC must be unlocked: `$4F`, `$38` to `$D03F`). No block RAM.
  Plus a raw download index `$0A`: bytes straight into RAM at the 2-byte address in front -
  no reset and no BASIC pointers, unlike the menu's PRG load (index 1).
- **The ROM** (`rtl/roms/octo_C64.mif`, sources in `tools/octoos/kernal`): the commands, in the tape
  room `$F72C-$F8FA`; the V1.1 start screen calls `osinit`, which points BASIC's IMAIN (`$0302`) at
  them. LOAD, SAVE and OPEN on device 1 give ?ILLEGAL DEVICE NUMBER, since the tape code is gone.
- **Octophonic Main** (`tools/octoos/main`: a patch on Main_MiSTer, built by
  `.github/workflows/octoos-main.yml` onto the branch `octoos-main-build`).

## The mailbox

| Reg | Name | 6502 | Main |
|---|---|---|---|
| F0 | CMD | write: the command (STATUS goes to 1) | reads |
| F1 | STATUS | 0 idle, 1 busy, 2 done, $80+n error | writes (ends the request) |
| F2/F3 | ADDR | where the answer goes ($A000 if 0) | reads |
| F4/F5 | LEN | DIR: first entry | DIR: next entry |
| F6 | ARG | LOAD b0: at ADDR, not the file's address | reads |
| F7 | VALUE | DIR: lines per page | DIR: 1 if more; RUN: 8 if a disk went in |
| F8 | NAME | write: next character (max 32); read: count | reads |
| F9 | | write: empty the name | |
| FA/FB | RESULT | read | DIR/INFO: bytes, LOAD: end address |
| FC | VERSION | read: 2 | |
| FD | SEQ | write: the request's number, before CMD | reads |
| FE | RSEQ | read: the number STATUS answers | writes it first in every reply |
| FF | NET | read: b1-0 the network share (0 none set up, 1 waiting for it, 2 there, 3 set up but not there), b7 a screenshot is being copied out of video memory, b6 its PNG is being written | writes it whenever it changes (kept through a core reset) |

Commands: `01` DIR (PETSCII text, 0-terminated), `02` CHDIR, `03` LOAD, `04` RUN, `05` INFO,
`06` LIST (path 40 bytes, then 32-byte records: type, blocks, ext, name), `07` OPEN (entry LEN),
`08` SETLIST (40-byte lines: label, value), `09` SETSTEP (line ARG, VALUE 1 or $FF), `0A` SETAPPLY
(start the chosen chip preset), `0B` NOSHARE (stop waiting for the network: the SD card), `0C` SHOT,
`0D` APPEND, `0F` SHELL (SHELL.PRG to its load address).
OPEN on a lone `.reu` answers VALUE 2, RESULT its size in 64 KB units, LEN the list entry of its `.prg`
($FFFF none).
Errors: `$81` not found, `$82` not a folder, `$83` too big, `$84` can't read, `$85` can't run,
`$86` the network is not connected, `$8F` unknown.

An answer whose RSEQ isn't the 6502's current SEQ (the 6502 gave up and asked something else) is
dropped whole by the core, so a late answer never lands on a newer request; Main logs it.

Main's side, on hps_io's EXT_BUS: `0x70` poll (reply `$6F00` + pending), `0x71` read (each word
after the reply: the 16 registers, then the 32 name bytes), `0x72` write (each word
`{register, value}`; STATUS last).

## os.ini

```
enabled=1
boot=_Computer/Octophonic 64.mgl      ; or an .rbf; missing: the newest _Computer/.C64_Octophonic_*.rbf
startin=net                           ; net, sd or last (F8 START IN); missing: net if a share is set up, else sd
start=/media/fat/games/00-NETWORK/C64 ; optional: the share's C64 folder, if Main can't find it
```

Main starts the core once per power-on (`/tmp/octoos_booted`), so a menu reached with Win+F12 stays
a menu. With the OS active, plain F12 goes to the C64 and Win+F12 (or the Menu key) opens MiSTer's.

## Tests

`tools/octoos/test/romtest.cpp` runs the V1.1 ROM and the stock Commodore ROMs side by side on the
same emulated C64 with a real 1541 and a test disk (`mkd64.py`), and a model of Main's mailbox (with
its 40 ms answer time) serving a test folder, a network share that can be set to appear after a
while, the drives level, and lone .reu files. Build the ROM with `tools/octoos/kernal/build.sh`; the
start screen is also compared pixel by pixel with `boot_ref.idx`, and with no share set up there
must be no network light. Every BASIC/editor/disk case must match stock screen
and memory; the OS cases check the wedge, F1, the browser, the settings and the 3-second timeout.
