# 2026: AN OCTOPHONIC ODYSSEY

(C) 2026 Mong00se

One C64 program for three machines, by Mong00se. It looks at the machine it is on and shows what that machine can do
with the James Webb Space Telescope's "Cosmic Cliffs" in the Carina Nebula (NASA, ESA, CSA, STScI), to Johann Strauss
II's "The Blue Danube" (1866, arranged by Mong00se from the waltz's own melody and harmony). Everything you see and
hear is done by the 6502 on the machine; the PC only converts the picture and prepares data.

| machine | what it does |
|---|---|
| Octophonic 64 (OctoVIC 2+ and the .reu) | the picture in 256 colours (2048 x 1186) on OctoVIC's turned-and-sized layer, a camera from a star out to the whole cliffs, along the ridge, up to the stars, into the dust and back; stars twinkle (8 palette groups), sparkles and a comet (sprites, added light), 8 equaliser bars; the waltz on all 8 SIDs |
| C64 with a second SID ($D420, $D500 or $DE00) | our own Andromeda-style spiral galaxy (`galaxy.py`, no photo) in hires: the 6502 turns it and draws it anew (a 64x64 texture of the disk, tilted 60 degrees, a 16x16 dither), ~100 live stars orbit in its arms (the inner ones faster), stars twinkle, glints flash on the brightest, a scroll text and an equaliser in a text row; the waltz in stereo |
| stock C64 | the same galaxy, the waltz on 1 SID (the melody on soft strings, a gentle bass on the downbeat, soft held after-beats; the tremolo and horn call in the introduction) |

## Files

| file | what |
|---|---|
| `odyssey.asm` | the start: the machine test (OctoVIC's ID and version, our label at the start of the REU, else asks Octophonic Main for the .reu - command `$18`; a second SID told from a mirror by voice 3's OSC3), the BASIC line with the copyright, PETSCII art in the header for OCTOCODE |
| `player.asm` | the music player: 3 or 6 voices, instruments, slurs (legato), a bowed tremolo, a late light vibrato, PWM, SID 2's strings a few cents sharp, the strings' lowpass swell (`fcut`), the equaliser's levels |
| `show.asm`, `fx.asm`, `iris.asm`, `galaxy.asm` | the stock / 2-SID show (`galaxy.asm`: the turn and the live stars) |
| `octo.asm`, `octofx.asm`, `camera.asm` | the Octophonic show (the camera is Mona Lisa's) |
| `song.asm` | the notes (made by `song.py`) |
| `song.py` | the arrangement (from Strauss's score: theme, slurs, bass, harmony; a slow rubato tempo map): the 6502 player's note lists for SIDs 1-2, SIDs 3-8 rendered to register frames for the REU (same timing), the show's phrase table; `ODY_ONLY=p0,s5` keeps single parts, to record and measure each on its own |
| `galaxy.py` | the stock show's galaxy: the art, the texture, the tables, the live stars' rings (`galaxy.bin`); `galaxy_2x.png` shows frame 0 exactly as the 6502 draws it |
| `stockpic.py` | the disk packing (`pack()`, a small LZ that `show.asm` unpacks while loading); the old photo-to-views converter |
| `octopic.py` | the photo to the 256-colour picture, its half and quarter copies, the camera path, the sprites, the .reu |
| `petscii.py` | the source to PETSCII for the disk (OCTOCODE), with the header art's graphics; `--png` shows it as OCTOCODE will |
| `build.sh` | `build.sh PICTURE.jpg OUT`: everything, the .d64, the zip |
| `about.txt` | the zip's About.txt |

**The photo converters (`stockpic.py`, `octopic.py`) are for Neal's private use, not part of a public release.** The
photo itself is not in git (the full-size Webb TIF/JPG; any size works).

## Notes

* **The source in OCTOCODE.** The program is too big for one OCTOCODE file, so it is in 9 parts. Each part starts
  with `!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }` / `!if odyp = 0 { !src "odyssey.asm" } else {`:
  `odyssey.asm` sets `odytop` to 1 while it is read and 0 at its end, so a part compiled on its own pulls in the
  whole program and gives the same bytes (build.sh checks every part with Main's ACME options). ACME keeps symbols
  between passes, so an `!ifndef` guard would not work. OCTOCODE's compile runs ACME in the folder of the disk on the
  SD card, so the parts must be there too (the .bat copies them). The disk keeps 64 blocks free: OCTOCODE's F5
  writes a part (and the program) anew before the old copy goes; no part is over 50 blocks.
* **The stock galaxy.** GALAXY (27 blocks) loads behind the loading screen (with the music: `drready` waits for the
  drive itself, the interrupt running), then the KERNAL goes off (the texture lives at $E000) and the loading screen
  cuts straight into the galaxy on a phrase. Two hires bitmaps ($6000, $A000) swap 25 times a second: the live stars
  are taken off (their bytes put back, the last first) and plotted again in the one not shown; the rest of the time
  the 6502 draws the disk anew from the texture at the angle of the moment, top to bottom (a pass about every 5 s,
  into both bitmaps), so the galaxy turns about a quarter turn a song. The last row is a text row (an interrupt at
  line 238 switches to bank 1's text screen; row 23 is black, so the switch does not show). Measured in VICE: 104
  stars hold 25 fps (110 just do; 120 drop to 17).
* **The Octophonic's sleeping SIDs.** A SID other than SID 1 takes no writes of its own until it has had a volume
  and a control write; until then SID 1 gets them too. The stream's first frame put SID 3's filter routing into
  SID 1 (with no filter mode: silent). `oinit` wakes SIDs 3-8 first and the player clears SID 1/2's filter.
* **The music (build 2).** Slow and orchestral, after Kubrick's use of it: out of near-silence (a high string tremolo
  under a closed filter, then the horn call), the theme legato on strings with soft held after-beats and a gentle bass,
  swelling the second time; no arpeggio chords. 128.7 s a loop (was 96.3 s): `phtab` and the Octophonic camera follow
  song.py's tempo map, the galaxy's turn follows `songlen`. Balanced by recording each part alone in the Octophonic
  emulator. The strings' lowpass is set for a 6581 (the core's default); on an 8580 the same values are brighter.
* **Colours.** The stock galaxy is made for the core's palette 0 (`rtl/fpga64_rgbcolor.vhd`); the VICE
  recordings use the same palette.

## Tested

* Stock C64 and C64 + second SID at $D420: VICE 3.8 x64sc (stock, true 1541) - the galaxy loading and turning, 25 fps
  with 104 live stars, the 6502's drawing byte for byte the same as galaxy.py's, stereo with 2 SIDs.
* Octophonic 64: the Octophonic 64 emulator (current KERNAL) - the whole loop, 1 frame of 5266 over budget (the
  palette going in), the .reu asked for by name when the browser did not attach it, the 8-SID mix.
* OCTOCODE: the source loaded from the disk shows the header art; every part assembles to the same program with
  Main's ACME command.
