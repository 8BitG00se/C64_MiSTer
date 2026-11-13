# To do 78 - a button on RGB 256 that jumps to OctoPaint (design note)

(c) 2026 Mong00se. Batch 1 (13 Nov 2026). Not built: this is the plan, for Neal to say yes or no to.

**What Neal asked for:** while a game runs on RGB 256, a button that jumps to OctoPaint, so he can hand-paint
the picture to finish it, and then make an `.rgb` file for the game from it if he wants.

## Is there a hook point today?

- **OctoPaint: no.** It starts on an empty canvas; nothing tells it "open this picture". (OctoPaint build 2 now
  lists a disk's pictures to pick from - Fix 31 - but it still starts empty.)
- **The way in exists now for OCTOCODE** (batch 1, Fix 76): the browser asks Main to start a program and Main
  keeps a file name (`19` SRCOPEN); the program asks for it once at its start (`1A` SRCNAME). OctoPaint can use
  the same two-step: about 40 bytes in OctoPaint and one more command in Main.
- **The RGB 256 core has no UI of its own** (decision of 12 Nov: straight into the game, tweaks by hot keys).
  Its hot keys reach Main through the mailbox's poll word, and Main already switches between the two cores
  (`rgb_switch`, `rgb_home`).

## The plan, step by step

1. **The button.** A free remaster hot key in the RGB core (for example WIN+F8, "PAINT"). File-only: Main reads
   it from the poll word like the others. The game is paused while the core switches (the switch restarts it).
2. **The picture.** Main needs the frame the player sees, as palette slots, not as RGB:
   - *Option A (no core change):* MiSTer's own screenshot (as SHOT does) and the game's pack: every pixel's
     colour is matched back to the pack's slot. Exact for Level 1 packs (each slot one colour); close for
     gradients (Level 2).
   - *Option B (core change, next core batch):* the RGB core writes its slot numbers for one frame into DDR3
     (it has 40% room); exact for every level.
   Main writes `<game>.paint.oct` (OctoPaint's own .OCT format: 320 x 200, 256 colours, the pack's palette)
   beside the game.
3. **The jump.** Main switches back to the Octophonic core (`rgb_switch` to `.C64_Octophonic`), keeps the
   picture's name, and runs `Tools/OCTOPAINT.PRG`; OctoPaint asks for the name at its start (as OCTOCODE does
   with SRCNAME) and opens it.
4. **Painting.** As OctoPaint does now. A new key in OctoPaint, "make .rgb" (only when the picture came from a
   game), saves the picture and asks Main to build the pack.
5. **The pack.** Main compares the painted picture with the original slots: a slot whose colour was changed
   everywhere becomes a new colour in the pack (Level 1); painted detail inside a slot becomes Level 2 data
   (the remaster's per-tile shading) - only where the pack format can hold it, the rest is reported.
   The old pack is backed up first; one line in `update.log`.
6. **Back.** "Back to the game" restarts the game in RGB 256 with the new pack (as picking it in F1 does).

## Things Neal must decide first

- **The converter rule (6 Nov):** picture-to-.OCT converters are for his use only, not in the public release.
  Step 2 turns a game's frame into an .OCT on the machine. It is the game's own picture, not a photo, but it
  is a converter - keep it in, or make it his-copy-only?
- Option A now (file-only, close but not exact for gradients) or Option B with the next core batch (exact).
- Which hot key.

## What it needs

| Part | Kind | Size |
|---|---|---|
| hot key PAINT, the switch, the name hand-over | Main (file) | small |
| OctoPaint: ask for a picture at its start; "make .rgb" key | OctoPaint build 3 (file) | small |
| frame as slots - Option A | Main (file) | medium |
| frame as slots - Option B | RGB core (needs core) | medium |
| painted picture -> pack (Level 1, then Level 2) | Main (file) | medium |
