# C64RGB 256 (Fix 60) - progress

Branch rgb256 (from card8). Interrupted? Read this, then `git log`.

## Done
- RTL: VIC pixTag -> rtl/rgb256.sv (recolour unit) in c64.sv under `define RGB256; OPL2 dropped there;
  CORE_TAG "RGB256"; SHIFT+F3 cycles palettes (OSD line), SHIFT+F1 asks Main (poll word b2), reset after ~4 s.
- Build: build.yml builds both cores (matrix); rgb256 branch builds go to build-reports-rgb256.
- sim/rgb256 (Verilator vs model): RGB256_SIM_OK on the made-up frames and on real (private) game frames.
- tools/rgb256 (grab/starter/make/preview), emulator patch (OCTO_TAGDUMP, OCTO_RGBPACK), docs/RGB256.md.
- Main patch octophonic-rgb256.patch (pack beside game -> MGL switch; back on SHIFT+F1/CTRL+F12/no-pack game).
- Card: step 032, recheck-test (RECHECK_TEST_OK), build-image.sh payload + expect, check-image.sh, Check card.bat,
  install_core.sh / install .bat carry the RGB core.

## Results
- C64RGB 256 core (run 43003624471, commit 12b0896, same RTL as HEAD): fit OK, 38,769/41,910 ALMs (93 %),
  523/553 M10K (95 %); timing met: setup +0.154 ns (HDMI clock), hold +0.249 ns, 0 TNS.
- Main (octoos-main-build-rgb256, e209273): builds clean.

## Left (for the Core 10 merge)
- build.yml conflicts with fix55-on-card8 in the reports step only: keep the rgb256 side, the $REV paths,
  with fix55's  sed 's/  */ /g'  in place of cut.
