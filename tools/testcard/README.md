# TESTCARD.PRG - monitor test card

(c) 2026 Mong00se

A test card for setting up a CRT (or checking HDMI): a white crosshatch on black filling the whole
320x200 screen edge to edge - 16 x 10 squares of 20 pixels, a dot in each, a centre cross, a big centre
circle and four corner circles (drawn for the PAL pixel shape, so on a correctly set screen they are round).

Keys: SPACE border grey / white / black / blue - RETURN back to the start screen - I black lines on white.

What to look for on a CRT (JVC service menu items in brackets):
- outer frame lines straight and all four inside the visible picture - size and centre (D02, D01; D04, D03)
- side lines bowed in or out halfway down - side pincushion (D07); corners pulled or flared (D08)
- squares taller at the top than the bottom - vertical linearity (D05); middle squares a different
  height to the top and bottom ones - vertical S-correction (D06)
- circles round, not oval - width against height

Built from source by `build.sh` (make_card.py draws the bitmap, testcard.asm shows it). The card build puts
it in games/C64/Tools (step 057).
