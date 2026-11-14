# Octophonic Fast Load (Fix 49)

(c) 2026 Mong00se. Original work, written for the Octophonic 64: the 6502 code on both sides, the
protocol and the core logic are ours.

## What it does

Reading a file from the core's own 1541 goes over the core's parallel port instead of the serial
bus. It is on by default (menu: Hardware, "Fast loader: On/Off") and needs no cartridge and no
special disk. It covers

- `LOAD"...",8` and `LOAD"...",8,1`, `VERIFY`, the directory (`LOAD"$",8`);
- any program that reads a file through the KERNAL: `OPEN` / `CHKIN` / `CHRIN` / `GETIN`,
  BASIC's `INPUT#` and `GET#`, or the low-level `TALK` / `TKSA` / `ACPTR`. OctoPlay and OCTOCODE
  read their files this way.

A 200-block file loads in about 22 seconds instead of 127 (measured in the emulator, see below).

## How it works

The drive's DOS opens the file and reads the disk exactly as it always does. Only the way each
byte crosses from the drive to the C64 is new ("fast talk").

**C64 side** (`tools/octoos/kernal/fastload.asm`). The routine stands in for the KERNAL's `ACPTR`,
"fetch a byte from the serial bus". The first 16 bytes after a file is addressed still come the
serial way. Then the routine sends the drive one DOS command (`M-E`, start address $1000, and the
secondary address) and from there takes each byte from the user port.

**Drive side** (`tools/octoos/kernal/fastdrive.asm`). A 512-byte ROM at $1000-$11FF in the core's
1541, where a real 1541 has nothing. It takes each byte the DOS has ready on the open channel
and puts it on the drive's VIA port A. Nothing is uploaded to the drive and none of its RAM is used.

**The wires.** The byte is on the eight parallel lines. CLK changes level with every byte (low for
the first, high for the second, and so on); DATA low means more follow, DATA high means it is the
file's last byte. The C64 reading the port pulses PC2, which tells the drive the byte was taken.
Neither side has to catch a pulse and there is no timing anywhere, so interrupts on either side are
harmless.

**Falling back.** Any ATN on the serial bus (that is, the C64 starting any serial command) makes
the drive drop back into its DOS, with the DOS's channel standing exactly on the next unread byte.
The serial bus carries on from there. Nothing has to be undone.

## The core's part

- `rtl/fpga64_buslogic.vhd`: a second ROM bank, Commodore's stock BASIC and KERNAL with the loader
  where the tape routines were. Only the 4K that differs is stored (`rtl/roms/octo_fastload.mif`).
- `rtl/fpga64_sid_iec.vhd`: the bank is switched in when the 6510 fetches the instruction at $EE13
  (`ACPTR`) from the Octophonic KERNAL ROM, and out on any write to $D03D. Not one byte of the
  Octophonic KERNAL is changed.
- The core listens to what the C64 sends under ATN, so it knows when the last thing said on the
  bus was "device 8, talk, secondary address n".
- `rtl/iec_drive/c1541_logic.sv`: the drive's ROM page (`rtl/iec_drive/c1541_fastload.mif`).
- `c64.sv`: the menu line, and the user port stays wired to the drive while a fast session is on.

Registers (three of the VIC-II's unused ones; all read $FF with the fast loader off):

| Address | Read | Write |
|---|---|---|
| $D03C | b7: the drive is talking the fast way; b0-6: a byte count | b7 set: "it is"; b7 clear: count one |
| $D03D | the secondary address device 8 was last told to talk on | the loader's bank out |
| $D03E | b7 0: a fast loader is here; b0 0: drive 8 can take it | - |

ATN low clears $D03C.

## When the serial bus is used instead

The ordinary serial routine does the work, unchanged, whenever

- "Fast loader" or "Parallel port" is Off in the menu, or External IEC is enabled;
- the drive is not the 1541 on its built-in standard ROM (a drive ROM file was loaded, or it is a 1581);
- a System ROM file was loaded over the built-in KERNAL, or another System ROM is selected;
- the program has set the user port to outputs, or the KERNAL's RS-232 is in use;
- the talker is not device 8, or it is the command channel (15);
- fewer than 16 bytes have been read since the file was last addressed (BASIC's `GET#` re-addresses
  the file for every byte, so it always stays on the serial bus);
- the drive does not answer.

Programs that bring their own loader (their own drive code and their own serial routines) never call
`ACPTR`, so they are not touched. Saving is not speeded up.

The Octophonic 64 RGB companion core does not have the fast loader (its rewind does not carry the
loader's ROM bank).

## The drive ROM

With the System ROM set to Octophonic the 1541 now runs the standard Commodore DOS that is built into
the core, unless a drive ROM file has been loaded. The fast loader rests on that DOS's own routines.

## Speed

The speed is set by the disk, not by the wire: a standard disk has its file blocks ten sectors apart,
and the drive's one processor has to read and decode a block and pass it across before the next
one comes round. That gives about ten blocks a second on one track, with a pause at each change of
track.

## Building

`tools/octoos/kernal/build.sh` assembles both sides; `fastload.py` writes the two .mif files and the
emulator's copies (`octo_fastload.h`, `octo_fastdrive.h`). The emulator needs the matching changes
(the bank, the trap at $EE13, the three registers, the bus listener, the drive's ROM page, the
parallel cable) to behave as the core does.

## Testing

`sim/fastload/run.sh` runs the whole C64 and its 1541 in Verilator (the GitHub workflow "Fast load
simulation" does it on every push to a `fix49*` branch): the same file loaded with the fast loader
on, off, and on with the parallel port disabled, the memory compared each time.
