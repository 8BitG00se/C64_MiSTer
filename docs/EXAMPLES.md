# The example set (SD recipe step 015)

Something in every `games/C64` folder, so that every folder the browser opens has something
in it that runs. All of it is Octophonic 64 / Mong00se's own work: no Commodore ROMs, no
third-party games, demos, pictures or tunes. Built by `tools/examples/build.sh` (everything but
the demos) into the payload `files/examples/` of step `015-examples.sh`; the payload, with the
demos and their `.reu` files, lives on the `sdcard-examples` branch (binaries stay out of this
branch), and `tools/sdcard/build-image.sh` fetches it from there.

| Folder | What | Opened from the browser |
|---|---|---|
| Demos | every Octophonic demo build, a folder each with its `.prg` and the `.reu` it needs (Skipping Ball, Punching Cubes and Gold Black Hole start clean: the I key shows or hides their technical rows, LATE/REP/BLANK and the core line); `Stock64/` the stock one-SID versions | RETURN on the `.prg`: its `.reu` goes in (the load bar), then it runs |
| Games | `Note Bouncer.prg` - keep the bouncing balls up with the bar; every bounce (left wall, right wall, ceiling, bar) has its own sound on the eight SIDs. Joystick port 2 (or Z/X), fire/SPACE | runs |
| Tools | `OCTOPAINT.PRG` (the paint program), `OCTO WEAVER LITE.PRG` (with `Octo Weaver Disk build 1.d64`, three songs), `OCTOCODE.PRG` - the code editor (F5 also writes the program F2 made onto the disk) | runs |
| Code | the OCTOCODE examples, each as `.asm` and the `.prg` it makes: `hello` (copper bars, a scroller, a note), `stock` (a stock C64 program), `raster` (raster bars: 64 copper lists OctoVIC plays by itself), `scroll` (32x32 letters on a 256-colour layer, a wave through them, colour cycling), `sprites` (64 sprites in a sine wave, no multiplexer), `plasma` (a plasma on a turned-and-sized bitmap layer, colour cycling), `bounce` (a bouncing logo that squashes: FLD by the copper), `split` (split screens: three bands set up by the copper), `parallax` (a copper sky, a 16-colour mountain layer and a 256-colour hill layer at three speeds), `makereu` (batch 1, Fix 56: builds data in the REU and saves it as MADE.REU beside itself - SAVEREU) | the `.prg` runs (the `.asm` files are for OCTOCODE and the PC; the browser lists only the core's file types) |
| Music | `Crystal Harbour.prg` - a SIDWeaver tune on all eight SIDs (SID 1 plays it, OctoSID FX make SIDs 2-4, SIDs 5-7 take one voice each, SID 8 plays it all) with an equaliser that shows all eight | runs |
| SIDs | `Neal Plays.prg` - a SIDWeaver tune by Mong00se on one SID, in a player | runs (a raw `.sid` is not one of the core's file types, so tunes are `.prg` players) |
| Pictures | `Moonlight.prg` - an original 320x200 pixel-art picture (a lighthouse, the moon and an octopus) in 255 colours on a bitmap layer; SPACE fades it out | runs |
| My Chips | Mong00se's four measured SIDs (`.CHP`) | F8: MY CHIP LEFT / RIGHT list them (`.CHP` is not a browser file type) |
| Disks | `Starfield.d64`, `Colour Logo.d64`, `Wavy Pillar.d64` (three more effects, source as SEQ files for OCTOCODE's F3), `OCTOCODE Examples.d64` (the program first, its source as a SEQ file for OCTOCODE's F3), `Hello Disk.d64` (BASIC), `Hello Cart.crt` (an 8K cartridge) | a `.d64` goes into drive 8, LOAD"*",8,1 and RUN are typed; the `.crt` starts |
| Screenshots | `Take a Screenshot.prg` (SPACE asks Main for a screenshot, mailbox `10` SHOT; it says on screen where it went: `games/C64/Screenshots`, and also on the network share when there is one) and a picture | the `.prg` runs; the browser lists the `.png` files (they are for the PC, RETURN on one says it cannot run it) |
| Textures | `Brick Wall.d64` (BRICK.OCT, a seamless 320x200 brick tile, 256 colours, to open in OctoPaint) and `About Textures.txt` | the `.d64` goes into drive 8; open BRICK.OCT in OctoPaint |
| Saves | `Note Bouncer Save Disk.d64` (the game and its best score, which it keeps up to date), `Blank Disk.d64` (SHIFT+RETURN puts it in drive 8 to save to - OCTOCODE's F5) | the save disk runs the game; the blank disk is to save on |

Every item was opened from F1 in the Octophonic 64 Emulator (build 7) and seen running before it
went in.

The OctoVIC examples stay inside what the real MiSTer draws on time: at most one 256-colour layer
together with a 16-colour one, a few hundred VRAM bytes a frame at most while layers are on, and
the copper lists and sprite tables double-buffered or written outside the lines they change.
