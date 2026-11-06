# GREAT WAVE

A picture-viewer demo for the Octophonic 64 (OctoVIC 2+), by Mong00se: Katsushika Hokusai's woodblock print *The Great Wave off
Kanagawa* (about 1831, public domain, a scan of the print) as one 256-colour picture of 1024 x 702 pixels, revealed by a raster
wipe, then panned and zoomed by OctoVIC's turned-and-sized bitmap layer. 6502 (ACME); the PC only prepares the data. It started
as `tools/starrynight` and keeps its structure.

| file | what |
|---|---|
| `wave.asm` | the demo (`acme -f cbm`, `$0801`, `10 SYS2061`) |
| `gen.py` | the scan to `Great Wave.reu` (picture, two smaller copies, copper lists, palette), `data.inc`, `rows.inc` (the camera path) and `great wave.oct` |
| `music.py` | the music: Soran Bushi for 8 SIDs, rendered to SID register frames (`music.bin`, 2550 x 8 x 32 bytes) |
| `build.sh` | `build.sh WAVE.jpg OUT [STARRY]`: the `.prg`, the `.reu` (with the music appended), `OctoPaint Pictures build 2.d64` (Starry Night and Great Wave), `About.txt`, the zip |
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
* **The music** (build 2): `music.py` composes *Soran Bushi* (traditional, public domain; an original arrangement, D minor
  pentatonic, 120 bpm, 25 frames a beat) and renders it to SID register frames: 2550 frames, the length of the camera loop,
  8 SIDs x 32 bytes each ($00-$18 and zeros). They sit in the `.reu` after the picture data, on a 64 KB boundary (`R_MUS`, `build.sh`
  adds it to `data.inc`). The 6502 (`music_play` in `wave.asm`, called every frame after `advance`) does 4 REU DMA transfers of 64 bytes
  from R_MUS + frame * 256 into the SIDs' windows ($D400, $D480, $D500, $D580: SIDs 0+1, 4+5, 2+3, 6+7, so the stream is in that
  order) and counts the frame; the camera's wrap (`.wrap`) restarts it at 0, so picture and music loop together. SPACE: volume 0 on
  all SIDs (the frame counter waits, the next frame's registers bring the sound back); F7: every SID register 0. The REU is
  used only for this and for the start-up copies, so no registers need saving.
  The SIDs: 1 taiko (wavetable drums), 2 rim/clicks/toms, 3 rowing bass (D and A), 4 koto (plucked pulses), 5 shakuhachi lead (delayed
  vibrato, slides, breath noise), 6 harmony/answer (enters for the second A), 7 pad (filtered saws), 8 the sea (filtered noise, low).
  Technique in the Python: hard restart, wavetable drums, PWM, 50 Hz arpeggios, filter sweeps. Form (bars of 100 frames): intro 0-3
  (taiko roll into the title hold at frame 185), A 4-7 (the melody starts at frame 400, the glide to the boat begins at 385), B 8-11,
  chant 12, A' 13-16 (lead an octave up, harmony), B' 17-20 (the big taiko hit at frame 1715 as the zoom into Fuji starts; quieter over
  the Fuji hold 1615-1715; the volume builds up the crest, frames 615-1500), turn 21, chant 22-23 around the credit (2215), outro 24-25
  as it wipes out.

## Palette and dithering

255 colours (entry 0 is see-through on a layer and never used; entry 255 is the caption shadow's grey): k-means in OKLab on the
three pictures' pixels. The print is a few blues, cream paper and a grey sky, so the palette has colours to spare: the mean error
(OKLab x 100) is 0.55 plain against 1.13 for Starry Night. Plain nearest colour was compared with gentle Floyd-Steinberg (error
x 0.5, its length limited) by `gen.py --compare`: mean error 0.55 plain, 0.57 dithered; blurred 0.19 plain, 0.16 dithered. Looking at
crops of the sky, the foam and the paper (at 3x, and the sky blurred and stretched 6x in contrast to show any contouring) neither
shows steps in the gradient and both keep the paper grain; the dithered one only adds speckle. So: plain (`DITHER=0.5 build.sh` to try the other).

## Keys

SPACE pause (music muted), D the debug line (LATE, MAX, TOT, OVR), F7 quit.

## Checks (headless emulator + OctoVIC's RTL)

* The show was run in the headless emulator (frames of the whole 51 s loop drawn from the register log with the VIC's caption text
  composited, compared with the scan): wipe in, title, glide, pan, Fuji, 2x zoom, zoom out, credit, wipe out, black, loop.
  Found and fixed on the way: the wipe's last list left the backdrop at the last bar colour, so the margins around the whole
  print were dark navy instead of black (the lists now end with a black write on the last line).
* Keys (emulator, the real Octophonic OS drop of the .prg and .reu): D shows the debug line, SPACE freezes the picture (also in
  the glide) and a second SPACE goes on, F7 returns to BASIC.
* The register log replayed through OctoVIC's own RTL (octokit `octo_rtl.py`, memory build) with a busy DDR3 (80 % busy,
  40-120 clocks): 26 windows of 100 frames covering the wipe in, glide, the whole pan, the Fuji pause, zoom in and out and the
  wipe out: 2,600 frames, LATE 0, REPEAT 0, BLANK 0, LEAD 3 (the best) in every frame, the slowest line 1,231 of 2,016 clocks. The
  picture was identical line for line to the one from an idle DDR3, but for line 18 of the first frame of some windows (the
  replay's own start-up).
