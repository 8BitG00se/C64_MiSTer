# OctoVIC - the Octophonic 64's graphics chip

By Mong00se. Version 2 (31 Oct 2026): the maths unit, the blitter, the bitmap layer, collisions and the interrupt.

The VIC-II is untouched: every C64 program looks and runs as before. OctoVIC is a second video
chip, in the style of an 80s arcade board, that draws behind or in front of the VIC's picture:

- 16 MB of video memory (VRAM) of its own, in the DE10-Nano's DDR3
- a 256-colour palette, 24-bit colour, and the VIC's own 16 colours made programmable
- two scrolling tile layers: 8x8 tiles, 16 or 256 colours, maps up to 256x256 tiles,
  flips, a palette bank per tile, and a scroll offset per raster line (parallax in one layer)
- 128 hardware sprites, 8 to 64 pixels each way, 16 or 256 colours, flips, three priorities
- a copper: a list in VRAM of register writes, each at its raster line - splits, palette
  changes, scroll changes with no work for the 6510
- drawn over the whole visible picture, borders too (x -32..363, raster lines 16-299)
- version 2: a maths unit (16x16 multiply, 32/16 divide), a blitter (copy, fill, see-through
  copy, lines - in the VRAM, on its own), sprite collisions, and an interrupt

## Switching it on

OctoVIC hides until a program asks for it, so nothing that uses $D600-$D6FF as SID mirrors is
affected. Write $4F then $38 to $D03F (an unused VIC register) and $D600-$D6FF become OctoVIC's
registers; write anything else to $D03F and they are SID mirrors again. Reading $D61E then
gives $8C (the ID) and $D61F the version.

## Coordinates

x = 0 is the left edge of the VIC's 40-column window, y = 0 its top line in 25-row mode (raster
line 51). OctoVIC draws x = -32 to 363 on raster lines 16 to 299 - all the picture a screen
shows. Positions and scrolls are in pixels of the VIC's hires (320-wide) grid.

## Registers ($D600 + n)

| n | name | |
|---|---|---|
| 00-02 | VADDR | VRAM byte address, low byte first (24 bits) |
| 03 | VINC | added to VADDR after every VDATA read or write |
| 04 | VDATA | write: VRAM[VADDR] = value. Read: VRAM[VADDR] (fetched when VADDR was set or moved on; allow 2 us) |
| 05 | CTRL | b0 ENABLE (draw the layers and sprites), b1 VICPAL (the VIC's 16 colours from OctoVIC's VIC palette), b2 VICBACK (the VIC behind everything, else in front), b3 KEYEN (with the VIC in front: its KEY colour is see-through, to the layers or else the backdrop) |
| 06 | KEY | the VIC colour (0-15) that is see-through when KEYEN |
| 07 | - | (reserved) |
| 08 | STATUS (r) | b0 VRAM writes still queued, b1 the divider busy, b2 the blitter busy |
| 09-0A | LINE (r) | the raster line being shown |
| 0B | FRAME (r) | counts frames |
| 0C | XADJ | signed: moves all of OctoVIC's picture right (fine alignment, normally 0) |
| 0D | YADJ | signed: moves it down |
| 0E | COPCTL | b0 the copper on |
| 0F | SPRCOUNT | sprites in use, 0-128 |
| 10-12 | COPBASE | the copper list in VRAM |
| 13-15 | SATBASE | the sprite table in VRAM (copied in once a frame, before raster line 0 is drawn) |
| 16-18 | SPRGFX | sprite graphics base in VRAM |
| 19 | PALSEL | 0 the main palette (256), 1 the VIC palette (16), 2 the backdrop (1: shown where the VIC's KEY colour is over no layer pixel) |
| 1A | PALIDX | the palette entry to write |
| 1B-1D | PALR, PALG, PALB | its red, green, blue; writing PALB stores the entry and moves PALIDX on |
| 1E | ID (r) | $8C |
| 1F | VERSION (r) | 2 |
| 20-2F | LAYER 0 | see below |
| 30-3F | LAYER 1 | |
| 40-42 | COPSTEP | the animation: added to the copper list's address each step |
| 43-44 | COPSTEPS | how many steps before it starts again |
| 45 | COPDIV | frames a step (0: no copper animation) |
| 46-48 | SATSTEP | the same for the sprite table |
| 49-4A | SATSTEPS | |
| 4B | SATDIV | |
| 50-53 | MULA, MULB | version 2: the maths unit - two 16-bit numbers |
| 54-57 | MULR (r) | MULA x MULB, 32 bits, at once |
| 58 | MATHCTL | b0 the multiply is signed |
| 59-5C | DIVN | a 32-bit number to divide |
| 5D-5E | DIVD | by this (16 bits); writing 5E starts it - done in a microsecond (STATUS b1) |
| 60-63 | DIVQ (r) | the quotient (dividing by 0: $FFFFFFFF) |
| 64-65 | DIVR (r) | the remainder (dividing by 0: DIVN's low 16 bits) |
| 66-6D | LX0, LY0, LX1, LY1 | the blitter's line: from (LX0,LY0) to (LX1,LY1), signed 16-bit |
| 70-72 | BSRC | the blitter: source address in VRAM |
| 73-75 | BDST | destination (for LINE: the bitmap's first byte) |
| 76-77 | BW | width in bytes (LINE: the bitmap's width - the line is clipped to it) |
| 78-79 | BH | height in rows (LINE: the bitmap's height) |
| 7A-7B | BSSTR | source rows this many bytes apart (signed) |
| 7C-7D | BDSTR | destination rows this many bytes apart (signed; LINE: the bitmap's row length) |
| 7E | BFILL | the fill / line colour |
| 7F | BCTRL | write: b0 1 = go, b1-2 the operation - 0 COPY, 1 FILL, 2 COPY0 (source 0 bytes left out: see-through), 3 LINE. Read: b7 busy |
| 80-81 | IRQLINE | the raster line for the raster interrupt (9 bits) |
| 82 | IRQEN | the interrupt's causes on: b0 the raster line, b1 a sprite hit a sprite, b2 a sprite hit a layer, b3 the blitter finished |
| 83 | IRQST | read: what has happened (the same bits; set even when not enabled). Write 1s to clear those bits |
| 84 | COLLIDX | which 8 sprites COLLSS / COLLSL show (0-15: sprites 8n..8n+7) |
| 85 | COLLSS (r) | last frame: these sprites touched another sprite (a bit a sprite) |
| 86 | COLLSL (r) | last frame: these sprites touched a layer pixel |
| C0 | SIDFX | OctoSID FX: b0 chorus, b1 echo (see below); also in the core's menu |

### A layer (20 + 16*k)

| +n | name | |
|---|---|---|
| 0 | LCTRL | b0 on, b1 256 colours (else 16), b2 line scroll on, b3 BITMAP (version 2: see below), b4-5 map width (0 = 32, 1 = 64, 2 = 128, 3 = 256 tiles), b6-7 map height (the same) |
| 1-3 | MAPBASE | the map in VRAM (8-byte aligned) |
| 4-6 | TILEBASE | the tiles in VRAM (8-byte aligned) |
| 8-9 | SCROLLX | |
| A-B | SCROLLY | |
| C-E | LSBASE | the line scroll table: a signed 16-bit X offset per raster line (line n at LSBASE + 2n) |

A map entry is 16 bits: bits 0-9 the tile, 10 flip across, 11 flip up-down, 12-15 the palette
bank (16 colours: palette entry = bank*16 + pixel; 256 colours: bits 12-15 are the tile number's
top bits instead - tile = bits 12-15 * 1024 + bits 0-9, up to 16384 tiles). A tile is 32 bytes (16 colours: 4 bytes a
row, high nibble the left pixel) or 64 bytes (256 colours: a byte a pixel). Pixel 0 is
see-through.

The layer pixel at screen (x, y) is map pixel (x + SCROLLX + LS[line], y + SCROLLY), wrapping
round the map.

**BITMAP (version 2).** With LCTRL b3 set the layer has no map and no tiles: it is a picture of
one byte a pixel (256 colours, 0 see-through) at TILEBASE, (map width x 8) pixels wide and
(map height x 8) tall, a row (map width x 8) bytes - 256 to 2048 pixels each way. It scrolls and
wraps like a tile layer. The blitter draws straight onto it: a paint program's canvas.

## Sprites

The sprite table: 8 bytes a sprite, sprite 0 drawn on top.

| byte | |
|---|---|
| 0-1 | X (signed) |
| 2-3 | Y (signed) |
| 4-5 | GFX: the graphics at SPRGFX + 32*GFX |
| 6 | b0-1 width (8, 16, 32, 64), b2-3 height (the same), b4 flip across, b5 flip up-down, b6 256 colours, b7 on |
| 7 | b0-3 palette bank, b4-5 priority: 0 in front of both layers, 1 between them, 2 behind both |

Graphics are rows of (width/2) bytes (16 colours) or width bytes (256 colours), top row first.
Up to 64 sprites on one raster line - with both layers on, about 3000 sprite pixels a line (48 sprites 64 wide in 256 colours) whatever the DDR3 is doing.

## Version 2: the maths unit, the blitter, collisions, the interrupt

**Maths.** MULR is MULA x MULB at once, unsigned (or signed, MATHCTL b0) - for 3D, rotation,
physics, anything a 6510 multiplies slowly. Writing DIVD's high byte starts DIVN / DIVD; it is
done before the 6510 can read the answer.

**The blitter** works in the VRAM on its own while the 6510 gets on with something else, using
the DDR3 when nothing else wants it (the picture never waits for it). Set it up, write BCTRL with
b0 set, and wait for STATUS b2 (or BCTRL b7) to clear - or for the interrupt. A write to BCTRL
while it is busy is ignored.

- COPY: BW x BH bytes from BSRC to BDST, the rows BSSTR and BDSTR apart. Any alignment.
- FILL: the same rectangle at BDST, all BFILL.
- COPY0: COPY, but source bytes of 0 are not copied - see-through, for drawing shapes over a
  picture (a brush, a sprite, a font).
- LINE: a line from (LX0,LY0) to (LX1,LY1), both ends drawn, in BFILL, in a byte-a-pixel bitmap
  at BDST with BDSTR bytes a row, clipped to BW x BH.

The copper can start it too (write BCTRL from a copper list).

**Collisions.** While each line is drawn, OctoVIC notes for every pixel whether a layer pixel and
which sprite's pixel are there. A sprite pixel landing on another sprite's sets both sprites'
COLLSS bits; a sprite pixel and a layer pixel in the same place (either on top) set the
sprite's COLLSL bit. Only pixels drawn count (not see-through ones, and not off the edges). At
the end of each frame the frame's collisions become the readable ones (COLLIDX picks which 8
sprites to read).

**The interrupt.** OctoVIC can interrupt the 6510 (its IRQ, with the VIC's and the CIA's): when
the raster line reaches IRQLINE, when last frame had a collision, when the blitter finishes. IRQST
says which (write 1s to clear them); IRQEN says which interrupt. Nothing interrupts until IRQEN is
set, so no old program is affected.

## Animation

OctoVIC can step through a sequence of copper lists and sprite tables on its own, a frame at a
time, with no work for the 6510: every COPDIV frames the copper list in use moves on by COPSTEP
bytes, and after COPSTEPS steps it is back at COPBASE; the sprite table the same with SATDIV,
SATSTEP and SATSTEPS. A sunset fading to night is a few hundred copper lists, each loading the
palette for its moment; a ship flying past is a sprite table a frame. Writing COPBASE, SATBASE
or any of these registers starts both from the beginning.

## OctoSID FX

With 4 or 8 SIDs, what SID 1 plays can be spread over SIDs 2-4, for any program, untouched:
chorus (b0) - every write to SID 1 also goes to SID 2, its pitches 0.6% sharp: SID 1 left,
SID 2 right, a wide stereo sound; echo (b1) - every write to SID 1 again on SID 3, 140 ms later,
and SID 4, 200 ms later, at half the volume: a stereo echo. The extra writes go on clocks the
6510 is not using the SIDs. The core's menu (OctoSID FX) turns it on for anything; register
$C0 lets a program do it.

## The copper

A list in VRAM of 4-byte entries: raster line (16 bits), register (n, as above), value. Before
each raster line is drawn, the entries for it (and any earlier ones not yet done) are done in
order; the list ends with line $FFFF. It starts again from COPBASE at raster line 0 - and after COPCTL
or COPBASE is written, it waits for the next line 0 before it does anything. Registers
00-04 are not written by the copper.

## How it is drawn

Each raster line is drawn into a line buffer up to three lines ahead of the beam, in this order:
sprites of priority 2, layer 0, sprites of priority 1, layer 1, sprites of priority 0 - each
opaque pixel over what is there. The palette, the backdrop, CTRL and KEY are taken as the line is drawn,
so a change to any of them by the copper takes effect on its own line (a gradient sky: a backdrop
colour a line; a split: the VIC in front of one band and behind the next). Written by the 6510
instead, CTRL and KEY show up to three lines later. The VIC palette acts as the beam gets there.
On screen, the VIC's pixel is then put in front (see-through where it is the KEY colour) or behind.

VRAM is at DDR3 byte address $32000000 (16 MB); the 1541's track buffers are at $30000000.
