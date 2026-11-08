#!/usr/bin/env python3
# DNA WAVE build 2 - the data for dna.asm (the PC only prepares numbers and pictures; the 6502 runs it). By Mong00se.
#
# Pendulum Wave's maths and music as a double helix: 24 base pairs turning about the axis, rung i 30 + i times a minute,
# so the ladder twists tighter until, after exactly 60 s, it is flat again - and each rung rings its SID voice as it turns
# edge-on. Build 2: chrome and metal, an equaliser (a bar per voice) and three looks, one each minute, changing as the
# ladder goes flat:
#   look 0  GOLD AND STEEL - a studio, the screen split: the top half the helix standing on a mirror floor, the bottom
#           half its full reflection (the copper re-reads the layers upside down, line by line, at half brightness)
#   look 1  CHROME IN DEEP SPACE - a nebula, stars
#   look 2  CHROME SYNTHWAVE - a striped sun, a neon grid
# The beads are little chrome spheres (each pixel the reflection of the look's own world: sky, horizon, ground) drawn by
# the blitter onto the rung layer in depth order (far beads, rungs, near beads), so the mirror gets them too.
#   gen.py OUTDIR  ->  DNA Wave.reu, data.inc
import math, os, sys
import numpy as np
from PIL import Image, ImageFilter
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
NP = 24; CYCLE = 3000; NB = 2 * NP - 1
NSW = [30 + i for i in range(NP)]
INC = [round(n * (1 << 24) / CYCLE) for n in NSW]
W, H = 396, 284
X0, DX = 22, 15.0
rx = [int(round(X0 + DX * i)) for i in range(NP)]
bx = [int(round(X0 + DX * j / 2)) for j in range(NB)]
PENT = [0, 3, 5, 7, 10]
MIDI = [38 + 12 * (i // 5) + PENT[i % 5] for i in range(NP)]
def sidf(m): return int(round(440 * 2 ** ((m - 69) / 12) * 16777216 / 985248))
FREQ = [sidf(m) for m in MIDI]
SIDADR = [0xD400, 0xD420, 0xD500, 0xD520, 0xD480, 0xD4A0, 0xD580, 0xD5A0]
MIRROR = 142                                         # look 0: the floor line (picture row); below it, the reflection
def smoothstep(a, b, x): x = np.clip((x - a) / (b - a), 0, 1); return x * x * (3 - 2 * x)
def mix(a, b, t): return np.array(a, float) * (1 - t) + np.array(b, float) * t
rng = np.random.default_rng(3)
# ---------------------------------------------------------------- the worlds the chrome reflects
def env_studio(r):
    y = r[..., 1]
    sky = np.array((250, 250, 252)) * (1 - smoothstep(0.02, 0.45, y))[..., None] + np.array((110, 110, 125)) * smoothstep(0.02, 0.45, y)[..., None]
    ground = np.array((90, 86, 92)) * (1 - smoothstep(-0.02, -0.5, y))[..., None] + np.array((20, 20, 26)) * smoothstep(-0.02, -0.5, y)[..., None]
    c = np.where(y[..., None] > 0, sky, ground)
    return np.where((np.abs(y) < 0.05)[..., None], np.array((14, 14, 18)), c)
def env_sky(r):
    y = r[..., 1]
    sky = np.array((250, 252, 255)) * (1 - smoothstep(0.02, 0.45, y))[..., None] + np.array((90, 140, 220)) * smoothstep(0.02, 0.45, y)[..., None]
    sky = sky * (1 - 0.35 * smoothstep(0.5, 1, y))[..., None]
    ground = np.array((150, 110, 70)) * (1 - smoothstep(-0.02, -0.5, y))[..., None] + np.array((40, 28, 20)) * smoothstep(-0.02, -0.5, y)[..., None]
    c = np.where(y[..., None] > 0, sky, ground)
    return np.where((np.abs(y) < 0.05)[..., None], np.array((20, 18, 24)), c)
def env_sunset(r):
    y = r[..., 1]
    sky = np.array((255, 120, 190)) * (1 - smoothstep(0, 0.6, y))[..., None] + np.array((60, 20, 120)) * smoothstep(0, 0.6, y)[..., None]
    ground = np.array((20, 230, 240)) * (np.abs(np.sin(r[..., 0] * 18)) > 0.92)[..., None] * 0.8 + np.array((20, 10, 50))
    c = np.where(y[..., None] > 0, sky, ground)
    return np.where((np.abs(y) < 0.03)[..., None], np.array((255, 230, 255)), c)
def bead(env, tint, depth, rad):
    """a 16 x 16 chrome sphere (RGBA), lit from the upper left"""
    out = np.zeros((16, 16, 4))
    yy, xx = np.mgrid[0:16, 0:16].astype(float)
    dx, dy = (xx - 7.5) / rad, (yy - 7.5) / rad; q = dx * dx + dy * dy; m = q < 1
    nz = np.sqrt(np.clip(1 - q, 0, 1)); n = np.stack([dx, -dy, nz], -1)
    r = 2 * n[..., 2:3] * n - np.array((0, 0, 1.0))[None, None]
    c = env(r) * np.array(tint)
    c = c + (np.clip(r @ np.array((-0.4, 0.55, 0.73)), 0, 1) ** 40 * 255)[..., None]
    c = c * (0.55 + 0.45 * depth) * (1 - 0.5 * smoothstep(0.75, 1.0, q))[..., None]
    out[..., :3] = np.clip(c, 0, 255); out[..., 3] = m * 255
    return out
# ---------------------------------------------------------------- the backgrounds
def noise(sc, seed):
    r = np.random.default_rng(seed); g = r.random((H // sc + 2, W // sc + 2))
    return np.asarray(Image.fromarray((g * 255).astype(np.uint8)).resize((W + sc * 2, H + sc * 2), Image.BICUBIC))[:H, :W] / 255
def bg_studio():
    img = np.zeros((H, W, 3)); yy, xx = np.mgrid[0:H, 0:W].astype(float)
    spot = np.exp(-(((xx - 200) / 230) ** 2 + ((yy - 70) / 110) ** 2))
    img += np.array((26, 26, 34)) + np.array((80, 76, 70)) * spot[..., None]
    img[MIRROR - 3:MIRROR] = np.array((150, 150, 160))                   # the edge of the mirror floor, catching the light
    return img
def bg_space():
    img = np.zeros((H, W, 3))
    n = noise(48, 1) * 0.55 + noise(20, 2) * 0.3 + noise(8, 3) * 0.15; n2 = noise(40, 4) * 0.6 + noise(14, 5) * 0.4
    img += np.array((70, 20, 90))[None, None] * smoothstep(0.45, 0.85, n)[..., None]
    img += np.array((10, 70, 90))[None, None] * smoothstep(0.5, 0.9, n2)[..., None] + np.array((4, 4, 14))[None, None]
    for k in range(260):
        x, y = rng.integers(1, W - 1), rng.integers(1, H - 1); b = rng.random() ** 3
        img[y, x] = np.minimum(255, img[y, x] + 255 * b)
        if b > 0.6: img[y, x - 1] += 60; img[y, x + 1] += 60; img[y - 1, x] += 60; img[y + 1, x] += 60
    return img
def bg_synth():
    img = np.zeros((H, W, 3))
    for y in range(H): s = y / 200; img[y] = np.array((40, 8, 70)) * (1 - min(1, s)) + np.array((230, 60, 150)) * min(1, s) ** 2
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    sun = ((xx - 198) ** 2 + (yy - 150) ** 2) < 70 ** 2; stripes = (yy > 160) & ((yy.astype(int) // 6) % 2 == 0)
    sc = np.array((255, 220, 90)) * (1 - (yy - 80) / 140)[..., None] + np.array((255, 70, 140)) * ((yy - 80) / 140)[..., None]
    img = np.where((sun & ~stripes)[..., None], np.clip(sc, 0, 255), img)
    hor = 228; img[hor:] = np.array((16, 6, 34))
    for k in range(1, 14):
        y = int(hor + (k ** 2) * 0.35)
        if y < H: img[y] = (60, 230, 255)
    for k in range(-14, 15):
        for y in range(hor, H):
            x = int(198 + k * 9 * (1 + (y - hor) / 10))
            if 0 <= x < W: img[y, x] = (60, 230, 255)
    img[hor - 1:hor + 1] = (255, 200, 255)
    return img
# ---------------------------------------------------------------- the looks
RC = {0: [(190, 30, 40), (210, 160, 30), (30, 160, 90), (30, 90, 200), (150, 40, 170), (220, 100, 30)],
      1: [(230, 40, 60), (240, 190, 40), (40, 200, 120), (40, 120, 240), (200, 60, 220), (40, 210, 220)],
      2: [(255, 60, 170), (40, 230, 255), (255, 210, 60), (150, 80, 255), (255, 120, 60), (90, 255, 160)]}
LOOKS = [dict(name='gold and steel', bg=bg_studio, env=env_studio, tint=((1.15, 0.86, 0.42), (0.95, 0.98, 1.05)),
              cy=76, r=36, tilt=0.10, eqy=MIRROR - 2, eqh=24, rad=(3.8, 6.4), back=(10, 10, 14)),
         dict(name='chrome in deep space', bg=bg_space, env=env_sky, tint=((1.0, 1.0, 1.05), (1.0, 1.0, 1.05)),
              cy=132, r=50, tilt=0.26, eqy=280, eqh=30, rad=(4.6, 7.4), back=(4, 4, 14)),
         dict(name='chrome synthwave', bg=bg_synth, env=env_sunset, tint=((1.0, 1.0, 1.0), (1.0, 1.0, 1.0)),
              cy=124, r=50, tilt=0.26, eqy=280, eqh=30, rad=(4.6, 7.4), back=(16, 6, 34))]
reu = bytearray()
def put(data, align=0x10000):
    global reu
    reu += bytes(-len(reu) % align); a = len(reu); reu += data; return a
R_BG, R_PAL, R_GEO = [], [], []
beadimgs = bytearray()
for li, LK in enumerate(LOOKS):
    pal = np.zeros((256, 3))
    # 1-31 the background
    bgimg = np.clip(LK['bg'](), 0, 255).astype(np.uint8)
    q = Image.fromarray(bgimg).quantize(31, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal[1:32] = np.array(q.getpalette()[:93]).reshape(31, 3)
    bm = np.zeros((H, 512), np.uint8); bm[:, :W] = np.asarray(q).astype(np.uint8) + 1
    R_BG.append(put(bm.tobytes()))
    # 32-95: the beads, strand s 32 + 32 s (32 colours a strand, from its four depths)
    for s in range(2):
        imgs = [bead(LK['env'], LK['tint'][s], d / 3, LK['rad'][0] + (LK['rad'][1] - LK['rad'][0]) * d / 3) for d in range(4)]
        px = np.concatenate([im[..., :3][im[..., 3] > 0] for im in imgs])
        qi = Image.fromarray(px[None].astype(np.uint8)).quantize(32, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        cp = np.array(qi.getpalette()[:96]).reshape(32, 3); pal[32 + 32 * s:64 + 32 * s] = cp
        for im in imgs:
            idx = ((im[..., None, :3] - cp[None, None]) ** 2).sum(-1).argmin(-1) + 32 + 32 * s
            beadimgs += np.where(im[..., 3] > 0, idx, 0).astype(np.uint8).tobytes()
    # 160 + 4 c + 2 lit + tone: the rungs' glass (6 colours), lit up when they ring; 184-187 steel collars and caps
    for c, col in enumerate(RC[li]):
        for lit in range(2):
            body = mix(col, (255, 255, 255), 0.35 * lit) * (0.8 + 0.2 * lit)
            pal[160 + 4 * c + 2 * lit] = body; pal[160 + 4 * c + 2 * lit + 1] = mix(body, (255, 255, 255), 0.5)
    pal[184:188] = [(110, 112, 122), (225, 230, 240), (170, 174, 186), (70, 72, 80)]
    for k in range(8): pal[240 + k] = np.array((80, 110, 130)) * (k + 1) / 8          # the crossing glow (added)
    pal = np.clip(np.round(pal), 0, 255).astype(np.uint8)
    R_PAL.append(put(bytes(pal[:, 0]) + bytes(pal[:, 1]) + bytes(pal[:, 2]), 256))
    # the geometry: ycos (256), dep (256), ayb (64), ayr (32), then 4 bytes: eq floor, eq height, backdrop is in the palette
    geo = bytearray()
    geo += bytes([int(round(LK['r'] * math.cos(2 * math.pi * k / 256))) & 255 for k in range(256)])
    geo += bytes([min(3, int(2 + 2 * math.sin(2 * math.pi * k / 256))) for k in range(256)])
    geo += bytes([int(round(LK['cy'] - LK['tilt'] * (x - 198))) for x in bx] + [0] * (64 - NB))
    geo += bytes([int(round(LK['cy'] - LK['tilt'] * (x - 198))) for x in rx] + [0] * (32 - NP))
    geo += bytes([LK['eqy'] & 255, LK['eqy'] >> 8, LK['eqh']] + list(LK['back']))
    R_GEO.append(put(bytes(geo), 1024))
# the glow sprite (32 x 32): every look the same indices
glow = bytearray()
for y in range(32):
    for x in range(32):
        q2 = math.hypot(x - 15.5, y - 15.5) / 15.5
        glow.append(0 if q2 >= 1 else 240 + min(7, int((1 - q2) ** 1.6 * 8)))
R_BEADS = put(bytes(beadimgs)); R_GLOW = put(bytes(glow), 256)
# the copper for look 0: from the floor line down, each line shows the row as far above the floor as it is below
cop = bytearray()
def cw(line, reg, val): cop.extend([line & 255, line >> 8, reg, val & 255])
for reg in (0x2A, 0x3A): cw(16, reg, 35)
for reg in (0x2B, 0x3B): cw(16, reg, 0)
for reg in (0x2F, 0x3F): cw(16, reg, 0)
for y in range(MIRROR, H):
    line = y + 16; src = 2 * MIRROR - y - 1
    sy = (src - y + 35) % 512
    for reg in (0x2A, 0x3A): cw(line, reg, sy & 255)
    for reg in (0x2B, 0x3B): cw(line, reg, sy >> 8)
    if y == MIRROR:
        cw(line, 0x2F, 1); cw(line, 0x3F, 1)                             # the reflection at half brightness (mixed with the dark)
cop.extend([0xFF, 0xFF, 0, 0])
R_COP = put(bytes(cop), 256)
open(os.path.join(OUT, 'DNA Wave.reu'), 'wb').write(reu)
# ---- data.inc
L = ['; made by gen.py - do not edit', 'NP = %d' % NP, 'NB = %d' % NB, 'MIRROR = %d' % MIRROR, 'LEN_BG = %d' % (H * 512),
     'R_BEADS = $%06x' % R_BEADS, 'LEN_BEADS = %d' % len(beadimgs), 'R_GLOW = $%06x' % R_GLOW, 'R_COP = $%06x' % R_COP, 'LEN_COP = %d' % len(cop)]
def tab(name, vals): L.append('%-8s!byte %s' % (name, ','.join(str(int(v) & 255) for v in vals)))
for nm, arr in (('rbg', R_BG), ('rpal', R_PAL), ('rgeo', R_GEO)):
    tab(nm + '0', [a & 255 for a in arr]); tab(nm + '1', [(a >> 8) & 255 for a in arr]); tab(nm + '2', [a >> 16 for a in arr])
tab('inc0', [v & 255 for v in INC]); tab('inc1', [(v >> 8) & 255 for v in INC]); tab('inc2', [v >> 16 for v in INC])
tab('rxl', [x & 255 for x in rx]); tab('rxh', [x >> 8 for x in rx])
tab('bxl', [(x - 8) & 255 for x in bx]); tab('bxh', [((x - 8) >> 8) & 255 for x in bx])        # (a bead's left edge)
tab('frql', [f & 255 for f in FREQ]); tab('frqh', [f >> 8 for f in FREQ])
tab('vlo', [(SIDADR[i // 3] + 7 * (i % 3)) & 255 for i in range(NP)])
tab('vhi', [(SIDADR[i // 3] + 7 * (i % 3)) >> 8 for i in range(NP)])
tab('sidlo', [a & 255 for a in SIDADR]); tab('sidhi', [a >> 8 for a in SIDADR])
RCOL = [((i * 5) % 6, (i * 5 + 2) % 6, (i * 5 + 3) % 6, (i * 5 + 1) % 6) for i in range(NP)]
for s_ in range(4): tab('rc%d' % s_, [160 + 4 * c[s_] for c in RCOL])
open(os.path.join(OUT, 'data.inc'), 'w').write('\n'.join(L) + '\n')
print('looks', len(LOOKS), 'reu', len(reu), 'copper', len(cop))
