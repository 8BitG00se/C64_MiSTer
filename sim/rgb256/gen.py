# C64RGB 256 (Fix 60): test frames for the recolour sim - tagged like the core's VIC tags them  (c) 2026 Mong00se
# gen.py OUT.tags: frame 0 a made-up screen (border, chars in every cell, 8 sprites, the colours in
# stripes); frame 1 random everything (every kind - blank too - every code, colour and position)
import sys, os
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../tools/rgb256'))
import rgb256 as R
H, W = R.H, R.W
x, y = R.coords(H, W)
win = (x >= R.X0) & (x < R.X0 + 320) & (y >= R.Y0) & (y < R.Y0 + 200)
cell = ((y - R.Y0) >> 3) * 40 + ((x - R.X0) >> 3)
idx = np.where(win, (cell + (y & 7)) & 15, 14).astype(np.uint8)
tag = np.where(win, cell & 255, 0x200).astype(np.int32)
for s in range(8):                               # sprites: 24x21 boxes
    sx, sy = R.X0 + 20 + s * 36, R.Y0 + 30 + s * 18
    m = (x >= sx) & (x < sx + 24) & (y >= sy) & (y < sy + 21)
    idx[m] = (s + 1 + ((x[m] - sx) >> 3)) & 15
    tag[m] = 0x100 | s
rng = np.random.default_rng(60)
ridx = rng.integers(0, 16, (H, W)).astype(np.uint8)
rtag = (rng.integers(0, 4, (H, W)) << 8 | rng.integers(0, 256, (H, W))).astype(np.int32)
rtag[(rtag >> 8) == 1] &= 0x1FF & ~0xF8 | 0x100     # a sprite's code is its number (0-7)
R.write_tags(sys.argv[1], [(0, idx, tag), (1, ridx, rtag)])
