# C64RGB 256 (Fix 60) - progress

Branch rgb256 (from card8). Interrupted? Read this, then `git log`.

## Done
- RTL: VIC pixTag (kind, char/sprite, raster X/Y) -> fpga64 rgb_index/rgb_tag -> rtl/rgb256.sv (the recolour
  unit) in c64.sv under `define RGB256; OPL2 dropped in that core; CORE_TAG "RGB256"; SHIFT+F3 cycles palettes,
  SHIFT+F1 asks Main (mailbox poll word b2) for the Octophonic core, reset after ~4 s if no Main.
- Build: .github/workflows/build.yml builds both cores (matrix), one reports commit (rgb256/ subfolder);
  the rgb256 branch's own builds go to build-reports-rgb256.

## To do
- sim/rgb256 (Verilator, tagged VIC frames from the emulator, reference model)
- tools/rgb256 (pack maker + frame grabber), docs/RGB256.md, pilot pack (scratchpad only, private)
- Main patch (octophonic-rgb256.patch): pack beside game -> MGL switch; home bit -> back
- card step, image payload/expect, check-image.sh
