# OCTO WEAVER LITE (build 2)

An 8-SID step sequencer for the Octophonic 64, by Mong00se. It is made for **demos and games**: each SID has one fixed job, a tune
has a shape (the SIDs come in one at a time), a short hook over a few chords. You do not have to play in time or in key: type notes
on the QWERTY row, they snap to the scale, and ROLL writes a musical idea for you.

Build 2 is a `.prg` (6502, ACME). It starts like OctoPaint: it needs OctoVIC (ID `$8C`, version 2 or more), else it prints a line and
goes back to BASIC. F7 asks, then silences all 8 SIDs and returns to BASIC.

## 1. Install and start

1. Copy `OCTO WEAVER LITE.PRG` (or the `.d64`) to the MiSTer: FileZilla, SFTP, host = the MiSTer's address, user `root`,
   password `1`, into `/media/fat/games/C64/Apps/`.
2. On the Octophonic 64: F1 BROWSE, SD CARD, Apps, the file. (The disk: attach the `.d64`, `LOAD"*",8,1`, `RUN`.)
3. The disk has the three demo songs and their PLAY players: `DARK DRIVE.OWS`, `OCEAN LIGHT.OWS`, `SKIP ROPE.OWS` to open in the
   editor (type the song's name with N, then L), and `DARK DRIVE PLAY`, `OCEAN LIGHT PLAY`, `SKIP ROPE PLAY` to run on their own
   (`LOAD"DARK DRIVE PLAY",8,1` and `RUN`, or load it from the disk in the browser). File names use the song's first 11 letters.

## 2. The screen

- Top: the title, the song name. Under it the **eq**: 24 bars (8 SIDs x 3 voices), one colour for each SID, drawn by OctoVIC. The
  bars move with the music; a muted track stays dark.
- The **8 track lanes**, one line each: the job name (PAD, LEAD, BASS, REESE, DRUMS, HATS, BELLS, FX - you can rename them), the
  mute / solo mark, and the bars around the play position (the pattern number each bar plays, `..` = silent).
- Under the lanes: `SPD` speed (frames a step), `KEY`, scale, `LEN` the song length in bars, `BAR` the cursor bar, the 4 `CHORDS`,
  and the dials of the cursor track's SID: `CUT` `RES` mode `VOL` `LFO`.
- The bottom lines are the keys that work now.

## 3. The music model

- **8 tracks, one per SID** (track n plays SID n). Each track plays one note line; its **sound** says how the SID's 3 voices are
  used (the voicing), so 8 note lines drive all 24 voices.
- **Patterns**: 16 steps; a step = a note (1-96, C0 = 1) and a sound (1-31). 48 patterns a track.
- **The song**: for each track a list of up to 128 **bars**, each bar a pattern number (0 = silent). All tracks advance together.
- **Speed**: frames a step (50 Hz). 6 = 125 bpm sixteenths, a bar = 16 steps.
- **31 sounds** shared by all tracks (section 6). **Dials per SID**: filter cutoff, resonance, mode, volume, LFO sweep, live.

## 4. Keys

### Track lanes (the first screen)

| key | what |
|---|---|
| cursor up / down | the track; left / right = the bar |
| `+` `-` | the pattern number of the cursor bar (0 = silent, 1-48) |
| RETURN or F3 | open the **pattern editor** for this bar (a free pattern is given if the bar has none) |
| F5 | the **sound editor** |
| F1 | play / stop (from the cursor bar) |
| F7 | quit (asks) |
| `M` `S` | mute / solo the track (the eq shows it dark) |
| `1` `2` | filter cutoff of this SID down / up (steps of 8) |
| `3` `4` | resonance down / up |
| `5` | filter mode: off, LP, BP, LP+BP, HP, notch, BP+HP, all |
| `6` | the filter LFO, a slow sweep of the cutoff: off, then four presets (depth 8 rate 2, depth 15 rate 3, depth 15 rate 6, depth 8 rate 12) |
| `7` `8` | volume of this SID down / up |
| `P` | a paddle on POT 1 turns the cutoff of the cursor track |
| `K` `T` | the song's key (C..B) and scale (major, minor, minor pentatonic, major pentatonic, dorian, blues) |
| `C` | the 4 chords: four digits 1-7 (the scale degree of each chord's root), default `1 6 4 5` |
| `J` | **ROLL**: fill the cursor bar's pattern with an idea for this track's job; press again for another |
| `B` | **SHAPE** (BUILD): the tracks come in one at a time, every 2 bars (asks first) |
| `N` `R` | rename the song / the track |
| `Q` | the track's roll style (PAD LEAD BASS REESE DRUMS HATS BELLS FX) |
| `9` `0` | the sound ROLL and SHAPE use for this track |
| `,` `.` | song length -1 / +1 bar (SHIFT = 4) |
| `/` `;` | speed slower / faster |
| `G`, HOME | forward 10 bars (SHIFT = back) / bar 1 |
| `W` `L` `X` | save, load, export (section 7) |
| `V` | a new empty song (asks) |

### Pattern editor

Up / down step through **scale notes only**; the row `A W S E D F T G Y H U J K` is a piano that plays the note and puts it in
the step, **snapped to the scale** (so a wrong key still sounds right), then moves to the next step.

| key | what |
|---|---|
| left / right | the step (up / down = the note of the step, in scale) |
| `A W S E D F T G Y H U J K` | the note (snapped), step entry |
| `Z` `X` | octave down / up |
| `O` | note off (the gate closes) |
| DEL | clear the step |
| `+` `-` | the sound of the step |
| SPACE | hear the step |
| `R` | ROLL this pattern |
| F5 | the sound editor |
| RETURN, F3 | back |

### Sound editor

Up / down the field, `+` `-` the value (SHIFT = fine), SPACE hear it (Z / X octave), left / right the other sound, RETURN back.

## 5. Making music without playing

- **Scale lock**: the key and scale are the song's (`K`, `T`); notes entered or stepped in the pattern editor are in the scale.
- **ROLL** writes for the track's job: LEAD a short hook (stated, repeated, varied), BASS the chord roots on the beat with passing
  notes, PAD long chord tones, DRUMS a sparse kick and a snare, HATS light offbeats, BELLS and FX sparse accents. It follows the
  4-chord loop (`C`), and it never touches the sounds.
- **SHAPE** (`B`) writes the bar lists so that the tracks enter **one at a time, every 2 bars, in track order**, until all 8 play
  (24 bars; each track plays its first four patterns round), and fills the empty patterns with ROLL. Then edit from there.

## 6. Sounds (16 bytes each, 31 of them)

| byte | field | |
|---|---|---|
| 0 | WAVE | the SID control byte without the gate: waves in bits 7-4 (`$10` triangle, `$20` saw, `$40` pulse, `$80` noise), `4` ring, `2` sync |
| 1 | AD | attack, decay |
| 2 | SR | sustain, release |
| 3 | PW | pulse width 0-15 (x 256) |
| 4 | PWM | pulse width motion speed 0-15 (0 off) |
| 5 | VIB | vibrato depth 0-15 (begins 12 frames after the note) |
| 6 | VOICING | 0 one voice, 1 **unison** pair (two voices, detuned), 2 **octave** stack (note, +12, -12), 3 **power** chord (root, fifth, octave), 4 **major** triad, 5 **minor** triad, 6 **drums** (voice 1 tone, voice 2 noise, voice 3 free) |
| 7 | DETUNE | 0-15, the unison spread; for drums the noise voice's decay (0 = no noise voice) |
| 8 | ARP | 0 none, 1-7 fixed arpeggios over the voicing's notes, at 50 Hz (1 octaves, 2 major, 3 minor, 4 fifths, 5 octave-fifth, 6 slow octaves) |
| 9 | GLIDE | 0-15 frames to slide from the last note |
| 10 | FILT | 1: the voices go through the SID's filter |
| 11-14 | WAVE PROGRAM | the control byte of frames 0-3 (0 = the sound's wave): the classic drum click |
| 15 | FALL | 0-15: the pitch falls from above (kicks, zaps) |

## 7. Files

**Save (W) / load (L)**: drive 8, the song's name (its first 11 letters, set with `N`) + `.OWS`: L loads the file that has the name of the song now in the editor, so type the name first. Before the disk is touched: `DISK IN DRIVE 8? Y/N` (N does nothing, the
drive is never touched unasked); a disk error shows its number and text. A song is read into a staging area first, so a bad file
cannot damage the song in memory. Loading takes about 45 seconds (the KERNAL, byte by byte, as SIDWEAVER LITE does).

**Export (X)** writes two files (same guard):

- `NAME.OWP` - **the player and the song** for a demo: a PRG that loads at `$1000` and ends at `$5AFF` (the song is inside it).
- `NAME PLAY` - a stand-alone program: the eq full screen and the song (SPACE pause / play, F7 or RUN/STOP exit), for a music disk.

### The .OWS song file, byte by byte (build 2, version 1)

`OWS1` (4 bytes), then the song, 14080 bytes = the memory image of the player's song block (`defs.inc`):

| offset | size | |
|---|---|---|
| 0 | 1 | speed, frames a step (1-31) |
| 1 | 1 | key 0-11 (C..B) |
| 2 | 1 | scale 0-5 |
| 3 | 4 | chords: the scale degree 0-6 of each chord's root |
| 7 | 1 | song length in bars 1-128 |
| 8 | 8 | ROLL style of each track (0 PAD 1 LEAD 2 BASS 3 REESE 4 DRUMS 5 HATS 6 BELLS 7 FX) |
| 16 | 48 | 8 job names x 6 bytes (ASCII capitals, space padded) |
| 64 | 8 | filter cutoff of each SID (SID register `$16`) |
| 72 | 8 | resonance in the top nibble (register `$17` without the routing bits) |
| 80 | 8 | mode in the top nibble, volume in the low (register `$18`) |
| 88 | 8 | the sound each track's ROLL / SHAPE notes use |
| 96 | 16 | song name |
| 112 | 8 | filter LFO of each SID: rate in the low nibble, depth in the high nibble (0 = none) |
| 120 | 136 | unused (zero) |
| 256 | 512 | sounds: 32 slots x 16 bytes (slot 0 unused, sound n at 256 + 16 n) |
| 768 | 12288 | patterns: 8 tracks x 48 patterns x 32 bytes: 16 notes (0 none, 1-96, 255 stop), then 16 sounds |
| 13056 | 1024 | bar lists: 8 tracks x 128 bytes, the pattern number 0-48 of each bar |

Notes: note n is `12 * octave + semitone + 1`, so C-4 = 49 and A-4 = 58 (440 Hz). The pattern of track t, number p (1-48) is at
`768 + 1536 t + 32 (p - 1)`. `owsong.py` reads and writes exactly this; the Windows version will start from it.

## 8. The player in a demo

`NAME.OWP` is the player (assembled at `$1000`) followed by the song at `$2500`. Interface:

| call | |
|---|---|
| `JSR $1000` | init: A = the bar to start at (0 = the beginning). Wakes all 8 SIDs, starts playing |
| `JSR $1003` | play: **once a frame**, from the demo's own raster interrupt. Trashes A X Y |
| `JSR $1006` | stop: volume 0 on all 8 SIDs, then the gates off |

(also `$1009` trig X = track A = note Y = sound, `$100C` gate X = track, `$100F` quiet, `$1012` invalidate - the editor uses them.)

Needs: the I/O area visible, zero page `$E0-$EF`, and `$1000-$5AFF` for itself (about 22 KB: the player and its variables
`$1000-$24FF`, the song `$2500-$5AFF`). The play routine writes the SIDs only (`$D400` + (n & 1) x `$20` + (n & 4) x `$20` + (n & 2) x `$80`);
it does not touch the VIC, the screen or the stack beyond 8 bytes.

A tiny demo that does it is `tools/octoweaver/example_demo.asm`: put `NAME.OWP` beside it, `acme -f cbm -o demo.prg example_demo.asm`. It
sets up its own raster interrupt and calls the player; **the border colour is the player's cost** (its band is as tall as the play
routine). An exported song played by it produced exactly the same SID writes as the editor playing the same song (67,140 writes
over the first minute of DARK DRIVE, all 8 SIDs in, no difference).

### What the player costs

The play routine is one call a frame. Measured in the headless Octophonic emulator (the border band, in raster lines of a 312-line
PAL frame, turbo off, screen on), with all 8 tracks busy for a whole song:

| song | mean | 95 % of frames under | worst frame |
|---|---|---|---|
| DARK DRIVE | 37 lines (11.9 %) | 58 lines (18.6 %) | 81 lines (26 %) |
| OCEAN LIGHTS | 36 lines (11.5 %) | 56 lines (18.0 %) | 86 lines (28 %) |
| SKIP ROPE | 34 lines (11.0 %) | 58 lines (18.6 %) | 74 lines (24 %) |

(The 6502 itself: about 1,900 cycles a frame on average = 9.7 % of the 19,656 a frame; the rest is the VIC's badlines and the
interrupt.) So **the average is under the 15 % budget, the worst frame is not**: a frame in which several tracks strike a note with
a unison, glide or fall sound, or play arpeggios, costs up to about 28 %. Keep a demo's own timing-critical work away from the line the music
runs at (the music runs from the top of your interrupt), or call the player from an interrupt that has the whole frame to itself. Cheaper:
fewer unison sounds, no arps, ARP / VIB / PWM only where they matter, the filter LFO on few SIDs. The filters are written every 4 frames.

## 9. The demo songs

Made with `demos.py` (original notes). Each uses all 8 SIDs with the SHAPE entrance (a track every 2 bars) and is under 2 minutes.

1. **DARK DRIVE** - A minor, 125 bpm, Am F Dm E, 48 bars (92 s). REESE (unison saws, the filter breathing), DRUMS (a sparse kick,
   backbeat snare), BASS, PAD, HATS, LEAD (a hook and its answer), BELLS, FX (a riser, zaps).
2. **OCEAN LIGHTS** - D major, slow (83 bpm), D Bm G A, 32 bars (92 s). Wide pads, a second pad of strings, a sub bass, a gentle
   pulse lead, a plucked arpeggio, twinkling lights, waves of filtered noise, a soft kick and a shaker.
3. **SKIP ROPE** - C major, 150 bpm, C Am F G, 48 bars (77 s). SID 1 and SID 2 are the two ropes: noise slaps, the second between
   the first's beats like double dutch; then a bouncy bass, claps and kick, a chant-like pulse melody, stabs, bells, blips and a whistle.

## 10. Limits of build 2

- A `.prg`; the Windows build comes later and shares the song format.
- How long a note lasts: until the next note or a **stop** (`O` in the pattern editor), whichever comes first; a bar with no notes in it (pattern 0, or an emptied pattern) also ends it, at the bar's first step. A sound with a high sustain and no stop rings on through rests (that is what a pad is); a muted track is gated off at once, and F1 stop silences all 8 SIDs. ROLL puts a stop three steps after each bell.
- No real-time recording (step entry only), no REU use, no export of the eq as a separate tool.
- The player takes `$1000-$5AFF` and zero page `$E0-$EF` (it cannot be moved in build 2).
- A track about to strike a new note holds its vibrato, PWM and arpeggio for the 1-4 frames before the strike.
- Save and load run at the 1541's own speed (a song is 14 KB: about 45 s).
- Tested in the headless emulator only; not yet on the real MiSTer.
