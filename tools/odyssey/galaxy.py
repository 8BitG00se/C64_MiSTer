#!/usr/bin/env python3
# (C) 2026 Mong00se
# GALAXY.PY - the stock C64's galaxy for ODYSSEY (2026: An Octophonic Odyssey), by Mong00se: an original, procedural
# Andromeda-style spiral galaxy in hires (320 x 192, black behind, one colour a cell). Nothing here is a photo: every
# pixel comes from formulas and a random seed.
#
# THE LOOK: the disk is tilted 60 degrees (an oval 280 x 140), two arms wind out of a bright core, dark dust lanes on
# their inner edges, knots along the outer arms, a soft halo, two small companions (like M32 and M110) and a starfield.
# Each 8x8 cell has ONE colour, from a ramp by its distance from the centre in the disk's plane (STEPS: white and
# yellow at the core, light grey, cyan, blue at the edge); the brightness is the density of a fixed 16x16 blue-noise
# dither, divided by the cell colour's own brightness so it runs on smoothly from one cell to the next. The ramp is
# round in the disk's plane, so the colours stay the same while the disk turns.
#
# THE TURN (galaxy.asm): the 6502 draws the disk anew, a byte at a time, from a 64x64 texture of dither levels in the
# disk's own plane, turned and tilted (two texture steps a byte, a nibble of the dither from each). render_rows() here
# is the same sums, byte for byte, so the pictures show exactly what the C64 shows. The rest (halo, companions, the
# starfield) stays still in the bitmap.
#
# THE LIVE STARS: NSTAR stars on NR rings in the disk's plane, seeded along the arms (a log spiral, with scatter); the
# 6502 moves them (the inner rings faster: the same speed along every ring) and starts a star again behind its arm
# when it runs too far ahead.
#
#   galaxy.py OUTDIR [t]  ->  OUTDIR/galaxy.bin (the disk file: pieces of where, how long, packed), galaxy_2x.png and
#                              galaxy_stars_2x.png (frame 0 as the C64 draws it), with t two frames of the turn too
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stockpic as sp
PEPTO = sp.PEPTO
W, H = 320, 192
CX, CY = 160.0, 94.0
INCL = np.radians(60.0)
A_PX = 140.0                        # the disk's radius in pixels (r = 1)
B_PX = A_PX * np.cos(INCL)          # its projected minor half axis
FLOOR = 0.07                        # the gaps between the arms (of the crest)
PITCH = 3.0                         # the arms' winding: psi = phi - PITCH ln r
LUM = (PEPTO @ np.array([0.299, 0.587, 0.114])) / 255.0
# the ramp, from the edge to the core (index 0 = black)
RAMP = [0, 11, 6, 14, 15, 10, 7, 1]

def bluenoise(n=64, seed=7):
    """a void-and-cluster threshold matrix (n x n, values 0..1): a fixed dither that looks like grain, not a grid"""
    r = np.random.RandomState(seed)
    def blur(m):
        f = np.fft.fft2(m); k = np.fft.fftfreq(n)
        g = np.exp(-(k[:, None] ** 2 + k[None, :] ** 2) * (2 * np.pi ** 2) * 1.9 ** 2)
        return np.real(np.fft.ifft2(f * g))
    m = r.rand(n, n) < 0.1
    while True:                          # make the starting pattern even
        b = blur(m.astype(float)); i = np.argmax(np.where(m, b, -1)); m.flat[i] = False
        b = blur(m.astype(float)); j = np.argmin(np.where(~m, b, 9)); m.flat[j] = True
        if i == j: break
    rank = np.zeros((n, n)); mm = m.copy(); ones = int(m.sum())
    for k in range(ones - 1, -1, -1):
        b = blur(mm.astype(float)); i = np.argmax(np.where(mm, b, -1)); mm.flat[i] = False; rank.flat[i] = k
    mm = m.copy()
    for k in range(ones, n * n):
        b = blur(mm.astype(float)); j = np.argmin(np.where(~mm, b, 9)); mm.flat[j] = True; rank.flat[j] = k
    return (rank + 0.5) / (n * n)

rng = np.random.RandomState(2026)
PG = 512                                # the disk's plane, sampled on a grid (-1.4 .. 1.4)
PEXT = 1.4
def plane_noise():
    s = lambda sig: ndimage.gaussian_filter(rng.randn(PG, PG), sig)
    n1 = s(2.0); n1 /= n1.std(); n2 = s(9.0); n2 /= n2.std()
    # the same under a half turn (the frames loop)
    n1 = (n1 + n1[::-1, ::-1]) / np.sqrt(2); n2 = (n2 + n2[::-1, ::-1]) / np.sqrt(2)
    return n1, n2
N1, N2 = plane_noise()
# the knots: clumps along the outer arms' crests (and their half-turn twins)
KN = []
for k in range(34):
    r = rng.uniform(0.45, 0.95); arm = rng.randint(2)
    phi = PITCH * np.log(r) + arm * np.pi + rng.normal(0, 0.12)
    KN.append((r * np.cos(phi), r * np.sin(phi), rng.uniform(0.012, 0.024), rng.uniform(0.6, 1.2)))
KN += [(-a, -b, s, w) for a, b, s, w in KN]

def sample(f, u, v):
    gi = (v + PEXT) / (2 * PEXT) * (PG - 1); gj = (u + PEXT) / (2 * PEXT) * (PG - 1)
    return ndimage.map_coordinates(f, [gi, gj], order=1, mode='nearest')

def disk_field(u, v):
    """brightness in the disk's plane (u, v; the disk's radius is 1)"""
    r = np.hypot(u, v) + 1e-6; phi = np.arctan2(v, u)
    psi = phi - PITCH * np.log(r)
    n1 = sample(N1, u, v); n2 = sample(N2, u, v)
    # the arms' crest brightness by radius, kept under the ramp's colour there (see STEPS)
    crest = np.interp(r, [0.0, 0.04, 0.10, 0.16, 0.30, 0.42, 0.60, 0.85, 0.98, 1.08], [1.3, 1.0, 0.86, 0.69, 0.62, 0.47, 0.40, 0.32, 0.20, 0.0])
    ramp_in = np.clip((r - 0.10) / 0.14, 0, 1)
    armsh = ((0.5 + 0.5 * np.cos(2 * psi)) ** 2.2) * (1 + 0.30 * n2)
    lane = ((0.5 + 0.5 * np.cos(2 * psi + 1.15)) ** 6.0) * np.clip((r - 0.06) / 0.12, 0, 1) * np.clip((1.0 - r) / 0.25, 0, 1)
    fl = np.interp(r, [0.1, 0.3, 0.6], [0.45, 0.22, FLOOR])
    m = (1 - ramp_in) * 1.0 + ramp_in * (fl + (1 - fl) * armsh)
    knots = np.zeros_like(u)
    for a, b, s, w in KN: knots += w * np.exp(-((u - a) ** 2 + (v - b) ** 2) / (2 * s * s))
    grain = 1 + 0.15 * n1
    L = crest * np.clip(m * (1 - 0.9 * lane) * grain + 0.6 * knots, 0, 1.15)
    halo = 0.12 * np.exp(-(r / 0.62) ** 2) * np.clip((1.30 - r) / 0.4, 0, 1)
    return np.maximum(L, halo)

# the companions: M32-like (small, bright, below the core) and M110-like (larger, fainter, elongated, above right):
# their middles, (half axes, turn, brightness) of a core and an envelope, and their cells' colours
COMP = [(116, 166), (116, 166), (264, 34), (264, 34)]
COMPS = [(2.8, 2.4, 0, 0.9), (6.5, 5.5, 0, 0.16), (13, 5.5, -32, 0.22), (5, 2.4, -32, 0.16)]
COMPCOL = [((116, 166), 9, 15), ((264, 34), 18, 15)]        # (middle, radius in pixels, colour)

def blob(x, y, cx, cy, sx, sy, rot=0.0):
    dx = x - cx; dy = y - cy
    c, s = np.cos(rot), np.sin(rot); a = dx * c + dy * s; b = -dx * s + dy * c
    return np.exp(-((a / sx) ** 2 + (b / sy) ** 2) ** 0.75)

def screen_field(alpha, ss=3):
    """the brightness on the screen (W x H) with the disk turned by alpha in its plane"""
    ys, xs = np.mgrid[0:H * ss, 0:W * ss]
    x = (xs + 0.5) / ss; y = (ys + 0.5) / ss
    u = (x - CX) / A_PX; v = (y - CY) / B_PX            # de-tilt
    c, s = np.cos(-alpha), np.sin(-alpha)
    L = disk_field(u * c - v * s, u * s + v * c)
    # the companions (they do not turn with the disk)
    for (cx, cy), (a, b, rot, w) in zip(COMP, COMPS):
        L = L + w * blob(x, y, cx, cy, a, b, np.radians(rot))
    L = L.reshape(H, ss, W, ss).mean(axis=(1, 3))
    return L

def tone(L):
    return np.clip(L, 0, 1)

def cell_radius():
    """each cell's distance from the centre in the disk's plane (from its middle)"""
    cy, cx = np.mgrid[0:24, 0:40]
    u = (cx * 8 + 4 - CX) / A_PX; v = (cy * 8 + 4 - CY) / B_PX
    return np.hypot(u, v)

STEPS = [(0.07, 1), (0.15, 7), (0.62, 15), (1.0, 3), (1.2, 6), (99, 0)]
JIT = 0.12                      # (only between light grey and cyan: the same brightness, so the dither's density is right in either)
def bayer(n):
    m = np.array([[0]])
    while m.shape[0] < n: m = np.block([[4 * m, 4 * m + 2], [4 * m + 3, 4 * m + 1]])
    return (m + 0.5) / (n * n)

def cell_colours():
    """one colour a cell, from the ramp by its distance from the centre in the disk's plane (STEPS: up to r, colour)"""
    rc = cell_radius(); col = np.zeros((24, 40), int)
    cb = bayer(4)                        # the band edges ragged (a cell either side), so they show no stairs
    for cy in range(24):
        for cx in range(40):
            r = rc[cy, cx]
            if 0.5 < r < 0.74: r += (cb[cy % 4, cx % 4] - 0.5) * JIT
            col[cy, cx] = next(c for lim, c in STEPS if r < lim)
            for (mx, my), rad, c in COMPCOL:
                if abs(cx * 8 + 4 - mx) < rad and abs(cy * 8 + 4 - my) < rad * 0.6 + 4 and rc[cy, cx] > 0.9: col[cy, cx] = c
    return col

# ======================================================================================= the 6502's side
# Memory (show.asm and fx.asm use the same addresses)
SCRB, BMA, BMB, TEXA = 0x8000, 0x6000, 0xA000, 0xE000
TEXLOAD = 0x6000                # (loaded here: the packing reads back what it wrote, and $E000 reads the KERNAL then)
SOFF, RINGT = 0x4C00, 0x5300                    # the stars' angles in their ring; the rings (5 x 48)
ROWC0, ROWNB, ROWUQ, ROWVQ = 0x5500, 0x55C0, 0x5680, 0x5740
SQL, SQH, NSQH, CQ, SQT = 0x8C00, 0x8D00, 0x8F00, 0x9100, 0x9200
XLR, XHR, MR, XLL, XHL, ML = 0x9300, 0x9400, 0x9500, 0x9600, 0x9700, 0x9800
YLO, YHA, YHB, DUL, DUH, SIN8 = 0x9900, 0x9A00, 0x9B00, 0x9C00, 0x9D00, 0x9E00
DITH, TWTAB, GLTAB = 0xC000, 0xC440, 0xC4A0
TS = 64                         # the texture: 64 x 64 levels (0-16) over the plane -EXT..EXT
EXT = 1.15
RREN = 1.06                     # the 6502 draws the bytes inside this radius anew; the rest is still
KX = TS / (2 * EXT) / A_PX      # texels a pixel (across)
KY = TS / (2 * EXT) / B_PX      # texels a line
DUX = 4 * KX                    # texels a group of 4 pixels
NR = 40                         # rings of live stars
NSTAR = 104                     # the live stars (at most 255; show.asm moves them all)
STAR_V = 0.30                   # the stars' speed in pixels an update (2 frames)

def thr16():
    return (np.argsort(np.argsort(bluenoise(16, 5).ravel())).reshape(16, 16)) // 16     # 0..15, each 16 times

def class_lum(r):
    """the colour (and its brightness) the ramp gives at plane radius r (no jitter)"""
    c = np.select([r < lim for lim, _ in STEPS], [c for _, c in STEPS], 0)
    return c, LUM[c]

def make_texture():
    gy, gx = np.mgrid[0:TS, 0:TS]
    acc = 0; ss = 4
    for i in range(ss):
        for j in range(ss):
            u = (gx + (i + 0.5) / ss) / TS * 2 * EXT - EXT; v = (gy + (j + 0.5) / ss) / TS * 2 * EXT - EXT
            T = tone(disk_field(u, v)); _, lum = class_lum(np.hypot(u, v))
            acc = acc + np.clip(T / np.maximum(lum, 0.05), 0, 1)
    return np.clip(np.floor(acc / ss / ss * 16 + 0.5), 0, 16).astype(np.uint8)

def row_spans():
    """each line's bytes drawn anew: the first byte column and how many (all 8 pixels inside RREN)"""
    rows = []
    for y in range(H):
        cols = [c for c in range(40) if all(np.hypot((x + 0.5 - CX) / A_PX, (y + 0.5 - CY) / B_PX) < RREN for x in (c * 8, c * 8 + 7))]
        if cols:
            c0 = cols[0]; nb = cols[-1] - c0 + 1
            uq = int(round(4 * ((c0 * 8 + 2) - CX) * KX)); vq = int(round(4 * (y + 0.5 - CY) * KY))
            rows.append((c0, nb, uq, vq))
        else: rows.append((0, 0, 0, 0))
    return rows

SIN8T = [int(round(127 * np.sin(2 * np.pi * i / 256))) for i in range(256)]
DUT = [int(round(256 * DUX * np.cos(2 * np.pi * i / 256))) for i in range(256)]

def render_rows(bm, tex, rows, a, which=None):
    """the 6502's drawing, exactly: lines `which` (all) of the bitmap (H x 40 bytes) at angle a (0-255)"""
    T16 = thr16()
    c8, s8 = SIN8T[(a + 64) & 255], SIN8T[a]
    du = DUT[a] & 0xFFFF; dv = (-DUT[(a - 64) & 255]) & 0xFFFF
    for y in (range(H) if which is None else which):
        c0, nb, uq, vq = rows[y]
        if not nb: continue
        u = (8192 + ((c8 * uq + s8 * vq) >> 1)) & 0xFFFF
        v = (8192 + ((-s8 * uq + c8 * vq) >> 1)) & 0xFFFF
        for c in range(c0, c0 + nb):
            byte = 0
            for half in range(2):
                lev = int(tex[v >> 8, u >> 8])
                x0 = c * 8 + half * 4
                for k in range(4):
                    if lev > T16[y & 15, (x0 + k) & 15]: byte |= 0x80 >> (half * 4 + k)
                u = (u + du) & 0xFFFF; v = (v + dv) & 0xFFFF
            bm[y, c] = byte

def dith_tables():
    """DITH + (p * 4 + k) * 17 + level: p the line (0-15), k 0/1 the left nibble of an even/odd byte, 2/3 the right"""
    T16 = thr16(); t = bytearray(16 * 4 * 17)
    for p in range(16):
        for k in range(4):
            par, half = k & 1, k >> 1
            x0 = par * 8 + half * 4
            for lev in range(17):
                b = 0
                for j in range(4):
                    if lev > T16[p, (x0 + j) & 15]: b |= 0x80 >> (half * 4 + j)
                t[(p * 4 + k) * 17 + lev] = b
    return t

def star_setup():
    """the rings (radius, stars, speed, arm angle) and each star's angle (its 8 high bits) in its ring"""
    rr = np.linspace(22, 134, NR)
    w = rr * np.exp(-rr / 70.0); w = w / w.sum()               # stars a ring: like the disk's light, by area
    cnt = np.maximum(1, np.round(w * NSTAR)).astype(int)
    while cnt.sum() > NSTAR: cnt[np.argmax(cnt)] -= 1
    while cnt.sum() < NSTAR: cnt[np.argmin(cnt)] += 1
    rings, offs = [], []
    for k in range(NR):
        r = rr[k]
        om = -int(round(STAR_V / r * 65536 / (2 * np.pi)))     # turning the way that makes the arms trail
        arm = int(round(PITCH * np.log(r / A_PX) * 128 / np.pi)) & 255
        rings.append((int(round(r)), int(cnt[k]), om & 0xFFFF, arm))
        for j in range(cnt[k]):
            d = rng.normal(2, 7)                                  # around the crest (units of 256 a turn)
            offs.append((arm + 128 * rng.randint(2) - int(round(d))) & 255)
    return rings, offs

def math_tables():
    t = {}
    f = [n * n // 4 for n in range(512)]
    t[SQL] = bytes(f[n] & 255 for n in range(256))
    t[SQH] = bytes(f[n] >> 8 for n in range(512))
    t[NSQH] = bytes(f[abs(n - 255)] >> 8 for n in range(512))
    t[CQ] = bytes(int(round(255 * np.cos((i + 0.5) * np.pi / 512))) for i in range(256))
    t[SQT] = bytes(int(round(255 * np.cos(INCL) * np.sin((i + 0.5) * np.pi / 512))) for i in range(256))
    xl = {}; 
    for side, (lo, hi, mk) in (('R', (XLR, XHR, MR)), ('L', (XLL, XHL, ML))):
        L, Hh, M = bytearray(256), bytearray(256), bytearray(256)
        for xo in range(160):
            x = 160 + xo if side == 'R' else 159 - xo
            o = (x >> 3) * 8; L[xo] = o & 255; Hh[xo] = o >> 8
            M[xo] = (0x80 >> (x & 7)) | ((0x80 >> ((x & 7) + 1)) if (x & 7) < 7 else 0x02)
        t[lo], t[hi], t[mk] = bytes(L), bytes(Hh), bytes(M)
    yl, ya, yb = bytearray(256), bytearray(256), bytearray(256)
    for i in range(256):
        yo = i & 127; y = SCY + yo if i < 128 else SCY - yo
        y = min(max(y, 0), 183)
        o = (y >> 3) * 320 + (y & 7); yl[i] = (BMA + o) & 255; ya[i] = (BMA + o) >> 8; yb[i] = (BMB + o) >> 8
    t[YLO], t[YHA], t[YHB] = bytes(yl), bytes(ya), bytes(yb)
    t[DUL] = bytes(d & 255 for d in DUT); t[DUH] = bytes((d >> 8) & 255 for d in DUT)
    t[SIN8] = bytes(v & 255 for v in SIN8T)
    return t

SCY = 94                        # the live stars' middle line

def star_xy(r, th16):
    """where a live star is plotted: exactly the 6502's sums (the quarter-square products' high bytes)"""
    f = [n * n // 4 for n in range(512)]
    q = th16 >> 14; i = (th16 >> 6) & 255
    if q & 1: i ^= 255
    cq = int(round(255 * np.cos((i + 0.5) * np.pi / 512))); sq = int(round(255 * np.cos(INCL) * np.sin((i + 0.5) * np.pi / 512)))
    mul = lambda a, b: (f[a + b] >> 8) - (f[abs(b - a)] >> 8)
    xo, yo = mul(r, cq), mul(r, sq)
    x = 160 + xo if q in (0, 3) else 159 - xo
    y = SCY + yo if q in (0, 1) else SCY - yo
    return x, y

def glint_sprites():
    """the glints: 4 sizes, each a white middle (sprite 2k) over light blue spikes (2k+1); the middle pixel at column
    11, line 10: 4 long spikes along the axes, 4 short ones on the diagonals, thinning out at their tips"""
    out = bytearray()
    for s in range(4):
        aw, ab, dw, db = [1, 1, 2, 3][s], [2, 4, 6, 9][s], [0, 0, 1, 1][s], [0, 1, 2, 3][s]
        wht = np.zeros((21, 24), bool); blu = np.zeros((21, 24), bool)
        wht[10, 11] = True
        if s >= 2: wht[9:12, 11] = True; wht[10, 10:13] = True
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            for k in range(1, ab + 1):
                x, y = 11 + dx * k, 10 + dy * k
                if k <= aw: wht[y, x] = True
                elif k < ab - 1 or (k == ab - 1 and s >= 2) or (k == ab and s == 3 and dy == 0): blu[y, x] = True
        for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            for k in range(1, db + 1):
                x, y = 11 + dx * k, 10 + dy * k
                if k <= dw: wht[y, x] = True
                else: blu[y, x] = True
        for m in (wht, blu):
            out += bytes(np.packbits(m, axis=1).reshape(-1)) + b'\0'
    return bytes(out)

def to_rgb(bits, col):
    c = np.repeat(np.repeat(col, 8, 0), 8, 1)
    return np.where(bits[..., None], PEPTO[c], 0).astype(np.uint8)

def to_bytes(bits):
    return np.packbits(bits.reshape(24, 8, 40, 8).transpose(0, 2, 1, 3).reshape(-1, 8), axis=1).reshape(-1)

def main():
    outd = sys.argv[1]; os.makedirs(outd, exist_ok=True)
    rows = row_spans(); tex = make_texture()
    # the still parts: the halo outside RREN, the companions, the starfield (per pixel, the 16x16 dither)
    T = tone(screen_field(0.0))
    col = cell_colours()
    T16 = thr16(); thr = np.tile(T16, (12, 20))
    lumc = np.repeat(np.repeat(LUM[col], 8, 0), 8, 1)
    lev = np.clip(np.floor(np.clip(T / np.maximum(lumc, 0.05), 0, 1) * 16 + 0.5), 0, 16)
    bits = lev > thr
    bits[184:] = False                                     # (row 23 stays black: the scroller's split)
    drawn = np.zeros((H, 40), bool)
    for y, (c0, nb, uq, vq) in enumerate(rows): drawn[y, c0:c0 + nb] = True
    # the starfield: one star in a sky cell (no galaxy light in it), a few with a second pixel
    cellT = T.reshape(24, 8, 40, 8).max(axis=(1, 3))
    sky = [(cy, cx) for cy in range(23) for cx in range(40) if col[cy, cx] == 0 and cellT[cy, cx] < 0.01]
    rng.shuffle(sky)
    scol = [1, 1, 15, 3, 7, 14, 1, 15, 12]
    stars = []
    for cy, cx in sky[:150]:
        px = cx * 8 + rng.randint(1, 7); py = cy * 8 + rng.randint(1, 7)
        bits[py, px] = True
        if rng.rand() < 0.2: bits[py, px + 1] = True
        c = scol[rng.randint(len(scol))]; col[cy, cx] = c
        stars.append((cy, cx, px, py, c))
    bmbytes = np.packbits(bits, axis=1)                    # H x 40
    bmbytes[drawn] = 0                                      # the 6502 draws these
    still = bmbytes.copy()
    # frame 0 as the 6502 draws it (for the pictures)
    full = still.copy(); render_rows(full, tex, rows, 0)
    # the twinkles (30 sky stars) and the glints (8 bright ones, clear of the scroller)
    tw = stars[:30]
    gl = [s for s in stars[30:] if s[4] in (1, 15, 3) and 20 < s[3] < 176][:8]
    twt = bytearray(96); twt[0] = len(tw)
    for k, (cy, cx, px, py, c) in enumerate(tw):
        o = cy * 40 + cx; twt[1 + 3 * k:4 + 3 * k] = bytes([o & 255, o >> 8, c])
    glt = bytearray(32); glt[0] = len(gl)
    for k, (cy, cx, px, py, c) in enumerate(gl):
        sx = 24 + px - 11; sy = 50 + py - 10                  # the glint's middle pixel: sprite column 11, line 10
        glt[1 + 3 * k:4 + 3 * k] = bytes([sx & 255, sx >> 8, sy])
    # the stars
    rings, offs = star_setup()
    ringt = bytearray(5 * 48)
    for k, (r, n, om, arm) in enumerate(rings):
        ringt[k] = r; ringt[48 + k] = n; ringt[96 + k] = om & 255; ringt[144 + k] = om >> 8; ringt[192 + k] = arm
    rowt = bytearray(4 * 192)
    for y, (c0, nb, uq, vq) in enumerate(rows):
        rowt[y] = c0; rowt[192 + y] = nb; rowt[384 + y] = uq & 255; rowt[576 + y] = vq & 255
    screen = bytes(int(col.reshape(-1)[i]) << 4 for i in range(960)) + bytes(40)
    bm = to_bytes(np.unpackbits(still, axis=1).astype(bool))
    segs = [(SCRB, screen), (BMB, bytes(bm)), (TEXLOAD, bytes(tex.reshape(-1))), (DITH, bytes(dith_tables())),
            (TWTAB, bytes(twt)), (GLTAB, bytes(glt)), (0x4880, glint_sprites()), (0x8880, glint_sprites()), (SOFF, bytes(offs)), (RINGT, bytes(ringt)), (ROWC0, bytes(rowt))]
    for addr, data in math_tables().items(): segs.append((addr, data))
    f = bytearray([0x00, 0xC0])
    for addr, data in segs:
        p = sp.pack(data); assert sp.unpack(p, len(data)) == data
        f += bytes([addr & 255, addr >> 8, len(data) & 255, len(data) >> 8]) + p
    f += bytes([0, 0])
    open(os.path.join(outd, 'galaxy.bin'), 'wb').write(f)
    pages = sum((len(d) + 255) // 256 for _, d in segs)
    print('galaxy.bin', len(f), 'bytes', (len(f) + 253) // 254, 'blocks;', pages, 'pages; drawn bytes', int(drawn.sum()),
          '; stars', len(offs), 'twinkles', len(tw), 'glints', len(gl))
    # the pictures: frame 0, and with the live stars
    def show(bmb, starsxy, name):
        b = np.unpackbits(bmb, axis=1).astype(bool)
        for x, y in starsxy:
            b[y, x] = True; b[y, x + 1 if (x & 7) < 7 else x - 1] = True
        rgb = to_rgb(b, col)
        Image.fromarray(rgb).resize((640, 384), Image.NEAREST).save(os.path.join(outd, name))
    show(full, [], 'galaxy_2x.png')
    pos = []; i = 0
    for k, (r, n, om, arm) in enumerate(rings):
        for j in range(n): pos.append(star_xy(r, (offs[i] << 8) & 0xFFFF)); i += 1
    show(full, pos, 'galaxy_stars_2x.png')
    if len(sys.argv) > 2:                                  # a strip of the turn
        for a in (8, 16):
            fb = still.copy(); render_rows(fb, tex, rows, (-a) & 255); show(fb, [], 'turn%d.png' % a)

if __name__ == '__main__': main()
