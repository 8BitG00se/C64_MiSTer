# My Chips - Neal's own SID chips in the Octophonic core

The reason Octophonic exists: to hear Neal's own SID chips on the FPGA. Four chips were measured
off his C64 Reloaded MK2 (the SIDWeaver VST's rips - `Source/ChipClones.h` and
`Source/ChipFilters.h` in SIDWeaver):

| Chip | Model | Combined waveforms | Filter curve |
|---|---|---|---|
| MOS 6581 5084 | 6581 | all 4096 positions, 3 pulse widths | measured registers 0-176 |
| MOS 6581 3184 | 6581 | all 4096 positions, 3 pulse widths | measured registers 0-246 |
| CSG 8580R5 3591 | 8580 | all 4096 positions, 3 pulse widths | measured registers 1-255 |
| MOS 8580R5 4687 | 8580 | all 4096 positions, 3 pulse widths | measured registers 1-255 |

`chips/mkchips.py` turns them into one `.CHP` file per chip. In the core's menu (Audio & Video):
**Load My Chip: Left SIDs** (SIDs 1 3 5 7) and **Load My Chip: Right SIDs** (2 4 6 8), and
**My Chips: On / Off** to compare with the core's own models. A loaded chip sets that side's model
(6581/8580), its combined waveforms and its filter curve; the Left/Right SIDs and Filter menu
settings apply again when My Chips is Off.

## The .CHP file (18688 bytes)

| Offset | What |
|---|---|
| $0000-$0FFF | S+T (triangle + saw), 4096 bytes |
| $1000-$1FFF | P+T (pulse + triangle) |
| $2000-$2FFF | P+S (pulse + saw) |
| $3000-$3FFF | P+S+T |
| $4000-$47FF | filter curve: 1024 x 16 bits, low byte first |
| $4800 | model: 0 6581, 1 8580 - writing it switches the chip on |
| $4810 | the chip's name (text; not used by the core) |

## How the measurements map onto the core

**The index.** A voice looks its combined waveform up with `acc_t` (sid_voice.sv):
`acc_t = {acc[23], acc[22:12] ^ {11{fold}}}`, where `fold` is the accumulator's MSB (or the
ring-mod source) when the saw is OFF, and 0 when the saw is on. So:

- S+T, P+S, P+S+T (saw on): `acc_t` is the accumulator's top 12 bits - the VST's position,
  directly. `table[j] = measured[j]`.
- P+T (saw off): `acc_t` is the triangle: positions $800-$FFF come out with their low 11 bits
  inverted. The fold is its own inverse, so `table[j] = measured[fold(j)]`,
  `fold(j) = {j11, j[10:0] ^ {11{j11}}}`. The core's own P+T tables use only 11 bits (they assume
  the two halves of the triangle sound alike); the chip tables keep all 12, so a chip's
  rising and falling triangle can differ, as measured.

**The pulse.** The core ANDs these tables with the pulse (`comb = p_t_out & {8{pulse}}`), so a
table only needs the values where the pulse is high. The VST measured each pulse combination at
three widths ($400, $800, $C00), and the values at one position are not the same at every width
(the pulse pulls on the same output lines). One table per combination is carried:

- positions $800-$FFF: the $800 (square) measurement
- positions $400-$7FF: the $400 (narrow) measurement - the only one with the pulse high there
- positions $000-$3FF: 0 - nothing was measured with the pulse high there

So at a pulse width of $800 the core plays the measurement exactly; at other widths it plays the
nearest measurement (see Results). The $C00 measurements are not used. Carrying all three widths
per side would need about 3x the memory (see Memory).

**Ring modulation** moves where the triangle folds; the chips were not measured with it on, and
the core folds the index the same way as without (as the VST, which falls back to its computed
waveform there).

**The filter.** `sid_filter.sv` takes `F0 = w0*T << 17` (T = 1 us), i.e. `F0 = 2*pi*f*2^17/1e6
= 0.8235 * f`; the 8580 path agrees (`F0 = 5*Fc`, 12.4 kHz at the top). The 6581 path reads
`F0 = curve[{cfg, Fc[10:1]}] / 2`, so a curve entry is `2 * 0.8235 * Hz`. The VST's curves give
Hz per register high byte (`Fc[10:3]`); each of the 1024 entries (`Fc[10:1]`) interpolates
between two of them. The curve is loaded into Custom filter slot 1 (left) or 2 (right) through
the existing Load Custom Filters path, and the side's `cfg` is set to it. With a chip on, the
8580 path uses the loaded curve too (`sid_tables.sv`: `chipf`), so an 8580 chip gets its own
cutoff curve, and the Fc offset (Adjustable) is off. The rest of the filter (resonance, mixing,
the 6581's distortion) is the core's model for that chip's type.

Note: the measured curves stop at the line input's limit (about 15 kHz) and are carried flat or
at their own slope beyond what was measured (as in the VST). The two 8580R5s measured flat near
8 kHz at the top, below the core's 12.4 kHz - that is what was measured, so that is what plays.

## Memory and timing

`rtl/sid/chip_bank.sv` holds both sides' four tables: 8 x 4096 x 8 bits = 256 Kbit, 32 M10K
blocks, shared by all four SID pairs. Each pair looks a waveform up on alternate clocks (states
1, 3 ... 11 of its 32-clock microsecond); pairs 3 and 4 run their state one clock behind
(`sid_top #(PHASE(1))`), so one port of each memory serves pairs 1 and 3 and the other pairs 2
and 4 - one copy for all eight SIDs. Per-pair copies (128 blocks) would not fit; three widths per
side (96 blocks) would not either.

## Results (sim/chips: the core's sid_top + chip_bank in Verilator, OSC3 read back every
microsecond on voice 3 of all 8 SIDs, compared with the measurement at the oscillator's position)

See sim/chips/results.txt. In short: S+T 100% everywhere; every pulse combination 100% at the
pulse width that was carried ($800); the other widths 92-100% (the pulse-width effect the single
table does not carry).
