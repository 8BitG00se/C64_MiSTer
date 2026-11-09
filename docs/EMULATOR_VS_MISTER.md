# Emulator vs real MiSTer: what "nailed" means

Before the Lemon64 post, the Octophonic 64 emulator has to behave like Neal's real MiSTer.
This is every known place where the two disagree, taken from his tests on the real machine
(Nov 2026), with what is known so far. Each one needs a test that runs the same program on
both and compares the results; that is the feedback loop.

| # | Where it shows | Real MiSTer | Emulator | Status |
|---|---|---|---|---|
| 1 | Code/sprites (Fix 8) | the balls stay put, only the colours move | the same, with the program he tested | **not a core bug - closed (9 Nov).** Neal tested the old program (5 Nov): 64 balls on a 64-step path, so each frame every ball hopped onto the next ball's place and only the colours seemed to move. The emulator shows exactly that with the old program (`git show 535bff0^:tools/examples/code/sprites.asm`: stills differ only in colour, the ball shapes stay). The new program (535bff0, 6 Nov) moves on both. The RTL replay of the new program (sim/sprtable/replay.py: its OctoVIC writes, logged by the emulator, through octovic.sv) gives the same sprite table as the emulator in every frame, DDR3 idle, 80% and 90% busy. |
| 2 | Game levels (Shooter Template, City demo) | jump around, the bullets come out of one place and the craft is in another | play properly | **not reproduced in the RTL with a normal DDR3; one way found, hardened (core-fixes, 9 Nov).** Night City replayed through the RTL: the same sprite table as the emulator every frame at 0/80/90% busy, and with garbage in all the VRAM it never wrote. The only way the RTL shows those symptoms: the DDR3 port held for more than ~500 clocks (15 us) while the vertical-blank REU upload writes VDATA - the 16-byte write queue filled, bytes were dropped without a trace, and every byte after a dropped one landed a place early (sprites from there on in the wrong places; with the ship's patch dropped, the ship drawn where it was while the bullets come from where it is). The queue is now 64 bytes (63 us of REU upload, ~2,000 clocks) and every dropped byte is counted in LOST ($D6B2): **the real MiSTer can now say whether it ever happens.** The emulator also drew each line one line later than the core (the core starts line L as the beam begins L-3: the table copy for line 0 starts as the beam begins line 309), so an upload ending during line 309 worked only in the emulator; it now draws at the core's moment (octophonic-backgrounds branch emu-core-fixes), and Night City's OctoVIC picture through the RTL (DDR3 80% busy) is pixel for pixel the emulator's. Other real-machine differences that can make a level misbehave there and not here: turbo (the engine sets $D030=1 - 4x on the MiSTer, 1 MHz in the emulator) and RAM that is not zero at power-on (the 3 Nov shake-counter bug was one; Shooter Template build 1 was built before that fix). |
| 3 | Horizon build 4 | two 256-colour tile layers on the same lines plus VRAM streaming starve the line buffer, and that band tears into streaks | clean | known: the emulator has no line-buffer bandwidth model. Needs the LATE/starve model so a demo that tears on the MiSTer tears in the emulator too |
| 4 | Code/stock (Fix 9) | border bars only reach mid-screen, the top bars are jagged | steady | raster timing on the real VIC path; compare cycle by cycle |
| 5 | Pictures/Sunset (Fix 16) | broken | shows | not looked at yet (being replaced anyway, but the cause may hit other pictures) |
| 6 | RUN/STOP+RESTORE (Fix 1) | does nothing on his 8BitDo keyboard | works | the keyboard mapping on the MiSTer; Fix 1 replaces it with one exit key on both |
| 7 | Sound level (Fix 28) | very quiet over HDMI (peak about -20 dB) | was as quiet (it copied the core's mix) | **fixed on branch `audio-levels` (core) and `audio-levels` (emulator), not yet on the MiSTer.** The mix divided each side by how many SIDs play into it, so 8-SID demos were 13-14 dB under VICE. Now: sum, ~10 Hz DC blocker, gain 1.25 (one SID = VICE's level), an automatic gain that only turns down when the SIDs together would pass the limiter, then the limiter - real 8-SID demos within ~1 dB of VICE, one SID within ~1 dB, nothing clips. The emulator mixes a microsecond at a time with the RTL's integer maths (checked bit for bit). Measurement loop: `sim/level/` |
| 8 | Mouse in OctoPaint (Fix 26) | n/a | needs Alt+M and a port setting | the emulator should have the mouse working with no setup |
| 9 | Classic games (e.g. IK+) | load | don't load properly in the old Weaver emulator | parked for the 10-day emulator test |

## The order to do it in
1. Item 1 is closed (the old program; see above). Item 2: a real-MiSTer run of Night City (or any level) that shows LOST ($D6B2) and LATE says whether the write queue ever overflows there.
2. Item 3: the bandwidth model, so the emulator warns where the real machine would tear.
3. Items 4, 7 and 8 next; 6 comes with Fix 1.
4. Then one "same program, both machines" test set: every Code example and every demo, a frame
   grab at fixed frames on both (his AVerMedia captures on the MiSTer side), compared side by side.

"Nailed" = that whole test set looks the same on both.
