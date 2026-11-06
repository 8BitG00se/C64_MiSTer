# OCTOPUS - the data for octopus.asm (Python only prepares data; the demo itself is 6502).
#   gen.py OUT_DIR [--preview x.png]  ->  Octopus.reu, data.inc
# The .reu is laid out like OctoVIC's memory (REU offset = VRAM offset) for the parts the 6502 copies up in 64 KB runs:
#   $000000 the octopus, a 256 x 256 BITMAP (palette bands: swirl of palette entries by distance and angle from the head)
#   $010000 sprites: the caption band's graphics, 6 star graphics, and the sprite table (3 band + NSTAR stars)
#   $020000 the copper lists, one a frame for PER frames (the palette flowing + twinkling stars + the backdrop bands)
# and, REU only (never in VRAM): R_CAM, the camera: 24 bytes (U0 V0 DUX DVX DUY DVY) padded to 32 for each of NFR frames,
# R_PAL, the 768 palette bytes the 6502 sets up at the start.
import sys, os, math, colorsys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

NFR = 1800            # the loop: 36 s... see TURN / PULSE
TURN = 450            # frames a full turn (9 s)
PULSE = 900           # frames a zoom breath (in 1.00 -> out ... back)
PER = 120             # frames the palette flow repeats after (NFR % PER == 0)
SHIFT = 2             # palette entries the flow moves a frame (240 entries: PER * SHIFT = 240)
NFLOW = 240           # entries 1..240 flow
I_WHITE, I_BLACK = 241, 242
I_STAR = 244          # 244..249: six star colours that twinkle
I_SHADOW = 255
NPAL = 249            # the copper rewrites entries 1..249 every list
NSTAR = 40
TEX = 256
assert NFR % PER == 0 and PER * SHIFT == NFLOW and NFR % TURN == 0 and NFR % PULSE == 0

def ramp(t):          # technicolour: a full hue circle round 240 entries, with brighter and darker stripes
    h = (t % NFLOW) / NFLOW
    v = 0.80 + 0.20 * math.cos(2 * math.pi * 5 * h)
    r, g, b = colorsys.hsv_to_rgb(h, 0.92, v)
    return int(r * 255), int(g * 255), int(b * 255)

# ------------------------------------------------------------------ the octopus (our own drawing of the OLED logo's character)
S = 4
def octopus():
    # design units: the head's middle is (0,0), head radius 62
    R = 62.0
    k = 3.65
    arms = []
    for a in range(8):
        side = (a - 3.5) / 3.5
        pts = []
        for i in range(80):
            u = i / 79
            x = side * (10 + 17 * u) * k + math.sin(u * 7 + a) * 3.0 * k
            y = 29 + u * 33 * k
            if u > 0.75:
                c = (u - 0.75) / 0.25 * 3.2
                x += (side / max(0.3, abs(side))) * math.sin(c) * 4 * k
                y -= (1 - math.cos(c)) * 3 * k
            pts.append((x, y, (2.8 - 1.3 * u) * k))
        arms.append(pts)
    def draw(sc, cx, cy):
        # returns idx-less layers as masks (hi-res, S x): body, eyes etc.
        W = TEX * S
        def im(): return Image.new('L', (W, W), 0)
        def P(x, y): return ((x * sc + cx) * S, (y * sc + cy) * S)
        body, white, black, pup = im(), im(), im(), im()
        db, dw, dk, dp = ImageDraw.Draw(body), ImageDraw.Draw(white), ImageDraw.Draw(black), ImageDraw.Draw(pup)
        for pts in arms:
            prev = None
            for x, y, w in pts:
                px, py = P(x, y); rr = w * sc * S
                db.ellipse([px - rr, py - rr, px + rr, py + rr], fill=255)
                if prev: db.line([prev, (px, py)], fill=255, width=int(rr * 2))
                prev = (px, py)
        px, py = P(0, 0); rr = R * sc * S
        db.ellipse([px - rr, py - rr, px + rr, py + rr], fill=255)
        for ex in (-25, 25):                                  # big round eyes: black ring, white, pupil, glint
            px, py = P(ex, 6); rr = 20 * sc * S; dk.ellipse([px - rr, py - rr, px + rr, py + rr], fill=255)
            rr = 16 * sc * S; dw.ellipse([px - rr, py - rr, px + rr, py + rr], fill=255)
            qx, qy = P(ex + 2, 8); rr = 9 * sc * S; dp.ellipse([qx - rr, qy - rr, qx + rr, qy + rr], fill=255)
            gx, gy = P(ex - 1, 4); rr = 3.2 * sc * S; dp.ellipse([gx - rr, gy - rr, gx + rr, gy + rr], fill=128)
        # the smile: an arc below the eyes, round ends
        cxs, cys = P(0, 24); rs = 21 * sc * S
        for ang in np.linspace(math.radians(28), math.radians(152), 60):
            x, y = cxs + rs * math.cos(ang), cys + rs * math.sin(ang); rr = 3.2 * sc * S
            dk.ellipse([x - rr, y - rr, x + rr, y + rr], fill=255)
        return body, white, black, pup
    return draw

def make_texture():
    draw = octopus()
    # pass 1: the size and the middle of what is drawn; then scaled so it fits a circle of radius 121 round (128,128)
    body = draw(1.0, 128, 128)[0]
    a = np.array(body.resize((TEX, TEX), Image.NEAREST)) > 0
    ys, xs = np.nonzero(a)
    cx0, cy0 = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    rad = np.sqrt((xs - cx0) ** 2 + (ys - cy0) ** 2).max() + 4
    sc = 121.0 / rad
    # the head's middle (design 0,0) goes where the bounding middle ends up at (128,128)
    hx = 128 + (128 - cx0) * sc + (cx0 - 128) * sc * 0   # placeholder, set below
    # design (0,0) was drawn at (128,128) in pass 1, so the bounding middle (cx0,cy0) is (cx0-128, cy0-128) design units from it
    ox, oy = 128 - (cx0 - 128) * sc, 128 - (cy0 - 128) * sc
    body, white, black, pup = draw(sc, ox, oy)
    def lo(m): return np.array(m.resize((TEX, TEX), Image.NEAREST))
    body, white, black, pupv = lo(body) > 0, lo(white) > 0, lo(black) > 0, lo(pup)
    pup, glint = pupv > 200, pupv == 128
    dil = np.array(Image.fromarray((body * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0
    yy, xx = np.mgrid[0:TEX, 0:TEX]
    dx, dy = xx - ox, yy - (oy - 30 * sc)          # the swirl turns about a point high in the head
    r = np.hypot(dx, dy); th = np.arctan2(dy, dx)
    phase = 0.85 * r + NFLOW * 2 * th / (2 * math.pi) + 0.3 * (yy - oy)
    flow = 1 + (np.floor(phase).astype(int) % NFLOW)
    tex = np.zeros((TEX, TEX), np.uint8)
    tex[dil] = I_BLACK                                        # the dark outline
    tex[body] = flow[body]
    tex[black] = I_BLACK                                       # smile, eye rings
    tex[white] = I_WHITE
    tex[pup] = I_BLACK
    tex[glint] = I_WHITE
    return tex, (ox, oy, sc, rad)

# ------------------------------------------------------------------ palette, copper lists
def pal_base():
    p = np.zeros((256, 3), np.uint8)
    for i in range(1, NFLOW + 1): p[i] = ramp(i - 1)
    p[I_WHITE] = (255, 255, 255); p[I_BLACK] = (0, 0, 0)
    star_c = [(255, 255, 255), (170, 210, 255), (255, 236, 170), (200, 255, 230), (255, 190, 230), (190, 190, 255)]
    for j in range(6): p[I_STAR + j] = star_c[j]
    p[I_SHADOW] = (0, 0, 20)
    return p

def star_col(j, f):
    q = 1 + (j % 2)
    b = 0.30 + 0.70 * (0.5 + 0.5 * math.sin(2 * math.pi * (q * f / PER + j / 6.0)))
    return pal_base()[I_STAR + j] * b

STARC = [pal_base()[I_STAR + j] for j in range(6)]

def backdrop(L, f):
    c = []
    for i, (lo, hi, per, q, ph) in enumerate(((4, 20, 71, 1, 0.0), (3, 26, 97, 2, 0.31), (20, 62, 83, 1, 0.62))):
        s = 0.5 + 0.5 * math.sin(2 * math.pi * (L / per - q * f / PER + ph))
        c.append(int(lo + (hi - lo) * s))
    return c

def cop_list(f):
    e = [(0, 0x19, 0), (0, 0x1A, 1)]
    for i in range(1, NPAL + 1):
        if i <= NFLOW: rgb = ramp(i - 1 - SHIFT * f)
        elif I_STAR <= i < I_STAR + 6:
            j = i - I_STAR; q = 1 + (j % 2)
            b = 0.30 + 0.70 * (0.5 + 0.5 * math.sin(2 * math.pi * (q * f / PER + j / 6.0)))
            rgb = tuple(int(v * b) for v in STARC[j])
        else: rgb = tuple(int(v) for v in pal_base()[i])
        n = len(e)
        for c in range(3): e.append(((len(e)) // 64, 0x1B + c, rgb[c]))
    assert (len(e) - 1) // 64 < 12, len(e)
    for L in range(16, 300):
        if L == 16: e.append((L, 0x19, 2))
        for c, v in zip((0x1B, 0x1C, 0x1D), backdrop(L, f)): e.append((L, c, v))
    b = bytearray()
    for ln, r, v in e: b += bytes([ln & 255, ln >> 8, r, v & 255])
    b += bytes([0xFF, 0xFF, 0, 0])
    while len(b) % 8: b += b'\xff\xff\x00\x00'
    return bytes(b)

# ------------------------------------------------------------------ camera
def camera():
    out = bytearray()
    cu = cv = TEX / 2; xc, Lc = 198.0, 158.0
    for f in range(NFR):
        a = 2 * math.pi * f / TURN
        scale = 1.0 + 0.15 * math.sin(2 * math.pi * f / PULSE)   # screen pixels to a texel: 0.85 .. 1.15
        z = 1.0 / scale
        DUX, DVX, DUY, DVY = z * math.cos(a), z * math.sin(a), -z * math.sin(a), z * math.cos(a)
        U0 = cu - (xc * DUX + Lc * DUY); V0 = cv - (xc * DVX + Lc * DVY)
        b = bytearray()
        for v in (U0, V0, DUX, DVX, DUY, DVY):
            n = int(round(v * 65536)) & 0xFFFFFFFF
            b += n.to_bytes(4, 'little')
        out += bytes(b) + bytes(8)
    return bytes(out)

def sprites():
    gfx = bytearray(0x800)
    gfx[0:1024] = bytes([I_SHADOW]) * 1024                    # the caption band (64 x 16), GFX 0
    for j in range(6):                                        # a star: a little plus, 8 x 8, GFX 32 + 2j
        base = 1024 + 64 * j
        for (x, y) in ((3, 4), (4, 3), (4, 4), (5, 4), (4, 5)): gfx[base + y * 8 + x] = I_STAR + j
    sat = bytearray()
    for n in range(3):                                        # the band behind the captions (VIC x 64-256): in front, half and half
        x = 64 + 64 * n
        sat += bytes([x & 255, x >> 8, 184, 0, 0, 0, 0xC7, 0x40])
    rng = np.random.RandomState(11)
    for n in range(NSTAR):
        x = int(rng.randint(-30, 356)); y = int(rng.randint(-40, 236)); j = n % 6
        sat += bytes([x & 255, (x >> 8) & 255, y & 255, (y >> 8) & 255, (32 + 2 * j) & 255, 0, 0xC0, 0x20])
    return bytes(gfx), bytes(sat)

def main():
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    tex, info = make_texture()
    print('texture: head at (%.1f,%.1f) scale %.3f radius %.1f; colours used %d' % (info[0], info[1], info[2], info[3], len(np.unique(tex))))
    if '--preview' in sys.argv:
        p = pal_base(); Image.fromarray(p[tex]).resize((512, 512), Image.NEAREST).save(sys.argv[sys.argv.index('--preview') + 1])
    V_PIC0, V_SPR, V_COP = 0, 0x10000, 0x20000
    lists = [cop_list(f) for f in range(PER)]
    FB = len(lists[0]); assert all(len(l) == FB for l in lists)
    LEN_COP = FB * PER
    gfx, sat = sprites()
    V_SAT = V_SPR + 0x800
    R_CAM = (V_COP + LEN_COP + 0xFFFF) & ~0xFFFF
    cam = camera()
    R_PAL = R_CAM + 0x10000
    reu = bytearray(R_PAL + 0x1000)
    reu[V_PIC0:V_PIC0 + TEX * TEX] = tex.tobytes()
    reu[V_SPR:V_SPR + len(gfx)] = gfx; reu[V_SAT:V_SAT + len(sat)] = sat
    for f in range(PER): reu[V_COP + f * FB:V_COP + (f + 1) * FB] = lists[f]
    reu[R_CAM:R_CAM + len(cam)] = cam
    p = pal_base()
    pb = bytes(p[:, 0]) + bytes(p[:, 1]) + bytes(p[:, 2])
    reu[R_PAL:R_PAL + 768] = pb
    open(os.path.join(out, 'Octopus.reu'), 'wb').write(reu)
    inc = ['; made by gen.py - do not edit',
           'V_PIC0 = $%06x' % V_PIC0, 'LEN_PIC0 = $%06x' % (TEX * TEX), 'R_PIC0 = $%06x' % V_PIC0,
           'V_SPR = $%06x' % V_SPR, 'V_SAT = $%06x' % V_SAT, 'LEN_SPR = $%06x' % 0x1000, 'R_SPR = $%06x' % V_SPR,
           'NSPR = %d' % (3 + NSTAR),
           'V_COP = $%06x' % V_COP, 'R_COP = $%06x' % V_COP, 'LEN_COP = $%06x' % LEN_COP, 'FB = %d' % FB, 'NLIST = %d' % PER,
           'R_CAM = $%06x' % R_CAM, 'NFR = %d' % NFR, 'R_PAL = $%06x' % R_PAL]
    open(os.path.join(out, 'data.inc'), 'w').write('\n'.join(inc) + '\n')
    print('REU %d bytes; lists %d x %d; camera %d frames' % (len(reu), PER, FB, NFR))

main()
