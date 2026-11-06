# OCTOPUS

A demo for the Octophonic 64 (OctoVIC 2+), by Mong00se: the Octophonic octopus mascot, turning and breathing in technicolour. The
idea of Black Hole (a big still picture, all its motion from palette cycling by the copper) with Great Wave's turned-and-sized bitmap
layer. 6502 (ACME); the PC only prepares the data.

| file | what |
|---|---|
| `octopus.asm` | the demo (`acme -f cbm`, `$0801`, `10 SYS2061`) |
| `gen.py` | draws the octopus, makes `Octopus.reu` (picture, sprites, copper lists, camera table, palette) and `data.inc` |
| `build.sh` | `build.sh OUT`: `Octopus.prg`, `Octopus.reu`, `About.txt`, `Octopus build N.zip` |
| `about.txt` | the text that goes in the zip |

## How it works

* **The picture**: a 256 x 256 BITMAP layer (VRAM `$000000`), LMODE b2+b3 (turned and sized, nothing outside). The octopus is drawn
  by `gen.py` as shapes (head, eyes, smile, 8 wavy arms with the OLED logo's character), bold on purpose: point-sampled rotation
  speckles fine detail. Body pixels hold palette indices 1-240 from `0.85 r + 240 * 2 * angle / 2pi + 0.3 y` (r, angle about a point in
  the head): a swirl of bands. Eyes (white, black rings and pupils, a glint) and the smile are fixed entries 241 / 242.
* **The colour**: the palette entries 1-240 hold a hue circle with brighter and darker stripes; every frame the copper list shifts
  it 2 entries (PER = 120 lists, `COPSTEP` animation, no 6502 work; pause = `COPDIV` 0). A list is 749 palette writes (lines 0-11,
  64 an entry per line, before the picture's first line 16) plus the backdrop's three colour writes on each of lines 16-299
  (slow dark bands), and six star colours that twinkle.
* **The turn and zoom**: R_CAM, 1800 rows of 32 bytes (U0 V0 DUX DVX DUY DVY, 16.16): a full turn each 450 frames, the zoom
  (screen pixels to a texel) 1 + 0.15 sin over 900 frames, so 0.85-1.15. The 6502 fetches one row a frame by REU DMA into
  `REGS` and writes it to OctoVIC in the vertical blank (as Great Wave does).
* **The sky**: 40 stars, 8 x 8 sprites of priority 2 (behind the layer), plus the dark caption band: 3 sprites 64 x 16 in
  "half and half" mode (over the backdrop it is plain navy, over the octopus it halves the light). Caption: VIC text rows 23-24,
  VIC colour 0 (black) see-through (KEY), colour 1 white.
* **The REU**: every part starts on a 64 KB boundary and goes into VRAM in 64 KB runs (the REU address wraps inside 512 KB).
* **Keys**: SPACE pause, F7 quit (all SID registers 0, BASIC warm start). A music hook: `JSR $1000` once, `JSR $1003` every frame (both RTS).

## Checks

Headless emulator: frames of the loop (spin, colour flow, caption, stars), SPACE freezes the frame and a second SPACE goes on,
F7 returns to READY. The register log replayed through OctoVIC's own RTL with a busy DDR3 (80 % busy, 40-120 clocks), two windows of
100 frames (around the biggest size and around the smallest): LATE 0, REPEAT 0, BLANK 0, lead 3; the slowest line 1,879 of 2,016
clocks (the rotating layer plus 43 sprites: closer to the limit than Great Wave, still clean).
