SACRED GEOMETRY for the Octophonic 64 - build 1            code by Mong00se / Octophonic 64

Fourteen disks, one figure each. Every program is plain BASIC V2: LOAD"*",8 then RUN - or LIST it,
change the numbers and RUN again, or put it through a BASIC compiler. They draw on OctoVIC's bitmap
layer with its blitter lines and sound the figure on SID 1. Needs the Octophonic 64 (OctoVIC 2+).

 01 Seed of Life        7 circles, one bell each (just-intonation scale)
 02 Egg of Life         7 touching circles; octaves and fifths
 03 Flower of Life      19 circles in two rings; a rising pentatonic
 04 Metatron's Cube     13 centres, 78 lines; the harmonic series
 05 Vesica Piscis       two circles; the notes are in its own ratio, 1 : root 3
 06 Tree of Life        10 spheres, 22 paths; a falling scale from the crown
 07 Merkaba             star tetrahedron, turning (3D in BASIC)
 08 64 Tetrahedron      the grid seen down its axis; the cuts ring the quarters
 09 Sri Yantra          4 up, 5 down, lotus rings and the gate (after the classic layout)
 10 Vector Equilibrium  cuboctahedron turning: every edge = every radius
 11 Golden Ratio        whirling squares and the spiral; each note phi times the last
 12 Fibonacci           squares 1 1 2 3 5 8 13 21; the numbers counted round a 7-note scale
 13 Platonic Solids     all five, edges found by the program itself
 14 Rose                r = cos(n/d a), live: the pen sings its distance from the centre,
                        two voices hold the n:d chord. Keys: N/M n up/down, D/E d up/down,
                        SPACE the next rose, Q quit.

The shared routines (same in every program, so you can lift them into your own):
 8000 line X0,Y0 -> X1,Y1 in colour C        8100 circle CX,CY radius R colour C
 8200 bell: F hertz on voice W (0-2)          8300 wait T sixtieths
 8400 clear the picture                       8500 3D point X,Y,Z turned by RA,RB -> SX,SY
 8900 "space again / q quit"                  9000 OctoVIC set-up (layer, palette, blitter)
 9500 the palette: 15 colours as R,G,B (after the 999 marker)

BASIC is slow at 1 MHz: the circles and 3D ones take a while to draw - that is the fun of watching.
