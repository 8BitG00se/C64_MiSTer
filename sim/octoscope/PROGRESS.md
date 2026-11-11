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
