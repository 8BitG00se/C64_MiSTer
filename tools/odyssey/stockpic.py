#!/usr/bin/env python3
# (C) 2026 Mong00se. All rights reserved.
# ODYSSEY - the stock C64 picture: the Webb "Cosmic Cliffs" (NASA, ESA, CSA, STScI) as a multicolour bitmap
# (160 x 192 shown, 4 x 8 cells, black background + 3 colours a cell), plus the tables the 6502 needs for its live effects:
# the star cells it twinkles, the brightest stars for the sparkle sprites, the gas cells it shimmers.
# For Neal's private use (the photo conversion) - not part of a public release. The PC only prepares data, like a paint
# program; everything that moves is done by the 6502 (odyssey.asm).
#
#   stockpic.py SOURCE.jpg OUTDIR        -> OUTDIR/stockpic.bin, stock_preview.png (as VICE's pepto palette shows it)
#
# stockpic.bin (loaded by the program at $8000):
#   $0000 1000  screen colours (hi nibble = bits 01, lo = bits 10), the real ones (the iris copies them in)
#   $0400 1000  colour RAM (bits 11)
#   $0800 8000  the bitmap (copied to $6000 at start)
#   $2740  star twinkle slots: NTW x (lo, hi of the screen/colour address offset, which: 0 hi nibble, 1 lo nibble,
#          2 colour RAM; base colour) - 4 bytes each, then
#          sparkle stars: NSP x (sprite x lo, x hi, y) - 3 bytes each
#          shimmer cells: NSH x (offset lo, hi, base colour, alternate colour, phase) - 5 bytes each
import sys, os, math
import numpy as np
from PIL import Image
from scipy import ndimage
Image.MAX_IMAGE_PIXELS = None

# the C64 colours as the Octophonic core shows them by default (rtl/fpga64_rgbcolor.vhd, palette 0)
PEPTO = np.array([(0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x81, 0x33, 0x38), (0x75, 0xce, 0xc8), (0x8e, 0x3c, 0x97), (0x56, 0xac, 0x4d),
                  (0x2e, 0x2c, 0x9b), (0xed, 0xf1, 0x71), (0x8e, 0x50, 0x29), (0x55, 0x38, 0x00), (0xc4, 0x6c, 0x71), (0x4a, 0x4a, 0x4a),
                  (0x7b, 0x7b, 0x7b), (0xa9, 0xff, 0x9f), (0x70, 0x6d, 0xeb), (0xb2, 0xb2, 0xb2)], np.float64)
M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
def s2l(c): c = c / 255.0; return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def oklab(rgb): return np.cbrt(s2l(np.asarray(rgb, np.float64)) @ M1.T) @ M2.T
PLAB0 = oklab(PEPTO)
W, H = 160, 192                     # multicolour pixels shown (the 25th text row is the scroller)
CW, CH = 40, 24
# colours the picture may use (green, light green and purple don't belong in it)
ALLOWED = [int(v) for v in os.environ.get('ALLOWED', '0,1,2,3,6,7,8,9,10,12,14').split(',')]
USM = float(os.environ.get('USM', '0.7'))
CONTRAST = float(os.environ.get('CONTRAST', '0'))
LIFT = tuple(float(v) for v in os.environ.get('LIFT', '0,1,1').split(','))   # lightness offset, lightness gain, chroma gain
WAB = float(os.environ.get('WAB', '3.0'))   # how much hue/chroma counts against lightness in the error
NSTARS = 40
DSTR = float(os.environ.get('DSTR', '0.55'))   # dither strength

def load(src):
    im = Image.open(src).convert('RGB')
    # the shown shape: 320 x 192 hires pixels, a PAL pixel 0.936 as wide as tall -> 1.56 : 1
    asp = 320 * 0.936 / 192
    w = int(round(im.height * asp)); x0 = (im.width - w) // 2 + int(im.width * 0.0)
    return im.crop((x0, 0, x0 + w, im.height))

def stars(im, n=60):
    # the stars: peaks of a white top-hat on a 640-wide copy; position in multicolour pixels, brightness, colour
    sm = im.resize((640, int(round(640 * im.height / im.width))), Image.LANCZOS)
    a = np.asarray(sm, np.float64); L = a.mean(axis=2)
    th = L - ndimage.grey_opening(L, size=(7, 7))
    mx = ndimage.maximum_filter(th, size=9)
    pk = np.argwhere((th == mx) & (th > 60))
    out = []
    for y, x in pk:
        out.append((th[y, x], x * W / sm.width, y * H / sm.height, a[y, x]))
    out.sort(key=lambda t: -t[0])
    return out

def prepare(im):
    # the target: 160 x 192, area-averaged, then lifted towards the C64's colours (the photo's deep blues and burnt
    # oranges are darker and more saturated than any C64 colour): a gentle curve on lightness
    t = np.asarray(im.resize((W, H), Image.LANCZOS), np.float64)
    lab = oklab(t)
    L = lab[..., 0]
    if CONTRAST:                    # an S-curve on lightness about its middle: gold ridges against brown shadows
        m = np.median(L); L = m + (L - m) * (1 + CONTRAST) - CONTRAST * 1.5 * (L - m) ** 3 / max(1e-3, L.std() ** 2) * 0.1
    if USM:                         # local contrast (an unsharp mask on lightness): the cliffs' ridges and folds stand out
        L = L + USM * (L - ndimage.gaussian_filter(L, 2.5))
    lab[..., 0] = np.clip(LIFT[0] + LIFT[1] * L, 0, 1)
    lab[..., 1:] *= LIFT[2]
    if RAMPS: lab = ramp_map(lab)
    return lab

# the tone map: the gold gas and the blue sky each spread along a C64 colour ramp by brightness (half its rank among
# the pixels of that colour, half its own lightness), so the picture uses the C64's whole range, as an artist would
def _ramp(env, dflt):
    v = os.environ.get(env, dflt).split(',')
    return [int(x.split(':')[0]) for x in v], np.array([float(x.split(':')[1]) for x in v])
RAMP_GOLD = _ramp('RG', '0:0,9:0.1,2:0.28,8:0.5,10:0.78,7:0.97,1:1')     # (colour, where on the ramp)
RAMP_BLUE = _ramp('RB', '0:0,6:0.4,14:0.8,3:0.97,1:1')
RAMPS = int(os.environ.get('RAMPS', '1'))
EQ = float(os.environ.get('EQ', '0.5'))
def ramp_map(lab):
    L = lab[..., 0]; b = lab[..., 2]; a = lab[..., 1]
    hue = b + 0.3 * a                                      # gold > 0, blue < 0
    w = np.clip((hue + 0.015) / 0.04, 0, 1); w = w * w * (3 - 2 * w)
    out = np.zeros_like(lab)
    for ramp, wt in ((RAMP_GOLD, w), (RAMP_BLUE, 1 - w)):
        sel = wt > 0.5
        ref = np.sort(L[sel]) if sel.sum() > 50 else np.sort(L.ravel())
        rank = np.searchsorted(ref, L) / len(ref)
        lin = np.clip((L - ref[int(len(ref) * 0.01)]) / max(1e-3, ref[int(len(ref) * 0.995)] - ref[int(len(ref) * 0.01)]), 0, 1)
        cols, stops = ramp
        p = np.clip(EQ * rank + (1 - EQ) * lin, 0, 1)
        i = np.clip(np.searchsorted(stops, p, side='right') - 1, 0, len(stops) - 2)
        f = ((p - stops[i]) / (stops[i + 1] - stops[i]))[..., None]
        R = PLAB0[cols]
        col = R[i] * (1 - f) + R[i + 1] * f
        out += col * wt[..., None]
    return out

def choose_cells(lab, starmask, bg=0):
    # every cell: the 3 colours (+ black) that give the least error after dithering, all triples of ALLOWED tried at once
    from itertools import combinations
    tri = np.array(list(combinations([c for c in ALLOWED if c != bg], 3)))     # T x 3
    T = len(tri)
    sets = np.concatenate([np.full((T, 1), bg), tri], axis=1)                   # T x 4
    cells = lab.reshape(CH, 8, CW, 4, 3).transpose(0, 2, 1, 3, 4).reshape(CH * CW, 32, 3)
    wts = starmask.reshape(CH, 8, CW, 4).transpose(0, 2, 1, 3).reshape(CH * CW, 32)
    best = np.zeros(CH * CW, int)
    P = PLAB[sets]                                                              # T x 4 x 3
    for i0 in range(0, CH * CW, 40):
        c = cells[i0:i0 + 40]                                                   # B x 32 x 3
        B = len(c)
        work = np.repeat(c[:, None], T, axis=1).copy()                          # B x T x 32 x 3
        outc = np.zeros((B, T, 32, 3))
        for y in range(8):
            xs = range(4) if y % 2 == 0 else range(3, -1, -1); dx = 1 if y % 2 == 0 else -1
            for x in xs:
                k = y * 4 + x
                v = work[:, :, k]                                               # B x T x 3
                d = ((v[:, :, None, :] - P[None]) ** 2).sum(-1)                 # B x T x 4
                j = d.argmin(-1)
                q = np.take_along_axis(P[None].repeat(B, 0), j[..., None, None].repeat(3, -1), axis=2)[:, :, 0]
                outc[:, :, k] = q
                e = (v - q) * 0.8
                xn = x + dx
                if 0 <= xn < 4: work[:, :, k + dx] += e * 7 / 16
                if y < 7:
                    if 0 <= x - dx < 4: work[:, :, k + 4 - dx] += e * 3 / 16
                    work[:, :, k + 4] += e * 5 / 16
                    if 0 <= xn < 4: work[:, :, k + 4 + dx] += e * 1 / 16
        # error: the pixels (stars count a lot) plus the cell's 2 x 2 blocks averaged (how it looks from the sofa)
        pe = (((outc - c[:, None]) ** 2).sum(-1) * (1 + 6 * wts[i0:i0 + B, None])).mean(-1)
        o4 = outc.reshape(B, T, 4, 2, 2, 2, 3).mean(axis=(3, 5)); c4 = c.reshape(B, 4, 2, 2, 2, 3).mean(axis=(2, 4))
        be = ((o4 - c4[:, None]) ** 2).sum(-1).mean(axis=(-1, -2))
        best[i0:i0 + B] = (0.5 * pe + 1.5 * be).argmin(1)
    return sets[best].reshape(CH, CW, 4)

def dither(lab, csets, strength=0.75):
    # Floyd-Steinberg over the whole picture (serpentine), each pixel limited to its cell's 4 colours
    work = lab.copy(); idx = np.zeros((H, W), int)
    for y in range(H):
        xs = range(W) if y % 2 == 0 else range(W - 1, -1, -1); dx = 1 if y % 2 == 0 else -1
        for x in xs:
            s = csets[y // 8, x // 4]; v = work[y, x]
            d = ((PLAB[s] - v) ** 2).sum(-1); j = int(d.argmin()); idx[y, x] = j
            e = (v - PLAB[s[j]]) * strength
            n = np.linalg.norm(e)
            if n > 0.12: e *= 0.12 / n
            xn = x + dx
            if 0 <= xn < W: work[y, xn] += e * 7 / 16
            if y + 1 < H:
                if 0 <= x - dx < W: work[y + 1, x - dx] += e * 3 / 16
                work[y + 1, x] += e * 5 / 16
                if 0 <= xn < W: work[y + 1, xn] += e / 16
    return idx

# the views: the whole picture, then the close-ups of the tour (left, top, width as fractions of the whole picture; the
# height follows from the C64's 1.56 : 1). Their names are what the scroll text says.
VIEWS = [
    (0.0, 0.0, 1.0, 'THE COSMIC CLIFFS'),
    (0.0, 0.17, 0.43, 'THE WESTERN PEAK'),
    (0.30, 0.20, 0.40, 'THE RIDGE AND ITS STARS'),
    (0.62, 0.05, 0.38, 'THE EASTERN CLIFFS'),
]

def view_crop(full, v):
    l, t, w, _ = v
    asp = 320 * 0.936 / 192
    if w >= 1.0:
        return load_whole(full)
    pw = w * full.width; ph = pw / asp
    x0 = l * full.width; y0 = t * full.height
    y0 = min(y0, full.height - ph)
    return full.crop((int(x0), int(y0), int(x0 + pw), int(y0 + ph)))

def load_whole(im):
    asp = 320 * 0.936 / 192
    w = int(round(im.height * asp)); x0 = (im.width - w) // 2
    return im.crop((x0, 0, x0 + w, im.height))

def convert(im):
    global PLAB
    PLAB = PLAB0
    lab = prepare(im)
    st = stars(im)
    starmask = np.zeros((H, W))
    for b, x, y, rgb in st[:NSTARS]:
        xi, yi = int(x), int(y)
        if 0 <= xi < W and 0 <= yi < H - 1:
            c = oklab(np.clip(rgb * 1.5 + 40, 0, 255)); c[0] = max(c[0], 0.85)
            lab[yi, xi] = c; starmask[yi, xi] = 1
    lab[H - 1] = PLAB0[0]                                   # the last line black (the scroller's split is just below it)
    PLAB = PLAB0 * np.array([1, WAB, WAB]); lab = lab * np.array([1, WAB, WAB])
    csets = choose_cells(lab, starmask)
    idx = ordered(lab, csets) if os.environ.get('ORD') else dither(lab, csets, DSTR)
    scr = np.zeros(1000, np.uint8); col = np.zeros(1000, np.uint8); bmp = np.zeros(8000, np.uint8)
    n3 = np.zeros(1000, int)
    for cy in range(CH):
        for cx in range(CW):
            s = list(csets[cy, cx]); blk = idx[cy * 8:cy * 8 + 8, cx * 4:cx * 4 + 4]
            order = sorted([1, 2, 3], key=lambda j: PLAB0[s[j]][0])      # the brightest colour goes in colour RAM (bits 11)
            remap = np.array([0, 0, 0, 0]); remap[order[0]] = 1; remap[order[1]] = 2; remap[order[2]] = 3
            cell = remap[blk]
            o = cy * 40 + cx
            scr[o] = (s[order[0]] << 4) | s[order[1]]; col[o] = s[order[2]]
            n3[o] = int((cell == 3).sum())
            for r in range(8):
                v = 0
                for px in range(4): v = (v << 2) | int(cell[r, px])
                bmp[o * 8 + r] = v
    for o in range(960, 1000): scr[o] = 0; col[o] = 0
    # twinkle slots: star cells whose colour-RAM colour is bright and only on a few pixels (the star itself)
    tw = []
    for b, x, y, rgb in st[:NSTARS]:
        o = int(y) // 8 * 40 + int(x) // 4
        if o < 960 and n3[o] <= 3 and col[o] in (1, 7, 15, 13, 3) and o not in [t[0] for t in tw]:
            tw.append((o, int(col[o])))
    tw = tw[:24]
    sp = []
    for b, x, y, rgb in st[:12]:
        if y < 150: sp.append((int(24 + x * 2 - 11), int(50 + y - 10)))
    sp = sp[:8]
    tab = bytearray(256)
    tab[0] = len(tw)
    for k, (o, c) in enumerate(tw): tab[1 + k * 3:4 + k * 3] = bytes([o & 255, (o >> 8) + 0xD8, c])
    tab[80] = len(sp)
    for k, (x, y) in enumerate(sp): tab[81 + k * 3:84 + k * 3] = bytes([x & 255, x >> 8, y])
    rgb = np.zeros((H, W, 3), np.uint8)
    for y in range(H):
        for x in range(W):
            rgb[y, x] = PEPTO[csets[y // 8, x // 4][idx[y, x]]]
    return bytes(scr) + bytes(col) + bytes(tab) + bytes(bmp), Image.fromarray(rgb).resize((320, H), Image.NEAREST)

BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16
MIXPEN = float(os.environ.get('MIXPEN', '0.25'))

def ordered(lab, csets):
    # ordered dither (pattern mixing): each pixel picks the pair of its cell's colours (and how much of each, in 16ths)
    # that mixes closest to it, a penalty for mixing far-apart colours; the 4 x 4 Bayer matrix decides which one it shows
    idx = np.zeros((H, W), int)
    ts = np.linspace(0, 1, 17)
    for cy in range(CH):
        for cx in range(CW):
            s = csets[cy, cx]; P = PLAB[s]
            blk = lab[cy * 8:cy * 8 + 8, cx * 4:cx * 4 + 4].reshape(-1, 3)
            best = None
            for i in range(4):
                for j in range(i, 4):
                    mix = P[i][None] + (P[j] - P[i])[None] * ts[:, None]           # 17 x 3
                    d = ((blk[:, None, :] - mix[None]) ** 2).sum(-1)                # 32 x 17
                    d = d + MIXPEN * ((P[i] - P[j]) ** 2).sum() * (ts * (1 - ts))[None] * 4
                    k = d.argmin(1); e = d.min(1)
                    cand = (e, i, j, ts[k])
                    if best is None:
                        best = [cand[0].copy(), np.full(32, i), np.full(32, j), cand[3].copy()]
                    else:
                        m = e < best[0]
                        best[0][m] = e[m]; best[1][m] = i; best[2][m] = j; best[3][m] = ts[k][m]
            ys, xs = np.mgrid[0:8, 0:4]
            thr = BAYER[(ys + cy * 8) % 4, (xs + cx * 4) % 4].reshape(-1)
            pick = np.where(best[3] > thr, best[2], best[1])
            idx[cy * 8:cy * 8 + 8, cx * 4:cx * 4 + 4] = pick.reshape(8, 4)
    return idx

def main():
    src, out = sys.argv[1], sys.argv[2]
    only = [int(a) for a in sys.argv[3:]] if len(sys.argv) > 3 else range(len(VIEWS))
    os.makedirs(out, exist_ok=True)
    full = Image.open(src).convert('RGB')
    if full.width > 4000:                                       # the full-size original: a 4096-wide copy is plenty
        full = full.resize((4096, int(round(4096 * full.height / full.width))), Image.LANCZOS)
    for k in only:
        data, pv = convert(view_crop(full, VIEWS[k]))
        assert len(data) == 10256
        open(os.path.join(out, 'view%d.bin' % k), 'wb').write(bytes([0x00, 0x90]) + data)   # a PRG file (address $9000, not used: the program reads it as bytes)
        pv.resize((960, 3 * H), Image.NEAREST).save(os.path.join(out, 'view%d.png' % k))
        print('view', k, VIEWS[k][3])

if __name__ == '__main__':
    main()
