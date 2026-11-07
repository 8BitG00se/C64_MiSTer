# Octo Karate (build 3)

The first slice of a one-on-one fighting game for the Octophonic 64: two fighters (VIC and SID) on the beach under the 60 second eclipse
of `tools/eclipse`. Everything runs as 6502 on the core. The PC only prepares data (`export.py`: sprites, boxes, frame data, palette
ticks, the REU image). Attract mode is computer against computer; fire on port 2 starts one player (you are VIC), fire on port 1 two players.

    tools/octokarate/build.sh OUT      # needs acme, c1541, zip, python3 + numpy + PIL
    OUT: Octo Karate.prg, Octo Karate.reu, Octo Karate build 3.d64, About.txt, Install to MiSTer.bat, Octo Karate build 3.zip

Files: `octokarate.asm` (the game), `export.py` (data), `fighters.py` (drawings, moves, boxes), `stage.py` (the eclipse stage, reduced
palette), `font.py` (HUD font), `art/` (the fighter drawing scripts), `about.txt`. The game holds no fighter data of its own: the
two fighters are the data files `fighters/vic.okf` and `fighters/sid.okf` (see FIGHTER FORMAT below), written by `export.py`.
Test build: `acme -DTRACE=1` adds trace registers at $D6D0-$D6EF (never in the release build); `-DFAKEJOY=1` on top of it adds a scripted stick on port 2 (walks, every attack, block, crouch block) that starts a one-player game.

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
* Pushboxes keep the fighters apart (the loader computes the minimum gap from the two fighters' data), stage corners, no scrolling.
* Input: 6-frame buffer, canonical bits (up, down, back, forward, fire) from either stick.
* CPU opponent: hovers at about its longest reach (from the loaded data), steps in to attack only when the chosen move reaches, steps out after, 50% block reaction, rubber band on the health lead. Attract mode is CPU vs CPU.
* SFX on spare SIDs 6 and 7 ($D580, $D5A0), volume 15: whoosh, clack, and a thud layered over both SIDs for an impact.
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

Budgets (build 3):

* Sprites: 125 of 128 (spark 1, fighters 12 = 6 each, shadows 2, spare 1, stage 109). Sprite tables are double buffered in VRAM
  ($020000 and $020400); SATBASE is switched at the top of the frame.
* Sprite graphics window: 1,824,928 of 2,097,152 bytes (fighters 588,672 = two files of 9,206 and 9,190 cells of 32 bytes; stage and sparks
  1,236,256). 50 drawings per fighter, 29 palette entries each (46 and 45 distinct colours, quantized); the stage keeps entries 0-197.
* REU: 5,300,224 bytes: picture 128 KB at 0, stage graphics at $020000, fighter files at $150000 (VIC) and $1b0000 (SID), scratch at
  $210000, 1500 ticks (palette + stage sprite table, 2048 bytes each) at $220000.
* CPU: LATE stays 0 and OVR 0 (CPU vs CPU and the scripted-stick one player run, 4000+ game frames each).

## FIGHTER FORMAT

A fighter is ONE file ("OKF1", 64 KB header-and-tables block, then the sprite graphics). The engine hard-codes nothing per character:
at boot a loader DMAs the file from the REU into a fighter slot (C64 RAM tables + OctoVIC sprite memory), copies the palette entries, builds
the fade table from the palette, and computes reach, rest gap, push gap and hover distance from the header. VIC and SID are two such files
(`export.py` writes them to `fighters/vic.okf` and `fighters/sid.okf`; SID is VIC's data mirrored by the `flip` byte, with its own palette).
All numbers are little endian; offsets are in the file.

Header (256 bytes at 0):

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `OKF1` |
| 4 | 8 | name, 8 screen codes padded with spaces (the HUD label) |
| 12 | 1 | HUD colour index |
| 13 | 1 | number of palette entries used (N, at most 29) |
| 14 | 1 | number of drawings (ND, at most 56) |
| 15 | 1 | number of moves (5) |
| 16 | 1 | flip: 1 = the drawings face left (the fighter starts on the right) |
| 18 | 2 | number of 32-byte graphics cells |
| 20 | 2 | length of the sequence area (bytes) |
| 22 | 1 | graphics start, in 64 KB units (1 = 64 KB into the file) |
| 24 | 1 | guard body reach: how far the guard silhouette extends forward from the origin, px |
| 25 | 1 | guard front reach: how far the front hand extends forward, px |
| 32 | 32 | the palette entries (OctoVIC palette indexes) this fighter owns |
| 64 | 96 | the N palette colours, 3 bytes each (R, G, B 0-255) at full light |
| 160 | 24 | standard drawing ids: guard, bob1, bob2, block, crouch, cblock, hit1, hit2, hit3, fall1, fall2, lie, then the walk cycle (6), then hitb1, hitb2 (a body blow), hitl1, hitl2 (a low blow) - build 6 |
| 184 | 5 x 14 | the move table, one 14-byte row per move (below) |

Move row: sequence length (frames), startup, last active frame, damage, hitstop, hitstun, blockstun, pushback on hit, pushback on block,
level (0 high, 1 mid, 2 low), tip (the strike box's forward edge in px, for reach), address of the sequence inside the file (2 bytes,
offset from the file start), drawing id of the strike drawing. The sequence area (after the drawing records) holds, per move, one drawing id
per frame; the frame number inside the sequence selects startup / active / recovery.

Drawing records (ND of them, 64 bytes each, starting at offset 256):

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | sprite mask: bit s set when slot s is used (slots 0-2 left column top / middle / bottom row, 3-5 right column) |
| 1 | 1 | origin x: the pixel column of the fighter's origin inside the drawing box (the ground point it stands on) |
| 2 | 12 | six graphics cell numbers (2 bytes each, one per slot) |
| 14 | 1 | 1 = this drawing has a HIT box |
| 16 | 12 | three HURT boxes (head, torso, legs): x0, x1 (signed, from the origin, facing right), y0, y1 (0-111 from the box top) |
| 28 | 4 | the HIT box: x0, x1, y0, y1 |
| 32 | 6 | per slot: x offset of the sprite inside the drawing box |
| 38 | 6 | per slot: sprite size flags ($C0 | height code << 2 | width code; 0=8, 1=16, 2=32, 3=64 px) |
| 44 | 6 | per slot: y offset of the sprite inside the drawing box |

Drawing box: 150 x 112 px, the three sprite rows start at y = 8 (64 high), 72 (32 high) and 104 (8 high); each row is covered by one or two cells
(the widest strike, the front kick, fits in two). The graphics follow at 64 KB: 256-colour cells, row after row, 32 bytes per cell unit,
indexes are the fighter's own OctoVIC palette entries (a fighter owns a block of entries above the stage's; the loader fades them with the eclipse
light). Boxes are measured from the drawing's pixels by `fighters.py`, never typed in.

What the engine derives from a loaded fighter: the reach of each move (from tip and the guard data, 72 / 68 / 81 / 88 / 76 px for VIC and SID), the hover
distance (longest reach + 2 = 90), the push gap (shortest reach = 68, so every move can connect at the closest allowed gap) and the rest gap
(76, where the guards just touch). Adding a fighter means a new file and one more slot (the engine has two slots
today); nothing in `octokarate.asm` names VIC or SID. The plan is a sprite creator in OctoPaint that writes this file straight from drawn sheets
(the `.oct` sheets in `sheets/` are the drawings, 7 per fighter).

## Build 3 changes

New fighter art: jacket skirts with a straight hem on every pose, hand-drawn standing feet, a traced front-kick foot and hand-drawn fists; the
sprite box is 150 px wide so the whole strike foot shows. The attract title and the control list are two pages that alternate every 4 s in the
sky (rows 3-10, never over the fighters or the health bars). The CPU hovers at its longest reach plus 2, steps in to attack and out again;
the pushbox gap keeps the guards from overlapping at rest (a short-reach punch closes with a 1 px per frame lunge in its startup). Crouch and
crouch block: feet planted, knees bent and spread, hips down 14 px, torso upright, guard up (crouch block holds the forearms lower).
Best of three rounds: ROUND 1 / ROUND 2 / FINAL ROUND banners in our own pixel lettering, round-win markers (ring / disc) under the health bars,
VIC WINS / SID WINS after two round wins, then back to attract; a draw replays the round. The eclipse RESTARTS from first contact in every
round (the 60 s round timer and the eclipse stay in step). Sound effects at volume 15 with punchier envelopes, impacts layered over two SIDs.
The fighters became data (FIGHTER FORMAT above).

Known rough spots: tested in the emulator only, the joystick path with a scripted stick (the emulator here ignores a real stick). The CPU
vs CPU play is somewhat repetitive. Two human fighters pushing in can overlap their guards by a few px at the push gap (the short punch
needs that reach). Banners and the attract control list can sit over the eclipse's sun in the sky (readable, but the sun shows through the text). Sprite budget is nearly full (125 of 128), so a third on-screen
element needs a stage sprite given up.
