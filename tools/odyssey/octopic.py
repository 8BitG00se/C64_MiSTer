#!/usr/bin/env python3
# (C) 2026 Mong00se
# ODYSSEY - the Octophonic picture: the Webb "Cosmic Cliffs" (NASA, ESA, CSA, STScI) in 256 colours for OctoVIC's turned-
# and-sized bitmap layer, the camera's path, the sprites' graphics, and the .reu that carries it all (with the music for
# SIDs 3-8 from song.py). Made from Mona Lisa's gen.py. For Neal's private use (the photo conversion) - not part of a
# public release. The PC only prepares data, like a paint program; everything that moves is done by the 6502 (OCTO.ASM).
#
#   octopic.py SOURCE.jpg MUSIC8.bin SONGLEN OUT.reu   (SOURCE: cliffs_large.jpg if there, else the 1280 copy - any size)
#
# The .reu (every part on a 64 KB boundary: the REU's address counter wraps inside each 512 KB):
#   $000000  "ODYSSEY1", "(C) 2026 MONG00SE. ALL RIGHTS RESERVED.", then at +64 a list of the parts, 6 bytes each
#            (REU address, length, 24 bits each): 0 the picture 2048 wide, 1 the half size, 2 the quarter size,
#            3 the palette (R, G, B x 256), 4 the sprites' graphics, 5 the camera's path, 6 the sparkle stars, 7 the music
#   The 6502 reads this list, so OCTO.ASM needs no numbers from this script.
import sys, os, math
import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree
from sklearn.cluster import KMeans
Image.MAX_IMAGE_PIXELS = None

M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
def s2l(c): c = c / 255.0; return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def l2s(l): l = np.clip(l, 0, 1); return np.where(l <= 0.0031308, l * 12.92, 1.055 * l ** (1 / 2.4) - 0.055) * 255
def oklab(rgb): return np.cbrt(s2l(rgb.astype(np.float64)) @ M1.T) @ M2.T
def unlab(lab): return np.clip(np.round(l2s(((lab @ np.linalg.inv(M2).T) ** 3) @ np.linalg.inv(M1).T)), 0, 255).astype(np.uint8)

W0 = 2048                                  # OctoVIC's widest bitmap
NPIC = 231                                 # palette entries 1-231: the picture
P_STAR = 232                               # 232-239: the twinkling stars (8 groups; the 6502 sets their brightness)
P_GLOW = 240                               # 240-247: the sparkles' glow (greys, drawn "added")
P_EQ = 248                                 # 248-255: the equaliser (deep blue to white)

def stars(L, thr, n=None):
    """the stars of a lightness picture: peaks of a white top-hat"""
    th = L - ndimage.grey_opening(L, size=(9, 9))
    mx = ndimage.maximum_filter(th, size=7)
    pk = np.argwhere((th == mx) & (th > thr))
    v = th[pk[:, 0], pk[:, 1]]
    o = np.argsort(-v)
    pk = pk[o]; v = v[o]
    return (pk[:n], v[:n]) if n else (pk, v)

def picture(im, w, pal_tree, rng):
    h = int(round(w * im.height / im.width))
    a = np.asarray(im.resize((w, h), Image.LANCZOS))
    lab = oklab(a)
    ix = pal_tree.query(lab.reshape(-1, 3))[1].reshape(h, w).astype(np.uint8) + 1
    # the stars' cores: into the 8 twinkle groups (a star keeps one group); thresholds by size so each copy twinkles
    L = a.mean(axis=2)
    pk, v = stars(L, 70 if w >= 2048 else 60)
    for (y, x), s in zip(pk, v):
        g = P_STAR + int(rng.integers(0, 8))
        ix[y, x] = g
        if s > 120 and w >= 1024:
            for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and L[yy, xx] > 150: ix[yy, xx] = g
    return ix, a, len(pk)

def sprite_graphics():
    """4 sparkle sizes (32 x 32, the glow greys: drawn added), the comet (64 x 16), the equaliser's bar at 17 heights
    (8 x 64). Returned as bytes, and each one's GFX number (32-byte units)"""
    out = bytearray(); gfx = {}
    def add(name, arr):
        gfx[name] = len(out) // 32
        out.extend(arr.astype(np.uint8).tobytes())
    for k, R in enumerate((4, 7, 11, 15)):
        img = np.zeros((32, 32))
        yy, xx = np.mgrid[0:32, 0:32] - 15.5
        r = np.hypot(xx, yy)
        img += np.clip(1.4 - r / (R * 0.35), 0, 1) ** 1.5            # the core
        for ang, ln in ((90, R), (30, R * 0.8), (150, R * 0.8), (0, R * 0.4)):
            a = math.radians(ang)
            d = np.abs(-xx * math.sin(a) + yy * math.cos(a))            # distance from the spike's line
            along = np.abs(xx * math.cos(a) + yy * math.sin(a))
            img += np.clip(1 - d / 0.9, 0, 1) * np.clip(1 - along / ln, 0, 1) ** 1.2
        lev = np.clip(np.round(img * 8), 0, 8).astype(int)               # 0 see-through, 1-8 the greys
        add('sp%d' % k, np.where(lev > 0, P_GLOW + np.minimum(lev, 8) - 1, 0))
    c = np.zeros((16, 64))
    for x in range(64):
        t = x / 63.0                                                     # the head on the left, the tail to the right
        y = 11 - 5 * t
        w = 2.2 * (1 - t) + 0.5
        for yy in range(16):
            c[yy, x] = max(c[yy, x], np.clip(1 - abs(yy - y) / w, 0, 1) * (1 - t) ** 0.7)
    lev = np.clip(np.round(c * 8), 0, 8).astype(int)
    add('comet', np.where(lev > 0, P_GLOW + np.minimum(lev, 8) - 1, 0))
    for L in range(17):
        b = np.zeros((64, 8))
        for row in range(64):
            if 63 - row < L * 4:
                if row % 4 != 3: b[row, 1:7] = P_EQ + min(7, (63 - row) // 8)
        add('eq%d' % L, b)
    return bytes(out), gfx

# ------------------------------------------------------------------ the camera's path (in pixels of the 2048 picture)
VW, VH, VX, VY = 396, 284, 198, 158        # OctoVIC's picture; the camera's middle
def smooth(s): return s * s * (3 - 2 * s)
def path_rows(spec, start, K=3):
    rows = []; cur = start; tot = 0
    for n, tgt, ev in spec:
        if tgt is None:
            rows.append((n, cur, ev)); tot += n; continue
        pts = {}
        for f in range(0, n + 1):
            s = smooth(f / n)
            pts[f] = (cur[0] + (tgt[0] - cur[0]) * s, cur[1] + (tgt[1] - cur[1]) * s,
                      math.exp(math.log(cur[2]) + (math.log(tgt[2]) - math.log(cur[2])) * s))
        f = 0
        while f < n:
            g = min(n, f + K)
            rows.append((g - f, pts[g], ev if f == 0 else 0)); f = g
        cur = tgt; tot += n
    return rows, tot

def b24(v): v = int(round(v)) & 0xFFFFFF; return bytes([v & 255, (v >> 8) & 255, v >> 16])

def main():
    src, mus, songlen, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    rng = np.random.default_rng(7)
    im = Image.open(src).convert('RGB')
    H0 = int(round(W0 * im.height / im.width))
    work = im.resize((4096, int(round(4096 * im.height / im.width))), Image.LANCZOS) if im.width > 4096 else im
    # the palette: k-means in OKLab on the picture's pixels (the 2048 copy and the half size), 231 colours
    a0 = np.asarray(work.resize((W0, H0), Image.LANCZOS)); a1 = np.asarray(work.resize((W0 // 2, H0 // 2), Image.LANCZOS))
    samp = np.vstack([oklab(a0).reshape(-1, 3)[rng.choice(a0.shape[0] * a0.shape[1], 220000, replace=False)],
                      oklab(a1).reshape(-1, 3)[rng.choice(a1.shape[0] * a1.shape[1], 60000, replace=False)]])
    km = KMeans(NPIC, n_init=1, max_iter=60, random_state=1).fit(samp)
    pal = np.zeros((256, 3), np.uint8)
    pal[1:1 + NPIC] = unlab(km.cluster_centers_)
    pal[P_STAR:P_STAR + 8] = (255, 250, 240)
    for k in range(8): pal[P_GLOW + k] = [int(255 * ((k + 1) / 8) ** 1.6)] * 3
    eqc = [(20, 30, 120), (30, 60, 170), (40, 100, 210), (60, 150, 230), (90, 200, 240), (150, 230, 250), (210, 245, 255), (255, 255, 255)]
    for k in range(8): pal[P_EQ + k] = eqc[k]
    tree = cKDTree(oklab(pal[1:1 + NPIC]))
    # the three copies
    pics = []
    for w in (W0, W0 // 2, W0 // 4):
        ix, a, ns = picture(work, w, tree, rng)
        pics.append(ix)
        sys.stderr.write('picture %d x %d: %d stars twinkle\n' % (ix.shape[1], ix.shape[0], ns))
    # sparkle stars: the 32 brightest in the 2048 picture
    L0 = np.asarray(work.resize((W0, H0), Image.LANCZOS)).mean(axis=2)
    pk, v = stars(L0, 90, 32)
    sp = bytearray([len(pk)])
    for y, x in pk: sp += bytes([x & 255, x >> 8, y & 255, y >> 8])
    # the path: through the cliffs, in time with the waltz (frames from song.py's tempo: 552 the introduction, then
    # 1920 each time through the theme, the coda); it ends where it starts, so the loop has no jump
    zf = (H0 - 8) / VH                                    # the whole picture's height on the screen
    WHOLE = (W0 / 2, H0 / 2, zf)
    STAR = (1385.0, 175.0, 0.45)                           # the bright star top right of the ridge: where it starts
    sx, sy = W0 / 1280.0, H0 / 741.0                      # (positions picked on the 1280 copy)
    PEAK = (250 * sx, 250 * sy, 1.25)                      # the western peak
    RIDGE = (590 * sx, 300 * sy, 1.0)                      # the ridge
    ABOVE = (700 * sx, 150 * sy, 0.8)                      # the stars above it
    EAST = (1080 * sx, 230 * sy, 1.2)                      # the eastern cliffs
    DUST = (620 * sx, 560 * sy, 1.1)                       # the deep dust
    STAR = (1112 * sx, 177 * sy, 0.5)
    SPEC = [(60, None, 1),                                # black; the palette fades up (event 1)
            (480, WHOLE, 2),                              # out from the star to the whole picture (the introduction)
            (240, None, 0),
            (420, PEAK, 0), (180, None, 0),
            (480, RIDGE, 0), (120, None, 0),
            (360, ABOVE, 0), (180, None, 0),
            (420, EAST, 0), (180, None, 0),
            (480, DUST, 0), (240, None, 0),
            (540, WHOLE, 0)]
    # fitted to the music's tempo map (song.py): the first move ends as the waltz begins, the tour spans the theme
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import song as SG
    p1, coda = SG.fr(SG.P1, 0), SG.fr(SG.CODA, 0)
    k = (coda - p1) / float(sum(n for n, _, _ in SPEC[2:]))
    SPEC = SPEC[:1] + [(p1 - 60, WHOLE, 2)] + [(int(round(n * k)), p, e) for n, p, e in SPEC[2:]]
    used = sum(n for n, _, _ in SPEC)
    rest = songlen - used
    SPEC += [(max(60, rest - 360), None, 3), (360, STAR, 0)]   # hold through the coda (the credit), then back to the star
    rows, tot = path_rows(SPEC, STAR)
    assert tot == songlen, (tot, songlen)
    for n, (x, y, z), ev in rows:                          # never past the picture's edges
        assert x - VX * z >= -1 and x + (VW - VX) * z <= W0 + 1 and y - (VY - 16) * z >= -1 and y + (299 - VY) * z <= H0 + 1, (x, y, z)
    path = bytearray()
    for n, (x, y, z), ev in rows:
        path += bytes([n & 255, n >> 8]) + b24(x * 256) + b24(y * 256) + b24(z * 65536) + bytes([ev])
    path += bytes(12)
    sgfx, gfx = sprite_graphics()
    # the .reu
    parts = []
    reu = bytearray(0x10000)
    def put(data):
        a = len(reu); reu.extend(data); reu.extend(bytes(-len(reu) % 0x10000)); parts.append((a, len(data)))
    p0 = np.zeros((H0, W0), np.uint8); p0[:, :] = pics[0]
    put(p0.tobytes())
    put(pics[1].tobytes())
    put(pics[2].tobytes())
    put(bytes(pal[:, 0]) + bytes(pal[:, 1]) + bytes(pal[:, 2]))
    put(sgfx)
    put(bytes(path))
    put(bytes(sp))
    m = open(mus, 'rb').read()
    assert len(m) == songlen * 192
    mm = bytearray()
    for f in range(songlen): mm += m[f * 192:(f + 1) * 192] + bytes(64)
    put(bytes(mm))
    hdr = b'ODYSSEY1' + b'(C) 2026 MONG00SE. ALL RIGHTS RESERVED.\0'
    hdr += bytes(64 - len(hdr))
    for a, n in parts: hdr += b24(a) + b24(n)
    hdr += bytes([gfx['sp0'], gfx['comet'], gfx['eq0'], H0 & 255, H0 >> 8])
    reu[:len(hdr)] = hdr
    open(out, 'wb').write(reu)
    Image.fromarray(pal[pics[0]]).save(os.path.splitext(out)[0] + '_preview.png')
    sys.stderr.write('reu %d bytes, %d path rows, sprite gfx %d bytes %s\n' % (len(reu), len(rows), len(sgfx), gfx))

if __name__ == '__main__':
    main()
