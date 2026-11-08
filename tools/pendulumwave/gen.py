#!/usr/bin/env python3
# PENDULUM WAVE - the data for pend.asm (the PC only prepares numbers and pictures; the 6502 runs the physics, the
# drawing and the sound). By Mong00se.
#
# 24 pendulums in a row, each a little shorter than the one before: pendulum i swings 30 + i times a minute, so in 60
# seconds every one has swung a whole number of times and they all line up again. Between, they drift into a snake,
# two waves, three, apparent chaos - and back. A pendulum's swing is a cosine of its phase; its length is set by its
# period (L = g T^2 / 4 pi^2), so the row of lengths is the curve 1 / (30 + i)^2. The view is from above and in front:
# the swing (towards us and away) shows as up and down on the screen, the ball rising a little at each end of its arc.
# Each pendulum is a SID voice (8 SIDs x 3 voices = 24): it sounds its note as it passes through the bottom of its swing.
#
#   gen.py OUTDIR  ->  Pendulum Wave.reu (sprite graphics, the palette), data.inc (tables)
import math, os, sys
import numpy as np
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
NP = 24
CYCLE = 3000                                      # frames until they line up again (60 s at 50 frames a second)
NSW = [30 + i for i in range(NP)]                 # swings in a cycle
AMP = 38                                          # the swing, towards / away (picture pixels)
VIEW = 0.62                                       # how much of that shows as up / down (looking down at the row)
BARY = 30                                         # the bar the pendulums hang from (picture rows; the picture is the screen)
PX = [34 + i * 14.4 for i in range(NP)]           # where they hang, across the screen (0-395)
LEN = [70 + 128 * (NSW[0] / n) ** 2 for n in NSW] # the strings, as they show (longest first, as the periods say)
# ---- the phase: 24 bits a pendulum, one turn = 2^24; the step a frame
INC = [round(n * (1 << 24) / CYCLE) for n in NSW]
# ---- tables of 256 (the phase's top byte)
cosb = [math.cos(2 * math.pi * k / 256) for k in range(256)]
ZY = [int(round(AMP * VIEW * c)) for c in cosb]                     # down the screen, signed
# the rise at the ends of the arc: the ball goes up by L (1 - cos theta), theta = AMP cos(phase) / L, about
# AMP^2 cos^2 / (2 L): a table of cos^2 (0-255) times a number a pendulum (its AMP^2 / 2L, in eighths of a pixel)
COS2 = [int(round(255 * c * c)) for c in cosb]
RK = [min(255, int(round(8 * AMP * AMP / (2 * L) * 0.55))) for L in LEN]
# ---- the notes: D minor pentatonic, the longest (slowest) pendulum lowest
PENT = [0, 3, 5, 7, 10]
MIDI = [38 + 12 * (i // 5) + PENT[i % 5] for i in range(NP)]        # D2 up to A6
def sidf(m): return int(round(440 * 2 ** ((m - 69) / 12) * 16777216 / 985248))
FREQ = [sidf(m) for m in MIDI]
# ---- colours: 24 hues round the rainbow, each ball a shaded sphere of 5 tones (palette 128 + 5 i + k)
def hsv(h, s, v):
    i = int(h * 6) % 6; f = h * 6 - int(h * 6); p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    return [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
pal = np.zeros((256, 3))
for k in range(32):                               # 1-32: the night behind them, deep indigo at the top to near black
    s = k / 31
    pal[1 + k] = np.array((26, 22, 70)) * (1 - s) + np.array((4, 4, 14)) * s
pal[33:41] = [(132, 104, 52), (176, 140, 72), (214, 176, 96), (240, 214, 140), (96, 74, 38), (60, 46, 26), (200, 200, 210), (120, 120, 136)]
# 33-36 the brass bar light to bright, 37-38 its shadow, 39 the strings, 40 the pivots
HUE = [i / NP * 0.92 for i in range(NP)]
for i in range(NP):
    r, g, b = hsv(HUE[i], 0.78, 1.0)
    base = np.array((r, g, b)) * 255
    for k, f in enumerate((0.28, 0.5, 0.75, 1.0, None)):
        pal[128 + 5 * i + k] = base * f if f else base * 0.35 + 255 * 0.65      # dark rim .. lit side, then the highlight
for k in range(8):                                # 248-255: the glow round a ball (added to what is under it)
    pal[248 + k] = np.array((60, 50, 40)) * (k + 1) / 8
# 64-127: the trails, 8 families x 8 ages - the 6502 sets these every frame (here: a start)
FAM = [hsv(HUE[3 * f + 1], 0.7, 1.0) for f in range(8)]
for f in range(8):
    for a in range(8): pal[64 + 8 * f + a] = np.array(FAM[f]) * 255 * (1 - a / 8) * 0.7
pal = np.clip(np.round(pal), 0, 255).astype(np.uint8)
# ---- the sprites: 24 balls 16 x 16 (256 colours), one glow 32 x 32
gfx = bytearray()
for i in range(NP):
    for y in range(16):
        for x in range(16):
            dx, dy = (x - 7.5) / 6.2, (y - 7.5) / 6.2
            d = dx * dx + dy * dy
            if d > 1: gfx.append(0); continue
            nz = math.sqrt(1 - d); lx, ly, lz = -0.45, -0.55, 0.7       # lit from the upper left, a little in front
            sh = max(0, dx * lx + dy * ly + nz * lz)
            k = 0 if d > 0.85 else min(3, int(sh * 4.2))
            if sh > 0.93: k = 4
            gfx.append(128 + 5 * i + k)
for y in range(32):
    for x in range(32):
        d = math.hypot(x - 15.5, y - 15.5) / 15.5
        gfx.append(0 if d >= 1 else 248 + min(7, int((1 - d) ** 2 * 8)))
assert len(gfx) == NP * 256 + 1024
# ---- the REU: the sprite graphics at 0, the palette at $010000 (R, G, B tables)
reu = bytearray(gfx) + bytes(0x10000 - len(gfx))
R_PAL = len(reu)
reu += bytes(pal[:, 0]) + bytes(pal[:, 1]) + bytes(pal[:, 2])
open(os.path.join(OUT, 'Pendulum Wave.reu'), 'wb').write(reu)
# ---- data.inc
L = ['; made by gen.py - do not edit', 'NP = %d' % NP, 'CYCLE = %d' % CYCLE, 'R_GFX = $000000', 'LEN_GFX = %d' % len(gfx),
     'R_PAL = $%06x' % R_PAL, 'BARY = %d' % BARY]
def tab(name, vals): L.append('%-8s!byte %s' % (name, ','.join(str(int(v) & 255) for v in vals)))
tab('inc0', [v & 255 for v in INC]); tab('inc1', [(v >> 8) & 255 for v in INC]); tab('inc2', [v >> 16 for v in INC])
pxs = [int(round(x)) for x in PX]
tab('pxl', [x & 255 for x in pxs]); tab('pxh', [x >> 8 for x in pxs])
tab('resty', [int(round(BARY + l)) for l in LEN])
tab('zy', ZY); tab('cos2', COS2); tab('rk', RK)
tab('zx', [int(round(AMP * 0.22 * c)) for c in cosb])                    # a little across too (we look from a bit to the side)
tab('bgrow', [1 + min(31, y * 32 // 284) for y in range(256)])            # the background's colour on each row (for rubbing out)
FR = []; FG = []; FB = []
for f in range(8):
    for a_ in range(8):                                                  # trail family f at age a: bright to nearly the night
        k = (1 - a_ / 8) ** 1.6
        bg = pal[1 + 20]
        c = np.array(FAM[f]) * 255 * 0.85 * k + bg * (1 - k)
        FR.append(int(c[0])); FG.append(int(c[1])); FB.append(int(c[2]))
tab('tr_r', FR); tab('tr_g', FG); tab('tr_b', FB)
tab('frql', [f & 255 for f in FREQ]); tab('frqh', [f >> 8 for f in FREQ])
tab('famrgb_r', [int(c[0] * 255 * 0.8) for c in FAM]); tab('famrgb_g', [int(c[1] * 255 * 0.8) for c in FAM]); tab('famrgb_b', [int(c[2] * 255 * 0.8) for c in FAM])
# the SID voice of pendulum i: SID i / 3, voice i % 3 (+7 v); the SIDs' windows: 0,1 at $D400/$D420, 2,3 at $D500/$D520,
# 4,5 at $D480/$D4A0, 6,7 at $D580/$D5A0
SIDADR = [0xD400, 0xD420, 0xD500, 0xD520, 0xD480, 0xD4A0, 0xD580, 0xD5A0]
tab('vlo', [(SIDADR[i // 3] + 7 * (i % 3)) & 255 for i in range(NP)])
tab('vhi', [(SIDADR[i // 3] + 7 * (i % 3)) >> 8 for i in range(NP)])
tab('sidlo', [a_ & 255 for a_ in SIDADR]); tab('sidhi', [a_ >> 8 for a_ in SIDADR])
# the glow under each ball: louder (brighter) for the low ones
open(os.path.join(OUT, 'data.inc'), 'w').write('\n'.join(L) + '\n')
# a picture of the row at rest and at a few moments (to look at)
from PIL import Image, ImageDraw
for name, fr in (('t0', 0), ('t10s', 500), ('t30s', 1500)):
    im = Image.new('RGB', (396, 284), (10, 10, 30)); d = ImageDraw.Draw(im)
    d.rectangle((20, BARY - 3, 380, BARY + 2), fill=(200, 160, 80))
    for i in range(NP):
        ph = (INC[i] * fr) % (1 << 24) >> 16
        y = BARY + LEN[i] + ZY[ph] - (COS2[ph] * RK[i] >> 8) / 8; x = PX[i] + AMP * 0.22 * cosb[ph]
        d.line((PX[i], BARY, x, y), fill=(200, 200, 210)); c = tuple(int(v) for v in pal[128 + 5 * i + 3])
        d.ellipse((x - 6, y - 6, x + 6, y + 6), fill=c)
    im.resize((792, 568), Image.NEAREST).save(os.path.join(OUT, 'look_%s.png' % name))
print('pendulums', NP, 'lengths %.0f-%.0f' % (LEN[0], LEN[-1]), 'notes', MIDI[0], MIDI[-1], 'reu', len(reu))
