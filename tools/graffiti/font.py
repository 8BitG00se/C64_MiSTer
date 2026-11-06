# our own bubble/wildstyle-lite graffiti alphabet: skeleton strokes drawn with a fat round pen, a thick dark outline,
# a gradient fill, a white streak, a shaded rim, paint drips. Cells are 128 rows tall, a whole number of 8-pixel tiles wide.
import math, numpy as np
from PIL import Image, ImageDraw, ImageFilter

H = 64            # skeleton height
R = 9             # pen radius (the stroke is 18 wide)
OUT = 5           # outline width
CELLH = 128
TOP = 18          # where the skeleton's top is in the cell (ink starts at TOP - R - OUT = 4)
MARG = 6          # blank pixels kept either side of the outline (the shadow's blur lives there)
SS = 4            # supersampling

def arc(cx, cy, rx, ry, a0, a1, n=40):
    return [(cx + rx * math.cos(math.radians(a)), cy + ry * math.sin(math.radians(a))) for a in np.linspace(a0, a1, n)]

def glyphs():
    g = {}
    def add(ch, w, *strokes): g[ch] = (w, [list(s) for s in strokes])
    add('A', 48, [(0, H), (24, 0), (48, H)], [(11, 42), (37, 42)])
    w = 44
    add('B', w, [(0, 0), (0, H)], [(0, 0), (24, 0)] + arc(24, 16, 16, 16, -90, 90) + [(0, 32)], [(0, 32), (26, 32)] + arc(26, 48, 18, 16, -90, 90) + [(0, H)])
    add('C', 46, arc(23, 32, 23, 32, -40, -320, 50))
    add('D', 46, [(0, 0), (0, H)], [(0, 0), (16, 0)] + arc(16, 32, 30, 32, -90, 90) + [(0, H)])
    add('E', 40, [(0, 0), (0, H)], [(0, 0), (40, 0)], [(0, 32), (32, 32)], [(0, H), (40, H)])
    add('F', 40, [(0, 0), (0, H)], [(0, 0), (40, 0)], [(0, 32), (32, 32)])
    add('G', 48, arc(24, 32, 24, 32, -40, -360, 50) + [(24, 36)])
    add('H', 46, [(0, 0), (0, H)], [(46, 0), (46, H)], [(0, 32), (46, 32)])
    add('I', 30, [(0, 0), (30, 0)], [(15, 0), (15, H)], [(0, H), (30, H)])
    add('J', 38, [(38, 0)] + [(38, 42)] + arc(19, 42, 19, 22, 0, 180, 24) + [(0, 36)])
    add('K', 46, [(0, 0), (0, H)], [(46, 0), (0, 36), (46, H)])
    add('L', 40, [(0, 0), (0, H), (38, H)])
    add('M', 62, [(0, H), (0, 0), (31, 38), (62, 0), (62, H)])
    add('N', 48, [(0, H), (0, 0), (48, H), (48, 0)])
    add('O', 50, arc(25, 32, 25, 32, 0, 360, 60))
    add('P', 44, [(0, H), (0, 0), (22, 0)] + arc(22, 18, 20, 18, -90, 90) + [(0, 36)])
    add('Q', 50, arc(25, 32, 25, 32, 0, 360, 60), [(30, 44), (52, 68)])
    add('R', 44, [(0, H), (0, 0), (22, 0)] + arc(22, 18, 20, 18, -90, 90) + [(0, 36)], [(18, 36), (44, H)])
    add('S', 44, arc(22, 16, 22, 16, -35, -270, 36)[:] + arc(22, 48, 22, 16, -90, 145, 36))
    add('T', 48, [(0, 0), (48, 0)], [(24, 0), (24, H)])
    add('U', 46, [(0, 0), (0, 40)] + arc(23, 40, 23, 24, 180, 0, 30) + [(46, 0)])
    add('V', 50, [(0, 0), (25, H), (50, 0)])
    add('W', 70, [(0, 0), (17, H), (35, 22), (53, H), (70, 0)])
    add('X', 48, [(0, 0), (48, H)], [(48, 0), (0, H)])
    add('Y', 48, [(0, 0), (24, 34), (48, 0)], [(24, 34), (24, H)])
    add('Z', 46, [(0, 0), (46, 0), (0, H), (46, H)])
    add('0', 42, arc(21, 32, 21, 32, 0, 360, 60))
    add('1', 36, [(0, 16), (22, 0), (22, H)], [(0, H), (36, H)])
    add('2', 44, arc(22, 17, 22, 17, -180, 35, 30) + [(0, H), (44, H)])
    add('3', 42, arc(21, 16, 21, 16, -150, 90, 30), arc(21, 48, 21, 16, -90, 150, 30))
    add('4', 46, [(32, 0), (0, 44), (46, 44)], [(32, 0), (32, H)])
    add('5', 44, [(42, 0), (4, 0), (6, 28)] + arc(22, 45, 22, 19, -125, 140, 36))
    add('6', 44, arc(44, 40, 44, 40, 180, 268, 20) + [(2, 40)][:0], arc(22, 45, 22, 19, 0, 360, 50))
    add('7', 44, [(0, 0), (44, 0), (14, H)])
    add('8', 44, arc(22, 15, 18, 15, 0, 360, 40), arc(22, 47, 22, 17, 0, 360, 50))
    add('9', 44, arc(22, 19, 22, 19, 0, 360, 50), arc(0, 24, 44, 40, 0, 88, 20))
    add('!', 20, [(10, 0), (10, 38)], [(10, 60), (10, 61)])
    add('.', 14, [(7, 59), (7, 60)])
    add('-', 30, [(0, 32), (30, 32)])
    add("'", 12, [(6, 0), (6, 16)])
    g[' '] = (24, [])
    return g

GRAD = [(255, 48, 150), (255, 140, 38), (255, 226, 64)]      # hot pink -> orange -> yellow
NG = 16                                                      # gradient steps, normal and shaded: 2 * NG palette entries

def grad(t):
    t = min(max(t, 0.0), 1.0) * 2
    i = min(int(t), 1); f = t - i
    return tuple(GRAD[i][c] * (1 - f) + GRAD[i + 1][c] * f for c in range(3))

def draw_glyph(ch, G, seed):
    """-> (letter, shadow): letter = indices 0 (see-through), 1..NG fill, NG+1..2NG shaded fill, 2NG+1 white, 2NG+2 outline;
    shadow = 0..8 (how dark); both CELLH rows x cell width"""
    w, strokes = G[ch]
    if not strokes:
        cw = 24
        return np.zeros((CELLH, cw), np.uint8), np.zeros((CELLH, cw), np.uint8)
    ink = w + 2 * R
    cw = int(math.ceil((ink + 2 * OUT + 2 * MARG) / 8.0) * 8)
    x0 = (cw - w) / 2.0
    Wp, Hp = cw * SS, CELLH * SS
    im = Image.new('L', (Wp, Hp), 0); d = ImageDraw.Draw(im)
    def P(x, y): return ((x0 + x) * SS, (TOP + y) * SS)
    rr = R * SS
    for s in strokes:
        pts = [P(*p) for p in s]
        for (a, b) in zip(pts[:-1], pts[1:]):
            d.line([a, b], fill=255, width=2 * rr)
        for p in pts:
            d.ellipse([p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr], fill=255)
    # paint drips off the bottom edge
    rng = np.random.RandomState(seed)
    body = np.array(im.resize((cw, CELLH), Image.BOX)) >= 128
    bottoms = []
    for x in range(int(2 * R), cw - int(2 * R)):
        col = np.nonzero(body[:, x])[0]
        if len(col) and body[col.max(), x] and col.max() < CELLH - 40: bottoms.append((x, col.max()))
    nd = {1: 0, 2: 1}.get(len(strokes), 1) + (1 if w > 40 else 0)
    if bottoms and ch not in "'-.!":
        for k in range(nd):
            x, yb = bottoms[rng.randint(len(bottoms))]
            ln = rng.randint(9, 17); dr = 3.0 + rng.rand() * 1.2
            d.line([(x * SS, (yb - 3) * SS), (x * SS, (yb + ln) * SS)], fill=255, width=int(2 * dr * SS))
            d.ellipse([(x - dr - 0.8) * SS, (yb + ln - dr) * SS, (x + dr + 0.8) * SS, (yb + ln + dr + 2) * SS], fill=255)
    m_ink = np.array(im.resize((cw, CELLH), Image.BOX)) >= 128
    def dil(a, n):
        k = 2 * n + 1
        return np.array(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(k))) > 0
    def ero(a, n):
        k = 2 * n + 1
        return np.array(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(k))) > 0
    # round outline: dilate by a disc, done as a few square steps rounded with a blur threshold
    def disc(a, n):
        f = np.array(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(n * 0.55))).astype(float)
        return np.array(Image.fromarray((a * 255).astype(np.uint8)).resize((cw * 4, CELLH * 4), Image.NEAREST).filter(ImageFilter.MaxFilter(2 * n * 4 + 1)).resize((cw, CELLH), Image.BOX)) >= 128
    full = disc(m_ink, OUT)
    yy = np.arange(CELLH)[:, None] * np.ones((1, cw))
    t = np.clip((yy - (TOP - R)) / (H + 2 * R), 0, 1)
    gi = np.clip((t * NG).astype(int), 0, NG - 1)
    out = np.zeros((CELLH, cw), np.uint8)
    out[full] = 2 * NG + 2
    out[m_ink] = 1 + gi[m_ink]
    # shaded rim, lower right inside the ink; white streak, upper left inside
    inner = ero(m_ink, 3)
    sh = m_ink & ~np.roll(np.roll(ero(m_ink, 1), -5, 0), -4, 1)
    out[sh & m_ink] = NG + 1 + gi[sh & m_ink]
    e2 = ero(m_ink, 5)
    hl = e2 & ~np.roll(np.roll(e2, 4, 0), 3, 1)
    # keep the streak to the upper part of each stroke, and break it into dashes
    hl &= (yy < TOP + H * 0.62)
    out[hl] = 2 * NG + 1
    # shadow: the outline's shape, blurred, 0..8
    sm = np.array(Image.fromarray((full * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.6))).astype(float) / 255
    shadow = np.clip(np.round(sm * 8), 0, 8).astype(np.uint8)
    return out, shadow

def palette(base=0):
    p = {}
    for i in range(NG):
        c = grad((i + 0.5) / NG)
        p[1 + i] = tuple(int(v) for v in c)
        p[NG + 1 + i] = tuple(int(v * 0.72) for v in c)
    p[2 * NG + 1] = (255, 255, 255)
    p[2 * NG + 2] = (28, 10, 40)
    return p      # letter indices 1..2NG+2; shadow levels are a separate set of 8 entries added after

if __name__ == '__main__':
    import sys
    G = glyphs()
    chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!.-' "
    bg = np.full((CELLH * 6, 1100, 3), (150, 85, 60), np.uint8)
    pal = palette()
    x = 0; row = 0
    for k, ch in enumerate(chars):
        L, S = draw_glyph(ch, G, 100 + k)
        if x + L.shape[1] > 1100: x = 0; row += 1
        y0 = row * CELLH
        sub2 = np.roll(np.roll(S, 7, 0), 7, 1)  # preview shadow offset
        sub = np.clip(bg[y0:y0 + CELLH, x:x + L.shape[1]].astype(float) - sub2[..., None] * 9, 0, 255)
        for idx, c in pal.items():
            sub[L == idx] = c
        bg[y0:y0 + CELLH, x:x + L.shape[1]] = sub.astype(np.uint8)
        x += L.shape[1]
    Image.fromarray(bg).save(sys.argv[1])
