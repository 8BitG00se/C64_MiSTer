# Octo Karate (build 2)

The first slice of a one-on-one fighting game for the Octophonic 64: two fighters (VIC and SID) on the beach under the 60 second eclipse
of `tools/eclipse`. Everything runs as 6502 on the core. The PC only prepares data (`export.py`: sprites, boxes, frame data, palette
ticks, the REU image). Attract mode is computer against computer; fire on port 2 starts one player (you are VIC), fire on port 1 two players.

    tools/octokarate/build.sh OUT      # needs acme, c1541, zip, python3 + numpy + PIL
    OUT: Octo Karate.prg, Octo Karate.reu, Octo Karate build 2.d64, About.txt, Install to MiSTer.bat, Octo Karate build 2.zip

Files: `octokarate.asm` (the game), `export.py` (data), `fighters.py` (drawings, moves, boxes), `stage.py` (the eclipse stage, reduced
palette), `font.py` (HUD font), `art/` (the fighter drawing scripts), `about.txt`.
Test build: `acme -DTRACE=1` adds trace registers at $D6E1-$D6EF and a scripted stick on port 2 (never in the release build).

## Controls

| Input | Move |
|---|---|
| left / right | walk (the cycle runs backwards when walking back) |
| hold back | block (stand: high and mid) |
| down + back | crouch block (high, mid and low) |
| fire | punch |
| up + fire | head kick |
| forward + fire | body kick |
| back + fire | front kick |
| down + fire | shin strike (low) |

Keys: 1-6 picture layers, 7 fighters, 8 HUD (labelled with L), D debug line, SPACE pause, F7 quit.

## DESIGN

Rules used (genre-standard, our own code):

* Fixed-step loop at 50 Hz, all timing in frames, locked to the raster IRQ (line 300); a frame timer and the LATE counter exist from the start.
* Frame data per move: startup, active, recovery, damage, hitstop, hitstun, blockstun, pushback (hit / block).
* A strike hurts only on its active frames, when its HIT box overlaps a HURT box (head, torso, legs); one hit per move.
* Hitstop (both fighters freeze), screen shake (XADJ/YADJ of OctoVIC) and a 7-frame hit spark; a different spark colour on block.
* Blocking: holding back blocks high and mid; the low shin strike must be blocked crouching. Block and crouch-block poses.
* KO: hit pose, fall, lie. Health 96 in 16 segments of 6 (green to red), round timer 60 s synced with the eclipse, time up = more health wins.
* Pushboxes keep the fighters apart (minimum gap 48 px), stage corners, no scrolling.
* Input: 6-frame buffer, canonical bits (up, down, back, forward, fire) from either stick.
* CPU opponent: distance bands, attacks from the move reach table, 50% block reaction. Attract mode is CPU vs CPU.
* SFX on spare SIDs 6 and 7 ($D580, $D5A0): whoosh, thud, clack.
* Octophonic rules: turbo ($D030=1); big uploads by REU DMA (64 KB parts, no transfer crosses 512 KB); layer keys with an on-screen
  label; clean screen by default, debug line on D; the picture is one 256-colour layer, no stacked 256-colour layers with VRAM streaming.

Frame data (frames; H high, M mid, L low):

| Move | Level | Startup | Active | Total | Dmg | Hitstop | Hitstun | Blockstun | Push hit | Push block |
|---|---|---|---|---|---|---|---|---|---|---|
| PUNCH | H | 5 | 4 | 17 | 6 | 6 | 14 | 10 | 6 | 8 |
| HEAD KICK | H | 14 | 5 | 33 | 14 | 8 | 22 | 15 | 12 | 10 |
| BODY KICK | M | 11 | 5 | 30 | 10 | 7 | 18 | 13 | 10 | 9 |
| FRONT KICK | M | 11 | 5 | 30 | 9 | 7 | 17 | 13 | 14 | 12 |
| SHIN STRIKE | L | 8 | 4 | 22 | 5 | 6 | 14 | 11 | 5 | 7 |

Budgets:

* Sprites: 125 of 128 (spark 1, fighters 12 = 6 each, shadows 2, spare 1, stage 109). Sprite tables are double buffered in VRAM
  ($020000 and $020400); SATBASE is switched at the top of the frame.
* Sprite graphics window: 2,073,888 of 2 MB (fighters 837,664; stage and sparks 1,236,224). 50 drawings per fighter, 56 colours each
  (quantized from 68); the stage keeps 144 palette entries, the fighters' colours fade with the eclipse light in the per-tick palette.
* REU: 5,365,760 bytes: picture 128 KB at 0, sprite graphics at $020000, scratch at $220000, 1500 ticks (palette + stage sprite table,
  2048 bytes each) at $230000.
* CPU: the frame's work ends at raster line ~146 on average, 238 at the 99th percentile; LATE stays 0, OVR 0.

Known rough spots: the crouch pose reads as kneeling; the control list overlaps the fighters during the attract title; one round only;
tested in the emulator only, and the joystick path was tested with a scripted stick (the emulator build here has no stick injection).
