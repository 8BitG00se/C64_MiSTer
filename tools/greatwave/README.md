# GREAT WAVE

A picture-viewer demo for the Octophonic 64 (OctoVIC 2+), by Mong00se: Katsushika Hokusai's woodblock print *The Great Wave off
Kanagawa* (about 1831, public domain, a scan of the print) as one 256-colour picture of 1024 x 702 pixels, revealed by a raster
wipe, then panned and zoomed by OctoVIC's turned-and-sized bitmap layer. 6502 (ACME); the PC only prepares the data. It started
as `tools/starrynight` and keeps its structure.

| file | what |
|---|---|
| `wave.asm` | the demo (`acme -f cbm`, `$0801`, `10 SYS2061`) |
| `gen.py` | the scan to `Great Wave.reu` (picture, two smaller copies, copper lists, palette), `data.inc`, `rows.inc` (the camera path) and `great wave.oct` |
| `build.sh` | `build.sh WAVE.jpg OUT [STARRY]`: the `.prg`, the `.reu`, `OctoPaint Pictures build 2.d64` (Starry Night and Great Wave), `About.txt`, the zip |
| `about.txt` | the text that goes in the zip |

The scan (1920 x 1315) is not in git; get it from Wikimedia Commons (Great Wave off Kanagawa2.jpg / the Google Art Project copy).

## How it works

* **The picture** is a BITMAP layer (1024 wide, rows 1024 bytes apart, map width/height code 2) in VRAM `$000000`, turned and
  sized (LMODE b2) with U0/V0/DUX/DVY set every frame in the vertical blank; nothing else is drawn on that layer.
* **Three copies.** Point-sampled, a zoomed-out picture is speckled (the print has hair-fine lines and dots). So there are also a
  512 x 351 copy at VRAM `$100000` (used from zoom 1.4) and a 352 x 241 copy (11/32 of the size) at `$140000` (from zoom 2.0),
  each averaged from the scan with the same palette; the 6502 swaps TILEBASE and scales the registers (1/2, or 11/32 = 1/4 + 1/16
  + 1/32 with shifts). The whole-print view is zoom 32/11, where the 11/32 copy is shown exactly 1:1 (352 x 241 pixels, no resampling).
* **The camera** (centre x, y and zoom) runs from the table in `rows.inc`, which `gen.py` writes from its path (`SPEC`): holds, eased
  glides (smoothstep, zoom in log steps) and the curved pan (a Catmull-Rom spline through the boat, up the wave, along the crest, through
  the claws, down to Fuji, the speed a cosine ramp up and down, flat between). Every row is a straight line in x, y and zoom over its
  frames (3 in the eased moves, 10 in the pan), so the 6502 only does `lerp` with the maths unit and never curves; x and y are 8.8, zoom
  8.16, so nothing rounds to a pixel. The camera's acceleration (screen pixels a frame squared) stays under 0.14.
  U0 = x - 198 z, V0 = y - 158 z (the middle of OctoVIC's 396 x 284 picture).
* **The wipe** is the copper's own animation (`COPSTEP`, one list a frame): 160 lists for the wipe in, 100 for the wipe out,
  each a few dozen entries (the layer on above the band, backdrop colours a line for the band, indigo - blue - sky blue - cream).
  The 6502 does nothing.
* **The captions** are VIC text in front (KEY = black see-through), faded with VIC palette colour 1; a dark band behind them
  is 5 sprites of 64 x 16 in "taken away" mode, its grey palette entry 255 faded with the text.
* **The REU.** Every part of the `.reu` starts on a 64 KB boundary and is copied 64 KB at a time: the REU's address counter
  wraps inside each 512 KB, so a transfer that crosses one reads the wrong bytes.
* The music hook: `JSR $1003` each frame (a `RTS` at `$1000`/`$1003`, init/play as a SID tune has them); build 1 is silent.

## Palette and dithering

255 colours (entry 0 is see-through on a layer and never used; entry 255 is the caption shadow's grey): k-means in OKLab on the
three pictures' pixels. The print is a few blues, cream paper and a grey sky, so the palette has colours to spare: the mean error
(OKLab x 100) is 0.55 plain against 1.13 for Starry Night. Plain nearest colour was compared with gentle Floyd-Steinberg (error
x 0.5, its length limited) by `gen.py --compare`: mean error 0.55 plain, 0.57 dithered; blurred 0.19 plain, 0.16 dithered. Looking at
crops of the sky, the foam and the paper (at 3x, and the sky blurred and stretched 6x in contrast to show any contouring) neither
shows steps in the gradient and both keep the paper grain; the dithered one only adds speckle. So: plain (`DITHER=0.5 build.sh` to try the other).

## Keys

SPACE pause, D the debug line (LATE, MAX, TOT, OVR), F7 quit.

## Checks (headless emulator + OctoVIC's RTL)

The show was run in the headless emulator (frames dumped, compared with the scan), the camera's numbers taken from the
register log (no jump but the picture swap, the acceleration under 0.2 px a frame squared), SPACE (also during a wipe),
D and F7 tried, and the register log replayed through OctoVIC's own RTL with a busy DDR3 (octokit `octo_rtl.py`, memory
build): LATE 0 in every window tried (see the report that came with the build).
