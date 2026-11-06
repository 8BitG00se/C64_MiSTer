# OCTO WEAVER LITE

An 8-SID step sequencer for the Octophonic 64 (OctoVIC 2+), by Mong00se. 6502, ACME. The user's manual, the `.OWS` song format byte by
byte and the player's interface are in [`docs/OCTOWEAVER.md`](../../docs/OCTOWEAVER.md); the design is in
[`docs/OCTOWEAVER_SPEC.md`](../../docs/OCTOWEAVER_SPEC.md).

| file | what |
|---|---|
| `weaver.asm` | the program (`acme -f cbm`, loads at `$0801`, `10 SYS2061`): the player, the song, the platform library, the editor |
| `defs.inc` | the memory map, the song layout, the sound layout, zero page, OctoVIC registers |
| `player.asm` | the **player** (assembled at `$1000`; `JSR $1000` init, `$1003` once a frame, `$1006` stop). The same code is in the editor, in `NAME PLAY` and in a demo's `NAME.OWP` |
| `front.asm` | the platform library (OctoVIC start / check, the 24-bar eq, text, keys, the frame interrupt) and the PLAY program |
| `editor.asm` `roll.asm` `disk.asm` | the editor (lanes, pattern editor, sound editor, dials), ROLL / CHORDS / SHAPE, the disk guard, save / load `.OWS`, export |
| `ftab.inc` `eqtab.inc` `sounds.inc` | tables made by `mktab.py` and `owsong.py` (do not edit) |
| `mktab.py` | the frequency table (PAL) and the eq's envelope table |
| `owsong.py` | the `.OWS` song in Python: the same bytes the 6502 uses; reads and writes song files (the Windows version starts here) |
| `demos.py` | the three demo songs (DARK DRIVE, OCEAN LIGHTS, SKIP ROPE), written with `owsong.py` |
| `build.py` | `python3 build.py OUT [N]`: the PRG, the PLAY players, `Octo Weaver Disk build N.d64`, `OCTO WEAVER LITE build N.zip`, `How to use.txt` |
| `md2txt.py` | `docs/OCTOWEAVER.md` to the plain text `How to use.txt` |
| `example_demo.asm` | the smallest demo that plays a song: includes `NAME.OWP`, calls the player once a frame; its border band is the player's cost |

Build: `python3 build.py OUT` (needs acme, c1541, python3). `python3 demos.py OUT` writes the three `.ows` files only.
`acme -DPROFILE=1 ...` makes a player that colours the border by phase (fx, filters, compute, strike) for measuring.

Testing was done in the headless Octophonic emulator with scripted keys and the audio dumped and measured: the editor plays a song, the eq
follows each SID; scale-locked entry; sound editor, dials, mute / solo; ROLL / SHAPE; save and load with the guard (the saved `.OWS`
equals `owsong.py`'s file byte for byte; after a change and a load the exported `.OWP` equals the original); the exported `.OWP`
played by `example_demo.asm` writes exactly the same SID registers as the editor (67,140 writes of the first minute of DARK DRIVE, no difference); the player's
cost measured as the border band over a whole song; per-SID levels with each track played alone, the whole-mix peak and the
entrance bar of each SID.
