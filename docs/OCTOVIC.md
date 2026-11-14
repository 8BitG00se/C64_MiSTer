# OctoVIC - the Octophonic 64's graphics chip

By Mong00se. Version 2 (31 Oct 2026): the maths unit, the blitter, the bitmap layer, collisions, the interrupt, see-through colours and turning and sizing.

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
  copy, lines - in the VRAM, on its own), sprite collisions, an interrupt, and see-through
  colours (half and half, added, taken away) for layers and sprites, and a bitmap layer turned
  and sized (rotation and zoom, perspective with the copper)

## Switching it on

OctoVIC hides until a program asks for it, so nothing that uses $D600-$D6FF as SID mirrors is
affected. Write $4F then $38 to $D03F (an unused VIC register) and $D600-$D6FF become OctoVIC's
registers; write anything else to $D03F and they are SID mirrors again. Reading $D61E then
gives $8C (the ID) and $D61F the version: 2 = the first OctoVIC (core builds up to 6), 3 = with the
memory work (line-end wait, copper read-ahead, late-line repeat, the meters at $D6A8-$D6B1) - core
memory build 3 on, 4 = with FINE SCROLL (quarter pixels, Fix 42), 5 = with OCTOSCOPE (an oscilloscope of every SID voice,
Fix 55). A demo that needs the memory work checks for 3 or more and says so if it isn't there.

## Coordinates

x = 0 is the left edge of the VIC's 40-column window, y = 0 its top line in 25-row mode (raster
line 51). OctoVIC draws x = -32 to 363 on raster lines 16 to 299 - all the picture a screen
shows. Positions and scrolls are in pixels of the VIC's hires (320-wide) grid.

## Registers ($D600 + n)

| n | name | |
|---|---|---|
| 00-02 | VADDR | VRAM byte address, low byte first (24 bits) |
| 03 | VINC | added to VADDR after every VDATA read or write |
| 04 | VDATA | write: VRAM[VADDR] = value (queued: up to 63 bytes wait while the DDR3 is busy - 63 us of an REU upload; a byte that finds the queue full is lost and counted in LOST). Read: VRAM[VADDR] (fetched when VADDR was set or moved on; allow 2 us) |
| 05 | CTRL | b0 ENABLE (draw the layers and sprites), b1 VICPAL (the VIC's 16 colours from OctoVIC's VIC palette), b2 VICBACK (the VIC behind everything, else in front), b3 KEYEN (with the VIC in front: its KEY colour is see-through, to the layers or else the backdrop), b4 HIDEVIC (with ENABLE: the VIC is left out of the picture - the layers and sprites over the backdrop; see SPLIT SCREENS) |
| 06 | KEY | the VIC colour (0-15) that is see-through when KEYEN |
| 07 | SPRFINE | version 4: b1-0 every sprite 0-3 quarter pixels further right (see FINE SCROLL) |
| 08 | STATUS (r) | b0 VRAM writes still queued, b1 the divider busy, b2 the blitter busy, b3 SPLIT (the Split Screens menu option is on), b4 QUARTER PIXELS (version 4: the 4x pixel clock reaches the output - FINE SCROLL shows), b5 60 Hz recording mode (always 0: there is none on the MiSTer) |
| 09-0A | LINE (r) | the raster line being shown |
| 0B | FRAME (r) | counts frames |
| 0C | XADJ | signed: moves all of OctoVIC's picture right (fine alignment, normally 0) |
| 0D | YADJ | signed: moves it down |
| 0E | COPCTL | b0 the copper on |
| 0F | SPRCOUNT | sprites in use, 0-128 |
| 10-12 | COPBASE | the copper list in VRAM |
| 13-15 | SATBASE | the sprite table in VRAM (copied in once a frame, before raster line 0 is drawn: the copy starts as the beam begins line 309 (PAL; 260 NTSC) - a table uploaded in the vertical blank must be in by then) |
| 16-18 | SPRGFX | sprite graphics base in VRAM |
| 19 | PALSEL | 0 the main palette (256), 1 the VIC palette (16), 2 the backdrop (1: shown where the VIC's KEY colour is over no layer pixel) |
| 1A | PALIDX | the palette entry to write |
| 1B-1D | PALR, PALG, PALB | its red, green, blue; writing PALB stores the entry and moves PALIDX on |
| 1E | ID (r) | $8C |
| 1F | VERSION (r) | 2; 3 with the memory work (core build 7 on); 4 with FINE SCROLL; 5 with OCTOSCOPE |
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
| 88-8B | U0 | version 2, TURNED AND SIZED: where in the picture raster line 0's pixel 0 is, across (16.16, signed) |
| 8C-8F | V0 | the same, down |
| 90-93 | DUX | the step across the picture for each pixel along a line (16.16, signed; 1.0 at reset) |
| 94-97 | DVX | the step down the picture for each pixel along a line (0 at reset) |
| 98-9B | DUY | the step across the picture for each line down (0 at reset) |
| 9C-9F | DVY | the step down the picture for each line down (1.0 at reset) |
| A0 | LATE (r) | last frame: lines shown before OctoVIC had finished drawing them (the line buffer ran dry), 0-255 |
| A1 | LATE0 (r) | of those, lines it was still drawing layer 0 for |
| A2 | LATE1 (r) | ... layer 1 |
| A3 | LATEOTH (r) | ... anything else: sprites, the copper, the sprite table, or not started at all |
| A4-A5 | LATEFIRST (r) | last frame's first late line (9 bits; $1FF none) |
| A6-A7 | LATETOTAL (r) | late lines since reset, 16 bits, stops at $FFFF |
| A8 | REPEAT (r) | memory build: last frame, late lines shown as a copy of the line above (instead of half drawn) |
| A9 | BLANK (r) | memory build: last frame, late lines shown without the layers (no finished line close enough to copy) |
| AA-AB | WORST (r) | memory build: last frame, the longest any line took to draw, in clocks (31.5 MHz PAL: 2016 clocks = one raster line; up to three lines ahead is fine) |
| AC-AD | WORSTLINE (r) | memory build: which line that was (9 bits) |
| AE | LATMAX (r) | memory build: last frame, the longest DDR3 round trip seen (a read asked for with none in flight, to its answer), clocks, 255 = 255 or more |
| AF | LATAVG (r) | memory build: a running average of that round trip, clocks |
| B0 | STALL (r) | memory build: last frame, the % of the frame the DDR3 port made OctoVIC wait |
| B1 | LEAD (r) | memory build: last frame, the fewest lines ahead of the beam a line was finished (3 best, 0 = late) |
| B2 | LOST (r) | VDATA writes lost since reset because the write queue was full (the DDR3 port held for over 63 writes), stops at 255; write anything to clear it. A healthy machine reads 0 (an older core reads $FF) |
| B4-B6 | BUILD DATE (r) | version 3: the core's build date, BCD: day, month, year (20xx) |
| B8-BF | CORE NAME (r) | version 3: the core's name, 8 ASCII letters padded with spaces (e.g. CORE7) - shown on the start screen and the F8 settings |
| C0 | SIDFX | OctoSID FX: b0 chorus, b1 echo (see below); also in the core's menu |
| C4 | SCV | version 5, OCTOSCOPE: what the scope shows - b0-4 a voice 0-23 (SID s, voice v: 3s + v; 24-31 count from 0 again), or with b5 set SID b0-2's whole output (after its filter and volume) |
| C5-C6 | SCY | the scope's centre raster line (9 bits) |
| C7 | SCH | half its height, in lines (it is drawn on lines SCY - SCH to SCY + SCH) |
| C8 | SCG | its gain: a sample s (-127..127) is drawn s x SCG / 128 lines above the centre |
| C9 | SCC | its colour (a palette entry); the glow is SCC + 1 |
| CA | SCX0 | the x of its first sample (x 0 is the 40-column window's left edge); 304 samples, a pixel each |
| CB | SCF | b0 the glow (a line more each way, in SCC + 1) |
| CC-CE | VMUTE0-2 (r/w) | Fix 65, the mixer: a mute bit for each of the 24 SID voices - CC b0-7 voices 0-7, CD voices 8-15, CE voices 16-23 (voice = 3s + v, as in SCV); 1 = muted, 0 = plays. Reads back, so a program can flip one bit. The voice is silenced just before its SID's filter (its oscillator, sync and ring links, and the scope's view of it are unchanged). All 0 after a reset. Solo is a program's job: write FF to the other bits. |
| CF | SCOPEKEY (r/w) | Fix 72, THE SCOPE OVER ANY PROGRAM (see below): b1-0 - 0 off, 1 all 24 voices' traces drawn over the picture; Fix 82, THE SCOPE ON THE SECOND SCREEN: 2 the scope screen on HDMI and the picture on the VGA output, 3 the two swapped. The hot key SHIFT+F3 (held) moves it on (0, 1, 2, 3, 0); a program may write it (the CPU only, not the copper). A reset leaves it as it is. |

### A layer (20 + 16*k)

| +n | name | |
|---|---|---|
| 0 | LCTRL | b0 on, b1 256 colours (else 16), b2 line scroll on, b3 BITMAP (version 2: see below), b4-5 map width (0 = 32, 1 = 64, 2 = 128, 3 = 256 tiles), b6-7 map height (the same) |
| 1-3 | MAPBASE | the map in VRAM (8-byte aligned) |
| 4-6 | TILEBASE | the tiles in VRAM (8-byte aligned) |
| 8-9 | SCROLLX | |
| A-B | SCROLLY | |
| C-E | LSBASE | the line scroll table: a signed 16-bit X offset per raster line (line n at LSBASE + 2n) |
| 7 | FINE | version 4: b1-0 the layer 0-3 quarter pixels further left (on from SCROLLX; see FINE SCROLL) |
| F | LMODE | version 2: b0-1 how the layer's pixels mix with what is under them (see SEE-THROUGH COLOURS), b2 TURNED AND SIZED (a bitmap layer), b3 with b2: nothing drawn outside the picture (else it repeats); version 5: b4 the layer is the OCTOSCOPE (see below) instead of tiles or a bitmap |

A map entry is 16 bits: bits 0-9 the tile, 10 flip across, 11 flip up-down, 12-15 the palette
bank (16 colours: palette entry = bank*16 + pixel; 256 colours: bits 12-15 are the tile number's
top bits instead - tile = bits 12-15 * 1024 + bits 0-9, up to 16384 tiles). A tile is 32 bytes (16 colours: 4 bytes a
row, high nibble the left pixel) or 64 bytes (256 colours: a byte a pixel). Pixel 0 is
see-through.

The layer pixel at screen (x, y) is map pixel (x + SCROLLX + LS[line], y + SCROLLY), wrapping
round the map.

**FINE SCROLL (version 4, Fix 42).** FINE (b1-0 of $D627 / $D637) carries on from SCROLLX: the
layer's position in quarter pixels is 4 x SCROLLX + FINE. Keep the scroll as 8.8 and write the whole
part to SCROLLX and the top two bits of the fraction (frac >> 6) to FINE - it moves a quarter pixel
at a time, the same way, across every whole-pixel step. SPRFINE ($D607) does the same for every sprite:
4 x X + SPRFINE. The copper can write all three (parallax bands: a FINE beside each band's SCROLLX).
Nothing is blended: each C64 pixel goes out as 4 sub-pixels on a 31.5 MHz pixel clock and the layer
just starts 1-3 of them later (inside: drawn a pixel further on and held back 4 - FINE). Where two
things with different FINE meet, the edge of the one in front is exact; what is behind it can be off
by up to 3/4 of a pixel right at that edge. A turned-and-sized layer ignores FINE; the VIC never moves.
It shows only while the menu's Quarter Pixels is On (the default) with Scandoubler Fx None and no
gamma curve - STATUS b4 says so; otherwise FINE is not used and everything moves in whole pixels.
On HDMI the scaler gets about 1,600 pixels a line: at 1080p a quarter step is about 0.9 HDMI pixel.

**BITMAP (version 2).** With LCTRL b3 set the layer has no map and no tiles: it is a picture of
one byte a pixel (256 colours, 0 see-through) at TILEBASE, (map width x 8) pixels wide and
(map height x 8) tall, a row (map width x 8) bytes - 256 to 2048 pixels each way. It scrolls and
wraps like a tile layer. The blitter draws straight onto it: a paint program's canvas.

**TURNED AND SIZED (version 2).** A bitmap layer with LMODE b2 set is drawn at any angle and any
size (the SNES's mode 7, and more: each line can be its own). For pixel x (0 = OctoVIC's left
edge, x = -32 on the C64's screen; 395 the right) of raster line L the picture's pixel is

    u = U0 + DUX * x + DUY * L        v = V0 + DVX * x + DVY * L        (16.16: the top 16 bits the pixel)

So for a turn by angle a and a zoom z (z picture pixels to a screen pixel): DUX = DVY = z cos a,
DVX = z sin a, DUY = -z sin a, and U0, V0 put the picture's middle where you want it:
U0 = cu - (xc DUX + Lc DUY), V0 = cv - (xc DVX + Lc DVY) puts picture pixel (cu, cv) at (xc, Lc).
The maths unit does the multiplies. The picture repeats in both directions (a floor that goes on
forever) unless LMODE b3 is set. SCROLLX/Y are not used. The copper can change any of the six
numbers on any line: a different DUX and U0 a line is a road or a floor going off into the
distance (perspective). It costs a VRAM read for each 1 to 4 pixels (4 when neighbours share
8 bytes - zoomed in), so it is the heaviest thing OctoVIC draws: with both layers and many big
sprites on the same lines, keep the other layer simple.

## Sprites

The sprite table: 8 bytes a sprite, sprite 0 drawn on top.

| byte | |
|---|---|
| 0-1 | X (signed) |
| 2-3 | Y (signed) |
| 4-5 | GFX: the graphics at SPRGFX + 32*GFX |
| 6 | b0-1 width (8, 16, 32, 64), b2-3 height (the same), b4 flip across, b5 flip up-down, b6 256 colours, b7 on |
| 7 | b0-3 palette bank, b4-5 priority: 0 in front of both layers, 1 between them, 2 behind both, b6-7 how its pixels mix (version 2: see below) |

**SEE-THROUGH COLOURS (version 2).** A layer (LMODE b0-1) or a sprite (byte 7 b6-7) can mix each
of its pixels with whatever is already drawn under it, red, green and blue each on its own:

| mode | the pixel's colour |
|---|---|
| 0 | its own (as version 1) |
| 1 | half and half: (under + own) / 2 - glass, ghosts, shadows in a colour |
| 2 | added: under + own, 255 at most - light, fire, beams, glows |
| 3 | taken away: under - own, 0 at least - shadows, darkness |

Pixel 0 stays see-through, and where nothing is under the pixel (the backdrop or the VIC shows
there) it is drawn as it is. A sprite mixes with what is drawn before it - the sprites behind it,
and the layers below its priority - so the order in HOW IT IS DRAWN decides what it sees.
Free: no extra time, any number of pixels.

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

## OCTOSCOPE (version 5, Fix 55)

A real oscilloscope of every SID voice, drawn by OctoVIC: a trace that stands still like a triggered scope and
always shows two whole cycles, whatever the note.

**What it captures.** Every microsecond, from every one of the 8 SIDs: each voice's waveform centred on its own
middle (the voice's 12-bit DAC value - 2048, whatever the chip's DC) times its envelope (0-255), >> 12 - a sample
from -127 to 127; and each SID's whole output (after its filter and volume) >> 10. That is 32 channels: SCV 0-23
the voices, SCV $20-$27 the SIDs' outputs.

- A voice playing a note (FREQ 839 or more, about 50 Hz and up) is captured **in step with its own oscillator**: a
  capture starts when the oscillator wraps round, and takes 152 samples a cycle - sample n is taken at the moment
  the oscillator has gone n / 152 of the way round - for two cycles: 304 samples. If the waveform changes during it
  (a hard sync, the test bit, a note change) the capture follows the oscillator; a wrap that comes early ends the
  cycle there (the rest of it is that moment's sample).
- Below 50 Hz, or a voice whose oscillator has stopped (the test bit held, FREQ 0), or a capture not complete
  40 ms after it started, it is captured **by time**: a sample every 66 us (304 = a frame across).
- The whole outputs are always captured by time.

A capture is shown only when it is complete. At the start of each frame (as OctoVIC starts raster line 0) the
newest complete capture of every channel is taken for that frame: a frame never shows two halves of different
captures.

**Showing it.** A layer with LMODE b4 set is drawn as the scope instead of tiles or a bitmap (LCTRL b0 must be on;
its map, tiles and scroll are not used). On each raster line L within SCH of SCY, for sample i = 0..303 at x =
SCX0 + i: y(i) = -(sample(i) x SCG) / 128 (rounded towards 0). The pixel is lit in colour SCC where
L - SCY is between y(i - 1) and y(i) (y(-1) = y(0)), each held to +-SCH - so the trace never breaks, however
steep. With SCF b0 (the glow), the pixels a line beyond that each way are drawn in SCC + 1. Everything else is
see-through. The scope's pixels mix (LMODE b0-1) and collide like any layer pixel; palette entry 0 is drawn, not
see-through. FINE does not move it. The 304 samples are drawn from SCX0 on and cut off at the right of OctoVIC's
picture (x 363).

**With the copper.** The copper can change SCV, SCY, SCH, SCG, SCC, SCX0, SCF and LMODE on any line - a band of
the screen for each voice (OctoPlay draws up to 24 bands, each with a palette change of its own). A line is drawn
with the registers as the copper leaves them for it, like CTRL (written by the 6510, they show up to three lines
early).

**What it costs.** The captures are in the DDR3, above the VRAM (byte $33000000, 29 KB - see
docs/OCTOVIC_MEMORY.md), so nothing of the 16 MB VRAM is used. Writing them is light: each channel gathers 8
samples into one word before it is written - a note of a few hundred Hz is a word every few hundred microseconds,
24 voices at the very top of the range under 2 words a microsecond - and those writes wait for the renderer's
reads. Drawing a scope line takes about 160 clocks (2 pixels a clock) after the pixels drawn before it on the line
are in; when a line shows a different channel from the line before (a new band) or a new frame's captures, its
304 samples are first fetched into a line cache: 38 reads, like a line of a bitmap layer.

**How the hardware does it (rtl/octovic/octoscope.sv).** One clock per channel: 32 clocks are one microsecond, so the
32 channels are taken one after the other, the voices' values held from the microsecond's edge (sid_voice, through
a record each SID pair hands over on request). Each channel has three slots of 304 samples in the DDR3 - the one
being captured, the newest complete one, the one shown - and only the slot numbers change (no copying): a complete
capture becomes the newest, the free slot is the next one captured into, and the frame's latch (at the end of a
whole microsecond) makes the newest the shown one; each channel takes that up as the engine next passes it, and the
renderer reads a frame's slots only once that is done and every word queued before the latch is in the DDR3 - so a
frame never shows a half-written capture. The two places where a capture would write many samples at once (the
jump to cycle 2 after a sync or test-bit wrap, and the rest of an early-ended cycle) are kept as a rule of the slot
(a range with one value) that the renderer applies when it reads. The renderer draws 2 pixels a clock into the same
pipeline as the layers' pixels. The emulator's code for all this (sc_store, scope_line) is the reference;
sim/octoscope checks the hardware against it sample for sample and pixel for pixel, with the DDR3 busy and held.

### THE SCOPE OVER ANY PROGRAM (Fix 72)

Hold **SHIFT+F3** for about a second, in anything - a game, a demo, BASIC, a program that has never heard of
OctoVIC: the core draws all 24 SID voices over the picture by itself. Hold it again and they are gone. The
program is not told and nothing of its own is touched (no layer, no copper, no scope register, no VRAM; OctoVIC
need not even be unlocked); the F3 is not passed on to it (rtl/hotkeys.sv). SCOPEKEY ($D6CF) is the same switch
for a program that wants it.

- 8 rows, one a SID, each in its own colour (green, cyan, yellow, orange, pink, violet, blue, white); 3 traces a
  row, the SID's voices 1-3. A trace is 120 pixels wide (raster X 6, 132 and 258 on: x -26, 100 and 226) and
  +-16 lines tall; row k is raster lines 19 + 33k to 51 + 33k (on a 60 Hz picture +-14 lines, 28 + 29k on).
- Each trace is the voice's shown capture - the same two whole cycles, held still, that the OCTOSCOPE layer
  shows - 5 samples to 2 pixels, at 1/8 of the layer's full height: pixel x is sample 5x/2 at -(sample >> 3)
  lines, joined to the pixel before it, so the trace never breaks.
- A trace's pixels are drawn in the row's colour; inside the traces' boxes the picture is at half brightness, so
  they can be read over anything.
- It costs the program nothing: the captures are fetched from the DDR3 a row ahead (114 reads a row, one at a
  time, behind every other user of OctoVIC's port) into one block of RAM, and the pixels are made as the beam
  goes (rtl/octovic/scope_screen.sv). A row is drawn only once all of it is in.

### THE SCOPE ON THE SECOND SCREEN (Fix 82)

With two screens on the MiSTer - HDMI, and a 15 kHz screen on the analogue VGA output - the program plays on one
and the scope is live on the other. Hold SHIFT+F3 again (SCOPEKEY 2): HDMI shows **the scope screen** - the same
24 traces as a picture of their own, on black, a dim line through the middle of each - and the VGA output shows
the program's whole picture (OctoVIC's layers and sprites too, not only the VIC). Hold it once more (SCOPEKEY 3)
and the two swap: the program on HDMI, the scope screen on the VGA output. Once more: off.

It uses the Split Screens arrangement, and needs what that needs: the VGA output at the core's own timing
(vga_scaler=0 and forced_scandoubler=0 in MiSTer.ini, no scandoubler in the menu). The two pictures share the
C64's own timing; no frame buffer is involved and sys/ is untouched. While SCOPEKEY is 2 or 3 the Split Screens
menu option's VIC-only picture is not shown (the VGA output carries the scope's arrangement instead).
With one screen only: on HDMI, SCOPEKEY 2 shows the scope screen alone and 3 looks like off; on a VGA screen
alone it is the other way round.

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
opaque pixel over what is there (or mixed with it: SEE-THROUGH COLOURS). The palette, the backdrop, CTRL and KEY are taken as the line is drawn,
so a change to any of them by the copper takes effect on its own line (a gradient sky: a backdrop
colour a line; a split: the VIC in front of one band and behind the next). Written by the 6510
instead, CTRL and KEY show up to three lines later. The VIC palette acts as the beam gets there.
On screen, the VIC's pixel is then put in front (see-through where it is the KEY colour) or behind.

VRAM is at DDR3 byte address $32000000 (16 MB); the 1541's track buffers are at $30000000.


## SPLIT SCREENS (core build 3)

The menu option Audio & Video > Split Screens sends two different pictures out of the MiSTer:

- **VGA (the analogue I/O board, native 15 kHz):** the VIC-II's picture alone - what a real C64's
  S-video would show. OctoVIC's layers and sprites never appear on it, whatever CTRL says.
- **HDMI:** OctoVIC's picture as usual. With CTRL b4 HIDEVIC set (and b0 ENABLE), the VIC is left
  out of it: the layers and sprites are drawn over the backdrop, so a stats screen drawn on the VIC
  shows only on the VGA screen.

A program reads STATUS ($D608) b3 to know the option is on: set, it can put its stats on the VIC
(text, colour RAM, the C64's own characters) and set HIDEVIC; clear, it keeps everything on one
screen as before (and should leave HIDEVIC clear, or the VIC's picture is not shown anywhere).

The option needs the VGA output at the core's own timing: vga_scaler=0 and forced_scandoubler=0
in MiSTer.ini (with the scandoubler on, VGA shows the same picture as HDMI). With direct_video=1
the HDMI socket carries the VGA picture, so direct video users see the VIC side on HDMI.

These two bits are the future Octophonic MiSTer Adapter's arrangement: there the real C64's
S-video is the VIC side and the MiSTer's HDMI the OctoVIC side.


## HEALTH (core build 3)

A late line is one the beam reached before OctoVIC had finished drawing it: on screen it shows
part of a layer, or none (the backdrop), for that frame - the "whole layer missing for a frame"
flicker. LATE ($D6A0) counts them for the last frame; LATE0/LATE1/LATEOTH say what was being drawn
when the beam got there; LATEFIRST is where it started; LATETOTAL keeps adding up, so a 6502 that
reads once a second still sees a single bad frame. A healthy picture reads 0 in all of them.

Build 3 also changes who gets the DDR3 first: when the line being drawn is due next (one line
ahead of the beam or less), its reads go before queued VRAM writes - as long as fewer than 10
writes are waiting, so a 6510 or REU writing VDATA flat out never loses a byte. Before, every
queued VRAM write went first, which is how REU streaming into VRAM could starve the picture.


## MEMORY (core memory build 1)

See docs/OCTOVIC_MEMORY.md for the measurements. Three changes and a meter:

- **A line is finished when its own reads are in.** It used to wait for the DDR3 port to be
  completely idle; the blitter's reads and the VDATA port's kept it busy, so with the blitter or
  REU streaming running a line could wait 5,000-15,000 clocks at its end - the main cause of the
  late lines (flicker) on real hardware.
- **The copper reads ahead.** A run of copper entries (a palette burst) is fetched up to 8 words
  ahead instead of one DDR3 round trip per word.
- **A late line is never shown half drawn.** Half drawn, the layer drawn first showed where the next
  should be (one layer flashing through another). Now the line above is shown again if it is still
  in the buffer (REPEAT), else that line has no layers (BLANK). Both are counted.
- **The meter** ($D6A8-$D6B1, above): how long lines take, how close to the beam they finish, the
  DDR3 round trip and how often the port says wait. OctoBench prints them as a table.
