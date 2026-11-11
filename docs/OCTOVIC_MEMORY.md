# OctoVIC and the MiSTer's memory

By Mong00se, core memory build 1 (1 Nov 2026). What OctoVIC needs from memory, what it gets,
what was wrong, what changed, and how to measure a real machine (OctoBench).

## The clock and the line

The core runs at 31.53 MHz (PAL; 32.73 MHz NTSC). One raster line is 64 us = **2016 clocks**.
OctoVIC draws each line into a four-line buffer up to three lines ahead of the beam, so a line may
take longer than 2016 clocks now and then - but on average lines must take less, and no run of
lines may fall more than three behind.

## Who uses which memory

| memory | used by | notes |
|---|---|---|
| DDR3 (the DE10-Nano's 1 GB, shared with the ARM) | Linux and Main on the ARM; the MiSTer scaler (ascal) - every HDMI frame is written to and read from DDR3, even with HDMI unplugged; the core: OctoVIC's 16 MB VRAM at $32000000, and the drives' track buffers at $30000000 | the core reaches it through one 64-bit port at 31.5 MHz; ddram_arb2 gives it to the drives or OctoVIC in turn |
| SDRAM board (32 MB) | the C64's RAM, cartridges, and the 16 MB REU at $1000000 | an 8-bit controller locked to the C64's bus (one byte per C64 half-cycle). Full, and far too slow for OctoVIC - not an option for VRAM |
| FPGA block RAM | line buffer (4 lines x 512 pixels), sprite table, palettes, the SID chip tables | 550 of 553 blocks used: no room for more buffering |

## What OctoVIC asks for, per raster line

Every read is one 64-bit word (8 bytes), asked for on its own (burst length 1), up to 30 in flight.

| piece | words a line | serial waits a line |
|---|---|---|
| clearing the line's slot | - (99 clocks of work) | |
| a tile layer, 256 or 16 colours | 51 tile rows + 13 map words (+1 line scroll) | 1 for the map, 1 more with line scroll |
| a bitmap layer | 51 | (1 with line scroll) |
| a sprite on the line | 1-8 (64 wide 256 colours: 8) | |
| the copper | 1 per 2 entries | was 1 per word, now 1 per run |
| the sprite table | 128 words once a frame (line 0) | |
| drawing the pixels | 4 a clock: 99 clocks a layer | |
| finishing the line | | 1 (was: until the whole port was idle) |

Two full 256-colour layers: about 130 words a line - 1 KB, about 16 MB/s at 50 Hz. DDR3 can move
hundreds of MB/s, so **bandwidth is not the limit**. What limits OctoVIC is:

1. **Round trips.** On a busy DDR3 a read can take 40-160 clocks to come back. Every place the
   renderer waits for an answer before it can go on costs a whole round trip.
2. **How often the port accepts a request.** Each word is one request. If the DDR3 is answering
   others (the scaler, the ARM), OctoVIC's requests wait their turn.

## What was wrong (found with the RTL replay, octokit/rtlsim)

Horizon builds 7 and 8, replayed through the real octovic.sv with DDR3 busy 80% of the time and
40-120 clock round trips:

- Lines took up to **13,000-15,000 clocks**; almost all of it at the end of the line (S_END),
  waiting for the port to be completely empty. The blitter (the 3D shapes) and the VDATA read
  port kept one read in flight nearly all the time, so "empty" hardly ever came. Result: 3-11 late
  lines a frame - the flicker on Neal's CRT.
- A late line was shown half drawn: layer 0 done, layer 1 not - one layer showing through the
  other ("other layers flashing up on the layer being used"). The copper's per-line CTRL/backdrop
  of a late line were also four lines old.
- A palette burst in the copper cost a round trip per word: 80 words x ~100 clocks = 4 lines.

Per-layer base and scroll registers cannot be swapped between layers or applied mid-line by a late
copper write: the copper's entries for a line are all done before that line's layers are drawn,
in order, and the renderer draws one line at a time. (A 6510 write lands on whatever line is being
drawn at that moment - up to three lines early - as documented.)

## The known-good baseline: Showcase "Lanterns"

Showcase build 1 runs perfectly on Neal's MiSTer (two scrolling hill layers, additive lantern
sprites, the turned-and-sized window layer, 128 copper lists stepped by the copper's own
animation, every picture uploaded by REU before it starts). Logged in the emulator and replayed
through the RTL beside Horizon:

| per frame, after loading | Showcase | Horizon 7 | Horizon 8 | Horizon 9 |
|---|---|---|---|---|
| VDATA writes (CPU/REU into VRAM) | 192 | 894 | 811 | 825 |
| of them while the picture is drawn (lines 16-299) | 192 | 538 | 418 | 699 |
| blitter starts | 0 | 25 | 0 | 15 |
| copper base / switch writes (whole run) | 0 | 6,276 | 7,776 | 10,026 |
| renderer time in maps + tiles (idle DDR3, clocks a frame) | 67,000 | | | 31,000 |
| renderer time on sprites (clocks a frame) | 3,900 | | | 34,000 |

Replayed on the OLD core: Showcase has 0 late lines at 80% busy / 40-120; Horizon 7 has 6-8 a
frame and Horizon 8 2-5 at the same setting. At the harsh 90% / 60-160, Showcase is far over
(200+ a frame) - and it is perfect on the real machine - so **Neal's real DDR3 behaves like the
80% model or better**, and the 90% model is pessimistic.

So Showcase actually draws MORE layer work per line than Horizon (more map and tile reads); what
it does not do is anything that keeps the DDR3 port busy while the picture is drawn. The Horizon
patterns that crossed the line on the old core:

1. **the blitter running during the picture** (the 3D shapes: 15-25 blits a frame) and
2. **VDATA traffic mid-picture** (3.5x Showcase's) - both kept a read in flight on the port, and on
   the old core a line could not finish until the port was empty (the S_END bug): lines waited
   thousands of clocks;
3. **copper lists rebuilt and switched every frame** (2-3 COPBASE/COPCTL writes a frame), and the
   build 5-8 copper-slot reuse (a list overwritten while it was being read), and a 160-entry
   palette burst read a word at a time (build 7);
4. **many big sprites** (Horizon spends 9x Showcase's time on sprites).

With memory build 1, 1-3 no longer cost anything at the 80% model (Horizon 7/8/9: 0 late). 4 is
real work and is what OctoBench's sprite tests measure.

## What changed (memory build 1)

| change | why |
|---|---|
| a line ends when its **own** reads are in (counted: ren_out) | the 13,000-clock waits are gone |
| the **copper reads ahead**, up to 8 words, once a run of entries starts | palette bursts no longer cost a round trip a word |
| a late line shows the **line above again** (REPEAT) or **no layers** (BLANK), never half drawn | no more one layer flashing through another |
| the **meter**: WORST, WORSTLINE, LEAD, LATMAX, LATAVG, STALL, REPEAT, BLANK ($D6A8-$D6B1) | the real machine can be measured, not guessed |

## Results (RTL replay)

Horizon (same frames, old core vs memory build), DDR3 busy 80%, round trip 40-120 clocks:

| demo | old: late lines a frame, worst line | memory build |
|---|---|---|
| Horizon build 7 (copper palette burst) | 6-8, lines 18-26 | **0**, worst 1,686 clocks, 3 lines ahead |
| Horizon build 8 | 2-5, worst 13,000-15,000 clocks | **0**, worst ~1,670, 3 lines ahead |
| Horizon build 9 | 0 (1 in the first frame), worst 6,757 | **0**, worst 1,691, 3 lines ahead |

The copper read-ahead alone takes a copper-heavy line from 1,955 to 1,686 clocks.

OctoBench's 13 tests replayed the same way (late lines in 9 frames, old / new):

| test | 80% busy, 40-120 | 90% busy, 60-160 |
|---|---|---|
| nothing, 1 layer, 2 layers, band | 0 / 0 | 0 / 0 |
| 2 layers + line scroll | 0 / 0 | 1570 / 1570 (over) |
| 2 layers + 32 sprites 64x64 | 0 / 0 | 1284 / 1284 (over) |
| 2 layers + 128 sprites 64x64 | 1154 / 1154 (over) | over |
| 2 layers + copper 64 | 0 / 0 | 13 / **0** |
| 2 layers + copper 160 | 17 / **0** | 135 / **0** |
| 2 layers + REU 4 KB a frame | 524 / **0** | 643 / 536 |
| 2 layers + REU 16 KB a frame | 1057 / **0** | 1149 / 1024 |
| 2 layers + blitter flat out | 982 / **0** | 1042 / 935 |
| everything | 1165 / 1048 | over |

So on a DDR3 as busy as the 80% model, everything but very heavy sprite use now fits. At the
harsh 90% model, two full layers with extras are over the limit: there every word is a request,
and requests are what runs out.

## What could go further (not in this build)

- **Bursts.** Map words, sprite rows, bitmap rows and the sprite table are consecutive in VRAM and
  could be asked for as bursts (one request, up to 8 words): about 20% fewer requests with two tile
  layers, far fewer for bitmap layers and big sprites. Tile rows of neighbouring tiles are not next
  to each other in VRAM, so tiles themselves gain nothing unless the tiles are laid out row by row.
- **Overlap the serial waits** (the map and line scroll for the next layer while this one draws):
  2-3 round trips a line.
- **A tile-row cache** for repeated tiles (scenery repeats): needs answers out of order; costs
  logic the core has little of (91% of ALMs).
- **SDRAM for VRAM**: not possible (full, 8-bit, C64-locked).

## OctoBench

OctoBench (a 6502 program) steps through those 13 tests on the real MiSTer, ~1 s each, and prints
LATE, WORST, LEAD, LATMAX, STALL and REPEAT+BLANK for each - green within the limit, red over it.
That table is the machine's real limits; the replay numbers above are only a model of its DDR3.

## OCTOSCOPE (Fix 55): where its block RAM comes from - Neal decides

OCTOSCOPE keeps its captures in block RAM: 3 slots x 32 channels x 304 one-byte samples, read 4 a clock - about
29 M10Ks (the slot rules and each channel's capture state are in MLABs). Nothing goes to the DDR3: capturing 24
voices at up to 0.6 samples a microsecond each would add up to ~120 DDR3 requests a line, the very thing that makes
lines late (above).

The fitter's report for core-fixes 8d28568 (11 Nov 2026, build-reports branch, fit_entities.txt): RAM blocks
548 / 553 (5 free), ALMs needed 39,671 / 41,910 (about 2,240 free), DSP 77 / 112. So OCTOSCOPE does **not** fit as
things are. The biggest users of M10Ks:

| part | M10Ks | ALMs | what it is |
|---|---|---|---|
| iec_drive (1541 74, 1581 73) | 147 | 3,466 | the drives, with their standard and loadable/parallel ROMs |
| the 4 sid_tops | 104 | 8,550 | 8 SIDs (26 each: waveform and filter tables) |
| fpga64_buslogic | 72 | 136 | the System ROMs: 4 KERNAL/BASIC sets x 16 (Octophonic, Standard, Weaver 2, Japanese) + 2 character sets x 4 |
| chip_bank | 64 | 16 | Neal's chip personalities (the measured combined waveforms) |
| ascal (HDMI scaler) | 43 | 2,156 | the MiSTer framework's scaler |
| opl3 (Sound Expander) | 37 | 1,285 | the OPL2 cartridge |
| octovic | 28 | 8,723 | |
| video_mixer (scandoubler, HQ2x, gamma) | 27 | 1,038 | the analogue output's scandoubler |

Choices that would make room (each takes a menu option away, so it is Neal's call):

- **the Sound Expander (OPL2)**: 37 M10Ks and ~1,285 ALMs - room for OCTOSCOPE's RAM and logic both. A fit trial
  of exactly this was built (branch fix55-trial-noopl, not for the card) to measure it.
- **the Japanese System ROM** (KERNAL/BASIC + its character set): 20 M10Ks - with the 5 free, 25: enough only if
  OCTOSCOPE packs 5 samples a word (23 M10Ks; a little more logic in the renderer), and no help with the logic.
- the 1541's DolphinDOS/parallel ROM, the HQ2x filter: possible, smaller, and they touch loaders and the picture.
