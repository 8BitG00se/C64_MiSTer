# OCTOPAINT

A 256-colour paint program for the Octophonic 64 (OctoVIC 2+), by Mong00se. 6502, ACME. The user's manual
and the `.OCT` file format are in [`docs/OCTOPAINT.md`](../../docs/OCTOPAINT.md); the design is in
[`docs/OCTOPAINT_SPEC.md`](../../docs/OCTOPAINT_SPEC.md).

| file | what |
|---|---|
| `octopaint.asm` | the program (`acme -f cbm`, loads at `$0801`, `10 SYS2061`) |
| `palette.inc` | the default palette, made by `mkpal.py` (do not edit) |
| `mkpal.py` | makes `palette.inc` (0 black, 1-15 C64-like, 14 hue ramps, 16 greys) |
| `mkoct.py` | `.OCT` files on a PC: the packing (same rule as the 6502), PNG to / from `.OCT`, Koala to `.OCT`, the checksum, the two example pictures |
| `md2txt.py` | `docs/OCTOPAINT.md` to the plain text `How to use.txt` |
| `build.sh` | `build.sh OUT`: `OCTOPAINT.PRG`, `OctoPaint Disk build N.d64`, `OCTOPAINT build N.zip` |
| `sprites.txt` | the pointer's drawing |

Source layout: platform (OctoVIC, blitter, input, KERNAL disk, toolbar) and paint (Bresenham, circle, fill,
packing, Koala decode) are kept apart; the paint code calls `plot`, `fillrect`, `readpixel` (and `readrow`,
`drawline`), listed at the top of `octopaint.asm`, so a Windows version can start from `mkoct.py` and the format
document.

Testing was done in the headless Octophonic emulator with scripted keys, looking at the frames: every tool, a
save / quit / restart / open round trip (same VRAM checksum, and the saved file equals `mkoct.py`'s packing of
the same pixels), the `DISK IN DRIVE 8?` N answer (no drive traffic, the disk image unchanged), a Koala import
against `mkoct.py from-koala`, and flood fill timings.
