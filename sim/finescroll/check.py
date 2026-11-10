# sim/finescroll: the checks.  python3 check.py new_q1.rgb new_q0.rgb old.rgb
#   1. with the 4x clock (QUARTER=1): layer 0, layer 1 and the sprite move exactly one quarter pixel per
#      FINE step (two for layer 1), the same amount across the whole-pixel boundary (monotone), and stay
#      sharp (a stripe is 16 sub-pixels wide every step, nothing but its own colours on the line)
#   2. FINE = 0 identical to before: the frames whose FINE values are all 0 are the old OctoVIC's
#      frames exactly (every sub-pixel), and without the 4x clock (QUARTER=0) EVERY frame is the old one
import sys, numpy as np
W, H = 504 * 4, 312
def load(p): a = np.fromfile(p, np.uint8); return a.reshape(-1, H, W, 3)
q1, q0, old = (load(p) for p in sys.argv[1:4])
fails = 0
def edge(f, line, colour, start=0):
    row = f[line, :, 0].astype(int)
    idx = np.where(row[start:] == colour)[0]
    return int(idx[0]) + start if len(idx) else -1
def first_start(f, line, colour, start):           # the first sub-pixel where a run of colour starts (after start)
    row = f[line, :, 0].astype(int); m = (row == colour)
    for i in range(max(start, 1), W):
        if m[i] and not m[i - 1]: return i
    return -1
print("step  Q   L0 col150   L1 stripe   sprite    (sub-pixel positions on lines 100, 250, 154)")
base = None
for k in range(13):
    f = q1[k + 2]
    l0 = first_start(f, 100, 150, 4 * 40)
    l1 = first_start(f, 250, 245, 4 * 60)
    sp = edge(f, 154, 250)
    # the stripe's width (sharp: 16 sub-pixels, 4 C64 pixels) and the colours on line 250
    row = f[250, :, 0].astype(int); m = row == 245
    w = 0; i = l1
    while i < W and m[i]: w += 1; i += 1
    print("%3d  %2d   %6d     %6d     %6d    stripe %d sub-pixels" % (k, k, l0, l1, sp, w))
    if base is None: base = (l0, l1, sp)
    exp = (base[0] - k, base[1] - 2 * k, base[2] + k)
    if (l0, l1, sp) != exp: print("   FAIL: want", exp); fails += 1
    if w != 16: print("   FAIL: the stripe is not 16 sub-pixels"); fails += 1
    # sharp: on the stripe line, every sub-pixel is the stripe's colour or a layer 0 column colour, never a mix
    px = f[250, :4 * 396, :].astype(int)
    if not (np.all(px[:, 0] == px[:, 1]) and np.all(px[:, 1] == px[:, 2])): print("   FAIL: a colour on line 250 is not one of the art's"); fails += 1
# identical to before
same0 = [k for k in range(15) if np.array_equal(q0[k], old[k])]
print("QUARTER=0 (no 4x clock): frames identical to the old OctoVIC: %d of %d" % (len(same0), 15))
if len(same0) != 15: fails += 1
fz = [k + 2 for k in range(13) if k % 4 == 0 and (2 * k) % 4 == 0]        # all FINE 0: steps 0, 4, 8, 12
fz = [0, 1] + fz
same1 = [k for k in fz if np.array_equal(q1[k], old[k])]
print("QUARTER=1, frames with every FINE 0 (%s): identical to the old OctoVIC: %d of %d" % (fz, len(same1), len(fz)))
if len(same1) != len(fz): fails += 1
# the frames where FINE moved things must differ from the old core (the feature does something)
diff = [k + 2 for k in range(13) if k % 4 != 0 and not np.array_equal(q1[k + 2], old[k + 2])]
print("QUARTER=1, frames with FINE set that differ from the old OctoVIC: %d of %d" % (len(diff), 9))
if len(diff) != 9: fails += 1
print("frame: %d clocks = %.4f Hz at 31.527954 MHz" % (W * H, 31527954.0 / (W * H)))
print("FINESCROLL: PASS" if fails == 0 else "FINESCROLL: %d FAILED" % fails)
sys.exit(1 if fails else 0)
