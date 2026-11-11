# Octo Weaver Lite build 1 - the build spec

Original project by Mong00se (Octophonic 64). Octo Weaver Lite is SIDWEAVER LITE (Neal's one-SID
step sequencer for the C64, Oct 2026) grown up for the Octophonic 64: **8 SIDs**, an OctoVIC
equaliser, and an export that demos can play. It is **demo-orientated**: its job is making the
music for Octophonic demos and games, the way Neal's best tunes were made - **each SID one fixed
job, the tune with a shape (SIDs entering one at a time), a short hook over a few chords**.
Build 1 is a `.prg` only; a Windows build comes later and shares the song format.

Read first, in this order:
1. **SIDWEAVER LITE**, the starting point (Neal's own code, reuse it freely):
   `/home/claude/sidweaver_zip/C64/Lite/lite.s` (xa syntax, 2530 lines - read its header and the
   player, the song layout, the dials, the save/load), `build.py` (tables, pitch table, the .d64),
   `demos.py` (the song format and three demo songs).
2. `docs/OCTOVIC.md` (OctoVIC registers), `docs/OCTOOS.md` (keys, start screen, the eq), and the
   OctoPaint build for how an app starts, quits and uses the disk guard:
   `tools/octopaint/` and `docs/OCTOPAINT_SPEC.md` (sections 2 and 8 apply here unchanged).
3. The 8-SID addresses: `docs/OCTOOS.md` / the core - SID n at `$D400 + (n&1)*$20 + (n&4)*$20 +
   (n&2)*$80` for n = 0-7 (the same formula as SHELL.PRG's jingle `jaddr` in
   `tools/octoos/kernal/shell.asm`). Check it against the core before relying on it.

## 1. Files

| path | what |
|---|---|
| `tools/octoweaver/weaver.asm` | the program, **ACME** (`-f cbm`), at `$0801` with `10 SYS2061`; ported from lite.s (xa) to ACME syntax |
| `tools/octoweaver/build.py` | tables (pitch, screen rows), the default sounds, the demo songs; assembles; makes the .d64 |
| `tools/octoweaver/demos.py` | the demo songs in the extended format |
| `tools/octoweaver/player.asm` | the **stand-alone player** for demos (section 7) |
| `tools/octoweaver/README.md` | build and test |
| `docs/OCTOWEAVER.md` | user manual + the song format byte by byte + the player's interface |

Names a user gets carry the build number: `OCTO WEAVER LITE build 1.zip`, `Octo Weaver Disk build 1.d64`, title `OCTO WEAVER LITE BUILD 1`.

## 2. Start and quit

As OctoPaint: OctoVIC on and checked (ID `$8C`, version >= 2), else a message and back to BASIC.
Keep SIDWEAVER LITE's design of its own raster interrupt with the ROMs out (`$01` = `$35`) and the
KERNAL back in only for disk I/O, a byte at a time. F7 = quit (asks), restoring everything (all 8
SIDs silenced: volume 0 then gates off), back to BASIC (`JMP ($A002)` with ROMs in).

## 3. The music model (the Lite's, extended)

- **8 tracks, one per SID.** Track n plays SID n. Each track has a **job name** (6 letters, editable:
  defaults PAD, LEAD, BASS, REESE, DRUMS, HATS, BELLS, FX) - the Halloween method: one fixed job a SID.
- **Each track plays one note line**, and its **sound** decides how the SID's 3 voices are used
  (the VOICING field, below): one voice, a unison pair (2 voices, detuned), an octave stack, a power
  chord (root + fifth + octave), a major or minor triad, or "drums" (voice 1 kick/tone, voice 2
  noise, voice 3 free). So 8 note lines drive all 24 voices, and each SID sounds big on its own.
- **Patterns**: 16 steps, a step = note (1-96, 0 none, 255 stop) + sound (1-31). **48 patterns per
  track** (8 x 48 x 16 x 2 bytes = 12 KB).
- **The song**: per track a list of up to **128 bars**, each bar a pattern number (0 = silent).
  All tracks advance together. Speed (frames per step) as the Lite.
- **Sounds**: 31 shared by all tracks, the Lite's fields **plus**: VOICING (0-6 above), DETUNE
  (0-15, for unison), ARP (0 none, 1-7: fixed arp patterns over the voicing's notes at 50 Hz),
  GLIDE (0-15 frames to slide from the last note), and a 4-step WAVE PROGRAM (waveform per frame for
  the first 4 frames, then the sound's wave: the classic drum/attack trick). Write each sound as 16
  bytes; document the layout.
- **Dials, per SID**: filter cutoff, resonance, mode, and volume - turned live with keys, and by a
  paddle/mouse on POT if present (the Lite's paddle code). Each SID has its own filter: that's the
  point of 8 SIDs.
- **Mute / solo** per track (keys), shown on screen; the eq shows muted tracks dark.

## 4. The screen

- VIC text, 40 columns, in the start screen's style and colours (navy, the yellow keys, the bar at
  the bottom: `F1 PLAY F3 BAR F5 SOUND F7 QUIT` - adjust to the real keys).
- Top: title, song name, speed, bar number, the SIDs' chip models if Main reports them (else leave out).
- **The eq**: 24 bars (8 SIDs x 3 voices) drawn by OctoVIC **sprites or a small layer-1 bitmap** at
  the top of the screen, one colour per SID (the same 8 colours as each track's name), heights from
  each voice's envelope (read OSC3/ENV3 only from voice 3 of each SID - for voices 1-2 use the
  player's own envelope model: a software ADSR level updated each frame from the sound's ADSR).
  It must move with the music in time and look good - this is the selling point.
- Middle: the **8 track lanes**, each one line: job name, mute/solo marks, and the bar list around
  the play position (scrolling). Cursor on a track: RETURN opens its **pattern editor** for the
  current bar (16 steps, notes shown as `C-4`, sound numbers), as the Lite's bar editor.
- Bottom: the sound editor when open (F5), else the dials of the current track's SID.

## 5. Making music for a non-musician (important)

Neal describes himself as a beginner at keys: note entry must not need playing in time or in key.
- **Scale lock**: a KEY (C..B) and SCALE (major, minor, minor pentatonic, major pentatonic, dorian,
  blues) for the song; in the pattern editor, the up/down keys step through **scale notes only**,
  and the QWERTY "piano" row (A W S E D F T G Y H U J K) plays/enters notes snapped to the scale.
- **Step entry**: put the cursor on a step, press a note key: it goes in. No real-time recording
  needed in build 1.
- **ROLL** (key `J`, as in Neal's old Weaver): fill the current pattern of the current track with a
  musical idea that fits the track's job and the key/scale - LEAD: a short hook (motif stated,
  repeated, varied); BASS: roots of the chord on the beat with passing notes; PAD: long chord
  tones; DRUMS: a kick/snare pattern (sparse, bass-orientated - Neal dislikes busy hats); HATS:
  light offbeats; BELLS/FX: sparse accents. Press J again for another. Never touch the sounds.
- **CHORDS**: a song-wide 4-chord loop (default Am F Dm E, editable as 4 numbers) that ROLL follows.
- **SHAPE** (key `B` for BUILD): writes the song's bar lists so the tracks **enter one at a time,
  every 2 bars**, in track order, until all 8 play - Neal's proven method. Then he edits from there.

## 6. Files on disk

Save / load the song to drive 8 with the OctoPaint disk guard (`DISK IN DRIVE 8? Y/N`, the error
channel shown, never touching the drive unasked), byte by byte through the KERNAL as the Lite does.
Format `.OWS` (Octo Weaver Song) version 1: `OWS1`, then header (speed, key, scale, chords, 8 job
names, dials for 8 SIDs), 31 sounds x 16 bytes, 8 tracks x 48 patterns x 32 bytes, 8 bar lists x 128.
Document every byte in `docs/OCTOWEAVER.md`. `build.py` must be able to write and read the same
format (the demo songs are made by it; the Windows version will start from it).

## 7. Export for demos (the point of it)

`X` exports **the player + the song** as a PRG for demos: `NAME.OWP` = the stand-alone player
(`player.asm`, assembled at `$1000`, no screen code) followed by the song data. Its interface:
`JSR $1000` init (A = 0), `JSR $1003` play once a frame (from the demo's own raster IRQ), `$1006`
stop (all 8 SIDs silenced). Cost: measure the play routine's worst-case raster time with 8 tracks
busy and write it in the manual (the budget: under 15% of a frame with turbo off; it may use the
REU later, not in build 1). Also export a **standalone player PRG** (`NAME PLAY`) that shows the
OctoVIC eq full screen and plays the song - a "music disk" item for the Music folder.

## 8. Demo songs (in `demos.py`, written for it - original notes only)

Three, each using all 8 SIDs with the SHAPE entrance, each under 2 minutes:
1. **DARK DRIVE** - dark, a reese bass (unison saws, filter moving), sparse kick, pads, bells.
2. **OCEAN LIGHTS** - slow, wide pads and a gentle pulse lead, for the ocean parallax example.
3. **SKIP ROPE** - for the future Skipping Ball upgrade: SID 1 and 2 are two "ropes" (short noise
   slaps, one panned left one right, landing between each other's beats like double dutch ropes),
   then bass, claps, a chant-like pulse melody, joining one by one. Original tune, rhythm idea only.

## 9. Testing (feedback loops - required)

The headless emulator harness in the session scratchpad (`emu1541/rt`, `k6/emu6.sh`, the recorders
in `showcase/` and how the OctoPaint build drove them - look in `/tmp/claude-0/-home-claude/edbf065c-c2ec-5cc1-9125-6a9ca2c55b40/scratchpad/octopaint/` for its scripts). Copy the
runtime to `/dev/shm` for your tests. For each step: run, capture frames **and the audio** (the
emulator writes a wav/pcm), **look at the screenshots and check the audio** (levels per SID, no
silence where notes should be, no clipping, notes at the right pitch - measure with numpy/FFT),
fix, then go on.

Steps, in order: (1) start/quit, the screen, 8 SIDs silent; (2) the player plays a hand-written
8-track song correctly (pitches, voicings, arp, glide, wave program - measure); (3) the eq moves in
time with each SID; (4) pattern editor + scale lock + step entry; (5) sound editor + dials per SID
+ mute/solo; (6) ROLL per job + CHORDS + SHAPE; (7) save/load `.OWS` with the guard - byte-identical
round trip, and build.py reads it; (8) export `.OWP` + `PLAY`: a tiny test demo that includes the
player plays it identically; raster cost measured; (9) the three demo songs; (10) package +
manual + a **60-second MP4** (the eq and the screen while DARK DRIVE builds up, with sound).

## 10. Rules

- 6502 only, ACME. Original music only (the demo songs' notes written for this). No Commodore ROM
  code. Neal's own SIDWEAVER LITE code may be reused freely.
- Commit as **Mong00se** on `octophonic-v1.1`, small commits, push as steps work. No releases.
- Touch only `tools/octoweaver/` and `docs/OCTOWEAVER*.md`. Don't change the core, Main, the SD
  recipe, OctoPaint or anything on Neal's PC or MiSTer.
- Deliverables in the session scratchpad `octoweaver/`: `OCTO WEAVER LITE build 1.zip` (PRG, the
  d64 with the three demo songs and their PLAY players, `How to use.txt` with the FileZilla steps:
  SFTP to the MiSTer, user root, password 1, into `/media/fat/games/C64/Tools/`), the MP4, and a
  small contact sheet.
- If something here is impossible or much too slow (e.g. the player's raster cost for 8 SIDs), stop
  and say so in the report rather than quietly redesigning.
