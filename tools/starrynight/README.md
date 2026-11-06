# STARRY NIGHT

A picture-viewer demo for the Octophonic 64 (OctoVIC 2+), by Mong00se: Vincent van Gogh's *The Starry Night* (1889,
public domain, a scan of the painting) as one 256-colour picture of 1024 x 816 pixels, revealed by a raster wipe, then
panned and zoomed by OctoVIC's turned-and-sized bitmap layer. 6502 (ACME); the PC only prepares the data.

| file | what |
|---|---|
| `starry.asm` | the demo (`acme -f cbm`, `$0801`, `10 SYS2061`) |
| `gen.py` | the scan to `Starry Night.reu` (picture, half size copy, copper lists, palette), `data.inc`, `tables.inc` and `Starry Night.oct` |
| `music.py` | the music (build 2): Satie's Gymnopedie No. 1 for 8 SIDs, rendered to SID register frames (`music.bin`, 2520 x 8 x 32 bytes) |
| `build.sh` | `build.sh SOURCE.jpg OUT`: the `.prg`, the `.reu` (with the music appended), `About.txt`, `Starry Night build N.zip` |
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
* **The music** (build 2): `music.py` arranges Erik Satie's *Gymnopedie No. 1* (1888, public domain; from the printed score, not from
  any recording) for 8 SIDs and renders it to SID register frames: 2520 frames, exactly the camera loop (the rows of `rows` add up to
  2520), 8 SIDs x 32 bytes each ($00-$18 and zeros). They sit in the `.reu` after the picture data, on a 64 KB boundary (`R_MUS`,
  `build.sh` adds it to `data.inc`; every 256-byte frame lies inside one 512 KB window). The 6502 (`music_play`, called every frame
  after `advance`) does 4 REU DMA transfers of 64 bytes from R_MUS + frame * 256 into the SIDs' windows ($D400, $D480, $D500, $D580:
  SIDs 0+1, 4+5, 2+3, 6+7, so the stream is in that order) and counts the frame; `nextrow` restarts it at 0 when the camera starts
  its first row again, so picture and music loop together. SPACE: volume 0 on all SIDs (the frame counter waits, the next frame's
  registers bring the sound back); F7: every SID register 0 before it quits. The REU is used only for this and the start-up copies.
  Tempo 71.6 beats a minute (42 frames a beat, 3/4, 126 frames a bar, 20 bars). The score used: bars 1-4 the accompaniment alone
  (G major 7: bass G2, chord B3 D4 F#4; D major 7: bass D2, chord A3 C#4 F#4), bars 5-12 the first melody phrase (rest F#5 A5 | G5 F#5
  C#5 | B4 C#5 D5 | A4 | F#4 held over bars 9-12), bars 13-19 the second (13-16 as 5-8, then C#5, F#5, E5 as dotted halves), bar 20 the
  accompaniment alone (D major 7). The continuation of the melody after bar 19 is not in the arrangement, on purpose.
  The SIDs: 1 melody (pulse, slow attack, delayed vibrato, no pitch bends or detuned doubles, three voices in turn so every note's release rings under the
  next), 2 bass (soft triangle + octave + two octaves up, for phone speakers), 3 chords (soft low-passed pulses with PWM, beats 2-3),
  4 string pad (filtered saws: D4 and F#4 held all through, the third voice breathes B3 / A3; filter and volume swell), 5 harp (plucked
  pulses rippling up the chord, each pluck opens the filter), 6 horns (the melody an octave down, second phrase), 7 soft timpani
  (wavetable: noise click, pitch dropping to D3 / G3), 8 shimmer (high triangles, ping and two echoes, the quietest).
  Sync (frames of the loop): the SIDs come in one at a time - bass 3, chords 42, pad 96-100 (during the wipe in, 25-185), harp 189 (the
  title), shimmer from bar 3; the melody at 546 as the glide to the left stars ends (385-585); phrase 1 over the pan (585-1685); horns
  at 1556, timpani at 1512 and 1680 (the zoom into the moon starts), the pad's filter and volume at their widest 1700-1935 (zoom, hold,
  zoom out); quieter from 2016; bar 20 (2394) resolves on D major 7 as the credit goes and the wipe out (2360-2460) runs; everything has
  rung out by the last frame, and the SID volumes are the same on the last frame as on the first, so the loop point has no click.

## Palette and dithering

255 colours (entry 0 is see-through on a layer and never used; entry 255 is the caption shadow's grey): k-means in OKLab on
the pictures' pixels. Plain nearest colour was compared with gentle Floyd-Steinberg (error x 0.5, its length limited) by
`gen.py --compare`: mean error (OKLab x 100) 1.13 plain, 1.17 dithered; blurred 0.39 plain, 0.32 dithered. Looking at the
crops (moon, swirl, cypress) the plain picture is as clean as the scan - the brush work hides the 255-colour steps - and the
dithered one only adds speckle that the zoomed views would turn to noise. So: plain (`DITHER=0.5 build.sh` to try the other).

## Keys

SPACE pause, D the debug line (LATE, MAX, TOT, OVR), F7 quit.

## Checks (headless emulator + OctoVIC's RTL)

Build 2 music checks (headless emulator, 2 loops of the real show with its sound): the melody's notes by FFT (F#5 740 Hz, A5 880, G5 784,
C#5 554, B4 494, F#4 370, E5 659 all on pitch), the loop point (silent for a few frames each side, no click), the levels (the whole
mix peaks at -9.6 dBFS, melody about 5 dB above the next part, shimmer the quietest), SPACE (volume 0 on all SIDs, no writes while paused,
the music goes on from the same frame) and F7 (all registers 0, no more writes), and OctoVIC's RTL replay with the music's DMA running
(3 windows of 100 frames, busy DDR3: LATE 0).

Build 1: the show was run in the headless emulator (frames dumped, compared with the scan), the camera's numbers taken from the
register log (no jump but the picture swap, the acceleration under 0.2 px a frame squared), SPACE (also during a wipe),
D and F7 tried, and the register log replayed through OctoVIC's own RTL with a busy DDR3 (octokit `octo_rtl.py`, memory
build): LATE 0 in every window tried (see the report that came with the build).
