# SPEC - what this machine has (Fix 59)

Tools > SPEC.PRG shows the core's name and build date, the OctoVIC version, how many SIDs answer, the SDRAM
board's size (as the MiSTer reports it), the REU setting, and PAL/NTSC. Any key goes back to the start screen.
Ask people to send a photo of it with bug reports.

The SDRAM size and REU setting come from OctoVIC's spec register, `$D6B3` (core 9 on):
b7 = the MiSTer reported the SDRAM size, b1-0 = SDRAM (0 none, 1 32MB, 2 64MB, 3 128MB),
b5-4 = REU (0 off, 1 512K, 2 2MB, 3 16MB). The emulator answers `$B3` too (`OCTO_SPEC`, default `$B3`).

Build: `./build.sh` (needs acme). The card image builds it from here (step 056 puts it in Tools).

(c) 2026 Mong00se
