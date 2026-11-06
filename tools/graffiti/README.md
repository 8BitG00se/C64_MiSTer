# GRAFFITI WALL

A demo for the Octophonic 64 (OctoVIC 2+), by Mong00se: a brick wall (Neal's own photo) with a big graffiti scroller on it. 6502
(ACME); the PC only prepares the data.

| file | what |
|---|---|
| `graffiti.asm` | the demo (`acme -f cbm`, `$0801`, `10 SYS2061`) |
| `gen.py` | makes `Graffiti Wall.reu` (tiles, map, wall sprites, text columns, palette) and `data.inc` |
| `wall.py` | the photo -> a seamless 384 x 256 brick tile |
| `font.py` | our own bubble/wildstyle-lite alphabet (A-Z 0-9 ! . - ' and space) |
| `build.sh` | `build.sh OUT PHOTO`: `Graffiti Wall.prg`, `.reu`, `About.txt`, `Graffiti Wall build N.zip` (`CHECK=x.png` also saves the tile 3 x 3) |
| `about.txt` | the text that goes in the zip |

## How it works

* **The wall** (`wall.py`): the photo is turned 1 degree (the angle that makes the mortar lines sharpest), the light evened out
  (divide by a blurred copy, keep the mean), then four courses (64 rows each, bed joint centre to bed joint centre) are cut, each
  one brick wide from head joint centre to head joint centre. Each is made periodic across by a cross-fade over 60 photo
  columns; the course's second brick is another course's brick turned round; every other course is moved half a brick (running
  bond); the mortar either side of each bed joint (including the wrap top to bottom) is blended over 14 rows. 384 x 256, 190
  colours (median cut, Floyd-Steinberg), palette 1-190.
* **On screen**: 35 sprites 64 x 64, 256 colours, priority 2 (behind both layers), graphics 6 x 4 blocks repeated 7 x 5.
* **The lettering**: layer 1, tiles 8 x 8 at 256 colours, map 256 x 32 tiles (2048 pixels round). Each letter is a cell 128 rows
  (16 tiles) tall and a whole number of tiles wide, drawn by `font.py` (skeleton strokes with a round pen of 9, outline 5, a
  16-step gradient with a shaded rim, a white streak, drips); the whole text is cut into tiles and equal tiles share a number
  (2137 pairs). Palette 191-224.
* **The shadow**: layer 0 uses the same map and a second tile set (the outline's shape blurred, 8 grey levels = palette 225-232)
  in LMODE 3 ("taken away"), scrolled 7 pixels back so it lies 7 right and down on the screen. It subtracts 9-72 from the wall.
* **The scroll**: SCROLLX += 2 a frame (the 6502, in the vertical blank, line 300); every 4th frame the next text column (32
  bytes, REU DMA) is written into the map column 53 ahead of the left edge, 16 words, where the beam can not see it. SCROLLY bobs
  12 +- 3 over 128 frames. The text has 40 blank columns before it (and so after it, round).
* **The REU**: every part starts on a 64 KB boundary and goes into VRAM in 64 KB runs.
* **Keys**: SPACE pause, F7 quit (all SID registers 0, BASIC warm start). A music hook: `JSR $1000` once, `JSR $1003` every frame.

## Checks

Headless emulator: frames of the loop (letters readable, bricks, shadow), the scroll measured frame to frame (exactly 2 pixels
every frame over 300 frames). The register log replayed through OctoVIC's own RTL with a busy DDR3 (80 % busy, 40-120 clocks),
two windows of 100 frames: LATE 0, REPEAT 0, BLANK 0, lead 3; the slowest line 1,666 of 2,016 clocks.
