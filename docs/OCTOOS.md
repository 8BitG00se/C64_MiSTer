# Octophonic OS (milestone 1, build 3; F keys and the SD tree: build 6)

The MiSTer starts straight into Octophonic 64, and the SD card is used from the READY prompt.
Nothing changes for a MiSTer without `/media/fat/octophonic/os.ini`.

## The start screen (mock-up 12)

The top box holds two rows:
- Row 0: the 8-SID eq, OCTOPHONIC 64, NET and the network light.
- Row 1: 8 SIDS, OCTOVIC 256 and the REU really attached (read from the REU's bank register: 16M, 2M,
  512K ... or NO REU).

Under the box: 38911 BASIC BYTES FREE, then READY. On row 24 is the bar:
`F1 BROWSE F3 LOAD F5 SIDS F7 DUAL F8 SET`.

The screen editor uses rows 0-23 only. Typing and scrolling never reach the bar, and the top box
scrolls away with the text, a line at a time. CLR clears rows 0-23, and the box goes with its words.

RUN, SYS and LOAD switch the box and bar off and give back the stock 25-row editor; so do RUN/STOP+RESTORE and a reset.
With no OctoVIC (a stock VIC) the words are plain and there is no bar.

Nothing covers rows 0-23: the box is dark only behind rows 0-1, the rules run under the VIC's
pixels, and the bar's dark box starts on row 24's first line (its rule on row 24's last). The
recording checks compare every VIC pixel of rows 0-23 with the VIC's own picture.

**The start jingle** (about 2 s) is in SHELL.PRG, not the ROM:
- At a cold start (and after CTRL+F12) the ROM asks Main for SHELL.PRG, as F1 does, and calls its
  `$C003`. It only does this when Main serves the OS (NET b4); with no Main, no os.ini or no
  SHELL.PRG there is silence.
- The music: C major pentatonic up an octave and back down, a third above it in the key on the next
  SID, a soft C-G pad, ending on the C chord.
- Melody and third use voice 3 of the 8 SIDs, so the eq shows them.
- Every note has sustain 0 and dies away by itself.
- Build 6: about 9 dB louder (peak about -6 dBFS, was -15): volume 15, every note on voices 2 and 3
  of its SID with the oscillators reset together (TEST) so they add in phase, the pad on SIDs 1-6.
  At its end it lets go of every gate (the release rates are the decay rates, so nothing is cut
  short), so a BASIC POKE that gates a voice afterwards sounds and the eq shows it.
- The player runs from the IRQ in the tape buffer (`$033C`, unused on the core). It stops at once,
  leaving the SIDs alone, when RUN, SYS or LOAD shut the start screen, or when the IRQ vector is no
  longer its own. The browser stops it too.

**The eq shows any voice** (build 6): while OctoVIC's CTRL (`$D605`) holds `$0B` - the value only the
start screen writes; its octoff writes 0 at RUN, SYS, LOAD and CINT - a read of a SID's ENV3 (`$1C`)
gives the loudest of that SID's three envelopes, not voice 3's alone (the core:
`rtl/fpga64_sid_iec.vhd` and `rtl/sid/sid_top.sv`, `eq_any`; the emulator: `coresid.c`). So POKEing a
tone on voice 1 from BASIC moves the bar. Every program gets the real ENV3 (unless it writes `$0B`
to CTRL itself). No ROM byte is used.

How it is drawn is described in `tools/octoos/kernal/octo.asm`:
- OctoVIC's copper switches KEY between the page and the box.
- A bitmap layer carries the words' gradient, the eq and the rules.
- The IRQ draws the eq from each SID's ENV3 (voice 3's envelope), every other frame.

## At READY

| Type | Does |
|---|---|
| `@` | the current folder, paged like a disk directory (any key: next page, RUN/STOP: stop) |
| `@NAME` | into folder NAME, then its directory (`@..` up) |
| `@/NAME` | the same, from the start folder; `@/` alone goes back to it; `@A/B` goes two down |
| `/NAME` | load and run NAME (.prg, or a .crt); a .d64/.g64/.d81 goes into drive 8 |
| `@!` | out to the MiSTer's own menu (MENU, `12`) |
| F1 BROWSE | the browser at the drives: SD CARD and NETWORK, titled `F1 BROWSE: RETURN RUNS, M MOUNTS A DISK` - browse and run anything |
| F3 LOAD | **no browser**: the disk in drive 8. `F3 LOAD - DRIVE 8: <name>`, then `LOAD"*",8,1` typed and RUN after it. Drive 8 empty: `F3 LOAD: DRIVE 8 IS EMPTY.` and how to put one in (F1, the bar on a disk, M) - nothing is loaded (SHELL.PRG build 5; build 4 had no name) |
| F5 SIDS | its own page, **SID CHIPS** (which SIDs play, and which chips): chip preset, my chips, left/right models, MY CHIPS, OCTOPHONIC, OCTOSID FX |
| F7 DUAL | its own page, **DUAL SCREEN** (C64 on the CRT, OctoVIC on HDMI): SPLIT SCREENS |
| F8 SET | its own page, **SETTINGS**: every line, SHOWCASE last (F7 on any of the three goes straight back to READY) |
| C=+F1 | the MiSTer's own menu (other cores, MiSTer's settings): types `@!`, only on a MiSTer (NET b5); the emulator ignores it |

The F keys need nothing new from Main: F1 is `02` CHDIR `*`, F3's RETURN is `07` OPEN (VALUE 8: a
disk went into drive 8 - SHELL.PRG then types `LOAD"*",8,1` on the screen, RETURN on it, and the ROM's
AUTORUN types RUN after the load; VALUE 1: the core resets into the `.prg`/`.crt`; VALUE 2: a `.reu`
attached), F5/F7/F8 are `08` SETLIST and `09` SETSTEP. (The emulator's Main model autostarts a
`.t64`; the real Main mounts it in drive 8, VALUE 8.)

The ROM types `@@` and a letter on a clear screen (`B` F1, `C` F3, `D` F5, `A` F7, `E` F8; SHIFT+F1/F3/F5
as F1/F3/F5); the wedge loads SHELL.PRG, which finds the letter still in the input buffer at `$0202`.
F1 works at any READY; F3, F5, F7 and F8 only while the start screen (and its bar) is up - after a
program has run, READY's F keys are a stock C64's again.

Names match whole, then without the extension, then by their start (`/HOR` finds `horizon.prg`).

Every request carries a number (SEQ) and waits up to 20 seconds for the answer with that number,
the border flickering while Main works (a folder on a network share can take a while); then
`?NO MAIN REPLY (CMD nn)` (build 6; shorter, for the ROM's room). In the browser, folder scans and loads show SCANNING... or
LOADING... and also wait 20 s; the settings wait 3 s.

## F1: the browser

**Batch 1 (SHELL.PRG build 9, Fix 76): F1 opens the DISKS page** - CHDIR `/DISKS`, the Disks folder of the
start drive (no Disks folder: the drives, as before; F1 on the page: the drives). Row 23 always shows the keys
`R/RETURN RUN  M MOUNT  O SOURCE  N NEW`; a key that does nothing for the entry under the bar is dimmed (dark
grey): M only on a disk, O only on a disk with source on it (LIST b3), N not at the drives level. O puts the disk
in drive 8 and opens its source in OCTOCODE (`19` SRCOPEN; OCTOCODE asks `1A` SRCNAME). N asks for a name on the
status line and makes a blank disk there (`1B` NEWDISK); the bar goes on it, and it is in drive 8. F3 LOAD at
READY is unchanged (LOAD"*",8,1 and RUN). SHELL.PRG loads at `$B000` since build 9 (its new code sits under
BASIC's ROM at `$B000-$B9FF`, the list at `$BA00`).

F1 at READY (the editor waiting for a line, direct mode) clears the screen and types `@@B`, which
loads `SHELL.PRG` from `/media/fat/octophonic` to `$C000` and runs it; it opens at the drives
(CHDIR `*`) - before build 9. F-keys and cursor keys only:

| Key | Does |
|---|---|
| cursor up/down, joystick 2 | move the bar |
| RETURN, fire | a folder: into it; a program or cartridge: load and run; a disk: into drive 8, then LOAD"*",8,1 and RUN |
| M (or SHIFT+RETURN) | a disk: into drive 8 only, not run (build 5). While the bar is on a disk the status line says `RETURN: LOAD+RUN IT   M: MOUNT IT ONLY`. Then the start screen says `DISK IN DRIVE 8: <name>` / `F3 LOADS AND RUNS IT` |
| F1 | the drives (SD CARD / NETWORK) |
| F3, DEL, cursor left, joystick left | up a folder |
| F5 / F6 | page down / up |
| F2 | the start folder |
| HOME | the top of the folder |
| F8 | settings |
| C=+F1 | on a MiSTer: the MiSTer's own menu; holding C= shows it on the help line |
| F7, RUN/STOP | back to READY (the BASIC program is kept) |

RETURN on a `.reu` attaches it (as the menu does, no reset), then the list comes back with
`REU ATTACHED (16M)` on the status line and the bar on the `.prg` of the same name. RETURN on a
`.prg` attaches its `.reu` first (same name, or the only one in the folder) unless that very file is
attached already, so a 16 MB REU is never loaded twice. In each folder the `.prg` files come first
after the folders. `..` shows as `.. (UP A FOLDER)`; sizes are blocks under 1000, else K or M; a
name the C64 can't show comes out with `?`, never blank. Names use 28 columns; a longer one is cut in
the middle (`OCTOPHONIC SHOWC..N BUILD 12`) so the build number at its end always shows.

**Which disk is in drive 8 (build 5).** Besides F3's title and M's message, at every cold start
(power-on, CTRL+F12 / Esc held, a chip preset) the start screen shows `DRIVE 8: <name>` on row 23, just
above the F-key bar, when a disk is in - the jingle's entry (`$C003`) asks Main (`17` DRIVE8) first.
Nothing is shown with the drive empty. It is ordinary text: typing scrolls it away like the box.

**SHELL.PRG build 5 loads at `$BE00`** (was `$C000`): the jingle's code lives at `$BE00-$BFFF` in
the RAM under BASIC's ROM and runs with BASIC switched out ($01 = $36), and the browser's list buffer
moved from `$CDC0` to `$B800-$BA30`, also under BASIC's ROM (read a byte at a time with BASIC out:
`recb`, `compact`). `$C000-$CFFF` is all the browser's code. The ROM still calls `$C000` and `$C003`;
no ROM change. So F1 (and the jingle) now use `$B800-$BFFF` of the RAM under BASIC, besides `$C000-$CFFF`.

## Drives and the network

The top of the browser is the drives: **SD CARD** (`games/C64` on the card: Demos, Games, Tools,
Code, Music, SIDs, Pictures, My Chips, Disks, Screenshots, Saves - docs/SDCARD.md), **NETWORK** (the
C64 folder of a network share) and **USB n** (`games/C64` on a stick). F1 opens the browser there;
F3 from the top of a drive goes up to them. NETWORK is always listed but only opens while a share
is there: `OFF` while one that is set up isn't connected, `NONE` with none set up (RETURN on it
says `?THE NETWORK IS NOT CONNECTED`).

At power-on Main decides where to start (F8: START IN - NETWORK, SD CARD or LAST USED, saved as
`startin=` in os.ini; without it: the SD card, and Main never waits for a network - build 6).
A share is "set up" if one is mounted (cifs/smb/nfs in /proc/mounts), has been seen before on this
MiSTer, or MiSTer's cifs script has a SERVER. Both ways of mounting work: over `/media/fat/games`
(then `games/C64` is the share) and in a folder of its own (`games/00-NETWORK/C64`,
`/media/network/C64`); `start=` in os.ini, if it points at a folder on the share, is used.

While a share that is set up is still connecting, the start screen's network light is red. It is the
ball at row 0, column 38, coloured by the IRQ, and it is also shown in the browser. It turns green once
the share is there, and is not lit at all without a share. With `startin=net`, F3 shows
`PLEASE WAIT - CONNECTING TO NETWORK...` and opens the share's C64 folder the moment it mounts.
Any key, or 60 seconds, uses the SD card instead (`NO NETWORK - USING THE SD CARD`).

## Screenshots and reports (for the demos' self-tests)

`10` SHOT takes a screenshot with MiSTer's own code (the scaler's picture, as Win+PrtScn) and saves
it as `<share C64 folder>/Octophonic/Screenshots/NAME.png` (no share: `/media/fat/games/C64/
Screenshots/NAME.png`). NAME may hold folders (`HORIZON/NIGHT-0351`); letters, digits, `- _ . /`.
Main answers at once and does the rest in the background: the picture is copied out of video memory
at the next vsync (NET bit 7 set from the request until that copy is done), then a worker thread
writes the PNG (NET bit 6) and Main copies it to the share. At most one a second; a SHOT while one
is under way is ignored. No message is put on the screen. A demo can tell a screenshot is under way
from **NET (`$D6FF`) bit 7** (the picture being copied out of video memory - the extra DDR3 reads
happen then) and **bit 6** (the PNG being written - no extra video memory traffic); counter readings
taken while bit 7 is set include the copy's DDR3 traffic.

`11` APPEND writes text for reports: VALUE `$FF` makes file ARG (0-3) the path NAME (under the same
Screenshots folder; folders are made); any other VALUE puts NAME's text (up to 32 characters - the name buffer holds 32,
PETSCII to ASCII) on the end of file ARG, with a new line unless VALUE bit 0 is set (a long line in
pieces). Not logged (there can be many).

CTRL+F11 (OS mode): a screenshot of whatever is running into `Screenshots/Manual`.

## Settings (F8)

Cursor up/down picks a line, left/right changes it, RETURN on CHIP PRESET starts it.
Lines: chip preset (the `_Computer/Octophonic 64*.mgl` launchers; the one started becomes `boot=` in
os.ini), my chip left/right (the `.CHP` files in `games/C64/My Chips`), START IN (network / SD card / last used), then the core's options:
Left/Right SIDs, My Chips, Octophonic, OctoSID FX, Split Screens, Turbo mode, Turbo speed, and last
(line 12, os-fixes) **SHOWCASE**: OFF / ON - NO DEBUG ROWS, saved as `showcase=` (0/1) in os.ini.

**SHOWCASE (Fix 29)** is for recording demos on the real machine. Main shows it as **NET (`$D6FF`)
bit 3**, from power-on and through every core reset. A demo with technical rows (LATE/REP/BLANK, the
CORE line) checks it at its start: bit 3 set - start with them hidden and stay that way (its I key may
still show them); clear - its own default, as before. Default off. Skipping Ball, Punching Cubes and
Gold Black Hole already start clean (EXAMPLES.md); new demos and the kit should read bit 3:

```
        lda #$4F        ; OctoVIC's page (the mailbox)
        sta $D03F
        lda #$38
        sta $D03F
        lda $D6FF       ; NET
        and #$08        ; SHOWCASE
        bne clean       ; on: no debug rows
```

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

**One key from any program: hold Esc (RUN/STOP on a Keyrah) for about 1.5 seconds.** It does the same
as CTRL+F12 (back to the start screen), without needing a second key. A short tap of Esc/RUN-STOP is
still passed to the C64 as usual, so only a deliberate hold leaves. Main sees the key at the USB/Keyrah
level, so it works even when a demo has taken over the C64's keyboard and RESTORE. Not tested on real
hardware yet.

## The front screen (Fix 27, Fix 20)

The tty2oled screen shows the animated Octophonic logo from power-on (tty2oled's daemon, recipe step 084, sends the
core's name; the Octophonic screen firmware plays the logo for it). When OPEN (`07`) or RUN (`04`) starts a program
that has a `.oled` beside it - the same name, or the only one in the folder - Main has `octophonic/oled.sh` send it
and the screen plays it until the program ends: CTRL+F12, Esc held, the browser (`01 02 06`), the settings
(`08 09 0A 0B`), MENU (`12`), or a cold start's SHELL request (`0F`, not within 10 s of starting a program) bring
the logo back. Main never waits for the screen. Details: `tools/oled/README.md`.

## The pieces

- **The core** (`rtl/octovic/octo_os.sv`): the mailbox, 16 registers at `$D6F0-$D6FF` in OctoVIC's
  page (OctoVIC must be unlocked: `$4F`, `$38` to `$D03F`). No block RAM.
  Plus a raw download index `$0A`: bytes straight into RAM at the 2-byte address in front -
  no reset and no BASIC pointers, unlike the menu's PRG load (index 1).
- **The ROM** (`rtl/roms/octo_C64.mif`, sources in `tools/octoos/kernal`, built by `build.sh`):
  - The commands are in the tape room `$F72C-$F928` (wedge.asm) and `$FB97-$FCD0` (wedge2.asm).
  - The start screen (octo.asm) is in `$F92C-$FB96`, plus every other piece of ROM the core never
    runs. These are the tape's LOAD, SAVE, OPEN, CHRIN, CHROUT and CLOSE paths and its messages, the old
    banner, and the stock ROMs' unused bytes. All of them are listed in octo.asm and checked by patch.py.
  - It calls `osinit`, which points BASIC's IMAIN (`$0302`) at the commands.
  - ROM room left (build 6): 27 bytes, all in small gaps (f 2, d 3, m 3, k 5, b 4, c 4, tape room 3,
    wedge 1, wedge2 2). Build 6 took 11: the F keys (keyhk +14, with its ?NO MAIN REPLY message 15
    shorter, @'s page prompt just MORE, RUN's text moved to $E4E6, the hex digit and CINT's hook
    moved into wedge.asm), octoff's
    eq-cell clean-up (+12) and the cells printed after the copper is on (+1).
  - LOAD, SAVE and OPEN on device 1 give ?ILLEGAL DEVICE NUMBER, since the tape code is gone.
  - Two bits of stock code inside the tape areas are still used by the disk and are left alone:
    `$F5A9-$F5AE` (the disk LOAD's end) and `$FB8E-$FB96` (the disk SAVE's start address).
    patch.py checks both, and `refscan.py` stops the build if any stock code calls into a piece.
    (Up to start screen build 1, `$FB8E` was written over, so SAVE to disk took its start address
    from whatever `$AC/$AD` held.)
  - `build.sh` makes the core's `.mif` and the emulator's `octo_rompatch.h` from the same source, then
    runs romtest.
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
| FF | NET | read: b1-0 the network share (0 none set up, 1 waiting for it, 2 there, 3 set up but not there), b4 Main serves the OS (the start jingle is asked for only then), b5 Main is on a MiSTer (so MENU is offered; the emulator's model leaves it clear), b7 a screenshot is being copied out of video memory, b6 its PNG is being written | writes it whenever it changes (kept through a core reset) |

Commands: `01` DIR (PETSCII text, 0-terminated), `02` CHDIR (NAME `*`: the drives), `03` LOAD, `04` RUN, `05` INFO,
`06` LIST (path 40 bytes, then 40-byte records: type, size text (5), ext (3), name (31; Main cuts a long name in the middle to 28 so its end - a build number - shows)), `07` OPEN (entry LEN),
`08` SETLIST (40-byte lines: label, value), `09` SETSTEP (line ARG, VALUE 1 or $FF), `0A` SETAPPLY
(start the chosen chip preset), `0B` NOSHARE (stop waiting for the network: the SD card), `10` SHOT,
`11` APPEND, `0F` SHELL (SHELL.PRG to its load address), `13` COMPILE, `14` COMPLOG, `15` GO (the
OCTOCODE editor: see below), `12` MENU (answered, then Main loads `menu.rbf`, MiSTer's own menu;
Main starts the Octophonic core only once per power-on, so the menu stays a menu).
`17` DRIVE8 (os-fixes): the name of the disk in drive 8 (as the core has it - also one put in from
the MiSTer's menu) to ADDR, PETSCII, at most 32 characters, 0 after it; RESULT its length (0: empty).
`18` REU (os-fixes): see "A running program asks for its .reu" below.

**Batch 1 (files-batch1, `octophonic-batch1.patch` + `octo_b1.h`, (c) 2026 Mong00se):**

| Cmd | Name | 6502 gives | Main does | Answer |
|---|---|---|---|---|
| `06` LIST | (as before) | | a disk with source - a closed SEQ file on the `.d64`, as OCTOCODE saves it, a name ending `.ASM` first - gets **b3** in its record's type byte (`2 + 8`) | the Disks page lights **O** for it (Fix 76) |
| `19` | SRCOPEN | LEN the list entry (a disk with source) | puts the disk in drive 8, keeps the source's name, runs `games/C64/Tools/OCTOCODE.PRG` (the core resets, as for any program) | VALUE 1; `$81` no source on it, or no OCTOCODE on the card |
| `1A` | SRCNAME | ADDR where | the name SRCOPEN kept (PETSCII, 0 after it) - once | RESULT its length (0: none: OCTOCODE starts as before) |
| `1B` | NEWDISK | NAME (16 at most; letters, digits, space `- _ . ! ( ) +`) | a blank, formatted 35-track `NAME.d64` (disk name NAME, ID `OC`) in the browser's folder, put in drive 8 (Fix 46) | VALUE 8, LEN its list entry (the bar goes on it); `$87` a file of that name is there already |
| `1C` | SAVEREU | ADDR the VRAM page (VRAM address / 256), LEN how many 256-byte pages, NAME the file (`.reu` added), ARG b0 add to its end | writes those VRAM bytes to `NAME.reu` in the program's own folder (as `18` looks), else beside the disk in drive 8, else the browser's folder (Fix 56). The program puts its data in VRAM first: REU -> C64 with the C64 address fixed at VDATA `$D604` | RESULT the file's size in 64 KB; `$83` past VRAM's end, `$84` can't write |
| `13` | COMPILE | (as before) | **Fix 57:** before ACME runs, every `!source "x"` / `!src` / `!binary "x"` / `!bin` file that isn't in the folder yet is taken off the `.d64` in drive 8 (source files PETSCII -> ASCII, and searched for their own `!source` lines); the log says `Joined x from the disk` | as before |
| `08`/`09` | SETLIST / SETSTEP | | lines **13 VIDEO OUT** (HDMI ONLY, HDMI+VGA 31K, HDMI+CRT 15K, CRT ONLY 15K; "NOT SET - PICK ONE" until chosen) and **14 SCALING** (FILL SCREEN, SHARP PIXELS) - os.ini `video=` / `scaling=`, written to MiSTer.ini (below); VIDEO OUT other than HDMI+CRT 15K turns SPLIT SCREENS off | SETSTEP on them: VALUE 4 = switch off and on to see it |

What VIDEO OUT / SCALING write to `/media/fat/MiSTer.ini` (every active line of the key, any section; a missing
key goes under `[MiSTer]`; nothing else in the file is touched). The first change after Main starts backs
the old file up to `octophonic/backups/MiSTer.ini.<date-time>`; every change is a line in `update.log`.
Nothing is restarted: MiSTer reads MiSTer.ini when it starts.

| VIDEO OUT | vga_scaler | forced_scandoubler | vsync_adjust |
|---|---|---|---|
| HDMI ONLY | 0 | 0 | 2 |
| HDMI+VGA 31K (a PC monitor; its split C64 side needs a new core - Fix 54) | 0 | 1 | 2 |
| HDMI+CRT 15K (Neal's set-up: the same two lines his DEV step 910 sets) | 0 | 0 | 2 |
| CRT ONLY 15K | 0 | 0 | 2 |

| SCALING | vscale_mode |
|---|---|
| FILL SCREEN (MiSTer's default) | 0 |
| SHARP PIXELS (integer scale: every pixel the same size, e.g. on a 4K TV) | 1 |
OPEN on a lone `.reu` answers VALUE 2, RESULT its size in 64 KB units, LEN the list entry of its `.prg`
($FFFF none).

**A `.reu` goes in with no MiSTer OSD bar (build 6, Octophonic Main `octophonic-quiet-load.patch`).**
When an OPEN (`07`) or RUN (`04`) has a `.reu` to put in the REU - a lone `.reu`, or a demo's `.prg`
with its `.reu` beside it (the one of the same name, else the only one in the folder), unless that
`.reu` is in already - Main sends it into the core itself (index `$81`, as the menu's F1 entry does,
but without MiSTer's `ProgressMessage`), and **while the request is still busy (STATUS stays 1)** it
keeps writing, after every 64 KB:

| Reg | Main writes (no STATUS: the request carries on) |
|---|---|
| FE RSEQ | the request's number first, as in every reply (a request the 6502 gave up on gets none of it) |
| F7 VALUE | `3` - a `.reu` is going in |
| FA/FB RESULT | the 64 KB blocks in so far (0 at the start, then up to LEN) |
| F4/F5 LEN | the 64 KB blocks in all (256 for 16 MB) |

Then the answer as before: a lone `.reu` STATUS 2, VALUE 2, RESULT its size in 64 KB, LEN its `.prg`'s
entry; a demo STATUS 2, VALUE 1 - and only after that answer the `.prg`, whose load resets the core.
(Before build 6 a demo's answer came first and the `.reu` went in after it, under MiSTer's grey bar.)
The 6502 sets VALUE to 0 before an OPEN, so a 3 is always Main's. SHELL.PRG draws the bar on the
status line (`reu` in yellow, 32 cells: in white, still to come light blue, from RESULT*32/LEN) and
starts its 60-second wait again whenever RESULT moves. The ROM's `/NAME` (RUN) has no room for a bar:
it just waits (20 s); its answer comes once the `.reu` is in.
While the OS is active, Main also never draws MiSTer's OSD "Loading" bar for anything else (a `.prg`,
a `.crt`, a chip file a preset loads): `ProgressMessage` returns at once.
**The emulator's model of Main** should do the same: for those OPENs, write VALUE 3, RESULT and LEN
a few times while "loading" (busy), then answer.
Errors: `$81` not found, `$82` not a folder, `$83` too big, `$84` can't read, `$85` can't run,
`$86` the network is not connected, `$8F` unknown.

An answer whose RSEQ isn't the 6502's current SEQ (the 6502 gave up and asked something else) is
dropped whole by the core, so a late answer never lands on a newer request; Main logs it.

Main's side, on hps_io's EXT_BUS: `0x70` poll (reply `$6F00` + pending), `0x71` read (each word
after the reply: the 16 registers, then the 32 name bytes), `0x72` write (each word
`{register, value}`; STATUS last).

## A running program asks for its .reu (`18`, os-fixes - for "2026: An Octophonic Odyssey")

A program can ask Main to put a `.reu` from its own folder into the REU while it runs - e.g. a demo
run from OCTOCODE after editing (where the browser's automatic `.reu` didn't happen), or one that
changes its REU between scenes.

| 6502 gives | Main does | Answer |
|---|---|---|
| NAME the `.reu` (with or without `.reu`, no folders), ARG b0: 1 = load it again even if it is in, VALUE 0 | looks for it in: the folder of the program Main last started (browser OPEN, `/NAME`), or where OCTOCODE's last COMPILE/GO worked; then the folder of the disk in drive 8; then the browser's folder. Puts it in as OPEN does (no OSD bar, VALUE 3 and RESULT/LEN the 64 KB blocks while it goes in, STATUS still 1) | STATUS 2, VALUE **2** put in now / **4** it was in already (nothing loaded), RESULT its size in 64 KB; `$81` not found |

The C64 keeps running while it goes in (a 16 MB `.reu` takes several seconds on the MiSTer) - don't
read the REU until the answer. The tiny example (the whole test is `tools/octoos/test/reureq.asm`):

```
        lda #$4F        ; OctoVIC's page (the mailbox)
        sta $D03F
        lda #$38
        sta $D03F
        sta $D6F9       ; NAME: empty
        ldx #0
-       lda name,x      ; then its letters
        beq +
        sta $D6F8
        inx
        bne -
+       lda #0
        sta $D6F6       ; ARG: not again if it is in already
        sta $D6F7       ; VALUE 0 (Main writes 3 while loading)
        lda $D6FE       ; a request number of our own
        clc
        adc #1
        sta seq
        sta $D6FD       ; SEQ
        lda #$18        ; REU
        sta $D6F0       ; CMD
-       lda $D6F1       ; STATUS: wait while 1 (busy)
        cmp #1
        beq -
        ldx $D6FE       ; ... and until the answer carries our number
        cpx seq
        bne -
        cmp #2          ; 2: done - $D6F7 is 2 (put in) or 4 (in already)
        bne failed      ; else $81: not found
        ...
name    !pet "odyssey part 2", 0
seq     !byte 0
```

Tested in the emulator: `REU Request.prg` beside `Part A.reu` and `Part B.reu` (`mkreureq.sh`) asks for
A (VALUE 2), B (2), B again (4) and shows each one's first 40 bytes from the REU.

## OCTOCODE: write code, press F2, it runs (`13`-`15`)

Build 2 of the editor (build 6 of the emulator) has the one key map: **F1 BROWSE** (the editor and its
code go into VRAM, then the browser at the drives; RUN brings it back), **F2 COMPILE**, F3 LOAD,
F5 SAVE, F7 READY, SHIFT+RETURN deletes a line, F4 a new line, F6/F8 page up/down. Its bar is in the
start screen's style: `F1Browse F2Compile F3Load F5Save F7Ready`, keys yellow. OCTOCODE.PRG goes in
the SD card's `Tools` folder, so the browser starts it at once.

**The target.** A comment line `; target stock` anywhere in the source makes the file a stock C64
program: COMPILE's log says `Target: STOCK C64`, warns about each line that names an Octophonic-only
address (OctoVIC `$D600-$D6FF`, `$D03F`; a second SID `$D420-$D7FF`; the REU `$DF00-$DF0A`), and GO
runs it on a stock machine - one SID, no REU, OctoVIC can't be opened - until RUN/STOP+RESTORE
brings the editor back (the emulator; `stock.asm` is the example). Without it: `Target: OCTOPHONIC 64`.

OCTOCODE.PRG is a code editor on the C64 (6502, `tools/octoos/octocode`). The source is ACME assembler
text, PETSCII in the upper/lower case set; Main saves it, assembles it with ACME and starts it.

| Cmd | Name | 6502 gives | Main does | Answer |
|---|---|---|---|---|
| `13` | COMPILE | ADDR/LEN the source in C64 RAM (lines end with RETURN), NAME the file name (`HELLO.ASM`), ARG b0: the same bytes are also in OctoVIC's VRAM at `$FE0000` | writes `<name>.asm` (lower case, ASCII) in the folder of the disk in drive 8 (else its current folder), runs `acme -v1 -f cbm -o <name>.prg -Wno-label-indent --maxerrors 10 <name>.asm` there, and keeps its messages as a log | STATUS 2 at once; `$81` nothing to compile |
| `14` | COMPLOG | ADDR where, LEN the first log line wanted, VALUE how many (0: 8) | those lines to ADDR, PETSCII, RETURN after each, 0 at the end (36 characters a line at most; a long message carries on, indented two) | VALUE 0 still compiling, 1 done and good, 2 done with errors; RESULT the first error's line (0 none); LEN the log's lines so far |
| `15` | GO | (NAME still from COMPILE) | `<name>.prg` into C64 RAM at its own address, no reset | RESULT the load address, LEN the end; `$81` none, `$83` it would reach below `$0400` |
| `16` | PRGVRAM | (NAME: the file being saved; build 3 of OCTOCODE) | `<name>.prg` of the last good COMPILE into OctoVIC's VRAM at `$FD0000`, its two address bytes first | RESULT its length; `$81` nothing compiled (or it had errors) |

The log's lines start with what they are, so the box can colour them: `Saved ...`, `ACME ...`,
`Error line N: ...`, `Warning line N: ...`, `Made <name>.prg: N bytes, $0801-$0A92`, then `OK - compiled.`
or `Not compiled. First error: line N`. PETSCII to ASCII: unshifted letters are lower case, shifted
ones capitals, left arrow `_`, SHIFT+`+` `{`, SHIFT+`-` `}`; ASCII to PETSCII the other way.

After GO answers, the 6502 starts the program itself: at `$0801` as RUN does (`$A533`, `$A659`,
`$A7AE`, BASIC's pointers from LEN), anywhere else with a JMP to RESULT - after the KERNAL's own
RUN/STOP+RESTORE set-up (`$FDA3` `$FD15` `$E518`), OctoVIC off and its page shut, the SIDs quiet.
The launcher runs from `$0100-$01A0` (out of Main's reach: GO refuses anything below `$0400`).

**F5 SAVE writes the program too (OCTOCODE build 3).** After a good F2, F5 asks Main for PRGVRAM
(`16`), then writes those bytes, read back through VDATA, to drive 8 as a PRG file named as the
source without `.asm` (`@0:RASTER,P,W`) - before the source's SEQ file, so on a new disk the
program is the first file and the disk runs with LOAD"*",8,1 and RUN (F3 at READY does that).
Without a compiled program (or with a Main that doesn't know `16`) F5 saves the source only and
says so. The emulator's Main does `16` (emulator build 7); the MiSTer's Main draft does not yet.

**Back to the editor.** Before GO, OCTOCODE copies itself and the source (`$0801` to the end of the
text) into VRAM at `$FF0000` (`'O'`, its build, the pages, then the bytes) and points the NMI vector
(`$0318`) at a handler in the tape buffer (`$0334`): RUN/STOP+RESTORE copies it all back and the
editor carries on, code, cursor and file name as they were. If the program took the NMI vector,
the tape buffer or the top of VRAM, RESTORE gives READY as on any C64; a reset, then LOAD"*",8 and
RUN find the copy in VRAM (OctoVIC's VRAM survives a reset) and the code is back. F7 (EXIT) leaves a
copy too. Programs have `$0400`-`$FFFF` and VRAM `$000000-$FDFFFF`.

**On the MiSTer** (draft, `tools/octoos/main/octocode-compile.patch.draft`): Main can't read C64 RAM,
so it takes the source from VRAM - DDR3 `$32FE0000`, through `shmem_map` - which is why the editor
also writes it there (ARG b0) and waits for OctoVIC's write queue (STATUS b0) before asking. The log
and the program go into C64 RAM with the raw download (index `$0A`) as LOAD's do. ACME is an ARM
build in `/media/fat/octophonic/acme`, run in a thread so COMPLOG can say "still compiling".

## os.ini

```
enabled=1
boot=_Computer/Octophonic 64.mgl      ; or an .rbf; missing: the newest _Computer/.C64_Octophonic_*.rbf
startin=sd                            ; net, sd or last (F8 START IN); missing: sd
video=hdmi+crt15                      ; (batch 1) F8 VIDEO OUT / F7: hdmi, hdmi+vga31, hdmi+crt15, crt15; missing: not set
scaling=fill                          ; (batch 1) F8 SCALING: fill or sharp
start=/media/fat/games/00-NETWORK/C64 ; optional: the share's C64 folder, if Main can't find it
```

Main starts the core once per power-on (`/tmp/octoos_booted`), so a menu reached with Win+F12 stays
a menu. With the OS active, plain F12 goes to the C64 and Win+F12 (or the Menu key) opens MiSTer's.

## Tests

`tools/octoos/test/romtest.cpp` runs the V1.1 ROM and the stock Commodore ROMs side by side on the
same emulated C64 with a real 1541 and a test disk (`mkd64.py`), and a model of Main's mailbox (with
its 40 ms answer time) serving a test folder, a network share that can be set to appear after a
while, the drives level, and lone .reu files. Build the ROM with `tools/octoos/kernal/build.sh`; the
start screen is also compared pixel by pixel with `boot_ref.idx`, and with no share set up the network
light must be unlit.

Every BASIC, editor and disk case starts with a RUN, which leaves the start screen as any program does, and
must then match stock screen and memory. The OCTO cases check:
- the start screen's own 24-row editor: the bar is never touched, the box scrolls away, CLR, RUN and
  RUN/STOP+RESTORE;
- the plain screen with no OctoVIC;
- C=+F1 with and without NET b5;
- the wedge, F1, the browser, the settings and the timeouts.

`mktest.sh DIR` makes the test folders.
