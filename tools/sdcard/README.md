# The Octophonic SD recipe

One card, built by numbered steps. The same steps that bring Neal's card up to date build the
release `.img` on a freshly formatted card - which is why the card and the image can never
drift apart.

```
tools/sdcard/
  run-steps.sh          the runner
  octo-step-lib.sh      helpers every step shares
  steps/
    010-folders.sh      the docs/SDCARD.md folder tree
    015-examples.sh     the example set in every games/C64 folder (demos with their .reu files,
                        OCTOCODE, code examples, a game, a picture, tunes, chips) - payload
                        files/examples/, from the sdcard-examples branch (see docs/EXAMPLES.md)
    020-os-ini.sh       octophonic/os.ini, with startin=sd
    030-core.sh         the core (hidden .rbf) + the launchers
    040-main.sh         Octophonic Main
    050-shell-prg.sh    octophonic/SHELL.PRG
    055-code-tools.sh   octophonic/acme (OCTOCODE's F2 COMPILE on the MiSTer) and Apps/OCTOCODE.PRG
    060-mister-ini.sh   makes sure a MiSTer.ini exists; sets no video
    065-mister-ini-vsync.sh   vsync_adjust=2: HDMI follows the core's 50 Hz (Fix 43; release, not DEV)
    070-migrate-drop-octophonic-folder.sh   the old games/C64/Octophonic folders, if empty
    080-bootcore.sh     MiSTer.ini: bootcore=Octophonic 64.mgl, every bootcore_timeout off
    095-stock-menu-core.sh  menu.rbf: MiSTer's own (white noise) menu core back, if the old navy one was in
    900-DEV-ssh-key.sh          Neal's ssh key + the startup hook
    910-DEV-mister-ini-crt.sh   Neal's JVC CRT video settings
    920-DEV-network-share.sh    reports his share; configures nothing
  files/                the payload the steps install (not in git - see below)
```

## The three rules every step keeps

1. **It can run twice with no harm.** Every step checks first and only changes what needs
   changing. Run the recipe again and finished steps are skipped; force them and they still
   come out the same.
2. **It backs up anything it replaces**, into `octophonic/backups/<run>/`.
3. **It writes one line to `octophonic/steps-done.txt`** when it finishes. That file is how the
   updater knows what is left to do.

## Running it

```sh
sh run-steps.sh                     # bring this card up to date. DEV steps are skipped.
OCTO_LIST=1 sh run-steps.sh         # say what would run, change nothing
OCTO_DEV=1 sh run-steps.sh          # Neal's machine: also the DEV steps
OCTO_ONLY=030 sh run-steps.sh       # just one step
OCTO_FORCE=1 sh run-steps.sh        # run them all again, done or not
OCTO_ROOT=/mnt/newcard sh run-steps.sh   # build a fresh card for the release image
```

It stops at the first failure and says so, so a half-finished step never leaves the next one
running on top of it.

## DEV steps and the release image

A step whose name contains `-DEV-` is Neal's own setup and **the runner skips it unless
`OCTO_DEV=1`**. The image build simply does not set that, so the image can never pick up:

- his SSH public key, or the `OCTOPHONIC SSH KEY` block in `linux/user-startup.sh`
- his JVC CRT video settings in `MiSTer.ini`
- anything about his network share

That is the whole point of the split: the image is built by the same steps, with the dev ones
left out, rather than by a separate script that might fall behind.

## The payload (`files/`)

The steps are logic; the things they install are the payload, and binaries do not belong in
git. A build package carries them:

```
files/
  C64_Octophonic_<date>_<tag>.rbf
  core-number.txt
  install_core.sh                 (a copy of tools/install/install_core.sh)
  MiSTer
  SHELL.PRG
  _Computer/Octophonic 64.mgl     and the chip-preset launchers
  examples/MANIFEST.txt           step 015: "<md5>  games/C64/<path>" a line
  examples/games/C64/...          (the sdcard-examples branch; build-image.sh fetches it,
                                   or OCTO_EXAMPLES=<folder>; OCTO_EXAMPLES=none: no examples)
  dev/octophonic-key.pub          DEV only
```

A step with no payload stops with a clear message and does **not** mark itself done, so the
next run picks it up once the payload is there.

**SHELL.PRG must come from the same commit as the core**, since it calls into the KERNAL ROM at
fixed addresses. Build it with `acme -f cbm -o SHELL.PRG tools/octoos/kernal/shell.asm` -
`shell.asm` is self-contained and needs no Commodore ROMs.

## What is NOT here

No Commodore ROMs, ever. The Octophonic KERNAL is a patch, and the ROM lives inside the core's
FPGA image (`rtl/roms/octo_C64.mif`), built from the user's own ROMs.
