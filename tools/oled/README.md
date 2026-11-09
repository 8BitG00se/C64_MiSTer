# The front screen (tty2oled)

The MiSTer's little front screen (256 x 64, 16 greys; Antonio Villena's tty2oled board running
8BitG00se/octophonic-tty2oled) shows **the animated Octophonic logo all the time**, and **a program's own
animation while that program runs** - then the logo again when it ends (Fix 27; Fix 20: the logo from power-on).

## Giving a program its own animation

Put `NAME.oled` in the program's folder, with the same name as the program (`Night City.prg` + `Night City.oled`;
`Disk.d64` + `Disk.oled`), or as the only `.oled` in that folder. That's all: copy the folder onto the card
(FileZilla) and run the program from F1/F3 or `/NAME`.

Make one from a GIF, a video or a folder of frames:

    python3 make_anim.py "Night City.gif" -o "Night City.oled"
    python3 make_anim.py "frames/*_hdmi_*.png" -o "Demo.oled" --crop 70,104,256,64 --every 2 --fps 12.5

It writes a preview beside it (`NAME_preview.gif`, three times the size, tinted like the acid-green perspex).
Options are listed at the top of `make_anim.py`; the useful ones: `--crop` (what part to show - the screen is 4:1),
`--bounce` (forwards then backwards: smooth loops for swings and turns), `--levels` (fewer greys = smaller),
`--max-kb` (default 64 KB, about 6 s to send; a longer clip is cut to fit), `--shear` (straighten a diagonal).

The screen is fed over a 115200-baud serial line, so an animation is sent once (a few seconds, while the program
loads) and then plays from the screen's own memory; running the same program again sends nothing. Only what
changes between frames is sent, and rows that scroll are moved by the screen itself (parallax), so still
backgrounds and scrollers cost little; many small things moving every frame cost the most.

## The examples

`examples.py FRAMES OUT` makes these from the demos' own frames in the Octophonic 64 emulator
(`/home/claude/emu/emusnd.sh` with `OCTO_DUMP_FROM/STEP/TO`):

| animation | from |
|---|---|
| `Night City.oled` | the city at its own pixel size, the jet and UFOs flying through, scrolling (73 frames, 12.5 fps, ~6 s loop) |
| `DNA Wave.oled` | the whole helix turning, tilted level so it fits the strip, bounce |
| `Pendulum Wave.oled` | the row of 24 balls swinging, bounce |
| `Mona Lisa.oled` | the demo's held views - title, face, eyes, smile - each brought in by a raster wipe |

## How it works

- **Octophonic Main** (`tools/octoos/main/octophonic-oled.patch`, `support/octo/octo_oled.cpp`): when OPEN or RUN
  starts a `.prg/.crt/.d64/...`, it looks for the `.oled`; CTRL+F12, Esc held, the browser and the settings bring
  the logo back (a cold start's SHELL request too, but not in the 10 s after a program was started - loading a
  `.prg` resets the C64). Main starts `octophonic/oled.sh` in the background and never waits for the screen.
- **`oled.sh`** (`octophonic/oled.sh` on the card) owns the serial line: asks the screen's firmware once a
  power-on (`CMDHWINF`), sends `CMDOANI` (or `CMDOANP` for the one held already), `CMDOCTO,0` for the logo; a newer
  request waits for a transfer to finish (cutting one short would make the screen read the next command as picture
  data). Older firmware: the still picture at the end of the `.oled`. No screen: nothing. Log: `octophonic/oled.log`.
- **The firmware** (OCTO4): `CMDOANI,<bytes>,<frames>,<ms>,<mode>` + the frames, held in RAM (up to 96 KB; more
  than fits: the frames that fit), looped (mode 0) or bounced (mode 1) until the next command.
- **The `.oled` file**: described at the top of `make_anim.py` (PackBits of each frame XOR the one before, optional
  parallax bands, then a plain `.gsc` still at the end).
- **The recipe**: 042 (this Main), 084 (tty2oled's daemon on a card without it, its own updater off - it would
  flash the stock firmware over the logo), 085 (title cards), 087 (`oled.sh`), 088 (the screen's firmware to OCTO4,
  only on a screen that already runs an Octophonic firmware).

## Checks

- `fwcheck/check.sh FIRMWARE.ino FILE.oled` - compiles the firmware's own decoder (cut out of the `.ino`) on the PC
  and checks it shows exactly the frames `make_anim.py` meant.
- `fwcheck/fake_screen.py oled.sh A.oled B.oled` - a pretend screen on a pseudo-terminal: boot, play, logo, the same
  program again, a request during a transfer, an older firmware.

## Title cards (still pictures)

`make_card.py` makes a 256 x 64 `.gsc` card (`GeometrySings.gsc`); step 085 puts cards in `tty2oled/pics_pri`,
where tty2oled shows the one named after the running core (`/tmp/CORENAME`, set by a launcher's `<setname>`).

`tty2oled/` holds venice1200's MiSTer scripts (GPL-3, https://github.com/venice1200/MiSTer_tty2oled, commit
de8bb4b) that step 084 puts on a card without tty2oled.
