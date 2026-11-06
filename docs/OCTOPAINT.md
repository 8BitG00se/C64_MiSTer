# OCTOPAINT (build 1)

A 256-colour paint program for the Octophonic 64, by Mong00se. It draws on a 320 x 200 picture, 256
colours from a palette you can edit, with a pencil, brushes, lines, boxes, circles, flood fill,
zoom, undo, a colour picker, and it saves and opens pictures on a disk (drive 8). It needs the
Octophonic 64 core (OctoVIC 2 or later): a stock C64 gets a message and nothing else.

## Putting it on the MiSTer (FileZilla)

1. Find the MiSTer's IP address (the MiSTer menu, or your router's list).
2. Open FileZilla and connect: protocol SFTP, host = the MiSTer's IP, user `root`, password `1`
   (unless you changed it), port 22.
3. On the MiSTer side go to `/media/fat/games/C64/Apps/`.
4. Drag `OCTOPAINT.PRG` (from the zip) there. The disk `OctoPaint Disk build 1.d64` goes in the same
   folder (or in `/media/fat/games/C64/Disks/`). It has OCTOPAINT and two example pictures.
5. Start the Octophonic 64 core. Press F1 (the browser), pick OCTOPAINT.PRG in Apps, and RETURN. Or
   mount the disk in the OSD and type `LOAD"*",8,1` then `RUN`.

**The mouse.** Open the core's OSD and set `Pot 1/2` to `Mouse`. The mouse then acts as a 1351 in port 1
and moves the pointer exactly as on screen. Without that setting the mouse does nothing, but the
keyboard and joysticks always work. `M` turns reading the mouse on and off.

**Before you save or open anything:** put a disk in drive 8 (mount a .d64 in the OSD). OCTOPAINT
always asks `DISK IN DRIVE 8? Y/N` first. N means nothing at all is sent to the drive. It never
touches the drive when it starts.

## The screen

The picture is the top 320 x 200 of the screen. The toolbar sits over the bottom 24 lines: the
current colour, two rows of 16 colour swatches (32 of the 256 colours at a time), the tool, the brush
size, the zoom, and a line for messages and the colour number. `TAB` hides it.

## Moving the pointer, drawing

Everything works at once:
- **Mouse** (see above): left button draws, right button is the rubber (draws colour 0).
- **Joystick**, port 1 or port 2: moves the pointer one pixel a frame, four with fire held for more
  than half a second. A tap of fire is a click; hold fire to draw (pen down).
- **Keyboard**: cursor keys move the pointer one pixel (with the Commodore key `C=` held, eight; SHIFT turns right / down into left / up as on a C64). `RETURN` is the left
  button (draw while held), `SPACE` the right button (the rubber).

The pointer does not draw until a button is down. Clicking a swatch on the toolbar picks that colour.

## The keys

| key | does |
|---|---|
| `P` | pencil (1 pixel) |
| `B` | brush (size 1, 2, 4, 8; square) |
| `1` `2` `3` `4` | brush size 1, 2, 4, 8 |
| `L` | line: press at the start, drag, let go at the end (the crosshair marks the start) |
| `R` | rectangle outline; `SHIFT+R` filled |
| `C` | circle outline: press at the centre, drag for the radius; `SHIFT+C` filled |
| `F` | flood fill (4-way, same colour); the time it took is shown |
| `K` | pick the colour under the pointer |
| `+` `-` | colour number up / down |
| `<` `>` (SHIFT+`,` and SHIFT+`.`) | the swatch window: 32 colours back / forward |
| `E` | edit the current colour: `Q`/`A`, `W`/`S`, `E`/`D` raise / lower R, G, B by 4 (SHIFT: by 1), shown live on the swatch and as numbers; `RETURN` keeps it, `RUN/STOP` puts it back |
| `U` | undo (one level: the whole last stroke, shape, fill, open, import or clear) |
| `Z` | zoom 1x, 2x, 4x around the pointer; when zoomed, move the pointer to the edge to pan |
| `TAB` (the `<-` key, or `CTRL`) | hide / show the toolbar |
| `N` | new picture: asks `CLEAR THE PICTURE? Y/N`, clears to colour 0 |
| `S` | save: asks the name (max 12 letters), then the disk question |
| `O` | open: asks the name, then the disk question |
| `I` | import a Koala picture |
| `M` | mouse reading on / off |
| `H` | help page, any key goes back |
| `D` | debug overlay on / off (see below) |
| `F7` | quit: asks `QUIT? Y/N`, then back to BASIC (READY) |

Colour 0 is black and see-through: it is what the rubber draws and what a new picture holds.
The toolbar uses colours from the palette (a dark blue, a grey, white); if you edit those, the
toolbar changes too.

## Saving, opening, importing

`S`, `O` and `I` ask for a name first: type letters, digits, space, `-` or `.` (up to 12);
`DEL` rubs out; `RETURN` accepts; `RUN/STOP` cancels. The last name is kept for next time.
OCTOPAINT adds `.OCT` unless you typed it. Then `DISK IN DRIVE 8? Y/N`. Y starts; a bar on the line
above the toolbar shows the rows done (a disk is slow: roughly 200 bytes a second, so a 12 KB picture
takes about a minute). The result is shown at the bottom, for example `SAVED TEST.OCT 3,102 BYTES`.
If the drive says something other than `00` (file not found, disk full, drive not ready ...) its
message is shown. Saving over a name that exists replaces it.

A bad file (not an .OCT, a different picture size, cut short) is refused with a message; a
picture that fails half way is a half picture, and `U` brings the old one back. Opening a picture
loads its palette too (this one is not undone).

`I` reads a Koala painter file (a PRG of 10003 bytes) under the name exactly as typed (no `.OCT`
is added). Each 160 x 200 multicolour pixel becomes two pixels across; C64 colour c becomes palette
entry c (0-15), so import is best with the default palette.

### The .OCT format (version 1)

| offset | bytes | value |
|---|---|---|
| 0 | 4 | `OCT1` (ASCII) |
| 4 | 2 | width, little endian (320) |
| 6 | 2 | height, little endian (200) |
| 8 | 1 | bits per pixel: 8 |
| 9 | 1 | packing: 0 none, 1 run-length |
| 10 | 768 | palette: 256 x (R, G, B), 0-255 |
| 778 | ... | pixels, row 0 first, left to right, packed (or 64000 raw bytes) |

OCTOPAINT build 1 reads and writes 320 x 200 only; it writes packing 1. Pixel value = palette entry
number. Run-length packing works over the whole picture (rows are not separate):

- control byte `n` = 0 to 127: `n + 1` literal bytes follow;
- control byte `n` = 128 to 255: the next byte is repeated `n - 125` times (3 to 130).

The writer is the same on the 6502 and in `tools/octopaint/mkoct.py`, so the files are
byte for byte the same: a run of 3 or more equal bytes (at most 130) becomes a repeat packet; everything
else goes into literal packets of up to 128 bytes. A literal packet is written when it is full, before
a repeat packet, and at the end. A worst case picture is 64000 x 129/128 + 778 bytes, a little over 65 KB.

`mkoct.py` makes and reads .OCT files on a PC:

    mkoct.py to-oct picture.png OUT.OCT     (320 x 200, any PNG/BMP; scaled and reduced to 256 colours)
    mkoct.py to-png OUT.OCT picture.png
    mkoct.py from-koala PIC.KLA OUT.OCT     (the same decode as the I key)
    mkoct.py csum OUT.OCT                   (the checksum the debug overlay shows)
    mkoct.py examples DIR                   (the two pictures on the disk)

## The debug overlay (D)

Two lines at the top of the screen: `LATE` (OctoVIC lines that were late last frame, 0 is right),
`TOT` (late lines since reset), `CRC` (a checksum of the 320 x 200 picture, worked out when you press
D, about two seconds: two pictures with the same pixels have the same CRC), `FILL` (the last flood fill's
time in frames, 50 to the second), `PTR` (the pointer on the screen), `CVS` (the canvas pixel under it) and
`FREE` (RAM left between the program and the buffers).

## Technical notes (for the Windows version, and for tinkerers)

**Hardware used.** OctoVIC (unlock `$4F`, `$38` to `$D03F`): layer 0 is the canvas, a 256-colour bitmap, 512 x
256 in VRAM, the picture in its top left 320 x 200 (colour 0 shows the black backdrop); layer 1 is the
toolbar bitmap; the VIC-II text (colour RAM and screen RAM) is in front with KEYEN on and key colour black,
so only the letters show; sprite 0 is the arrow, sprite 1 the crosshair. Lines and filled rectangles, the
undo copy and clears are blitter jobs; single pixels and the flood fill's reading go through VDATA with VINC = 1.
Zoom is layer 0 "turned and sized" (DUX = DVY = 1/zoom).
No blit runs flat out across the whole picture except the undo copy, which is 320 x 200 once per stroke.
OctoVIC's LATE counter stays 0.

| VRAM | what |
|---|---|
| `$000000` | the canvas (512 x 256) |
| `$020000` | the undo copy |
| `$040000` | the toolbar bitmap |
| `$060000` | sprite graphics |
| `$061000` | the sprite table |

**RAM.** The program is at `$0801` (SYS 2061) up to about `$3C00`. `$A000-$ABFF` is the fill's stack
(1024 seeds in three arrays), `$AC00` the packer's literal buffer, `$C000` the fill's row, `$C400` a
loaded palette waiting, `$CA00-$CCFF` the working palette (768 bytes). A Koala import uses `$A000-$C7E7`.
The KERNAL is on and BASIC is off; BASIC's own pointers are untouched, so quitting gives a normal READY.

**Input.** The keyboard is read from the CIA matrix directly; CIA interrupts are masked, and one raster
interrupt per frame (line 252) is the clock. `$DC00` is kept at `$7F` between scans so that port 1's POT lines are
selected (bit 6 high). The joysticks are read with `$DC00 = $FF`. The mouse is a 1351 on POTX/POTY:
`(POT >> 1) & $3F` is 6 bits, the difference from the last frame is signed, jumps of 24 or more are noise and
ignored, and Y is inverted. The 1351's buttons are the joystick's fire (left) and up (right) bits.

The keys used, as (CIA column, row): P 5,1; B 3,4; L 5,2; R 2,1; C 2,4; F 2,5; K 4,5; E 1,6; U 3,6; Z 1,4;
N 4,7; S 1,5; O 4,6; I 4,1; H 3,5; D 2,2; M 4,4; F7 0,3; `<-` 7,1; CTRL 7,2; RETURN 0,1; DEL 0,0;
RUN/STOP 7,7; SPACE 7,4; Q 7,6; W 1,1; A 1,2; S 1,5; D 2,2; Z 1,4; digits 1 7,0, 2 7,3, 3 1,0, 4 1,3;
`+` 5,0, `-` 5,3, `,` 5,7, `.` 5,4; cursor keys: right 0,2 and down 0,7 (with SHIFT: left, up).

**Disk.** Everything goes through the KERNAL (OPEN, CHKIN, CHKOUT, CHRIN, CHROUT, CLOSE) to device 8, and
the raster interrupt is switched off while the drive is busy. Saving first scratches the old file (`S0:NAME.OCT`
on the command channel), then writes `NAME.OCT,S,W`; the drive's error channel is read after opening and after
closing. The picture never sits in RAM: it streams between the file and VRAM.

**The paint routines are kept apart from the hardware.** The paint code touches the picture only through
`plot`, `fillrect`, `readpixel` (and `readrow`, `drawline`) with coordinates and colours in fixed variables; the
list is at the top of `octopaint.asm`. A Windows version can start from `mkoct.py` and the format above.

## What build 1 does not have

- No grid at 4x zoom (the key `G` is not used).
- The palette has 14 hue ramps of 16 steps (the spec asks for 15, which would not leave room for the grey
  ramp in 240 entries): entries 0 black, 1-15 C64-like, 16-239 the ramps (dark to light), 240-255 greys.
- Keyboard diagonal moves (two cursor keys at once) work, but TAB is the `<-` key or CTRL (a C64 has no TAB).
- Flood fill reads 320 pixels a row through VDATA: an empty 320 x 200 picture takes about 8 seconds.
  A 4-way fill into a picture shaped like a comb can run out of its 1024 seeds: `FILL TOO BIG`.
- One level of undo.

## Building it

    tools/octopaint/build.sh OUTDIR

needs `acme`, `c1541` (VICE), `zip` and python3 with PIL. It makes `OCTOPAINT.PRG`, `OctoPaint Disk build
1.d64` (OCTOPAINT first, then the two example pictures TESTCARD.OCT and PALETTE.OCT drawn by `mkoct.py`) and
`OCTOPAINT build 1.zip` with a plain text copy of this file as `How to use.txt`.
