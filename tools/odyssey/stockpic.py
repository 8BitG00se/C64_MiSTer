#!/usr/bin/env python3
# (C) 2026 Mong00se. All rights reserved.
# ODYSSEY - the stock C64 pictures: the Webb "Cosmic Cliffs" (NASA, ESA, CSA, STScI) as four multicolour bitmaps
# (160 x 192 shown, 4 x 8 cells, black background + 3 colours a cell), plus the tables the 6502 needs for its live effects:
# the star cells it twinkles and the brightest stars for the sparkle sprites.
# For Neal's private use (the photo conversion) - not part of a public release. The PC only prepares data, like a paint
# program; everything that moves is done by the 6502 (show.asm, fx.asm).
#
#   stockpic.py SOURCE.jpg OUTDIR [VIEW ...]
#       -> OUTDIR/view0.bin .. view3.bin   the disk files (packed, see below)
#          OUTDIR/view0.png .. view3.png   each picture as the C64 shows it (palette 0 of the core)
#          OUTDIR/stock_views.png          a contact sheet of all four
#
# THE FOUR VIEWS are tight crops of the photo that have strong shapes - the cliff edge against the blue and its glowing
# star, the hook-shaped western peak, the golden ridge, the eastern cliffs under the 8-point star - not the whole picture,
# which turns into orange mush in 4 colours a cell. The tour cuts between them in time with the music's phrases.
#
# HOW A VIEW IS MADE (the steps a C64 scener would take by hand):
#   1. the crop, area-averaged to 160 x 192 in linear light, to Oklab (a space where distance is what the eye sees)
#   2. the sky (blue) and the cliffs (warm) told apart by hue; each gets its own tone map: local contrast first (an unsharp
#      mask for the folds and ridges, a wide one for the big shapes), then the lightness is spread over a hand-made colour
#      ramp - sky: black, blue, light blue, cyan, white; cliffs: black, dark brown, brown, (light red where the gas is
#      rosy), yellow, white - so the bright rims come out gold and the shadows deep, and nothing collapses to one orange
#   3. the stars (white top-hat peaks) are put back crisp, and the diffraction spikes of the bright ones come with them
#   4. every 4 x 8 cell gets the best 3 colours (+ black) from 10 the picture may use (all 120 sets tried against the
#      dithered cell, the stars weighing most), then an ordered (Bayer) pattern mix of the cell's colours, which keeps
#      edges clean and gradients regular - and packs well on the disk
#
# THE DISK FILE (loaded by show.asm, unpacked while it loads):
#   2 bytes   a PRG address ($9000, not used)
#   packed    2256 bytes: screen colours (1000: hi nibble = bits 01, lo = bits 10), colour RAM (1000: bits 11), the
#             table (256): n twinkles x (colour RAM lo, hi, its own colour) from byte 0; the sparkle stars from byte 80:
#             n, then n x (sprite x lo, x hi, y)
#   packed    8000 bytes: the bitmap
#   The packing is a small LZ (pack() below; unpack in show.asm): token $00-$7F = a run of token+1 literal bytes; $80-$BF =
#   copy (token&$3F)+2 bytes from a distance (next byte, 1-255) back; $C0-$FF = the same with a 16 bit distance (lo, hi).
import sys, os
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from itertools import combinations
Image.MAX_IMAGE_PIXELS = None

# the C64 colours as the Octophonic core shows them by default (rtl/fpga64_rgbcolor.vhd, palette 0)
PEPTO = np.array([(0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x81, 0x33, 0x38), (0x75, 0xce, 0xc8), (0x8e, 0x3c, 0x97), (0x56, 0xac, 0x4d),
                  (0x2e, 0x2c, 0x9b), (0xed, 0xf1, 0x71), (0x8e, 0x50, 0x29), (0x55, 0x38, 0x00), (0xc4, 0x6c, 0x71), (0x4a, 0x4a, 0x4a),
                  (0x7b, 0x7b, 0x7b), (0xa9, 0xff, 0x9f), (0x70, 0x6d, 0xeb), (0xb2, 0xb2, 0xb2)], np.float64)
M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
def s2l(c): c = c / 255.0; return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def lin2lab(c): return np.cbrt(np.asarray(c, np.float64) @ M1.T) @ M2.T
def oklab(rgb): return lin2lab(s2l(np.asarray(rgb, np.float64)))
PLAB0 = oklab(PEPTO)
W, H = 160, 192                     # multicolour pixels shown (the 25th text row is the scroller)
CW, CH = 40, 24
ALLOWED = [0, 1, 2, 3, 6, 7, 8, 9, 10, 14]   # black, white, red, cyan, blue, yellow, brown, dark brown, light red, light blue
WAB = 3.0                           # how much hue/chroma counts against lightness in the error
NSTARS = 48
MIXPEN = 0.12                       # the ordered dither's penalty for mixing far-apart colours
ASP = 320 * 0.936 / 192             # the shown shape: a PAL pixel is 0.936 as wide as tall -> 1.56 : 1

# the colour ramps (colour, where on the ramp as a fraction of the family's tone range)
RAMPS = {
    'gold': ([0, 9, 8, 7, 1], [0, 0.30, 0.58, 0.92, 1.0]),
    'rose': ([0, 9, 2, 10, 7, 1], [0, 0.28, 0.44, 0.64, 0.92, 1.0]),
    'sky': ([0, 6, 14, 3, 1], [0, 0.38, 0.60, 0.79, 1.0]),
}

# the views: crops of the photo in its 1280-wide coordinates (left, top, width; the height follows from 1.56 : 1),
# their names (what the scroll text says) and what each one needs tuned
VIEWS = [
    dict(name='THE CLIFF EDGE', box=(330, 130, 500), p=dict(wide=1.2, usm=1.0)),
    dict(name='THE WESTERN PEAK', box=(180, 120, 400), p=dict(wide=1.2, usm=1.0)),
    dict(name='THE GOLDEN RIDGE', box=(600, 190, 440), p=dict(wide=1.8, usm=1.3, wide_s=10)),
    dict(name='THE EASTERN STARS', box=(820, 50, 460), p=dict(wide=1.2, usm=1.0)),
]
DEFAULT = dict(usm=0.9, usm_s=1.0, usm_sky=0.3, sky_smooth=0.8, wide=1.0, wide_s=6.0, glo=2, ghi=99.5, warm_gam=0.85, sky_gam=1.0,
               rose=0.5, hue_lo=22, hue_hi=48)

def view_crop(full, v):
    x, y, w = v['box']; h = w / ASP; S = full.width / 1280.0
    return full.crop((int(x * S), int(y * S), int((x + w) * S), int((y + h) * S)))

def stars(im):
    # the stars: peaks of a white top-hat on a 640-wide copy; position in multicolour pixels, brightness, colour
    sm = im.resize((640, int(round(640 * im.height / im.width))), Image.LANCZOS)
    a = np.asarray(sm, np.float64); L = a.mean(axis=2)
    th = L - ndimage.grey_opening(L, size=(7, 7))
    mx = ndimage.maximum_filter(th, size=9)
    pk = np.argwhere((th == mx) & (th > 60))
    out = [(th[y, x], x * W / sm.width, y * H / sm.height, a[y, x]) for y, x in pk]
    out.sort(key=lambda t: -t[0])
    return out

def ramp(name, t):
    cols, stops = RAMPS[name]; stops = np.array(stops, float)
    R = PLAB0[cols]; t = np.clip(t, 0, 1)
    i = np.clip(np.searchsorted(stops, t, side='right') - 1, 0, len(stops) - 2)
    f = ((t - stops[i]) / (stops[i + 1] - stops[i]))[..., None]
    return R[i] * (1 - f) + R[i + 1] * f

def prepare(im, p):
    # the target: 160 x 192 in linear light, to Oklab, then tone-mapped onto the sky and cliff colour ramps
    a = np.asarray(im.convert('RGB').resize((W * 4, H * 4), Image.LANCZOS), np.float32)
    import cv2
    lin = cv2.resize(s2l(a).astype(np.float32), (W, H), interpolation=cv2.INTER_AREA)
    lab = lin2lab(lin)
    L = lab[..., 0]; A = lab[..., 1]; B = lab[..., 2]
    w = np.clip((B + 0.3 * A + 0.01) / 0.03, 0, 1); w = w * w * (3 - 2 * w)       # 1: warm (the cliffs), 0: blue (the sky)
    w = ndimage.gaussian_filter(w, 0.8)
    Ls = ndimage.gaussian_filter(L, p['sky_smooth'])                              # the sky is smoothed: its faint stars are noise
    Lw = w * L + (1 - w) * Ls
    Lc = (Lw + (w * p['usm'] + (1 - w) * p['usm_sky']) * (Lw - ndimage.gaussian_filter(Lw, p['usm_s']))
          + p['wide'] * (Lw - ndimage.gaussian_filter(Lw, p['wide_s'])))
    ang = ndimage.gaussian_filter(np.degrees(np.arctan2(B, A)), 1.0)
    wr = np.clip((p['hue_hi'] - ang) / (p['hue_hi'] - p['hue_lo']), 0, 1) * p['rose']      # 1: the rosy gas
    out = np.zeros(lab.shape, np.float64)
    for fam, wt, gam in (('warm', w, p['warm_gam']), ('sky', 1 - w, p['sky_gam'])):
        sel = wt > 0.5
        ref = Lc[sel] if sel.sum() > 80 else Lc.ravel()
        lo, hi = np.percentile(ref, p['glo']), np.percentile(ref, p['ghi'])
        t = np.clip((Lc - lo) / max(1e-3, hi - lo), 0, 1) ** gam
        if fam == 'warm': col = ramp('gold', t) * (1 - wr[..., None]) + ramp('rose', t) * wr[..., None]
        else: col = ramp('sky', t)
        out += col * wt[..., None]
    return out

def choose_cells(lab, starmask, plab, bg=0):
    # every cell: the 3 colours (+ black) that give the least error after dithering, all triples of ALLOWED tried at once
    tri = np.array(list(combinations([c for c in ALLOWED if c != bg], 3)))     # T x 3
    T = len(tri)
    sets = np.concatenate([np.full((T, 1), bg), tri], axis=1)                   # T x 4
    cells = lab.reshape(CH, 8, CW, 4, 3).transpose(0, 2, 1, 3, 4).reshape(CH * CW, 32, 3)
    wts = starmask.reshape(CH, 8, CW, 4).transpose(0, 2, 1, 3).reshape(CH * CW, 32)
    best = np.zeros(CH * CW, int)
    P = plab[sets]                                                              # T x 4 x 3
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

BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16

def ordered(lab, csets, plab):
    # ordered dither (pattern mixing): each pixel picks the pair of its cell's colours (and how much of each, in 16ths)
    # that mixes closest to it, a penalty for mixing far-apart colours; the 4 x 4 Bayer matrix decides which one it shows
    idx = np.zeros((H, W), int)
    ts = np.linspace(0, 1, 17)
    for cy in range(CH):
        for cx in range(CW):
            s = csets[cy, cx]; P = plab[s]
            blk = lab[cy * 8:cy * 8 + 8, cx * 4:cx * 4 + 4].reshape(-1, 3)
            best = None
            for i in range(4):
                for j in range(i, 4):
                    mix = P[i][None] + (P[j] - P[i])[None] * ts[:, None]           # 17 x 3
                    d = ((blk[:, None, :] - mix[None]) ** 2).sum(-1)                # 32 x 17
                    d = d + MIXPEN * ((P[i] - P[j]) ** 2).sum() * (ts * (1 - ts))[None] * 4
                    k = d.argmin(1); e = d.min(1)
                    if best is None:
                        best = [e.copy(), np.full(32, i), np.full(32, j), ts[k].copy()]
                    else:
                        m = e < best[0]
                        best[0][m] = e[m]; best[1][m] = i; best[2][m] = j; best[3][m] = ts[k][m]
            ys, xs = np.mgrid[0:8, 0:4]
            thr = BAYER[(ys + cy * 8) % 4, (xs + cx * 4) % 4].reshape(-1)
            pick = np.where(best[3] > thr, best[2], best[1])
            idx[cy * 8:cy * 8 + 8, cx * 4:cx * 4 + 4] = pick.reshape(8, 4)
    return idx

def convert(im, p):
    q = dict(DEFAULT); q.update(p)
    lab = prepare(im, q)
    st = stars(im)
    starmask = np.zeros((H, W))
    for b, x, y, rgb in st[:NSTARS]:                                # the stars, crisp: near white with their tint
        xi, yi = int(x), int(y)
        if 0 <= xi < W and 0 <= yi < H - 1:
            c = oklab(np.clip(rgb * 1.5 + 40, 0, 255)); c[0] = max(c[0], 0.85)
            lab[yi, xi] = c; starmask[yi, xi] = 1
    lab[H - 1] = PLAB0[0]                                           # the last line black (the scroller's row is just below it)
    wt = np.array([1, WAB, WAB]); plab = PLAB0 * wt; lab = lab * wt
    csets = choose_cells(lab, starmask, plab)
    idx = ordered(lab, csets, plab)
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
    for b, x, y, rgb in st[:NSTARS + 12]:
        o = int(y) // 8 * 40 + int(x) // 4
        if o < 960 and n3[o] <= 3 and col[o] in (1, 7, 15, 13, 3) and o not in [t[0] for t in tw]:
            tw.append((o, int(col[o])))
    tw = tw[:24]
    # sparkle stars: the brightest, not too near one another, clear of the bottom (the equaliser) rows
    sp = []
    for b, x, y, rgb in st:
        if y < 150 and all((x - sx) ** 2 + (y - sy) ** 2 > 16 ** 2 for sx, sy, _ in sp): sp.append((x, y, b))
        if len(sp) == 8: break
    sp = [(int(24 + x * 2 - 11), int(50 + y - 10)) for x, y, _ in sp]
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

# ------------------------------------------------------------------------------------------------ the packer
def pack(data):
    """the disk packing (show.asm's unpack): an optimal parse into literal runs and copies of earlier output"""
    n = len(data); d = bytes(data); INF = 10 ** 9
    cost = [INF] * (n + 1); cost[0] = 0; how = [None] * (n + 1)
    pos = {}
    for i in range(n + 1):
        ci = cost[i]
        if ci >= INF: continue
        for k in range(1, min(128, n - i) + 1):                        # a run of k literals: a token and k bytes
            c = ci + k + 1
            if c < cost[i + k]: cost[i + k] = c; how[i + k] = ('L', i, k)
        if i + 2 <= n:
            best = {}
            for j in reversed(pos.get(d[i:i + 2], [])[-600:]):
                dist = i - j; l = 2; mx = min(65, n - i)
                while l < mx and d[j + l] == d[i + l]: l += 1           # (a copy may overlap what it makes)
                for ll in range(2, l + 1):
                    if ll not in best or dist < best[ll]: best[ll] = dist
            for ll, dist in best.items():
                c = ci + (2 if dist < 256 else 3)
                if c < cost[i + ll]: cost[i + ll] = c; how[i + ll] = ('M', i, ll, dist)
            pos.setdefault(d[i:i + 2], []).append(i)
    seq = []; i = n
    while i > 0: h = how[i]; seq.append(h); i = h[1]
    o = bytearray()
    for h in reversed(seq):
        if h[0] == 'L': o.append(h[2] - 1); o += d[h[1]:h[1] + h[2]]
        else:
            _, a, l, dist = h
            o += bytes([0x80 | (l - 2), dist]) if dist < 256 else bytes([0xC0 | (l - 2), dist & 255, dist >> 8])
    return bytes(o)

def unpack(p, n):
    o = bytearray(); i = 0
    while len(o) < n:
        t = p[i]; i += 1
        if t < 0x80: o += p[i:i + t + 1]; i += t + 1
        else:
            l = (t & 0x3f) + 2
            if t & 0x40: dist = p[i] | (p[i + 1] << 8); i += 2
            else: dist = p[i]; i += 1
            for _ in range(l): o.append(o[-dist])
    return bytes(o[:n])

def contact_sheet(pngs, names, path):
    w, h = pngs[0].size; s = 2
    sh = Image.new('RGB', (2 * w * s + 30, 2 * (h * s + 28) + 10), (12, 12, 16))
    dr = ImageDraw.Draw(sh)
    for i, (im, nm) in enumerate(zip(pngs, names)):
        x = 10 + (i % 2) * (w * s + 10); y = 8 + (i // 2) * (h * s + 28 + 0)
        sh.paste(im.resize((w * s, h * s), Image.NEAREST), (x, y + 18))
        dr.text((x, y + 3), '%d  %s' % (i, nm), fill=(220, 220, 230))
    sh.save(path)

def main():
    src, out = sys.argv[1], sys.argv[2]
    only = [int(a) for a in sys.argv[3:]] if len(sys.argv) > 3 else range(len(VIEWS))
    os.makedirs(out, exist_ok=True)
    full = Image.open(src).convert('RGB')
    if full.width > 5000:                                       # the full-size original: a 5120-wide copy is plenty
        full = full.resize((5120, int(round(5120 * full.height / full.width))), Image.LANCZOS)
    pngs = []
    for k in only:
        v = VIEWS[k]
        data, pv = convert(view_crop(full, v), v['p'])
        assert len(data) == 10256
        p1, p2 = pack(data[:2256]), pack(data[2256:])
        assert unpack(p1, 2256) == data[:2256] and unpack(p2, 8000) == data[2256:]
        f = bytes([0x00, 0x90]) + p1 + p2                         # a PRG file (address $9000, not used: the program unpacks it)
        open(os.path.join(out, 'view%d.bin' % k), 'wb').write(f)
        pv = pv.resize((640, 2 * H), Image.NEAREST)
        pv.save(os.path.join(out, 'view%d.png' % k)); pngs.append(pv)
        print('view', k, v['name'], len(f), 'bytes,', (len(f) + 253) // 254, 'blocks')
    if len(pngs) == 4: contact_sheet(pngs, [v['name'].title() for v in VIEWS], os.path.join(out, 'stock_views.png'))

if __name__ == '__main__':
    main()
