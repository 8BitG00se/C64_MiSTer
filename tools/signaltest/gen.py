#!/usr/bin/env python3
# SIGNAL TEST - the data for signal.asm (the PC only prepares pictures, tables and the music's register frames; the 6502
# runs everything). By Mong00se.
#   Layer 0 (a 512 x 512 bitmap, wrapping): four bands of scenery that the copper scrolls at their own speeds -
#     stars (1/8 px a frame), far mountains (1/4), hills (1/2), a pine forest (1). The sky between them is see-through:
#     the copper paints the backdrop a colour a line (a night sky), and the moon (sprites) sits behind the layer.
#   Layer 1: the valley floor (a meadow and a river), TURNED AND SIZED; the copper sets each line's start and step, so it is drawn in
#     perspective (1.5 px a frame at the horizon, 6 at the bottom). The 6502 moves the camera: 2 bytes a line a frame.
#   Sprites: the moon and its halo, fir trees in front (4 x 2, 7 px a frame), 8 SID meters, the 50 Hz ticker (50 dots).
#   gen.py OUTDIR  ->  Signal Test.reu, data.inc, look.png (a still worked out the same way, to check the art)
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import music
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(11)
W = 512
B_STAR, B_FAR, B_MID, B_NEAR, B_FLOOR = 0, 90, 140, 175, 200          # band rows (picture rows; raster = row + 16)
FLN = 84                                                              # floor rows 200-283
pal = np.zeros((256, 3))
def mix(a, b, t): return np.array(a, float) * (1 - t) + np.array(b, float) * t
def peaks(x, base, parts, seed):
    r = np.random.default_rng(seed); h = np.full(x.shape, float(base))
    for m, a in parts:
        f = (m * x / W + r.uniform(0, 1)) % 1.0
        h -= a * (1 - np.abs(2 * f - 1)) ** 1.25
    return h
def ridge(x, base, parts, seed):
    r = np.random.default_rng(seed); h = np.full(x.shape, float(base))
    for m, a in parts:
        h += a * np.sin(2 * np.pi * m * x / W + r.uniform(0, 2 * np.pi))
    return h
xs = np.arange(W)
# ======================================================================================== layer 0: the scenery (RGB + see-through)
img = np.zeros((B_FLOOR, W, 3)); opq = np.zeros((B_FLOOR, W), bool)
H1 = (44, 56, 84); H2 = (22, 32, 50); HC = (7, 12, 20)          # the mist behind the hills, behind the forest; the forest
# stars (rows 0-55: none low in the sky)
for k in range(150):
    x, y = rng.integers(0, W), int(rng.uniform(0, 1) ** 1.4 * 54)
    b = rng.uniform(0.3, 1.0); col = mix((255, 255, 255), (170, 200, 255) if k % 3 else (255, 235, 200), rng.uniform(0, .5)) * b
    img[y, x] = col; opq[y, x] = True
    if b > 0.9 and k % 4 == 0:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if 0 <= y + dy < 56: img[y + dy, (x + dx) % W] = col * 0.45; opq[y + dy, (x + dx) % W] = True
def range_(y0, y1, hb, cb, rimb, hf_, cf, rimf, flat, flat_from, snow=None):
    for y in range(y0, y1):
        for x in range(W):
            c = None
            if y >= hb[x]:
                d = y - hb[x]; c = mix(cb, flat, min(1, d / 26.0))
                if snow is not None and d < (snow - hb[x]) * 0.5 + 1.5 and hb[x] < snow: c = mix(c, (200, 210, 228), 0.8 - 0.1 * d)
                if d < 1: c = mix(c, rimb, 0.55)
            if y >= hf_[x]:
                d = y - hf_[x]; c = mix(cf, flat, min(1, d / 18.0))
                if snow is not None and d < (snow + 6 - hf_[x]) * 0.4 + 1 and hf_[x] < snow + 6: c = mix(c, (172, 186, 210), 0.7 - 0.12 * d)
                if d < 1: c = mix(c, rimf, 0.7)
            if y >= flat_from: c = np.array(flat, float)
            if c is None:
                if y0 == B_FAR: continue
                c = np.array(H1, float)
            img[y, x] = c; opq[y, x] = True
# far mountains: blue-grey, snow on the high peaks, moonlight along the ridges
hb = np.clip(peaks(xs, 136, [(3, 22), (5, 13), (8, 7), (13, 3), (29, 1.2)], 1), B_FAR + 3, B_MID - 14)
hf = np.clip(peaks(xs, 139, [(4, 13), (7, 8), (11, 4), (23, 1.5)], 3), B_FAR + 8, B_MID - 6)
range_(B_FAR, B_MID, hb, (92, 106, 140), (210, 222, 240), hf, (62, 76, 108), (170, 186, 214), H1, B_MID - 4, snow=110)
# rolling hills (in front of the mist): dark green-blue, faint moonlight on top
hb2 = np.clip(ridge(xs, 150, [(2, 5), (3, 4), (5, 2.5), (9, 1)], 2), B_MID + 2, B_NEAR - 10)
hf2 = np.clip(ridge(xs, 159, [(2, 4), (4, 3.5), (7, 1.8), (13, .7)], 4), B_MID + 5, B_NEAR - 7)
range_(B_MID, B_NEAR, hb2, (38, 54, 70), (96, 118, 140), hf2, (26, 40, 52), (80, 104, 124), H2, B_NEAR - 5)
# the pine forest (over the hills' mist): fir after fir round the 512, two cottages with lit windows
top = np.full(W, float(B_FLOOR))
x = 0; firs = []
while x < W:
    h_ = rng.uniform(9, 21); hw = h_ * rng.uniform(0.32, 0.42); firs.append((x, h_, hw)); x += rng.uniform(3, 7)
for (cx_, h_, hw) in firs:
    for dx in range(-int(hw) - 1, int(hw) + 2):
        xx = int(cx_) + dx; t_ = B_FLOOR - 4 - h_ + abs(dx) / hw * h_ * 0.9 + (1 if (xx * 3 + int(h_)) % 4 == 0 else 0)
        top[xx % W] = min(top[xx % W], t_)
top = np.maximum(top, B_NEAR + 1)
for y in range(B_NEAR, B_FLOOR):
    for x in range(W):
        if y < top[x]: img[y, x] = H2
        else: img[y, x] = mix((16, 26, 34), HC, min(1, (y - top[x]) / 3)) if y - top[x] < 1 else HC
        opq[y, x] = True
for cx_ in (140, 395):                                            # cottages: a roof, a wall, a warm window
    for y in range(B_FLOOR - 11, B_FLOOR - 3):
        for x in range(cx_ - 7, cx_ + 8):
            yy = y - (B_FLOOR - 11)
            if yy < 4 and abs(x - cx_) > 3 + yy * 1.2: continue
            img[y, x] = (20, 22, 30) if yy < 4 else (30, 30, 38)
    for (wx, wy) in ((cx_ - 3, B_FLOOR - 6), (cx_ + 2, B_FLOOR - 6)):
        img[wy:wy + 2, wx:wx + 2] = (255, 196, 100)
    img[B_FLOOR - 13:B_FLOOR - 10, cx_ + 4] = (40, 40, 48)       # the chimney
img[B_FLOOR - 1, :] = (10, 16, 22)
# quantise the opaque pixels to 62 colours (no dither: the bands' flat colours stay exactly flat)
q = Image.fromarray(img[opq][None].astype(np.uint8)).quantize(62, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
pal[1:63] = np.array(q.getpalette()[:186]).reshape(62, 3)
L0 = np.zeros((B_FLOOR, W), np.uint8); L0[opq] = np.asarray(q)[0] + 1
# the sky's backdrop colours, a line each (rows 0-149): night, lighter towards the hills
SKY = []
for y in range(150):
    t = min(1, y / 140)
    pts = [(0, (3, 5, 16)), (.4, (8, 14, 38)), (.8, (22, 36, 68)), (1, (40, 56, 90))]
    for (a_, ca), (b_, cb) in zip(pts, pts[1:]):
        if a_ <= t <= b_: SKY.append(np.round(mix(ca, cb, (t - a_) / (b_ - a_))).astype(int)); break
# ======================================================================================== layer 1: the valley floor (a 2048 x 84 texture)
FW = 2048; R0 = 27.67
sj = 1.5 * (np.arange(FLN) + R0) / (FLN - 1 + R0)                  # px a texel, row by row
fl = np.zeros((FLN, FW, 3)); u = np.arange(FW)
RV0, RV1 = 13, 31                                                 # the river's rows
for j in range(FLN):
    if j < RV0:                                                   # the far meadow, misty towards the horizon
        base = mix((40, 54, 70), (18, 32, 34), (j / RV0) ** 0.7); row = np.tile(base, (FW, 1))
    elif j < RV1:                                                 # the river: dark water, moonlight glinting on the ripples
        base = mix((22, 34, 60), (14, 22, 44), (j - RV0) / (RV1 - RV0)); row = np.tile(base, (FW, 1))
        if j in (RV0, RV1 - 1): row[:] = (12, 16, 22)
        else:
            for k in range(int(FW / 26)):
                g0 = int(rng.integers(0, FW)); ln = int(rng.integers(3, 12) / sj[j] * 1.2) + 1
                row[np.arange(g0, g0 + ln) % FW] = mix(base, (150, 172, 210), rng.uniform(0.3, 0.8))
    else:                                                         # the near meadow: grass, tufts with moonlit tips, stones
        base = mix((18, 34, 30), (10, 22, 16), (j - RV1) / (FLN - RV1)); row = np.tile(base, (FW, 1))
        n = (np.sin(u * 2 * np.pi * 7 / FW) + np.sin(u * 2 * np.pi * 19 / FW + j * .3)) * 0.06
        row *= (1 + n)[:, None]
    fl[j] = row
for k in range(1400):                                              # tufts (a few rows tall) and stones on the near meadow
    j = int(rng.integers(RV1 + 2, FLN)); x0 = int(rng.integers(0, FW)); hh = 1 + int((j - RV1) / 16)
    if k % 9 == 0:
        w_ = int(5 / sj[j]) + 1
        for jj in range(j, min(FLN, j + hh + 1)): fl[jj, np.arange(x0, x0 + w_) % FW] = (58, 64, 74) if jj == j else (34, 38, 46)
    else:
        for jj in range(max(RV1, j - hh), j + 1):
            fl[jj, x0 % FW] = (88, 120, 104) if jj == j - hh else (40, 66, 52)
qf = Image.fromarray(fl.astype(np.uint8)).quantize(31, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
pal[65:96] = np.array(qf.getpalette()[:93]).reshape(31, 3)
FL = (np.asarray(qf) + 65).astype(np.uint8)
# ======================================================================================== sprites
gfx = bytearray(); GFX = {}
def add(name, arr):
    while len(gfx) % 32: gfx.append(0)
    GFX[name] = len(gfx) // 32; gfx.extend(arr.astype(np.uint8).tobytes())
# the moon and its halo, one 64 x 64 sprite behind layer 0: the halo is baked over the sky's own colours at those rows
# (the moon never moves), fading to nothing at its edge, so the sprite's square never shows
MX, MY = 166, 64                                                  # the sprite's top left (picture)
mo = np.zeros((64, 64, 3)); mm = np.zeros((64, 64), bool)
seas = [(-6, -5, 6), (5, 3, 5), (-2, 8, 4), (7, -7, 3)]
for y in range(64):
    for x in range(64):
        dy, dx = y - 31.5, x - 31.5; r_ = math.hypot(dx, dy)
        g = max(0.0, 1 - (r_ - 14) / 17) ** 2.2 if r_ >= 14 else 1
        if r_ < 15:
            lit = 0.75 + 0.25 * (-dx - dy) / 21
            for (sx, sy, sr) in seas:
                if math.hypot(dx - sx, dy - sy) < sr: lit -= 0.28
            mo[y, x] = mix((120, 124, 120), (236, 236, 222), np.clip(lit, 0, 1)); mm[y, x] = True
        elif g > 0.07:
            mo[y, x] = np.array(SKY[min(149, MY + y)], float) + g * np.array((34, 40, 52)); mm[y, x] = True
qm = Image.fromarray(mo[mm][None].astype(np.uint8)).quantize(32, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
pal[96:128] = np.array(qm.getpalette()[:96]).reshape(32, 3)
moon = np.zeros((64, 64), np.uint8); moon[mm] = np.asarray(qm)[0] + 96
add('moon', moon)
# a fir tree: 64 x 128 (two sprites): tiers of drooping branches, moonlight on their upper right edges
S4 = 4; cv = Image.new('L', (64 * S4, 128 * S4), 0); d = ImageDraw.Draw(cv)
d.rectangle([29 * S4, 112 * S4, 35 * S4, 128 * S4], fill=255)
for k in range(9):
    yt = 4 + k * 11.5; yb = yt + 19 + k * 0.6; hw = 6 + k * 3.1
    pts = [(32, yt)]
    for i in range(13):
        t = i / 12; xx = 32 + hw * (2 * t - 1); jag = (2.5 if i % 2 else 0)
        pts.append((xx, yb - jag - 3 * (1 - abs(2 * t - 1))))
    d.polygon([(px * S4, py * S4) for px, py in [pts[0]] + pts[1:][::-1] + [pts[0]]], fill=255)
    d.polygon([(px * S4, py * S4) for px, py in pts[1:] + [pts[0]]], fill=255)
m = np.asarray(cv.resize((64, 128), Image.BOX)) > 110
tree = np.zeros((128, 64), np.uint8); tree[m] = 180
for y in range(128):
    for x in range(64):
        if m[y, x] and x >= 31 and (y == 0 or not m[y - 1, x] or (x < 63 and not m[y, x + 1])): tree[y, x] = 181
        elif m[y, x] and (y + 2 * x) % 9 == 0 and y < 110: tree[y, x] = 182
pal[180] = (6, 12, 16); pal[181] = (90, 118, 140); pal[182] = (14, 24, 28)
add('treeT', tree[:64]); add('treeB', tree[64:])
# the SID meters: 16 x 64, 16 segments, level 0-16 (added: they glow over the sky)
for k in range(16):
    c = (50, 255, 130) if k < 10 else (255, 220, 60) if k < 13 else (255, 60, 70)
    pal[128 + 2 * k] = np.array(c) * 0.16; pal[129 + 2 * k] = c
for lv in range(17):
    a = np.zeros((64, 16), np.uint8)
    for k in range(16):
        y0 = 63 - (k * 4 + 3)
        a[y0:y0 + 3, 2:14] = 129 + 2 * k if k < lv else 128 + 2 * k
    add('met%d' % lv, a)
# the 50 Hz ticker: 8 x 8, a 4 x 4 dot: unlit, the one before, the frame now
pal[176] = (50, 50, 80); pal[177] = (90, 150, 255); pal[178] = (255, 255, 255)
for k in range(3):
    a = np.zeros((8, 8), np.uint8); a[2:6, 2:6] = 176 + k; add('tick%d' % k, a)
pal = np.clip(np.round(pal), 0, 255).astype(np.uint8)
# ======================================================================================== the copper list
cop = []; COP = {}
def ce(line, reg, val, name=None):
    if name: COP[name] = len(cop) * 4 + 3
    cop.append((line, reg, val & 255))
def band(line, n): ce(line, 0x28, 32, 'b%d' % n); ce(line, 0x29, 0, None)
ce(0, 0x19, 2)
band(0, 0)
for y in range(150):
    L = 16 + y
    if y == B_FAR: band(L, 1)
    if y == B_MID: band(L, 2)
    r_, g_, b_ = SKY[y]; ce(0 if y == 0 else L, 0x1B, r_); ce(0 if y == 0 else L, 0x1C, g_); ce(0 if y == 0 else L, 0x1D, b_)
band(16 + B_NEAR, 3)
DUX = [int(round(65536 / s)) for s in sj]
C = [(-198 * dx) & 0xFFFFFFFF for dx in DUX]
for j in range(FLN):
    L = 16 + B_FLOOR + j
    for k in range(4): ce(L, 0x88 + k, C[j] >> (8 * k), 'fl' if (j == 0 and k == 2) else None)
    for k in range(4): ce(L, 0x90 + k, DUX[j] >> (8 * k))
cop.append((0xFFFF, 0, 0))
copb = bytearray()
for (l, r_, v) in cop: copb += bytes((l & 255, l >> 8, r_, v))
# ======================================================================================== the music and the REU
stream, met = music.build(); N = music.N
reu = bytearray(stream.reshape(-1).tobytes())
def align(): reu.extend(bytes(-len(reu) % 256))
align(); R_MET = len(reu); reu += met.tobytes()
align(); R_PAL = len(reu); reu += bytes(pal[:, 0]) + bytes(pal[:, 1]) + bytes(pal[:, 2])
align(); R_GFX = len(reu); reu += gfx
align(); R_L0 = len(reu); reu += L0.tobytes()
align(); R_FL = len(reu); reu += FL.tobytes()
align(); R_COP = len(reu); reu += copb
align()
open(os.path.join(OUT, 'Signal Test.reu'), 'wb').write(reu)
# ======================================================================================== data.inc
Ls = ['; made by gen.py - do not edit']
def eq(n, v): Ls.append('%-10s= %s' % (n, v))
TB = []
def tab(name, vals): TB.append('%-8s!byte %s' % (name, ','.join(str(int(v) & 255) for v in vals)))
eq('NMUS', N)
for n, v in (('R_MET', R_MET), ('R_PAL', R_PAL), ('R_GFX', R_GFX), ('R_L0', R_L0), ('R_FL', R_FL), ('R_COP', R_COP)): eq(n, '$%06x' % v)
for n, ln in (('GFX', len(gfx)), ('L0', L0.size), ('FL', FL.size), ('COP', len(copb))):
    eq('NCH_' + n, ln >> 16); eq('REM_' + n, ln & 0xFFFF)
for k, v in GFX.items(): eq('G_' + k.upper(), v)
for k, v in COP.items(): eq('C_' + k.upper(), v)
eq('FLN', FLN)
hi = [c >> 16 for c in C]
tab('flhl', [h & 255 for h in hi]); tab('flhh', [h >> 8 for h in hi])
sec = music.SECTIONS
tab('secl', [s & 255 for s in sec] + [255]); tab('sech', [s >> 8 for s in sec] + [255])
open(os.path.join(OUT, 'data.inc'), 'w').write('\n'.join(Ls) + '\n')
open(os.path.join(OUT, 'tables.inc'), 'w').write('; made by gen.py - do not edit\n' + '\n'.join(TB) + '\n')
# ======================================================================================== look.png: frame 0 as the 6502 + OctoVIC draw it
look = np.zeros((284, 396, 3), np.uint8)
for y in range(284):
    look[y] = SKY[min(y, 149)]
def spr(a, X, Y):
    for y in range(a.shape[0]):
        for x in range(a.shape[1]):
            if a[y, x] and 0 <= Y + y < 284 and 0 <= X + x < 396: look[Y + y, X + x] = pal[a[y, x]]
spr(moon, MX, MY)
for y in range(B_FLOOR):
    for x in range(396):
        if L0[y, x]: look[y, x] = pal[L0[y, x]]
for j in range(FLN):
    for x in range(396):
        u = (C[j] + DUX[j] * x) & 0xFFFFFFFF; look[B_FLOOR + j, x] = pal[FL[j, (u >> 16) & (FW - 1)]]
spr(tree, 300, 156); spr(tree[:, ::-1], 30, 156)
for i in range(8):
    spr(np.asarray(gfx[GFX['met%d' % (4 + 1.5 * i if False else [16, 11, 7, 13, 5, 9, 14, 3][i])] * 32:][:1024], np.uint8).reshape(64, 16), [40, 64, 88, 112, 264, 288, 312, 336][i], 76)
Image.fromarray(look).resize((792, 568), Image.NEAREST).save(os.path.join(OUT, 'look.png'))
print('reu', len(reu), 'gfx', len(gfx), 'copper entries', len(cop), 'music frames', N)
