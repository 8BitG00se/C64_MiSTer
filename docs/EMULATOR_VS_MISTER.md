# Emulator vs real MiSTer: what "nailed" means

Before the Lemon64 post, the Octophonic 64 emulator has to behave like Neal's real MiSTer.
This is every known place where the two disagree, taken from his tests on the real machine
(Nov 2026), with what is known so far. Each one needs a test that runs the same program on
both and compares the results; that is the feedback loop.

| # | Where it shows | Real MiSTer | Emulator | Status |
|---|---|---|---|---|
| 1 | Code/sprites (Fix 8) | the balls stay put, only the colours move | the balls travel round the figure 8 (checked 7 Nov: frames 500 and 520 differ as they should) | **confirmed mismatch**. The program double-buffers its sprite table and flips SATBASE ($D613-$D615) each frame; the core copies the table at line 0 (`sat_fr <= satbase + sat_off`, octovic.sv ~980). Suspects: the 6510's VRAM-port writes ($D604) during the copy, or the SATBASE flip timing. The emulator must copy at the same moment and lose the same writes. |
| 2 | Game levels (Shooter Template, City demo) | jump around, the bullets come out of one place and the craft is in another | play properly | same family as 1 (sprite table/positions); check after 1 is found |
| 3 | Horizon build 4 | two 256-colour tile layers on the same lines plus VRAM streaming starve the line buffer, and that band tears into streaks | clean | known: the emulator has no line-buffer bandwidth model. Needs the LATE/starve model so a demo that tears on the MiSTer tears in the emulator too |
| 4 | Code/stock (Fix 9) | border bars only reach mid-screen, the top bars are jagged | steady | raster timing on the real VIC path; compare cycle by cycle |
| 5 | Pictures/Sunset (Fix 16) | broken | shows | not looked at yet (being replaced anyway, but the cause may hit other pictures) |
| 6 | RUN/STOP+RESTORE (Fix 1) | does nothing on his 8BitDo keyboard | works | the keyboard mapping on the MiSTer; Fix 1 replaces it with one exit key on both |
| 7 | Sound level (Fix 28) | very quiet over HDMI (peak about -20 dB) | was as quiet (it copied the core's mix) | **fixed on branch `audio-levels` (core) and `audio-levels` (emulator), not yet on the MiSTer.** The mix divided each side by how many SIDs play into it, so 8-SID demos were 13-14 dB under VICE. Now: sum, ~10 Hz DC blocker, gain 1.25 (one SID = VICE's level), an automatic gain that only turns down when the SIDs together would pass the limiter, then the limiter - real 8-SID demos within ~1 dB of VICE, one SID within ~1 dB, nothing clips. The emulator mixes a microsecond at a time with the RTL's integer maths (checked bit for bit). Measurement loop: `sim/level/` |
| 8 | Mouse in OctoPaint (Fix 26) | n/a | needs Alt+M and a port setting | the emulator should have the mouse working with no setup |
| 9 | Classic games (e.g. IK+) | load | don't load properly in the old Weaver emulator | parked for the 10-day emulator test |

## The order to do it in
1. Item 1 first. It is reproducible, small and confirmed, and items 2 and probably 5 may be the same bug.
2. Item 3: the bandwidth model, so the emulator warns where the real machine would tear.
3. Items 4, 7 and 8 next; 6 comes with Fix 1.
4. Then one "same program, both machines" test set: every Code example and every demo, a frame
   grab at fixed frames on both (his AVerMedia captures on the MiSTer side), compared side by side.

"Nailed" = that whole test set looks the same on both.
