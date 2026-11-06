# STARRY NIGHT

A picture-viewer demo for the Octophonic 64 (OctoVIC 2+), by Mong00se: Vincent van Gogh's *The Starry Night* (1889,
public domain, a scan of the painting) as one 256-colour picture of 1024 x 816 pixels, revealed by a raster wipe, then
panned and zoomed by OctoVIC's turned-and-sized bitmap layer. 6502 (ACME); the PC only prepares the data.

| file | what |
|---|---|
| `starry.asm` | the demo (`acme -f cbm`, `$0801`, `10 SYS2061`) |
| `gen.py` | the scan to `Starry Night.reu` (picture, half size copy, copper lists, palette), `data.inc`, `tables.inc` and `Starry Night.oct` |
| `build.sh` | `build.sh SOURCE.jpg OUT`: the `.prg`, the `.reu`, `OctoPaint Pictures build N.d64`, `About.txt`, the zip |
| `about.txt` | the text that goes in the zip |

The scan (1920 x 1520) is not in git; get it from Wikimedia Commons (The Starry Night - Vincent van Gogh - Google Art Project).

## How it works

* **The picture** is a BITMAP layer (1024 wide, rows 1024 bytes apart, map width/height code 2) in VRAM `$000000`, turned and
  sized (LMODE b2) with U0/V0/DUX/DVY set every frame in the vertical blank; nothing else is drawn on that layer.
* **Two copies.** Zoomed out, a point-sampled 1024 picture is speckled (every third pixel of the brush work). So there is
  also a 512 x 408 copy (made by gen.py from the scan, same palette) in VRAM `$100000`, used from zoom 1.4 up to the whole
  painting (the 6502 swaps TILEBASE and halves the numbers).
* **The camera** (centre x, y and zoom) runs from a table of rows in `starry.asm` (`rows`): each row glides from the last
  target to its own over so many frames, smoothstep eased (3s^2 - 2s^3 with the maths unit), linear in x, y and zoom, the pan
  with a sine drift in y. U0 = x - 198 z, V0 = y - 158 z (the middle of OctoVIC's 396 x 284 picture).
* **The wipe** is the copper's own animation (`COPSTEP`, one list a frame): 160 lists for the wipe in, 100 for the wipe out,
  each a few dozen entries (the layer on above the band, backdrop colours a line for the band). The 6502 does nothing.
* **The captions** are VIC text in front (KEY = black see-through), faded with VIC palette colour 1; a dark band behind them
  is 5 sprites of 64 x 16 in "taken away" mode, its grey palette entry 255 faded with the text.
* **The REU.** Every part of the `.reu` starts on a 64 KB boundary and is copied 64 KB at a time: the REU's address counter
  wraps inside each 512 KB, so a transfer that crosses one reads the wrong bytes (found in the emulator: the first copper
  lists came out as picture data).
* The music hook: `JSR $1003` each frame (a `RTS` at `$1000`/`$1003`, init/play as a SID tune has them); build 1 is silent.

## Palette and dithering

255 colours (entry 0 is see-through on a layer and never used; entry 255 is the caption shadow's grey): k-means in OKLab on
the pictures' pixels. Plain nearest colour was compared with gentle Floyd-Steinberg (error x 0.5, its length limited) by
`gen.py --compare`: mean error (OKLab x 100) 1.13 plain, 1.17 dithered; blurred 0.39 plain, 0.32 dithered. Looking at the
crops (moon, swirl, cypress) the plain picture is as clean as the scan - the brush work hides the 255-colour steps - and the
dithered one only adds speckle that the zoomed views would turn to noise. So: plain (`DITHER=0.5 build.sh` to try the other).

## Keys

SPACE pause, D the debug line (LATE, MAX, TOT, OVR), F7 quit.

## Checks (headless emulator + OctoVIC's RTL)

The show was run in the headless emulator (frames dumped, compared with the scan), the camera's numbers taken from the
register log (no jump but the picture swap, the acceleration under 0.2 px a frame squared), SPACE (also during a wipe),
D and F7 tried, and the register log replayed through OctoVIC's own RTL with a busy DDR3 (octokit `octo_rtl.py`, memory
build): LATE 0 in every window tried (see the report that came with the build).
