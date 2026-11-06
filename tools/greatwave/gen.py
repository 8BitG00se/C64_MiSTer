#!/usr/bin/env python3
# gen.py - Great Wave build 1 for the Octophonic 64: turns the scan of Hokusai's "The Great Wave off Kanagawa" (about
# 1831, public domain) into what the 6502 needs. Original work by Mong00se. The PC only prepares data; everything on screen
# is done by wave.asm.
#
#   gen.py SOURCE.jpg OUTDIR [--dither S] [--compare]
#
# Makes in OUTDIR:
#   Great Wave.reu     the REU image the demo uploads into OctoVIC's VRAM before the show:
#                        $000000  the picture, 1024 x 702, 256 colours, 1024 bytes a row (an OctoVIC BITMAP layer, map 128 x 128 tiles)
#                        $0B0000  a half size copy (512 x 351, 512 a row) for the middle zooms
#                        $0E0000  an 11/32 size copy (352 x 241, 512 a row): at the whole-print zoom (32/11) it is shown 1:1, exactly
#                        $100000  the copper lists of the two raster wipes (a band of colour bars), $280 bytes each
#                        palette  256 x R, then 256 x G, then 256 x B
#   data.inc, tables.inc, rows.inc   the numbers wave.asm needs (addresses, counts; the camera path as rows)
#   great wave.oct     320 x 200 for OctoPaint (the whole print fitted, letterbox bars of colour 1 = black)
#   (--compare: PNGs of plain nearest-colour against error diffusion, and the numbers)
import sys, os, math, struct
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from sklearn.cluster import KMeans
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'octopaint'))
import mkoct

# ------------------------------------------------------------------ colour: OKLab, so "close" means close to the eye
M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
def s2l(c): c = c / 255.0; return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def l2s(l): l = np.clip(l, 0, 1); return np.where(l <= 0.0031308, l * 12.92, 1.055 * l ** (1 / 2.4) - 0.055) * 255
def oklab(rgb): return np.cbrt(s2l(rgb.astype(np.float64)) @ M1.T) @ M2.T
def unlab(lab): return np.clip(np.round(l2s(((lab @ np.linalg.inv(M2).T) ** 3) @ np.linalg.inv(M1).T)), 0, 255).astype(np.uint8)

def make_palette(imgs, ncol, seed=1, nsamp=(220000, 60000, 40000), iters=80):
    # k-means in OKLab on a sample of the pictures' pixels; the centres, back to 8-bit sRGB
    rng = np.random.default_rng(seed)
    labs = [oklab(i).reshape(-1, 3) for i in imgs]
    samp = np.vstack([l[rng.choice(len(l), min(len(l), n), replace=False)] for l, n in zip(labs, nsamp)])
    km = KMeans(ncol, n_init=1, max_iter=iters, random_state=seed).fit(samp)
    return unlab(km.cluster_centers_)

def plain(lab, tree):
    return tree.query(lab.reshape(-1, 3))[1].reshape(lab.shape[:2])

def fs(lab, plab, tree, strength, clamp=0.05):
    # Floyd-Steinberg (serpentine) in OKLab; the error is scaled down (strength) and its length limited (clamp)
    H, W, _ = lab.shape; work = lab.copy(); out = np.zeros((H, W), np.int32); q = tree.query
    for y in range(H):
        xs = range(W) if y % 2 == 0 else range(W - 1, -1, -1); dx = 1 if y % 2 == 0 else -1
        for x in xs:
            v = work[y, x]; i = q(v)[1]; out[y, x] = i
            e = (v - plab[i]) * strength; n = np.linalg.norm(e)
            if n > clamp: e *= clamp / n
            xn = x + dx
            if 0 <= xn < W: work[y, xn] += e * (7 / 16)
            if y + 1 < H:
                if 0 <= x - dx < W: work[y + 1, x - dx] += e * (3 / 16)
                work[y + 1, x] += e * (5 / 16)
                if 0 <= xn < W: work[y + 1, xn] += e * (1 / 16)
    return out

# ------------------------------------------------------------------ the layout
W0, H0 = 1024, 702                     # the print is 1920 x 1315 (1.460): 1024 x 701.3, rounded up to an even 702
W1, H1 = 512, 351
W2, H2 = 352, 241                      # 11/32 of the full size
ZW = 32 / 11                           # the whole-print zoom: the 11/32 copy then shows 1:1
# every part starts on a 64 KB boundary: the REU's address counter wraps inside each 512 KB (a 64 KB transfer from a 64 KB
# boundary never crosses one; one that did would read from the start of the same 512 KB instead)
R_PIC0, R_PIC1, R_PIC2 = 0x000000, 0x0B0000, 0x0E0000
R_COP = 0x100000
COPSTRIDE = 0x280
NIN, NOUT, TAIL = 160, 100, 8          # wipe frames (the lists after that repeat the last, so a frame early or late does not show)
BL = 36                                # the band: lines
CTRL1_ON = 0x5B                        # layer 0: on, 256 colours, bitmap, 512 wide (code 1), 512 tall (code 1)

# the colour bars of the wipe: the print's own colours, indigo - prussian blue - sky blue - cream
BARS = [(8, 24, 70), (22, 62, 130), (60, 120, 176), (150, 192, 220), (238, 228, 200), (150, 192, 220), (60, 120, 176), (22, 62, 130)]
def bar_colour(k, f, n):
    # the colour of band line k (0 = top) in wipe frame f: soft bars, shaded dark - bright - dark, drifting colours; the
    # bottom (leading) edge fades to black
    nb, bh = 4, BL // 4
    bi, j = divmod(k, bh)
    shade = math.sin(math.pi * (j + 0.5) / bh) ** 0.8
    pos = ((bi * 0.19 + f * 0.011) % 1.0) * len(BARS)
    i0 = int(pos) % len(BARS); fr = pos - int(pos); c0, c1 = BARS[i0], BARS[(i0 + 1) % len(BARS)]
    rgb = [c0[i] + (c1[i] - c0[i]) * fr for i in range(3)]
    fade = 1.0 if k < BL * 0.6 else max(0.0, 1.0 - (k - BL * 0.6) / (BL * 0.4)) ** 1.3
    s = shade * fade
    return tuple(int(c * s) for c in rgb)

def cop_list(ytop, f, out_mode):
    e = []
    def Wr(line, reg, v):
        if 0 <= line < 300: e.append((line, reg, v & 255))
    Wr(0, 0x19, 2)
    for c in (0x1B, 0x1C, 0x1D): Wr(0, c, 0)
    yb = ytop + BL                                         # the band: lines ytop .. yb-1
    if not out_mode:                                       # in: the picture above the band
        if ytop > 0: Wr(0, 0x20, CTRL1_ON)
        Wr(max(ytop, 0), 0x20, CTRL1_ON & ~1)
    else:                                                  # out: black above the band, the picture below it
        Wr(0, 0x20, CTRL1_ON & ~1)
        Wr(max(yb, 0), 0x20, CTRL1_ON)
    for k in range(BL):
        L = ytop + k
        if 0 <= L < 300:
            for c, v in zip((0x1B, 0x1C, 0x1D), bar_colour(k, f, BL)): Wr(L, c, v)
    if 0 <= yb < 300:
        for c in (0x1B, 0x1C, 0x1D): Wr(yb, c, 0)
    e.sort(key=lambda t: t[0])                              # (stable: the writes of a line stay in order)
    b = bytearray()
    for line, reg, v in e: b += bytes([line & 255, line >> 8, reg, v])
    b += bytes([0xFF, 0xFF, 0, 0])
    assert len(b) <= COPSTRIDE, len(b)
    return bytes(b) + bytes(COPSTRIDE - len(b))

def ytop_at(f, n):
    s = min(1.0, f / (n - 1)); s = 0.7 * s + 0.3 * s * s * (3 - 2 * s)
    return int(round(-BL + 16 + (300 - (16 - BL) ) * s))

# ------------------------------------------------------------------ the camera path
# The camera is (x, y, zoom): the picture pixel (full size, 1024 wide) in the middle of OctoVIC's 396 x 284 view, and how many
# picture pixels one screen pixel is. The 6502 walks the ROWS below: each row goes in a straight line (x, y, zoom) from where
# the last one ended, taking so many frames; the rows are short (3 frames in the eased moves) so the eased moves are smooth, and the 6502 needs no
# curves. Positions are 8.8 pixels, zoom 8.16, so a row's end is not rounded to a pixel (a slow pan would stutter).
K_EASE, K_PAN = 3, 10                   # frames a row takes (the row's own speed is constant: a short row where the speed changes fast)
def smooth(s): return s * s * (3 - 2 * s)
WHOLE = (512.0, H0 / 2, ZW)
BOAT = (200.0, 420.0, 1.0)                                   # the boat in the trough under the wave (1:1: x 2-398)
CREST = [BOAT[:2], (228, 335), (292, 252), (372, 196), (450, 168), (540, 202), (606, 262), (632, 350), (650, 440)]   # up the wave, along the crest, through the claws, down to Fuji
FUJI = (650.0, 440.0, 1.0)
FUJI2 = (650.0, 478.0, 0.5)                                  # 2x into Fuji

def catmull(pts, n=400):
    P = [pts[0]] + list(pts) + [pts[-1]]; out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = (np.array(P[i + j], float) for j in (-1, 0, 1, 2))
        for t in np.linspace(0, 1, n, endpoint=False):
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(np.array(pts[-1], float))
    return np.array(out)

def pan_profile(nfr, ramp=0.2):
    # distance fraction at each frame 0..nfr: a speed that rises and falls as a cosine, flat in between
    t = np.linspace(0, 1, 4001); v = np.ones_like(t)
    a = t < ramp; v[a] = (1 - np.cos(np.pi * t[a] / ramp)) / 2
    b = t > 1 - ramp; v[b] = (1 - np.cos(np.pi * (1 - t[b]) / ramp)) / 2
    u = np.cumsum(v); u = (u - u[0]) / (u[-1] - u[0])
    return np.interp(np.arange(nfr + 1) / nfr, t, u)

def path_rows(spec):
    # spec: (frames, kind, target, event); kinds: hold, ease (x, y straight, zoom in log steps, smoothstep), pan (the spline, target ignored)
    rows = []; cur = WHOLE; tot = 0
    for n, kind, tgt, ev in spec:
        if kind == 'hold':
            rows.append((n, cur, ev)); tot += n; continue
        pts = {}
        if kind == 'ease':
            for f in range(0, n + 1):
                s = smooth(f / n)
                pts[f] = (cur[0] + (tgt[0] - cur[0]) * s, cur[1] + (tgt[1] - cur[1]) * s,
                          math.exp(math.log(cur[2]) + (math.log(tgt[2]) - math.log(cur[2])) * s))
        else:
            sp = catmull(CREST); seg = np.hypot(*np.diff(sp, axis=0).T); cum = np.concatenate([[0], np.cumsum(seg)])
            u = pan_profile(n) * cum[-1]
            for f in range(0, n + 1):
                pts[f] = (float(np.interp(u[f], cum, sp[:, 0])), float(np.interp(u[f], cum, sp[:, 1])), 1.0)
            tgt = pts[n]
        f = 0; K = K_EASE if kind == 'ease' else K_PAN
        while f < n:
            g = min(n, f + K)
            if n - g < K // 2 and g != n: g = n
            rows.append((g - f, pts[g], ev if f == 0 else 0)); f = g
        cur = pts[n]; tot += n
    return rows, tot

SPEC = [
    (25,   'hold', None, 0),                    # black
    (160,  'hold', None, 1),                    # the wipe: the whole print appears behind the colour bars
    (200,  'hold', None, 2),                    # hold 4 s (the title)
    (200,  'ease', BOAT, 0),                    # glide left: the boat in the trough
    (30,   'hold', None, 0),
    (1000, 'pan',  None, 0),                    # up the wave, along the crest, through the claws, down to Fuji
    (100,  'hold', None, 0),                    # a pause on Fuji, framed under the wave
    (150,  'ease', FUJI2, 0),                   # zoom into Fuji, 2x
    (100,  'hold', None, 0),
    (250,  'ease', WHOLE, 0),                   # zoom back out to the whole print
    (175,  'hold', None, 3),                    # the credit
    (100,  'hold', None, 4),                    # the wipe out
    (60,   'hold', None, 0),                    # black
]

def b24(v): v = int(round(v)); v &= 0xFFFFFF; return '%d,%d,%d' % (v & 255, (v >> 8) & 255, v >> 16)

def rows_inc(rows):
    out = ['; made by gen.py - do not edit', '; row: frames (16), x (8.8, 24 bits), y (8.8), zoom (8.16), event']
    out.append('keyfit  !byte %s, %s, %s' % (b24(WHOLE[0] * 256), b24(WHOLE[1] * 256), b24(WHOLE[2] * 65536)))
    out.append('rows')
    for n, (x, y, z), ev in rows:
        out.append('        !word %d : !byte %s, %s, %s, %d' % (n, b24(x * 256), b24(y * 256), b24(z * 65536), ev))
    out.append('        !word 0')
    return '\n'.join(out) + '\n'

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    src, out = args[0], args[1]
    dith = 0.0; compare = '--compare' in sys.argv
    if '--dither' in sys.argv: dith = float(sys.argv[sys.argv.index('--dither') + 1])
    os.makedirs(out, exist_ok=True)
    im = Image.open(src).convert('RGB')
    sizes = ((W0, H0), (W1, H1), (W2, H2))
    pics = [Image.fromarray(np.asarray(im.resize(s, Image.LANCZOS))) for s in sizes]
    pal = np.zeros((256, 3), np.uint8)
    pal[1:255] = make_palette([np.asarray(p) for p in pics], 254)    # entry 0 stays unused (see-through on a layer); 255 is the captions' shadow
    plab = oklab(pal[1:255]); tree = cKDTree(plab)
    labs = [oklab(np.asarray(p)) for p in pics]
    ixs = [plain(l, tree) + 1 for l in labs]
    if compare or dith > 0:
        import cv2
        d0 = fs(labs[0], plab, tree, dith or 0.5) + 1
        for name, ix in (('plain', ixs[0]), ('dither%.1f' % (dith or 0.5), d0)):
            img = pal[ix]; Image.fromarray(img).save(os.path.join(out, 'compare_%s.png' % name))
            l2 = oklab(img); de = np.linalg.norm(l2 - labs[0], axis=2).mean() * 100
            b1 = cv2.GaussianBlur(labs[0].astype(np.float32), (0, 0), 1.5); b2 = cv2.GaussianBlur(l2.astype(np.float32), (0, 0), 1.5)
            print('%-10s mean colour error (OKLab x100) %.2f, blurred %.2f' % (name, de, np.linalg.norm(b1 - b2, axis=2).mean() * 100))
        if dith > 0:
            ixs[0] = d0
            for k in (1, 2): ixs[k] = fs(labs[k], plab, tree, dith) + 1
    assert all(ix.min() >= 1 and ix.max() <= 254 for ix in ixs)
    # --- the bitmaps, rows 1024 / 512 bytes apart (width code 2 = 1024 and 1 = 512)
    pic0 = np.zeros((H0, 1024), np.uint8); pic0[:, :W0] = ixs[0]
    pic1 = np.zeros((H1, 512), np.uint8); pic1[:, :W1] = ixs[1]
    pic2 = np.zeros((H2, 512), np.uint8); pic2[:, :W2] = ixs[2]
    reu = bytearray(R_COP)
    for r, p in ((R_PIC0, pic0), (R_PIC1, pic1), (R_PIC2, pic2)): reu[r:r + p.size] = p.tobytes()
    lists = bytearray()
    for f in range(NIN + TAIL): lists += cop_list(ytop_at(min(f, NIN - 1), NIN), f, False)
    for f in range(NOUT + TAIL): lists += cop_list(ytop_at(min(f, NOUT - 1), NOUT), f, True)
    lists += bytes([0xFF, 0xFF, 0, 0]) + bytes(COPSTRIDE - 4)            # the empty list (the 6510 sets the layer and the picture)
    reu += lists
    reu += bytes(-len(reu) % 0x10000)
    R_PAL = len(reu)
    reu += bytes(pal[:, 0]) + bytes(pal[:, 1]) + bytes(pal[:, 2])
    open(os.path.join(out, 'Great Wave.reu'), 'wb').write(reu)
    # --- data.inc
    V_PIC1, V_PIC2, V_COP = 0x100000, 0x140000, 0x200000
    inc = ['; made by gen.py - do not edit',
           'R_PIC0 = $%06x' % R_PIC0, 'LEN_PIC0 = $%06x' % pic0.size, 'R_PIC1 = $%06x' % R_PIC1, 'LEN_PIC1 = $%06x' % pic1.size,
           'R_PIC2 = $%06x' % R_PIC2, 'LEN_PIC2 = $%06x' % pic2.size,
           'R_COP = $%06x' % R_COP, 'LEN_COP = $%06x' % len(lists), 'R_PAL = $%06x' % R_PAL,
           'V_PIC0 = $000000', 'V_PIC1 = $%06x' % V_PIC1, 'V_PIC2 = $%06x' % V_PIC2, 'V_COP = $%06x' % V_COP, 'COPSTRIDE = $%04x' % COPSTRIDE,
           'NIN = %d' % NIN, 'NOUT = %d' % NOUT, 'NLISTIN = %d' % (NIN + TAIL), 'NLISTOUT = %d' % (NOUT + TAIL),
           'L_IN = V_COP', 'L_OUT = V_COP + %d * COPSTRIDE' % (NIN + TAIL), 'L_EMPTY = V_COP + %d * COPSTRIDE' % (NIN + TAIL + NOUT + TAIL),
           'REU_TOTAL = $%06x' % len(reu)]
    open(os.path.join(out, 'data.inc'), 'w').write('\n'.join(inc) + '\n')
    rows, tot = path_rows(SPEC)
    open(os.path.join(out, 'rows.inc'), 'w').write(rows_inc(rows))
    np.save(os.path.join(out, 'path.npy'), np.array([(n, x, y, z, ev) for n, (x, y, z), ev in rows]))
    # --- Great Wave.oct for OctoPaint: 320 x 200, the whole print, letterbox bars of colour 1 (black), its own palette
    w = int(round(200 * im.width / im.height)); small = im.resize((w, 200), Image.LANCZOS)
    opal = np.zeros((256, 3), np.uint8)
    opal[2:] = make_palette([np.asarray(small)], 254, seed=2, nsamp=(60000,))   # 0 black (see-through, unused), 1 black (the bars), 2-255 the picture
    ot = cKDTree(oklab(opal[2:]))
    oix = plain(oklab(np.asarray(small)), ot) + 2
    canvas = np.ones((200, 320), np.uint8); x0 = (320 - w) // 2; canvas[:, x0:x0 + w] = oix
    blob = mkoct.make_oct(canvas.tobytes(), [tuple(int(c) for c in r) for r in opal])
    open(os.path.join(out, 'great wave.oct'), 'wb').write(blob)
    w2, h2, p2, px2 = mkoct.read_oct(blob)                                # the file reads back to the same picture
    assert (w2, h2) == (320, 200) and px2 == canvas.tobytes() and p2[1] == (0, 0, 0)
    Image.fromarray(np.array([p2[v] for v in px2], np.uint8).reshape(200, 320, 3)).save(os.path.join(out, 'oct_preview.png'))
    print('reu %d bytes (picture %d + half %d + small %d + copper %d + palette 768); oct %d bytes; %d camera rows, %d frames (%.1f s)'
          % (len(reu), pic0.size, pic1.size, pic2.size, len(lists), len(blob), len(rows), tot, tot / 50.0))

if __name__ == '__main__':
    main()
