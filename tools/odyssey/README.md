# 2026: AN OCTOPHONIC ODYSSEY

(C) 2026 Mong00se. All rights reserved.

One C64 program for three machines, by Mong00se. It looks at the machine it is on and shows what that machine can do
with the James Webb Space Telescope's "Cosmic Cliffs" in the Carina Nebula (NASA, ESA, CSA, STScI), to Johann Strauss
II's "The Blue Danube" (1866, arranged by Mong00se from the waltz's own melody and harmony). Everything you see and
hear is done by the 6502 on the machine; the PC only converts the picture and prepares data.

| machine | what it does |
|---|---|
| Octophonic 64 (OctoVIC 2+ and the .reu) | the picture in 256 colours (2048 x 1186) on OctoVIC's turned-and-sized layer, a camera from a star out to the whole cliffs, along the ridge, up to the stars, into the dust and back; stars twinkle (8 palette groups), sparkles and a comet (sprites, added light), 8 equaliser bars; the waltz on all 8 SIDs |
| C64 with a second SID ($D420, $D500 or $DE00) | the tour: four multicolour views (the whole picture, the western peak, the ridge and its stars, the eastern cliffs) loaded from the disk while the one before is shown, swapped with an iris or a fade through the C64's colour ramps; twinkles (colour RAM), sparkle and comet sprites, a scroll text naming each view, an equaliser; the waltz in stereo |
| stock C64 | the same tour, the waltz on 1 SID (melody, bass, the arpeggiated "pah-pah" chords) |

## Files

| file | what |
|---|---|
| `odyssey.asm` | the start: the machine test (OctoVIC's ID and version, our label at the start of the REU, else asks Octophonic Main for the .reu - command `$18`; a second SID told from a mirror by voice 3's OSC3), the BASIC line with the copyright, PETSCII art in the header for OCTOCODE |
| `player.asm` | the music player: 3 or 6 voices, instruments, hard restart, vibrato, PWM, the chord arpeggio, the equaliser's levels |
| `show.asm`, `fx.asm`, `iris.asm` | the stock / 2-SID show |
| `octo.asm`, `octofx.asm`, `camera.asm` | the Octophonic show (the camera is Mona Lisa's) |
| `song.asm` | the notes (made by `song.py`) |
| `song.py` | the arrangement: the 6502 player's note lists for SIDs 1-2, and SIDs 3-8 rendered to register frames for the REU (same timing) |
| `stockpic.py` | the photo to the four multicolour views (`view0-3.bin`, packed with a small LZ that `show.asm` unpacks while loading) |
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
* **Loading while the show runs (stock).** The KERNAL's serial routines hold the interrupt off while the 1541 looks
  for a file or reads the next sector; `drready` waits for the drive's CLK line itself, with the interrupt running,
  so the music never stops. With more than two sprites on a bad line the KERNAL misses the 1541's bits and the load
  hangs (found in VICE: three sparkles at the top of the screen), so while a view loads there is one sparkle (kept
  above the equaliser's rows) and no comet. The scroll text is drawn into the bitmap's last row (no split screen:
  a held-off interrupt would make a split jump).
* **The Octophonic's sleeping SIDs.** A SID other than SID 1 takes no writes of its own until it has had a volume
  and a control write; until then SID 1 gets them too. The stream's first frame put SID 3's filter routing into
  SID 1 (with no filter mode: silent). `oinit` wakes SIDs 3-8 first and the player clears SID 1/2's filter.
* **Colours.** The stock views are converted for the core's palette 0 (`rtl/fpga64_rgbcolor.vhd`); the VICE
  recordings use the same palette.

## Tested

* Stock C64 and C64 + second SID at $D420: VICE 3.8 x64sc (stock, true 1541) - the tour through all four views and
  back, the music without gaps during loads, stereo with 2 SIDs.
* Octophonic 64: the Octophonic 64 emulator (current KERNAL) - the whole loop, 1 frame of 5266 over budget (the
  palette going in), the .reu asked for by name when the browser did not attach it, the 8-SID mix.
* OCTOCODE: the source loaded from the disk shows the header art; every part assembles to the same program with
  Main's ACME command.
