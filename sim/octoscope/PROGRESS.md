# OCTOSCOPE (Fix 55) - progress

Kept up to date while the work goes on, so an interrupted session can carry on from here.

## Done
- RTL: rtl/octovic/octoscope.sv (the capture engine, triple-buffered slots, the slot rules, the latch),
  sid_voice.sv (sc_dac/sc_env/sc_acc/sc_wrap/sc_lock), sid_top.sv (sc_sel -> sc_rec, sc_aud), octovic.sv
  ($C4-$CB, VERSION 5, LMODE b4 scope pass, pixels into the consumer), fpga64_sid_iec.vhd wiring, files.qip.
- sim/octoscope (run.sh): PASS - seed 1 (DDR3 20% busy, 6-30) and seed 2 (50% busy, 20-80), 13 frames:
  256,221 us, 1,797 captures all 304 samples equal, 14 latches x 32 channels equal, 1,462,032 pixels equal,
  72 band first lines, 434 trace joins, no late lines. regmap (VERSION 5), finescroll PASS with the new octovic.
- docs/OCTOVIC.md: OCTOSCOPE section, $C4-$CB rows, LMODE b4, VERSION 5.

## Branches (11 Nov)
- core-fixes: only the build-report improvements (8d28568, e9bad65) - it still builds and fits.
- fix55-octoscope: core-fixes + OCTOSCOPE (RTL, sim, docs). Not merged into core-fixes because it cannot fit
  until block RAM is freed (Neal's choice - docs/OCTOVIC_MEMORY.md, OCTOSCOPE).
- fix55-trial-noopl: fix55-octoscope with the Sound Expander removed - a FIT TRIAL only (build run 42978396818):
  fits, 543/553 M10K, 41,138 ALMs (98%), core clocks pass, HDMI clock -0.017 ns (that path was -0.135 ns before
  OCTOSCOPE too).
- Emulator: octophonic-backgrounds emu-core-fixes b7cd33f (source; x64sc not rebuilt).

## Open
- BLOCK RAM: about 29 M10Ks needed, 5 free (548/553 at 8d28568). The design cannot be fitted until block RAM
  is freed elsewhere - Neal decides what (see docs/OCTOVIC_MEMORY.md, OCTOSCOPE). The baseline build with the
  RAM summary (run 42971666867) tells where the blocks are.
- ALMs: OCTOSCOPE measured at ~1,450 ALMs + 32 M10K + 5 DSP (fit trial).
- No Quartus here: fit and timing only from the GitHub build (build.yml, workflow_dispatch).
- Emulator port: octophonic-backgrounds branch emu-core-fixes (the emulator EMULATOR_VS_MISTER.md names for
  core-fixes); it has no FINE SCROLL emulation (only the scratchpad e115 tree does).

## 11 Nov, Neal's decision: fit WITHOUT removing the Sound Expander and without touching sys/
Plan (coordinator): 1) captures to DDR3 (byte $33000000, above VRAM), small on-chip cache + write FIFO;
2) lean logic; 3) if still over, list unused C64-side pieces for Neal; 4) note a shared SID engine for later.
Builds of this branch push their reports to build-reports-fix55 (not build-reports: card8's build uses that).
Measured cost of the BRAM version (trial vs baseline "ALMs needed"): octovic +1,450 (octoscope.sv 569),
each sid_top +~135 (+540): about 2,000 ALMs; baseline headroom 2,239.

### Step 1 done (11 Nov): the captures in the DDR3
- octoscope.sv: slots at byte $33000000 (96 x 304 bytes); per-channel 8-byte gathering word + 256-word write queue
  (block RAM), lazy latch per channel (gen bit), r_ok = latch applied + queue past the latch mark.
- octovic.sv: scope writes after the renderer's reads (before them when the queue is over half full), 22-bit
  request addresses, a 38-word line cache loaded on a channel/frame change, 2 pixels a clock with shared
  per-sample compare flags (no min/max/clip: shown equal to scope_line on every drawn line).
- sim/octoscope PASS: seed 1 (20% busy), seed 2 (50% busy, 20-80 clocks), seed 3 (30%, port held a line a
  frame): 1,762 captures, 14 latches x 32, 1,462,032 pixels, 434 trace joins, 0 words lost, no late lines.
- Next: GitHub build of fix55-octoscope (reports to build-reports-fix55), then step 2 (lean) from its numbers.

### Build of step 1 (run 42988809330, f634b2a): does NOT fit - 4,212 LABs needed, 4,191 in the device (~210 ALMs over).
octovic 9,701 ALMs needed (baseline 8,723; octoscope.sv 451), each sid_top ~2,250 (baseline ~2,136). M10Ks fine.

### Step 2 (lean), same behaviour:
- multiplies in DSP blocks (octoscope, octoscope_px: x = acc x 152, (DAC-2048) x ENV, slot x 38, s x SCG);
- one pixel a clock (one octoscope_px), registers read live (no copies);
- sid_voice no longer works out the wrap (24 x a 24-bit "!= 0" and a carry): it hands over osc[7:0] != 0 and the
  engine compares with last microsecond's osc[23:8] (kept in its block RAM) - exact (a check voice makes 18 of the
  rare wraps from below 256 to 0 happen; all equal).
- sim/octoscope PASS (both runs).

### Build of step 2 (run 42995830630, 6686575, on core-fixes): FITS
- 41,410 / 41,910 ALMs (99%), 553 / 553 M10K (100%), 82 / 112 DSP, 50,343 registers.
- Timing: every core clock and hold passes; only the HDMI clock (sys/, pll_hdmi) setup -0.047 ns (same path as
  before OCTOSCOPE: -0.135 ns on core-fixes alone). Compile took ~110 min (device full).

## 11 Nov: Core 10 = card8 (Core 9) + OCTOSCOPE + C64RGB 256 (separate job, branch rgb256), one burn tonight
- fix55-on-card8 = origin/card8 + fix55-octoscope (merge 0952509, both octovic ports kept: sysinfo $B3, scope).
  sim/octoscope PASS on it (1,916 captures, 1,462,032 pixels, 0 words lost), regmap (VERSION 5), finescroll, sprtable PASS.
- Build of fix55-on-card8 (run 43008327648, SEED 3) and seed trials fix55-on-card8-s5 / -s8 (runs 43011670743,
  43011675130; only the SEED differs) - read their artifacts (C64.sta.summary), the reports branch is shared.
- Proof MP4s (emulator, current KERNAL, real-core mode): scratchpad/ob4/OctoPlay build 4 - *.mp4.
