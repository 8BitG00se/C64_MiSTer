#!/usr/bin/env python3
# CHAOS - eight double pendulums for the Octophonic 64. The data for chaos.asm. By Mong00se.
#
# Eight double pendulums (two arms, two weights) hang from one pivot, let go from almost the same place: each one a
# hundred-millionth of a radian further round than the last. For a few seconds they move as one; then the difference
# doubles and doubles until they fly apart - the butterfly effect, which you can see and hear.
# The motion is worked out here, properly (the equations of motion from Lagrange's method, integrated with 4th-order
# Runge-Kutta at 400 steps a second, double precision) and sampled 50 times a second into the REU: two angles a pendulum,
# 16 bits each. The 6502 does everything you see and hear from them, live: the arms (sine tables, the blitter's lines),
# the weights and their glow (sprites), the fading light trails, and the sound - each pendulum is a SID: its inner arm
# plays a note on voice 1, its outer arm on voice 2 (and a fifth above on voice 3), the note set by the arm's height and
# struck again whenever it moves to a new one. While they move as one, all 8 SIDs play the same notes; then the harmony
# comes apart with them.
#   gen.py OUTDIR  ->  Chaos.reu, data.inc
import math, os, sys
import numpy as np
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
NPD = 8
SECS = 120; FPS = 50; NF = SECS * FPS
g = 9.81; Lm = 1.0                                   # metres: a period of about 2 seconds, as a real one of a metre
ARM = 72                                             # pixels an arm
PIVX, PIVY = 198, 126
def acc(t1, t2, w1, w2):
    d = t1 - t2; den = 3 - np.cos(2 * d)
    a1 = (-3 * g * np.sin(t1) - g * np.sin(t1 - 2 * t2) - 2 * np.sin(d) * (w2 * w2 * Lm + w1 * w1 * Lm * np.cos(d))) / (Lm * den)
    a2 = (2 * np.sin(d) * (2 * w1 * w1 * Lm + 2 * g * np.cos(t1) + w2 * w2 * Lm * np.cos(d))) / (Lm * den)
    return a1, a2
t1 = math.radians(125) + np.arange(NPD) * 1e-8
t2 = np.full(NPD, math.radians(135)); w1 = np.zeros(NPD); w2 = np.zeros(NPD)
SUB = 8; dt = 1 / (FPS * SUB)
A1 = np.zeros((NF, NPD)); A2 = np.zeros((NF, NPD))
for f in range(NF):
    A1[f] = t1; A2[f] = t2
    for _ in range(SUB):
        s = (t1, t2, w1, w2)
        fn = lambda s: (s[2], s[3]) + acc(*s)
        k1 = fn(s); k2 = fn(tuple(a + dt / 2 * b for a, b in zip(s, k1)))
        k3 = fn(tuple(a + dt / 2 * b for a, b in zip(s, k2))); k4 = fn(tuple(a + dt * b for a, b in zip(s, k3)))
        t1, t2, w1, w2 = (a + dt / 6 * (b + 2 * c + 2 * d_ + e) for a, b, c, d_, e in zip(s, k1, k2, k3, k4))
U = lambda a: (np.round(np.mod(a, 2 * math.pi) / (2 * math.pi) * 65536).astype(np.int64)) & 0xFFFF
Q1, Q2 = U(A1), U(A2)
spread = [np.degrees(np.ptp(A2[f])) for f in range(0, NF, 250)]
# ---- the REU: frame f at f * 32: pendulum k's inner angle (lo, hi) then outer angle, 8 of them
rec = np.zeros((NF, NPD, 4), np.uint8)
rec[:, :, 0] = Q1 & 255; rec[:, :, 1] = Q1 >> 8; rec[:, :, 2] = Q2 & 255; rec[:, :, 3] = Q2 >> 8
reu = rec.tobytes()
open(os.path.join(OUT, 'Chaos.reu'), 'wb').write(reu)
# ---- data.inc: the sine table (1280: sin then on into cos), the notes, the colours
L = ['; made by gen.py - do not edit', 'NPD = %d' % NPD, 'NF = %d' % NF, 'PIVX = %d' % PIVX, 'PIVY = %d' % PIVY]
def tab(name, vals): L.append('%-8s!byte %s' % (name, ','.join(str(int(v) & 255) for v in vals)))
SINT = [int(round(ARM * math.sin(2 * math.pi * k / 1024))) for k in range(1280)]
for p in range(5): tab('sint%d' % p, SINT[p * 256:(p + 1) * 256])
# the note for an arm at angle a (the top byte): 12 steps round, by height - straight down the lowest, up the highest
PENT = [0, 3, 5, 7, 10, 12, 15]                       # D minor pentatonic, 7 notes from D
def sidf(m): return int(round(440 * 2 ** ((m - 69) / 12) * 16777216 / 985248))
step = [min(k, 12 - k) for k in range(12)]           # 0 (down) .. 6 (up)
tab('qstep', [step[((a * 12 + 128) >> 8) % 12] for a in range(256)])
tab('n1l', [sidf(50 + PENT[s]) & 255 for s in range(7)]); tab('n1h', [sidf(50 + PENT[s]) >> 8 for s in range(7)])
tab('n2l', [sidf(62 + PENT[s]) & 255 for s in range(7)]); tab('n2h', [sidf(62 + PENT[s]) >> 8 for s in range(7)])
tab('n3l', [sidf(69 + PENT[s]) & 255 for s in range(7)]); tab('n3h', [sidf(69 + PENT[s]) >> 8 for s in range(7)])
SIDADR = [0xD400, 0xD420, 0xD500, 0xD520, 0xD480, 0xD4A0, 0xD580, 0xD5A0]
tab('sidlo', [a & 255 for a in SIDADR]); tab('sidhi', [a >> 8 for a in SIDADR])
def hsv(h, s, v):
    i = int(h * 6) % 6; f = h * 6 - int(h * 6); p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    return [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
pal = np.zeros((256, 3))
HUE = [k / NPD * 0.9 for k in range(NPD)]
for k in range(NPD):
    base = np.array(hsv(HUE[k], 0.75, 1.0)) * 255
    pal[16 + k] = base * 0.75                              # 16-23 the arms
    for j, f in enumerate((0.3, 0.55, 0.8, 1.0, None)):    # 128 + 5 k: the weights, shaded
        pal[128 + 5 * k + j] = base * f if f else base * 0.35 + 255 * 0.65
    for a in range(16):                                    # 32 + 16 k: the trail, 16 ages (set by the 6502 each frame too)
        pal[32 + 16 * k + a] = base * (1 - a / 16) ** 1.5 * 0.9
pal[24] = (200, 190, 160); pal[25] = (120, 110, 90)        # the pivot
for j in range(8): pal[248 + j] = np.array((70, 60, 50)) * (j + 1) / 8   # the glow (added)
pal = np.clip(np.round(pal), 0, 255).astype(np.uint8)
TR = []
for k in range(NPD):
    base = np.array(hsv(HUE[k], 0.75, 1.0)) * 255
    TR += [base * (1 - a / 16) ** 1.5 * 0.9 for a in range(16)]
tab('tr_r', [c[0] for c in TR]); tab('tr_g', [c[1] for c in TR]); tab('tr_b', [c[2] for c in TR])
# ---- the sprites (to the REU after the frames): 8 inner weights 16 x 16, 8 outer 16 x 16, a glow 32 x 32
gfx = bytearray()
for k in range(NPD * 2):
    kk = k % NPD; r = 5.0 if k < NPD else 6.5
    for y in range(16):
        for x in range(16):
            dx, dy = (x - 7.5) / r, (y - 7.5) / r; d = dx * dx + dy * dy
            if d > 1: gfx.append(0); continue
            nz = math.sqrt(1 - d); sh = max(0, -0.45 * dx - 0.55 * dy + 0.7 * nz)
            j = 0 if d > 0.85 else min(3, int(sh * 4.2))
            if sh > 0.93: j = 4
            gfx.append(128 + 5 * kk + j)
for y in range(32):
    for x in range(32):
        d = math.hypot(x - 15.5, y - 15.5) / 15.5
        gfx.append(0 if d >= 1 else 248 + min(7, int((1 - d) ** 2 * 8)))
R_GFX = (len(reu) + 0xFFFF) & ~0xFFFF
R_PAL = R_GFX + 0x10000
reu2 = bytearray(reu) + bytes(R_GFX - len(reu)) + gfx + bytes(0x10000 - len(gfx))
reu2 += bytes(pal[:, 0]) + bytes(pal[:, 1]) + bytes(pal[:, 2])
open(os.path.join(OUT, 'Chaos.reu'), 'wb').write(reu2)
L += ['R_GFX = $%06x' % R_GFX, 'LEN_GFX = %d' % len(gfx), 'R_PAL = $%06x' % R_PAL]
open(os.path.join(OUT, 'data.inc'), 'w').write('\n'.join(L) + '\n')
print('frames', NF, 'reu', len(reu2), 'spread of the outer arms every 5 s (degrees):', [round(x, 1) for x in spread[:8]])
