#!/usr/bin/env python3
# (C) 2026 Mong00se
# ODYSSEY - the stock C64's galaxy: an original, procedural Andromeda-style spiral galaxy as a hires bitmap (320 x 192, 2 colours a
# cell, the colours of each cell chosen along a ramp: the core white/yellow/brown, the arms blue), tilted like M31 (77 degrees) with
# its two small companions (like M32 and M110), a halo, dust lanes, blue star-forming knots and a starfield. Nothing here is
# a photo: every pixel is made from formulas and a random seed. The 6502 then puts ~250 live stars in orbit over it (show.asm).
#
#   galaxy.py OUTDIR  ->  OUTDIR/galaxy.bin (the disk file), OUTDIR/galaxy.png (as the C64 shows it), galaxy_2x.png
#
# THE DISK FILE: 2 bytes (a PRG address, unused), packed 1256 bytes (screen RAM 1000 = fg<<4|bg a cell, then the 256 byte table:
# byte 0 n twinkle cells then n x (screen RAM address lo, hi, the cell's background colour) up to 30; byte 96 n sparkle stars then
# n x (sprite x lo, x hi, y)), packed 8000 bytes (the bitmap, $6000 on the C64). Packing: stockpic.pack().
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stockpic as sp
PEPTO, PLAB0 = sp.PEPTO, sp.PLAB0
W, H = 320, 192
CX, CY = 160.0, 96.0
A_PX = 134.0                       # the disk's semi-major axis in pixels
B_PX = A_PX * 0.21875              # its semi-minor axis in lines (the live stars' ellipse: the same)
rng = np.random.RandomState(2026)
ALLOWED = [0, 6, 14, 3, 1, 9, 8, 2, 10, 7, 4, 5]

def fields(ss=2):
    ys, xs = np.mgrid[0:H * ss, 0:W * ss]
    x = (xs + 0.5) / ss; y = (ys + 0.5) / ss
    u = (x - CX) / A_PX; v = (y - CY) / B_PX
    # a slight twist of the whole disk (the major axis is not quite level), as in the real one
    ang = np.radians(-4.0); u, v = u * np.cos(ang) + v * np.sin(ang) * 0.0, v
    r = np.hypot(u, v); phi = np.arctan2(v / 1.0, u)
    # the plane: v is already de-projected (B_PX is the projected minor axis)
    psi = phi - 3.4 * np.log(r + 0.04)
    nz = lambda s, sd: ndimage.gaussian_filter(rng.randn(H * ss, W * ss), s) * sd
    n1 = nz(1.5 * ss, 1.0); n1 /= n1.std(); n2 = nz(6 * ss, 1.0); n2 /= n2.std()
    mask = np.clip((1.0 - r) / 0.14, 0, 1)
    bulge = np.exp(-(r / 0.075) ** 1.15) * 1.25 + 0.5 * np.exp(-(r / 0.24) ** 1.5)
    disk = np.exp(-r / 0.42) * mask
    arm = (0.5 + 0.5 * np.cos(2 * psi)) ** 2.2 * np.clip((r - 0.10) / 0.2, 0, 1) * mask * (1 + 0.6 * n2)
    lane = (0.5 + 0.5 * np.cos(2 * psi + 1.15)) ** 6.0 * np.clip((r - 0.07) / 0.13, 0, 1) * mask
    knots = np.clip(n1 - 1.4, 0, None) * arm * 2.2
    halo = 0.16 * np.exp(-(r / 0.8) ** 1.2) + 0.05 * np.exp(-r / 1.6)
    warm = bulge + 0.62 * disk * (1 - 0.88 * lane) * (1 + 0.12 * n2)
    blue = 1.5 * arm * (1 - 0.75 * lane) * (0.35 + disk) + 1.0 * knots
    # companions: M32 (small, compact, bright; below left of the core) and M110 (larger, fainter, elongated; above right)
    def blob(cx, cy, sx, sy, rot=0.0):
        dx = x - cx; dy = y - cy
        c, s = np.cos(rot), np.sin(rot); a = dx * c + dy * s; b = -dx * s + dy * c
        return np.exp(-((a / sx) ** 2 + (b / sy) ** 2) ** 0.8)
    m32 = blob(106, 117, 5.0, 3.6) * 1.0 + 0.3 * blob(106, 117, 11, 8)
    m110 = blob(262, 62, 19, 9, np.radians(-15)) * 0.42
    return warm, blue, halo, m32, m110

def render(ss=2):
    warm, blue, halo, m32, m110 = fields(ss)
    rgb = (warm[..., None] * np.array([1.0, 0.80, 0.46]) + blue[..., None] * np.array([0.50, 0.62, 1.0])
           + halo[..., None] * np.array([0.45, 0.52, 0.95]) + m32[..., None] * np.array([1.0, 0.86, 0.55])
           + m110[..., None] * np.array([0.9, 0.78, 0.62]))
    rgb = 1 - np.exp(-1.5 * rgb)
    rgb = rgb.reshape(H, ss, W, ss, 3).mean(axis=(1, 3))
    return np.clip((rgb - 0.07) / 0.93, 0, 1) ** 0.85

BAYER8 = None
def bayer(n):
    m = np.array([[0]])
    while m.shape[0] < n: m = np.block([[4 * m, 4 * m + 2], [4 * m + 3, 4 * m + 1]])
    return (m + 0.5) / (n * n)

RAMPS = ([0, 9, 8, 7, 1], [0, 6, 14, 3, 1])          # warm (the core, the bulge) and cool (the arms, the halo) colour ramps
def quantise(rgb, minfg_cells):
    CWn, CHn = 40, 24
    lum = rgb.max(axis=2)                                   # brightness 0..1
    warmth = rgb[..., 0] / (rgb[..., 0] + rgb[..., 2] + 1e-6)
    bay = bayer(8)
    out_bits = np.zeros((CHn, CWn, 8, 8), bool); scr = np.zeros((CHn, CWn), np.uint8)
    for cy in range(CHn):
        for cx in range(CWn):
            L = lum[cy * 8:cy * 8 + 8, cx * 8:cx * 8 + 8]; Wm = warmth[cy * 8:cy * 8 + 8, cx * 8:cx * 8 + 8]
            if L.max() < 0.02: continue
            wsum = (Wm * L).sum() / L.sum()
            ramp = RAMPS[0] if wsum > 0.50 else RAMPS[1]
            n = len(ramp) - 1
            pp = np.clip(L, 0, 1) ** 1.1 * n
            i = int(np.clip(np.floor(np.percentile(pp, 20)), 0, n - 1))
            j = min(n, max(i + 1, 2 if minfg_cells[cy * CWn + cx] else i + 1))
            j = max(j, int(min(n, np.ceil(np.percentile(pp, 92)))))
            t = np.clip((pp - i) / (j - i), 0, 1)
            thr = bay
            out_bits[cy, cx] = t > thr
            scr[cy, cx] = (ramp[j] << 4) | ramp[i]
    return out_bits.reshape(CHn * CWn, 8, 8), scr.reshape(-1), None, None

def main():
    outd = sys.argv[1]; os.makedirs(outd, exist_ok=True)
    rgb = render()
    # cells the live stars cover (the disk's ellipse and a margin): their foreground must be bright
    ys, xs = np.mgrid[0:H, 0:W]
    ell = (((xs - CX) / (A_PX + 8)) ** 2 + ((ys - CY) / (B_PX + 8)) ** 2) < 1.0
    ellc = ell.reshape(24, 8, 40, 8).any(axis=(1, 3)).reshape(-1)
    bits, scr, pairs, choice = quantise(rgb, ellc)
    bm = bits.reshape(24, 40, 8, 8)
    img_bits = bm.transpose(0, 2, 1, 3).reshape(H, W)
    scr = scr.reshape(24, 40).copy()
    # the starfield: single pixels in sky cells (cells whose pixels are all dark), a few 2 pixel ones
    cellbright = rgb.reshape(24, 8, 40, 8, 3).max(axis=(1, 3, 4))
    cellset = img_bits.reshape(24, 8, 40, 8).any(axis=(1, 3))
    sky = [(cy, cx) for cy in range(24) for cx in range(40) if cellbright[cy, cx] < 0.06 and not cellset[cy, cx]]
    rng.shuffle(sky)
    cols = [1, 1, 3, 7, 14, 15, 1, 3]
    tw = []; stars = []
    used = set()
    for cy, cx in sky:
        if len(stars) >= 190: break
        if any(abs(cy - a) < 1 and abs(cx - b) < 2 for a, b in used): continue
        used.add((cy, cx))
        px = cx * 8 + rng.randint(1, 7); py = cy * 8 + rng.randint(1, 7)
        img_bits[py, px] = True
        if rng.rand() < 0.25: img_bits[py, min(W - 1, px + 1)] = True
        c = cols[rng.randint(len(cols))]
        scr[cy, cx] = (c << 4) | 0
        stars.append((cy, cx, px, py, c))
    # the twinkles: 30 of those; the sparkle (glint sprite) stars: the 8 brightest-coloured that are clear of the disk and the scroller
    tw = stars[:30]
    sprs = [s for s in stars if s[3] < 170 and s[4] in (1, 3, 7)][:8]
    # pack the bitmap in the C64's layout
    bmp = np.zeros(8000, np.uint8)
    for cy in range(24):
        for cx in range(40):
            for r in range(8):
                v = 0
                for px in range(8): v = (v << 1) | int(img_bits[cy * 8 + r, cx * 8 + px])
                bmp[(cy * 40 + cx) * 8 + r] = v
    tab = bytearray(256)
    tab[0] = len(tw)
    for k, (cy, cx, px, py, c) in enumerate(tw):
        o = 0x4000 + cy * 40 + cx; tab[1 + 3 * k:4 + 3 * k] = bytes([o & 255, o >> 8, 0])
    tab[96] = len(sprs)
    for k, (cy, cx, px, py, c) in enumerate(sprs):
        sx = 24 + px - 5 * 2 + 1; sy = 50 + py - 10          # (the glint's centre pixel is its column 5/6 of 12, x2)
        tab[97 + 3 * k:100 + 3 * k] = bytes([sx & 255, sx >> 8, sy])
    screen = bytearray(1000)
    for cy in range(24):
        for cx in range(40): screen[cy * 40 + cx] = scr[cy, cx]
    seg1 = bytes(screen) + bytes(tab)
    p1, p2 = sp.pack(seg1), sp.pack(bytes(bmp))
    assert sp.unpack(p1, 1256) == seg1 and sp.unpack(p2, 8000) == bytes(bmp)
    f = bytes([0x00, 0xC0]) + p1 + p2
    open(os.path.join(outd, 'galaxy.bin'), 'wb').write(f)
    print('galaxy.bin', len(f), 'bytes', (len(f) + 253) // 254, 'blocks', ' twinkles', len(tw), 'sparkles', len(sprs))
    out = np.zeros((H, W, 3), np.uint8)
    for cy in range(24):
        for cx in range(40):
            b = scr[cy, cx]; fg, bg = PEPTO[b >> 4], PEPTO[b & 15]
            blk = img_bits[cy * 8:cy * 8 + 8, cx * 8:cx * 8 + 8]
            out[cy * 8:cy * 8 + 8, cx * 8:cx * 8 + 8] = np.where(blk[..., None], fg, bg)
    Image.fromarray(out).save(os.path.join(outd, 'galaxy.png'))
    Image.fromarray(out).resize((640 * 1, 384 * 1), Image.NEAREST).resize((1280, 768), Image.NEAREST).save(os.path.join(outd, 'galaxy_2x.png'))
if __name__ == '__main__': main()
