# OCTOCODE - write code on the C64, press F2, it runs

Original project by Mong00se - Octophonic 64 and OctoVIC by Mong00se (github.com/8BitG00se).

- `octocode.asm` - the editor (6502, ACME). Navy page, a title row, the code (20 rows, 79 characters
  a line, the screen moves along for long lines), a status row and the key bar:
  F1 BROWSE, F2 COMPILE, F3 LOAD, F5 SAVE, F7 READY (build 2: the one key map; build 3: after a good F2,
  F5 also writes the program onto the disk, before its source, so the disk runs with LOAD"*",8,1); SHIFT+RETURN deletes
  a line, F4 a new line, F6/F8 page up/down;
  cursor keys, RETURN (splits, keeps the indent), DEL (joins at a line's start), INST, HOME, CLR.
- `stock.asm` - a stock C64 example: its `; target stock` line makes COMPILE warn about Octophonic-only
  addresses and run it on a stock machine (one SID, no OctoVIC, no REU).
- `hello.asm` - the example the editor opens: OctoVIC copper bars (the VIC's colour 0 set every
  raster line), a scrolling message, a SID note. Commented for changing.
- `a2p.py` - ASCII to PETSCII, as Main converts it; `build.sh` - the PRG and "Compile Test build 2.d64" (OCTOCODE, HELLO.ASM, STOCK.ASM).
- `main-compile.patch.draft` - the MiSTer Main side, a draft (not applied, not built).

The protocol (`13` COMPILE, `14` COMPLOG, `15` GO) is in `docs/OCTOOS.md`; the emulator's Main does it
in `vice/src/octophonic/octocompile.c` (Octophonic 64 Emulator build 5).
