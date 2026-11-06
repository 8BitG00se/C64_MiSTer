#!/usr/bin/env python3
# gen.py - Starry Night build 1 for the Octophonic 64: turns the scan of The Starry Night (1889, public domain) into
# what the 6502 needs. Original work by Mong00se. The PC only prepares data; everything on screen is done by starry.asm.
#
#   gen.py SOURCE.jpg OUTDIR [--dither S] [--compare]
#
# Makes in OUTDIR:
#   Starry Night.reu    the REU image the demo uploads into OctoVIC's VRAM before the show:
#                         $000000  the picture, 1024 x 816, 256 colours, 1024 bytes a row (an OctoVIC BITMAP layer, map 128 x 128 tiles)
#                         $0D0000  a half size copy (512 x 408, 512 a row): the zoomed-out views use it, so they are an averaged
#                                  (not a point sampled, speckled) picture
#                         $110000  the copper lists of the two raster wipes (a band of colour bars), $280 bytes each
#                         palette  256 x R, then 256 x G, then 256 x B
#   data.inc, tables.inc  the numbers starry.asm needs (addresses, counts; the sine table)
#   Starry Night.oct    320 x 200 for OctoPaint (the whole painting, letterbox bars of colour 1 = black)
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

def make_palette(imgs, ncol, seed=1):
    # k-means in OKLab on a sample of the pictures' pixels; the centres, back to 8-bit sRGB
    rng = np.random.default_rng(seed)
    labs = [oklab(i).reshape(-1, 3) for i in imgs]
    samp = np.vstack([l[rng.choice(len(l), min(len(l), n), replace=False)] for l, n in zip(labs, (220000, 60000))])
    km = KMeans(ncol, n_init=1, max_iter=80, random_state=seed).fit(samp)
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
W0, H0 = 1024, 816
W1, H1 = 512, 408
# every part starts on a 64 KB boundary: the REU's address counter wraps inside each 512 KB (a 64 KB transfer from a 64 KB
# boundary never crosses one; one that did would read from the start of the same 512 KB instead)
R_PIC0, R_PIC1 = 0x000000, 0x0D0000
R_COP = 0x110000
COPSTRIDE = 0x280
NIN, NOUT, TAIL = 160, 100, 8          # wipe frames (the lists after that repeat the last, so a frame early or late does not show)
BL = 36                                # the band: lines
CTRL1_ON = 0x5B                        # layer 0: on, 256 colours, bitmap, 512 wide (code 1), 512 tall (code 1)

def bar_colour(k, f, n):
    # the colour of band line k (0 = top) in wipe frame f: soft bars, shaded dark - bright - dark, drifting colours; the
    # bottom (leading) edge fades to black
    nb, bh = 4, BL // 4
    bi, j = divmod(k, bh)
    shade = math.sin(math.pi * (j + 0.5) / bh) ** 0.8
    hue = (bi * 0.17 + f * 0.012) % 1.0
    import colorsys
    r, g, b = colorsys.hsv_to_rgb(hue, 0.78, 1.0)
    fade = 1.0 if k < BL * 0.6 else max(0.0, 1.0 - (k - BL * 0.6) / (BL * 0.4)) ** 1.3
    s = shade * fade
    return tuple(int(255 * c * s) for c in (r, g, b))

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

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    src, out = args[0], args[1]
    dith = 0.0; compare = '--compare' in sys.argv
    if '--dither' in sys.argv: dith = float(sys.argv[sys.argv.index('--dither') + 1])
    os.makedirs(out, exist_ok=True)
    im = Image.open(src).convert('RGB')
    p0 = Image.fromarray(np.asarray(im.resize((W0, H0), Image.LANCZOS)))
    p1 = Image.fromarray(np.asarray(im.resize((W1, H1), Image.LANCZOS)))
    pal = np.zeros((256, 3), np.uint8)
    pal[1:255] = make_palette([np.asarray(p0), np.asarray(p1)], 254)    # entry 0 stays unused (see-through on a layer); 255 is the captions' shadow
    plab = oklab(pal[1:255]); tree = cKDTree(plab)
    lab0, lab1 = oklab(np.asarray(p0)), oklab(np.asarray(p1))
    ix0, ix1 = plain(lab0, tree) + 1, plain(lab1, tree) + 1
    if compare or dith > 0:
        import cv2
        d0 = fs(lab0, plab, tree, dith or 0.5) + 1
        for name, ix in (('plain', ix0), ('dither%.1f' % (dith or 0.5), d0)):
            img = pal[ix]; Image.fromarray(img).save(os.path.join(out, 'compare_%s.png' % name))
            l2 = oklab(img); de = np.linalg.norm(l2 - lab0, axis=2).mean() * 100
            b1 = cv2.GaussianBlur(lab0.astype(np.float32), (0, 0), 1.5); b2 = cv2.GaussianBlur(l2.astype(np.float32), (0, 0), 1.5)
            print('%-10s mean colour error (OKLab x100) %.2f, blurred %.2f' % (name, de, np.linalg.norm(b1 - b2, axis=2).mean() * 100))
        if dith > 0: ix0 = d0
    assert ix0.min() >= 1 and ix1.min() >= 1 and ix0.max() <= 254 and ix1.max() <= 254
    # --- the bitmaps, rows 1024 / 512 bytes apart (width code 2 = 1024 and 1 = 512)
    pic0 = np.zeros((H0, 1024), np.uint8); pic0[:, :W0] = ix0
    pic1 = np.zeros((H1, 512), np.uint8); pic1[:, :W1] = ix1
    reu = bytearray(R_COP)
    reu[R_PIC0:R_PIC0 + pic0.size] = pic0.tobytes()
    reu[R_PIC1:R_PIC1 + pic1.size] = pic1.tobytes()
    lists = bytearray()
    for f in range(NIN + TAIL): lists += cop_list(ytop_at(min(f, NIN - 1), NIN), f, False)
    for f in range(NOUT + TAIL): lists += cop_list(ytop_at(min(f, NOUT - 1), NOUT), f, True)
    lists += bytes([0xFF, 0xFF, 0, 0]) + bytes(COPSTRIDE - 4)            # the empty list (the 6510 sets the layer and the picture)
    reu += lists
    reu += bytes(-len(reu) % 0x10000)
    R_PAL = len(reu)
    reu += bytes(pal[:, 0]) + bytes(pal[:, 1]) + bytes(pal[:, 2])
    open(os.path.join(out, 'Starry Night.reu'), 'wb').write(reu)
    # --- data.inc
    V_PIC1, V_COP = 0x100000, 0x200000
    inc = ['; made by gen.py - do not edit',
           'R_PIC0 = $%06x' % R_PIC0, 'LEN_PIC0 = $%06x' % pic0.size, 'R_PIC1 = $%06x' % R_PIC1, 'LEN_PIC1 = $%06x' % pic1.size,
           'R_COP = $%06x' % R_COP, 'LEN_COP = $%06x' % len(lists), 'R_PAL = $%06x' % R_PAL,
           'V_PIC0 = $000000', 'V_PIC1 = $%06x' % V_PIC1, 'V_COP = $%06x' % V_COP, 'COPSTRIDE = $%04x' % COPSTRIDE,
           'NIN = %d' % NIN, 'NOUT = %d' % NOUT, 'NLISTIN = %d' % (NIN + TAIL), 'NLISTOUT = %d' % (NOUT + TAIL),
           'L_IN = V_COP', 'L_OUT = V_COP + %d * COPSTRIDE' % (NIN + TAIL), 'L_EMPTY = V_COP + %d * COPSTRIDE' % (NIN + TAIL + NOUT + TAIL),
           'REU_TOTAL = $%06x' % len(reu)]
    sin = [int(round(65535 * math.sin(math.pi * i / 256))) for i in range(257)]       # one half wave, 257 points
    open(os.path.join(out, 'data.inc'), 'w').write('\n'.join(inc) + '\n')
    open(os.path.join(out, 'tables.inc'), 'w').write('sinlo !byte ' + ','.join(str(v & 255) for v in sin) + '\nsinhi !byte ' + ','.join(str(v >> 8) for v in sin) + '\n')
    # --- Starry Night.oct for OctoPaint: 320 x 200, the whole painting, letterbox bars of colour 1 (black), its own palette
    w = int(round(200 * im.width / im.height)); small = im.resize((w, 200), Image.LANCZOS)
    opal = np.zeros((256, 3), np.uint8)
    opal[2:] = make_palette([np.asarray(small)], 254, seed=2)            # 0 black (see-through, unused), 1 black (the bars), 2-255 the picture
    ot = cKDTree(oklab(opal[2:]))
    oix = plain(oklab(np.asarray(small)), ot) + 2
    canvas = np.ones((200, 320), np.uint8); x0 = (320 - w) // 2; canvas[:, x0:x0 + w] = oix
    blob = mkoct.make_oct(canvas.tobytes(), [tuple(int(c) for c in r) for r in opal])
    open(os.path.join(out, 'Starry Night.oct'), 'wb').write(blob)
    w2, h2, p2, px2 = mkoct.read_oct(blob)                                # the file reads back to the same picture
    assert (w2, h2) == (320, 200) and px2 == canvas.tobytes() and p2[1] == (0, 0, 0)
    Image.fromarray(np.array([p2[v] for v in px2], np.uint8).reshape(200, 320, 3)).save(os.path.join(out, 'oct_preview.png'))
    print('reu %d bytes (picture %d + half %d + copper %d + palette 768); oct %d bytes' % (len(reu), pic0.size, pic1.size, len(lists), len(blob)))

if __name__ == '__main__':
    main()
