# ECLIPSE BEACH

A backdrop demo for the Octophonic 64 (OctoVIC 2+), by Mong00se: the beach stage of a side-on fighting game, in the style of cinematic
hi-res gradient pixel art, with a total solar eclipse as a 60 s time lapse. 6502 (ACME); the PC only prepares data. Structure and toolchain
as `tools/greatwave`.

| file | what |
|---|---|
| `eclipse.asm` | the demo (`acme -f cbm`, `$0801`, `10 SYS2061`) |
| `gen.py` | the scene's maths to `Eclipse Beach.reu` (picture, sprite graphics, 1500 tick records), `data.inc` and the OctoPaint pictures |
| `build.sh` | `build.sh OUT`: `.prg`, `.reu`, `Eclipse Beach build N.d64` (program, source as PETSCII text, 5 `.oct` pictures), `About.txt`, the zip with `Install to MiSTer.bat` |
| `about.txt` | the text that goes in the zip |

## How it works

* **No copper, no blitter, no per-frame drawing.** The picture is one BITMAP layer (512 x 256, 256 colours) of palette *classes*; everything
  that moves is a palette change or a sprite-table change, 25 times a second (a *tick* = 2 frames). 60 s = 1500 ticks, then it loops.
* **The REU** holds, each part on a 64 KB boundary: the picture (128 KB), the sprite graphics (1.2 MB, de-duplicated), then 1500 records of
  2048 bytes (palette 3 x 256, sprite table 109 x 8; a record never crosses a 512 KB boundary). At start the 6502 copies the picture and
  the graphics into the VRAM (`V_PIC $000000`, `V_SAT $020000`, `V_SPR $030000`) while the screen is black. Each tick: REU DMA of the
  sprite table straight into the VRAM, REU DMA of the palette into RAM and a loop writing it to OctoVIC. About 9,000 cycles a tick.
* **Sky**: 41 palette levels of an 8x8 Bayer dithered gradient (the dither is in the picture, fixed); every tick the 41 colours are the
  day sky mixed with the night sky by `dark = 1 - visible_fraction**0.3` (light fails logarithmically).
* **Sea**: a pixel's class is (depth band, glitter-column strength, wave phase, wave strength) = 108 palette entries. The phase bucket
  of a crest travels because each tick's entries are the crest function shifted by the wave's phase: palette cycling, so the crests move
  toward the beach and the glitter shimmers with no pixel written. The depth bands and glitter classes are dithered between each other.
* **Beach**: still: wet strip 8 rows x 3 sun-streak levels, dry sand 5 ripple levels (lit edge, shadow edge) x 3 damp levels; their
  colours follow the sun and the eclipse by palette alone.
* **Sprites** (109, all in front of the layer): the sun glow (4 x 64x64, *added*), the sun and the moon's black bite (32x32, one frame per
  3 ticks, computed from the mockup's own maths: the moon is exactly the sun's size, invisible except where it covers the sun), the corona and
  the diamond ring with its starburst (4 x 64x64, *added*, a frame per 6 ticks, hidden behind the sun and the moon), 90 stars (8x8, the
  twinkle is the graphics frame: 15 brightness steps, top-down fade-in by the eclipse), two foam lines (5 x 64x16 each, *half and half*,
  moved up and down by the sprite table).
* **Keys**: 1-6 layers, L names (gold on, grey off), D debug line, SPACE pause, F7 quit. The labels are VIC text (key colour see-through).

## What differs from the approved mockup (and why)

* Sky bloom: a 128 x 128 added sprite that fades to nothing at 57 px (the mockup's reaches 130 px); the glow must stay above the horizon.
* The sea's wave field is one travelling wave plus a frozen field of strength (the mockup moves four sines at their own speeds): palette
  cycling can move only one phase per pixel. No wavy haze, crests and glitter look the same; they look a little calmer.
* The corona and ring are 128 x 128 (the spikes fade out softly at 64 px; the mockup's reach 100+), and have 15 levels instead of 12-16.
* The moon's faint texture (the mockup used a photo, which we do not) is left out: the disc is flat black; the sunspot is one pixel.
* Sprites, not pixels, so the sun / moon move in whole pixels (the sun lowers 9 px in the minute) and their frames change every 3 ticks.
* The horizon's thin lit line is not drawn. The foam's blend is half and half (the mockup: 55 % and 35 %).

## Checks (headless emulator)

Built and run in the Octophonic 64 Emulator as a drop (`.prg` + `.reu`): frames at 0, 15, 24, 30, 36 and 50 s were compared side by side
with the mockup's frames at the same times (`compare.png`); the sky, sea and sand colours agree to within a few steps (mean rows within
2-5 of 255), the eclipse's coverage, the ring and the stars follow the mockup. D showed LATE 0, MAX 0, TOT 0, OVR 0 over the run; keys
1, 3, L, D tried. A frame-exact MP4 of the whole loop was recorded from the emulator.
