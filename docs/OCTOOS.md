# Octophonic OS (milestone 1)

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
| FC | VERSION | read: 1 | |

Commands: `01` DIR (PETSCII text, 0-terminated), `02` CHDIR, `03` LOAD, `04` RUN, `05` INFO.
Errors: `$81` not found, `$82` not a folder, `$83` too big, `$84` can't read, `$85` can't run, `$8F` unknown.

Main's side, on hps_io's EXT_BUS: `0x70` poll (reply `$6F00` + pending), `0x71` read (each word
after the reply: the 16 registers, then the 32 name bytes), `0x72` write (each word
`{register, value}`; STATUS last).

## os.ini

```
enabled=1
boot=_Computer/Octophonic 64.mgl      ; or an .rbf; missing: the newest _Computer/.C64_Octophonic_*.rbf
start=/media/fat/games/C64            ; missing: games/C64, else /media/fat/Octophonic
```

Main starts the core once per power-on (`/tmp/octoos_booted`), so a menu reached with Win+F12 stays
a menu. With the OS active, plain F12 goes to the C64 and Win+F12 (or the Menu key) opens MiSTer's.
