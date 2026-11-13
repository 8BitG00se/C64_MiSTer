# Old-software regression test (Fix 69)

(c) 2026 Mong00se

> "We could end up in a situation where we ship a new core and everyone starts messaging me."

Before any core burn, everything we have made is run on the new core and compared with the last core.
**The core does not ship until this test says PASS.**

There are two parts:

| Part | What runs | Where | What it compares |
|---|---|---|---|
| **Emulator** (`regress.py`) | every program in `manifest.txt` (58 of ours can run today) | here, in the Octophonic 64 emulator with the **current KERNAL** | every frame's picture (HDMI and the VIC's own picture), the SID writes of every frame, the sound in 20 ms blocks |
| **RTL** (`rtl/`, workflow `Regression test (RTL)`) | the Octophonic KERNAL booting, plus our stock-VIC programs | GitHub Actions: the real core's C64 (GHDL + Verilator, the whole-C64 sim from `sim/rewind`) | every frame's picture and the SID registers at the end of every frame |

Each program ends up as one of these: **IDENTICAL**, **CHANGED** (with a side-by-side picture of the first
changed frame, and where the sound changed), **CRASHED** (the 6510 jammed, or it stopped early), **TIMED OUT**,
**DID NOT START**, or **SKIPPED** (it is not here to run, and the reason is printed). The run ends with **PASS**
or **FAIL**.

## The files

| File | What it is |
|---|---|
| `manifest.txt` | the list: every demo, game, tool and example we made that exists as a .prg/.d64(+.reu), and the slots for the stock C64 classics |
| `regress.py` | the emulator runner and comparator (`list`, `baseline`, `compare`, `determinism`) |
| `baselines/<name>/` | the last core's fingerprints: `index.json` (what was run, with which emulator and KERNAL) and one `<id>.fp.gz` a program |
| `make_test_candidate.py` | makes a TEST "new core" with one deliberate tiny change, to prove the test catches it |
| `rtl/run_rtl.sh` | builds one core tree's C64 in Verilator and runs the RTL list |
| `rtl/tb_regress.cpp` | the RTL testbench: loads a program, types RUN, fingerprints every frame |
| `rtl/compare_rtl.py` | compares the last core's RTL runs with the new core's |
| `../../.github/workflows/regress-rtl.yml` | runs the RTL part on GitHub (it fails when the new core is not identical) |

## How to use it (emulator part)

```
export OCTO_BUILDS=<folders holding Neal's finished builds>   # LOCAL entries
export NEAL_GAMES=<Neal's own stock C64 classics>              # NEAL entries (optional)
python3 tools/regress/regress.py list                          # what can run here
python3 tools/regress/regress.py baseline core10               # once, on the LAST core's emulator
python3 tools/regress/regress.py compare core10 --emu <the new core's emulator>/x64sc
```

The baseline refuses to run unless the emulator ran **this repo's KERNAL** (it reads the CRC the emulator
reports and checks it against `rtl/roms/octo_C64.mif`) and is the current-KERNAL build (`x64sc.md5`).
The compare prints the KERNAL the new core's emulator ran, and says so when it is not this repo's.

The report goes to `<work>/compare-.../REPORT.txt`, with the side-by-side pictures beside it:
LAST CORE | NEW CORE | WHAT CHANGED (magenta).

### What is in the list

- **In this repo, committed**: the 14 Sacred Geometry disks, OCTOCODE, the OCTOCODE Compile Test disk.
- **In this repo, assembled here** (acme): the 9 Code examples, the 3 Disks effects, Note Bouncer, the Moonlight
  picture viewer, SPEC.
- **In the octophonic-backgrounds repo**: Horizon build 10, Showcase build 1.
- **Neal's finished builds** (not in git; found by folder name under `OCTO_BUILDS`): Element 115 (Pacific Coast
  build 8, Front Line, Japan Express, Night City scroll fix, build 1), Night City build 3, Mona Lisa, DNA Wave,
  Pendulum Wave, The Abduction, Sacred City L1 Chapel build 4, Sacred City (compile it yourself), Elements,
  Dithering Doughnut build 5, Voices, RGB Flicker, Wake 8 SIDs, OctoPlay build 6, Capture Test, the Odyssey
  build 3, the five Shooter Template build 1 levels.
- **Stock C64 classics: Neal supplies them.** None are in the repo and none may be added or downloaded. Put
  your own copies in one folder, set `NEAL_GAMES`, and they run like the rest; without them they are skipped
  with a clear message. The slots: IK+, Uridium, Nebulus, Monty on the Run, Sabre Wulf Remastered, RoboCop,
  The Tuneful Eight, and two classic scene demo disks of your choice.

Not in the list, and why: the Sacred City intro build 2 folder has no .prg (only its source); GoFast is being
built by another job; Take a Screenshot writes files into the Screenshots folder; the art kit's `.reu` files are
level data, not programs.

## Every run is the same twice

VICE picks a random seed at start-up, and with it two runs of the same program differ (seen: frames 102-103
and 253-254 of Horizon, and the sound). `regress.py` always runs with `-seed 12345`; with that,
`regress.py determinism` runs each program twice and every picture, SID write and sound sample comes out the
same (checked on Horizon, Element 115 Pacific Coast, Code/stock, Sacred Geometry 14, Dithering Doughnut).

## What this test can and cannot catch - read this

The emulator is a **model** of the core, not the FPGA. The emulator part compares two emulators: the
last core's and the new core's. So:

- It **catches** anything that is in the emulator's model: a KERNAL or BASIC change (the KERNAL is built into
  the core *and* into the emulator from the same `octo_C64.mif`), an OS change (SHELL.PRG, the jingle), and any
  change made to the emulator's OctoVIC, SID, REU or mixer to follow a core change. A one-byte change is enough.
- It **cannot catch** a core change that nobody put into the emulator. If the RTL changes and the emulator
  does not, the two emulators are the same and the test passes. That is what the RTL part is for.
- It **cannot catch** what the emulator does not model at all (see `docs/EMULATOR_VS_MISTER.md`): the line-buffer
  bandwidth (Horizon build 4's tearing), DDR3 timing, turbo (4x on the MiSTer, 1 MHz in the emulator), RAM that is
  not zero at power-on, the HDMI/scaler/analogue output, the real keyboard and joystick.

The RTL part runs the **real core's own RTL** (the 6510, VIC-II, bus logic, CIAs, the rewind unit beside them),
so it catches RTL changes there - but this sim has **no OctoVIC, no SID sound and no REU**, so only the KERNAL
boot and stock-VIC programs can run in it, and the SIDs are compared by their registers, not their sound. It
also cannot see timing (Quartus fit and timing are separate), the analogue or HDMI output, or anything only the
real MiSTer does. **A real-MiSTer check is still needed** for what neither part models.

The RTL part can only build a core tree that has `sim/rewind` (build 13 onwards). The burnt Core 10 is older,
so its RTL cannot be the baseline; use the release line as the last core for the RTL side.
