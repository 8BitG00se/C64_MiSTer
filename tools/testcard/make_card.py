#!/usr/bin/env python3
# TESTCARD (c) 2026 Mong00se - makes card.bin: a 320x200 hires bitmap (C64 layout, 8000 bytes)
# a crosshatch for CRT geometry: lines every 20 px (16 x 10 squares), the outer frame on the very
# edge of the screen, a centre cross and circle, small corner circles, and dots between the lines.
import math, sys
W, H = 320, 200
px = [[0]*W for _ in range(H)]
def p(x, y):
    if 0 <= x < W and 0 <= y < H: px[y][x] = 1
for x in list(range(0, W, 20)) + [W-1]:
    for y in range(H): p(x, y)
for y in list(range(0, H, 20)) + [H-1]:
    for x in range(W): p(x, y)
for y in range(10, H, 20):                      # a dot in the middle of every square
    for x in range(10, W, 20): p(x, y)
ASPECT = 0.9365                                 # a PAL C64 pixel is narrower than it is tall
def circle(cx, cy, r):
    for a in range(0, 3600):                    # wider in pixels so it looks round on the screen
        t = a * math.pi / 1800
        p(round(cx + r/ASPECT*math.cos(t)), round(cy + r*math.sin(t)))
circle(159.5, 99.5, 88)                         # the big centre circle: round = right width/height
for (cx, cy) in [(40, 40), (279, 40), (40, 159), (279, 159)]:
    circle(cx, cy, 28)                          # corner circles: bent = corner trouble
for d in range(-6, 7):                          # thick centre cross
    p(160 + d, 99); p(160 + d, 100); p(159, 100 + d); p(160, 100 + d)
out = bytearray(8000)
for y in range(H):
    for x in range(W):
        if px[y][x]:
            out[(y // 8) * 320 + (x // 8) * 8 + (y % 8)] |= 0x80 >> (x % 8)
open(sys.argv[1] if len(sys.argv) > 1 else 'card.bin', 'wb').write(out)
