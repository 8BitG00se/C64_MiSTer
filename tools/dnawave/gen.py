#!/usr/bin/env python3
# DNA WAVE - the data for dna.asm (the PC only prepares numbers and pictures; the 6502 runs it). By Mong00se.
#
# Pendulum Wave's maths and music, seen as a double helix. 24 base pairs (rungs) along a DNA ladder, each turning about
# the ladder's axis like one of the 24 pendulums: rung i turns 30 + i times a minute. A rung's turn IS its pendulum's
# phase, and because the phases differ by i x (time) the ladder is a helix whose twist tightens as the minute goes on:
# flat at the start (all in line), a long slow twist, tighter and tighter, an apparent tangle, and after exactly 60 s
# flat again. Each rung is one of the 24 SID voices and rings its note as it turns edge-on (the two strands cross there)
# - Pendulum Wave's sound exactly.
# The strands are beads (sprites) in a row, shaded by their depth: the near side in front of the rungs, the far side
# behind them (sprite priorities either side of the rung layer). The rungs are base pairs in two colours, drawn by the
# blitter, and light up when they ring. A glow (an added sprite) flashes where the strands cross.
#   gen.py OUTDIR  ->  DNA Wave.reu (sprite graphics, palette, the copper's sky), data.inc
import math, os, sys
import numpy as np
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
NP = 24; CYCLE = 3000
NSW = [30 + i for i in range(NP)]
INC = [round(n * (1 << 24) / CYCLE) for n in NSW]
R = 52                                             # the helix's radius on the screen
CY = 150                                           # its axis (picture rows; the picture is the screen)
X0, DX = 22, 15.0                                  # rung i at X0 + DX i
NB = 2 * NP - 1                                    # beads a strand: on every rung and half way between
PENT = [0, 3, 5, 7, 10]
MIDI = [38 + 12 * (i // 5) + PENT[i % 5] for i in range(NP)]
def sidf(m): return int(round(440 * 2 ** ((m - 69) / 12) * 16777216 / 985248))
FREQ = [sidf(m) for m in MIDI]
SIDADR = [0xD400, 0xD420, 0xD500, 0xD520, 0xD480, 0xD4A0, 0xD580, 0xD5A0]
# ---- the palette
def mix(a, b, t): return np.array(a, float) * (1 - t) + np.array(b, float) * t
def hsv(h, s_, v):
    i = int(h * 6) % 6; f = h * 6 - int(h * 6); p, q, t = v * (1 - s_), v * (1 - f * s_), v * (1 - (1 - f) * s_)
    return [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
pal = np.zeros((256, 3))
# 1-31: the background (a dark teal night with out-of-focus lights - the picture is made below and fitted to these)
# beads: 8 hues x 4 depths (0 far .. 3 near) x 5 tones: 32 + 20 h + 5 d + j
HUES = [hsv(h, 0.78, 1.0) for h in (0.0, 0.07, 0.13, 0.33, 0.47, 0.55, 0.75, 0.88)]   # red orange gold green teal sky violet pink
for h in range(8):
    for d in range(4):
        light = 0.38 + 0.62 * d / 3
        base = np.array(HUES[h]) * 255 * light
        for j, f in enumerate((0.3, 0.55, 0.8, 1.0, None)):
            c = base * f if f else mix(base, (255, 255, 255), 0.5 * light)
            pal[32 + 20 * h + 5 * d + j] = mix(c, (6, 26, 34), 0.25 * (1 - d / 3))
# rungs: 6 colours x 2 (normal, lit up) x 2 tones (body, highlight): 192 + 4 c + 2 lit + tone
RC = [(230, 60, 40), (250, 160, 30), (240, 220, 60), (60, 200, 90), (40, 180, 220), (200, 70, 200)]
for c in range(6):
    for lit in range(2):
        body = mix(RC[c], (255, 255, 255), 0.35 * lit) * (0.8 + 0.2 * lit)
        pal[192 + 4 * c + 2 * lit] = body
        pal[192 + 4 * c + 2 * lit + 1] = mix(body, (255, 255, 255), 0.5)
for k in range(8): pal[240 + k] = np.array((80, 120, 130)) * (k + 1) / 8      # the crossing glow (added)
# ---- the background: dark teal, lighter in the middle, with big soft out-of-focus lights (made once, here)
from PIL import Image, ImageDraw, ImageFilter
W_, H_ = 396, 284
yy_, xx_ = np.mgrid[0:H_, 0:W_].astype(float)
bg = np.zeros((H_, W_, 3))
r0 = np.hypot((xx_ - 210) / 260, (yy_ - 150) / 190)
for c in range(3): bg[..., c] = mix((22, 64, 72), (4, 12, 18), np.clip(r0, 0, 1) ** 0.9)[c] if False else 0
bg[...] = (np.array((22, 64, 72))[None, None] * (1 - np.clip(r0, 0, 1)[..., None] ** 0.9) + np.array((3, 10, 16))[None, None] * np.clip(r0, 0, 1)[..., None] ** 0.9)
rng = np.random.default_rng(5)
glow = Image.new('RGB', (W_, H_), (0, 0, 0)); gd = ImageDraw.Draw(glow)
for k in range(26):
    x, y, r = rng.uniform(-20, W_ + 20), rng.uniform(-20, H_ + 20), rng.uniform(8, 46)
    col = [(240, 120, 70), (230, 90, 140), (90, 200, 200), (120, 160, 240), (240, 190, 90)][k % 5]
    a = rng.uniform(0.18, 0.5) * (0.5 if r > 30 else 1)
    gd.ellipse((x - r, y - r, x + r, y + r), fill=tuple(int(c * a) for c in col))
glow = np.asarray(glow.filter(ImageFilter.GaussianBlur(6))).astype(float)
bgimg = np.clip(bg + glow, 0, 255).astype(np.uint8)
q = Image.fromarray(bgimg).quantize(31, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
bpal = np.array(q.getpalette()[:93]).reshape(31, 3); pal[1:32] = bpal
bgidx = np.asarray(q).astype(np.uint8) + 1
pal = np.clip(np.round(pal), 0, 255).astype(np.uint8)
# ---- the sprites: beads 16 x 16 - 8 hues x 4 depths (near ones bigger), then the glow 32 x 32
gfx = bytearray()
for h in range(8):
    for d in range(4):
        rad = 4.4 + 2.8 * d / 3
        for y in range(16):
            for x in range(16):
                dx, dy = (x - 7.5) / rad, (y - 7.5) / rad; q2 = dx * dx + dy * dy
                if q2 > 1: gfx.append(0); continue
                nz = math.sqrt(1 - q2); sh = max(0, -0.4 * dx - 0.6 * dy + 0.7 * nz)
                j = 0 if q2 > 0.8 else min(3, int(sh * 4.2))
                if sh > 0.94: j = 4
                gfx.append(32 + 20 * h + 5 * d + j)
for y in range(32):
    for x in range(32):
        q2 = math.hypot(x - 15.5, y - 15.5) / 15.5
        gfx.append(0 if q2 >= 1 else 240 + min(7, int((1 - q2) ** 1.6 * 8)))
assert len(gfx) == 32 * 256 + 1024
bgbm = np.zeros((H_, 512), np.uint8); bgbm[:, :W_] = bgidx
reu = bytearray(gfx) + bytes(0x10000 - len(gfx))
R_PAL = len(reu); reu += bytes(pal[:, 0]) + bytes(pal[:, 1]) + bytes(pal[:, 2]); reu += bytes(-len(reu) % 0x10000)
R_BG = len(reu); reu += bgbm.tobytes()
open(os.path.join(OUT, 'DNA Wave.reu'), 'wb').write(reu)
Image.fromarray(pal[bgidx]).resize((792, 568), Image.NEAREST).save(os.path.join(OUT, 'look_bg.png'))
# ---- data.inc
L = ['; made by gen.py - do not edit', 'NP = %d' % NP, 'NB = %d' % NB, 'CY = %d' % CY, 'R_GFX = $000000', 'LEN_GFX = %d' % len(gfx),
     'R_PAL = $%06x' % R_PAL, 'R_BG = $%06x' % R_BG, 'LEN_BG = %d' % bgbm.size]
def tab(name, vals): L.append('%-8s!byte %s' % (name, ','.join(str(int(v) & 255) for v in vals)))
tab('inc0', [v & 255 for v in INC]); tab('inc1', [(v >> 8) & 255 for v in INC]); tab('inc2', [v >> 16 for v in INC])
rx = [int(round(X0 + DX * i)) for i in range(NP)]
bx = [int(round(X0 + DX * j / 2)) for j in range(NB)]
tab('rxl', [x & 255 for x in rx]); tab('rxh', [x >> 8 for x in rx])
tab('bxl', [(x - 40) & 255 for x in bx]); tab('bxh', [((x - 40) >> 8) & 255 for x in bx])     # (sprite X: x - 8 - 32)
tab('ycos', [int(round(R * math.cos(2 * math.pi * k / 256))) for k in range(256)])
tab('dep', [min(3, int(2 + 2 * math.sin(2 * math.pi * k / 256))) for k in range(256)])       # 0 far .. 3 near
TILT = 0.28                                                                                     # the helix runs up to the right
tab('ayb', [int(round(CY - TILT * (x - 198))) for x in bx]); tab('ayr', [int(round(CY - TILT * (x - 198))) for x in rx])
tab('hueA', [j % 8 for j in range(NB)]); tab('hueB', [(j + 3) % 8 for j in range(NB)])        # every bead its own colour
RCOL = [((i * 5) % 6, (i * 5 + 2) % 6, (i * 5 + 3) % 6, (i * 5 + 1) % 6) for i in range(NP)]   # each rung: 4 stripes
for s_ in range(4): tab('rc%d' % s_, [192 + 4 * c[s_] for c in RCOL])
tab('frql', [f & 255 for f in FREQ]); tab('frqh', [f >> 8 for f in FREQ])
tab('vlo', [(SIDADR[i // 3] + 7 * (i % 3)) & 255 for i in range(NP)])
tab('vhi', [(SIDADR[i // 3] + 7 * (i % 3)) >> 8 for i in range(NP)])
tab('sidlo', [a & 255 for a in SIDADR]); tab('sidhi', [a >> 8 for a in SIDADR])
open(os.path.join(OUT, 'data.inc'), 'w').write('\n'.join(L) + '\n')
print('rungs', NP, 'beads a strand', NB, 'reu', len(reu))
