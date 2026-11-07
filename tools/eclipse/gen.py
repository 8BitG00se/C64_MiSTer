#!/usr/bin/env python3
# gen.py - Eclipse Beach build 1 for the Octophonic 64: prepares the data eclipse.asm needs. Original work by Mong00se.
# The PC only prepares data (a picture, sprite frames, palettes, tables); everything on screen is drawn by eclipse.asm.
#
#   gen.py OUTDIR            writes into OUTDIR:
#     Eclipse Beach.reu      the REU image: [picture 512 x 256][sprite graphics][one 2 KB record per tick: palette 3 x 256, sprite table]
#     data.inc               addresses and counts for eclipse.asm
#     sky.oct sea.oct beach.oct sun frames.oct corona frames.oct (on the disk: corona.oct)   OctoPaint pictures (320 x 200) of the still layers and sprite frames
#     preview_NNNN.png       (--preview=T,T,..) the picture layer alone with the palette of those ticks
#
# The scene (an afternoon sky, a total solar eclipse as a 60 s time lapse, a sea with lit crests and a sun glitter column,
# a still beach) follows the approved mockup's maths. How it is split between OctoVIC's parts:
#   layer 0 (bitmap, 256 colours)  the sky as an 8x8 Bayer dithered gradient of 41 palette levels, the sea in classes
#                                  (depth band, glitter, wave phase, wave strength) whose palette entries are re-coloured every tick so the
#                                  crests travel (palette cycling), the wet strip and the dry sand with its ripples. Sea and sand darken
#                                  with the eclipse by palette alone.
#   sprites                        the sun glow (4 x 64x64, added), the sun and the moon's black bite (32x32, one frame per record),
#                                  the corona and the diamond ring (4 x 64x64, added, a frame per record), 90 stars (8x8, their
#                                  brightness chosen by the graphics), two foam lines (5 x 64x16 each, half and half).
import numpy as np, math, os, sys, struct
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'octopaint'))
import mkoct

W, H, HZ = 320, 200, 120
PDITHER = False         # dither the wave phase buckets (speckles) or not
SCV = [0.03, 0.3, 0.8]  # the glitter classes' values (the pixel is dithered between neighbouring classes)
NTICK = 1500            # 25 ticks a second = 60 s
REC = 3                 # sprite frames change every REC ticks
NREC = NTICK // REC
P, NB, NS = 6, 3, 3     # sea: wave phases, depth bands, glitter classes (and 2 wave-strength classes)
SR = 13.0               # the sun's radius (and the moon's)
B8 = np.array([[0,32,8,40,2,34,10,42],[48,16,56,24,50,18,58,26],[12,44,4,36,14,46,6,38],[60,28,52,20,62,30,54,22],
               [3,35,11,43,1,33,9,41],[51,19,59,27,49,17,57,25],[15,47,7,39,13,45,5,37],[63,31,55,23,61,29,53,21]]) / 64.0
KEYS = [  # (time, [5 sky colours top..horizon], sun core, sun rim, glow colour, glow strength): midday to dusk
 (0.00,[(30,70,150),(50,110,190),(90,150,215),(150,195,230),(200,225,240)],(255,255,245),(255,250,210),(255,250,225),0.35),
 (0.35,[(40,60,140),(70,100,180),(130,150,200),(220,190,170),(250,220,180)],(255,252,230),(255,230,160),(255,225,170),0.45),
 (0.60,[(44,30,96),(110,50,120),(200,80,100),(248,140,80),(255,200,120)],(255,246,210),(255,190,100),(255,190,110),0.6),
 (0.80,[(24,14,60),(70,26,96),(160,44,100),(232,90,70),(250,150,80)],(255,220,160),(244,120,60),(250,140,80),0.65),
 (1.00,[(10,8,30),(28,14,56),(70,24,80),(130,36,80),(190,70,70)],(250,170,110),(210,80,50),(220,90,60),0.5)]
NIGHT = [(2,3,12),(6,8,26),(14,18,52),(34,30,78),(90,56,84),(200,110,70)]
NAVY = np.array([10, 14, 34.0])
STARW = np.array([235, 240, 255.0])
CORW = np.array([240, 244, 252.0])


def lerp(a, b, t): return np.array(a, float) * (1 - t) + np.array(b, float) * t


def key(t):
    for (t0, *a), (t1, *b) in zip(KEYS, KEYS[1:]):
        if t <= t1:
            u = (t - t0) / (t1 - t0)
            return ([lerp(c0, c1, u) for c0, c1 in zip(a[0], b[0])], lerp(a[1], b[1], u), lerp(a[2], b[2], u),
                    lerp(a[3], b[3], u), a[4] * (1 - u) + b[4] * u)


def ramp(cols, tt):
    xs = np.linspace(0, 1, len(cols)); tt = np.asarray(tt, float)
    return np.stack([np.interp(tt, xs, [c[k] for c in cols]) for k in range(3)], -1)


# ---------------------------------------------------------------- palette allocation
# entries 0-15 bank 0: stars (pixel 1-15); 16-31 bloom; 32-47 sun body; 48-63 corona/ring; 64-79 bank 4: foam pixels 1,2 (the rest and 64 are the picture's)
BIT = [64] + list(range(67, 80)) + list(range(80, 256))
_it = iter(BIT)
def alloc(n): return np.array([next(_it) for _ in range(n)])
SKY_E = alloc(41)
SEA_E = alloc(NB * NS * P * 2).reshape(NB, NS, P, 2)
WET_E = alloc(8 * 3).reshape(8, 3)
DRY_E = alloc(5 * 3).reshape(5, 3)
E_STAR, E_BLOOM, E_BODY, E_GLOW, E_FOAM = 0, 16, 32, 48, 64

# ---------------------------------------------------------------- the still picture
yy, xx = np.mgrid[0:H, 0:W]
TH = B8[yy % 8, xx % 8]
SX0 = 196 - 20 * 0.27
edge = 150 + (np.arange(W) / W) * 14 + 2 * np.sin(np.arange(W) * 0.03)


def build_picture():
    pic = np.zeros((256, 512), np.uint8)
    info = {}
    # sky
    f = (yy[:HZ] / (HZ - 1)) * 40; k = np.floor(f)
    L = np.clip(k + ((f - k) > TH[:HZ]), 0, 40).astype(int)
    pic[:HZ, :W] = SKY_E[L]
    # sea
    ys = yy[HZ:]; xs = xx[HZ:]
    ty = (ys - HZ) / (H - HZ)
    Z = 1 / (0.02 + ty); X = (xs - W / 2) / W * Z * 1.6
    th1 = Z * 18 + X * 2.7 + 0.9 * np.sin(X * 6.9 + Z * 5.1)
    rest = (np.sin(Z * 27 - X * 4.8 + np.sin(X * 9.3 - Z * 6.6) * 0.7) * 0.35 + np.sin(Z * 44 + X * 11) * 0.22
            + np.sin(Z * 11 + X * 0.9) * 0.45)
    ph = (th1 / (2 * math.pi)) % 1.0
    pcl = np.floor(ph * P + (TH[HZ:] if PDITHER else 0.5)).astype(int) % P
    sea = ys < edge[None, :]
    med = np.percentile(rest[sea], 62)
    rcl = (rest > med).astype(int)
    TYB = [0.0, 0.2, 0.45]
    u = np.interp(ty, TYB, [0, 1, 2])
    band = np.clip(np.floor(u + TH[HZ:]), 0, NB - 1).astype(int)       # the depth gradient is dithered between the bands
    sc = np.exp(-(((xs - SX0) / (40 + 120 * ty)) ** 2))
    us = np.interp(sc, SCV, [0, 1, 2])
    scl = np.clip(np.floor(us + B8[(ys + 3) % 8, (xs + 5) % 8]), 0, NS - 1).astype(int)
    info['near_h'] = [float(np.exp(-2.2 * t_)) for t_ in TYB]
    info['sc'] = list(SCV)
    info['rest'] = [float(rest[sea & (rcl == r)].mean()) for r in range(2)]
    seapix = SEA_E[band, scl, pcl, rcl]
    # beach
    rel = ys - edge[None, :]
    wet = (rel >= 0) & (rel < 8)
    dry = rel >= 8
    streak = np.exp(-(((xs - SX0) / (6 + rel * 0.8)) ** 2))
    stl = np.where(streak < 0.2, 0, np.where(streak < 0.65, 1, 2))
    info['streak'] = [0.0, 0.45, 0.85]
    wetpix = WET_E[np.clip(np.floor(rel), 0, 7).astype(int), stl]
    dist = np.clip((rel - 8) / (H - 150), 0, 1)
    depth = 1 / (0.08 + dist)
    warp = np.sin(xs * 0.035 + dist * 6) * 1.6 + np.sin(xs * 0.011 - dist * 3) * 2.2
    drr = np.cos(depth * 9.0 + warp * 1.4 + xs * 0.045)
    qi = np.where(drr > 0.75, 0, np.where(drr > 0.45, 1, np.where(drr < -0.8, 4, np.where(drr < -0.55, 3, 2))))
    tt = rel - 8
    dn = np.where(tt < 2.5, 0, np.where(tt < 5, 1, 2))
    drypix = DRY_E[qi, dn]
    lower = np.where(sea, seapix, np.where(wet, wetpix, drypix))
    pic[HZ:H, :W] = lower
    return pic, info


# ---------------------------------------------------------------- the eclipse: positions and coverage for a tick
def state(n):
    t = n / (NTICK - 1); e = 0.22 + 0.10 * t
    cols, core, rim, bcol, bstr = key(e)
    ue = 0.002 + 0.996 * t
    us = 0.5 + 4 * (ue - 0.5) ** 3
    off = (us - 0.5) * 4 * SR
    SX = 196 - 20 * e; SY = 34 + (HZ + 2 - 34) * e
    mx = SX + off * 0.97; my = SY - off * 0.24
    x0, y0 = int(SX) - 20, int(SY) - 20
    ys, xs = np.mgrid[y0:y0 + 41, x0:x0 + 41]
    d = np.sqrt((xs - SX) ** 2 + ((ys - SY) * 1.06) ** 2)
    dm = np.sqrt((xs - mx) ** 2 + (ys - my) ** 2)
    sunm = d < SR; moon = dm < SR
    lw = 0.4 + 0.6 * np.sqrt(np.clip(1 - (d / SR) ** 2, 0, 1))
    cov = float((sunm & moon).sum()) / max(1, sunm.sum())
    vis = float((lw * (sunm & ~moon)).sum()) / max(1e-6, float((lw * sunm).sum()))
    light = vis ** 0.3
    return dict(n=n, t=t, e=e, cols=cols, core=core, rim=rim, bcol=bcol, bstr=bstr, SX=SX, SY=SY, mx=mx, my=my,
                cov=cov, vis=vis, light=light, dark=1 - light, i30=t * 1799)


# ---------------------------------------------------------------- palette for a tick
def palette(S, R, info):
    """S: this tick's state; R: the sprite record's state (its coverage decides how the sun is coloured)."""
    pal = np.zeros((256, 3))
    cols, core, rim, bcol, bstr, e, dark, light = S['cols'], S['core'], S['rim'], S['bcol'], S['bstr'], S['e'], S['dark'], S['light']
    bse = bstr * light
    # sky
    lv = np.arange(41) / 40.0
    day = ramp(cols, lv); nt = ramp(NIGHT, lv)
    pal[SKY_E] = day * (1 - dark) + nt * dark
    skysun = (day * (1 - dark) + nt * dark)[int(round(S['SY'] / (HZ - 1) * 40))]
    daysun = day[int(round(S['SY'] / (HZ - 1) * 40))]
    # sea
    nh = np.array(info['near_h']); scv = np.array(info['sc']); rr = np.array(info['rest'])
    darkc = lerp(cols[0], (10, 22, 30), 0.6) * 0.55; far = np.array(cols[-1]) * 0.55
    sheen = lerp(rim, core, 0.25) * (0.55 + 0.45 * (1 - e))
    base = darkc[None, :] + (far - darkc)[None, :] * nh[:, None] * 0.7                 # (band, 3)
    phi = 2 * math.pi * np.arange(P) / P - 0.15 * S['i30']
    wv = 0.55 * np.sin(phi)[:, None] + rr[None, :] - 0.15                                 # (P, r)
    crest = np.clip(wv, 0, None) / 1.3
    c = crest[None, None, :, :]
    lit = (c * (0.08 + 1.2 * scv[None, :, None, None]) * bse * 2 + c * 0.05
           + scv[None, :, None, None] * nh[:, None, None, None] * 0.25 * bse)
    lit = np.clip(lit, 0, 1)
    sea = base[:, None, None, None, :] + (sheen - base[:, None, None, None, :]) * lit[..., None]
    sea = sea * (1 - 0.82 * dark) + NAVY * 0.82 * dark
    pal[SEA_E.ravel()] = sea.reshape(-1, 3)
    # wet strip
    skymir = lerp(cols[-1], cols[-2], 0.4) * 0.85
    sandlit = lerp((200, 170, 150), cols[-1], 0.35)
    ty2 = (np.arange(8) + 0.5) / 8
    wetc = skymir[None, :] * (1 - ty2)[:, None] + sandlit[None, :] * 0.8 * ty2[:, None]            # (8, 3)
    sunl = lerp(core, rim, 0.5)
    st = np.array(info['streak'])
    wc = wetc[:, None, :] + (sunl[None, None, :] - wetc[:, None, :]) * (st[None, :, None] * 0.7 * bse)
    wc = wc * (1 - 0.82 * dark) + NAVY * 0.82 * dark
    pal[WET_E.ravel()] = wc.reshape(-1, 3)
    # dry sand
    sd = lerp((214, 186, 150), cols[-1], 0.22) * 0.96 * (1 - 0.42 * e)
    litc = lerp(sd, sunl, 0.35 * bse); shdc = lerp(sd, np.array(cols[1]) * 0.9, 0.28) * 0.88
    qv = [0.6, 0.3, 0.0, -0.35, -0.75]; nw = [0.7, 0.3, 0.0]
    for i, q in enumerate(qv):
        col = sd + (litc - sd) * q if q > 0 else sd + (shdc - sd) * (-q)
        for j, w in enumerate(nw):
            cc = col * (1 - 0.12 * w)
            pal[DRY_E[i, j]] = cc * (1 - 0.82 * dark) + NAVY * 0.82 * dark
    # stars: a white ramp (added)
    for v in range(1, 16): pal[E_STAR + v] = STARW * v / 15
    # sun glow (added): bcol over the sky at the sun, 14 levels
    dl = np.clip(np.array(bcol) - daysun, 0, None)
    for v in range(1, 15): pal[E_BLOOM + v] = dl * (v / 14) * bstr * light
    # the sun and the moon (normal)
    cv = R['cov']
    for v in range(1, 11):
        dt = (v - 1) / 10.0
        if 0.01 < cv < 0.985:
            limb = math.sqrt(max(0, 1 - ((v - 0.5) / 10) ** 2))
            col = np.floor(np.array([255, 128, 24.0]) * (0.72 + 0.28 * limb) / 6) * 6
        else:
            col = ramp([core, core, lerp(core, rim, 0.5), rim, np.array(rim) * 0.95], dt)
        pal[E_BODY + v] = col
    pal[E_BODY + 11] = (70, 30, 10); pal[E_BODY + 12] = (255, 90, 150)
    pal[E_BODY + 13] = (8, 8, 14)
    pal[E_BODY + 14] = (6, 6, 12) if cv > 0.985 else skysun * 0.35 + np.array([15, 16, 19]) * (1 + dark)
    pal[E_BODY + 15] = (26, 28, 44)
    for v in range(1, 16): pal[E_GLOW + v] = np.clip(CORW - skysun, 0, None) * v / 15      # added to the sky near the moon = a mix towards white
    # foam lines (half and half): alpha .55 and .35 of a pale line over the sea nearest the shore
    under = sea[2, 0].reshape(-1, 3).mean(0)
    fc = lerp(cols[-1], (255, 255, 255), 0.5) * (1 - 0.82 * dark) + NAVY * 0.82 * dark
    for k, a in enumerate((0.55, 0.35)):
        pal[E_FOAM + 1 + k] = under + 2 * a * (fc - under)
    return np.clip(np.round(pal), 0, 255).astype(np.uint8)


# ---------------------------------------------------------------- sprite frames
def pack4(a):
    a = np.asarray(a, np.uint8)
    return ((a[:, 0::2] << 4) | a[:, 1::2]).tobytes()


def body_frame(R):
    SX, SY, mx, my, cov = R['SX'], R['SY'], R['mx'], R['my'], R['cov']
    ox, oy = int(round(SX)) - 16, int(round(SY)) - 16
    gy, gx = np.mgrid[oy:oy + 32, ox:ox + 32]
    d = np.sqrt((gx - SX) ** 2 + ((gy - SY) * 1.06) ** 2)
    dm = np.sqrt((gx - mx) ** 2 + (gy - my) ** 2)
    sun = d < SR
    idx = np.zeros((32, 32), np.uint8)
    idx[sun] = (np.floor(np.clip(d / SR, 0, 1) * 10) + 1).astype(np.uint8)[sun]
    if 0.01 < cov < 0.985:
        spx, spy = int(round(SX - SR * 0.25)), int(round(SY + SR * 0.1))
        if math.hypot(spx - mx, spy - my) > SR and sun[spy - oy, spx - ox]: idx[spy - oy, spx - ox] = 11
    mdisc = (dm < SR) & (sun | (cov > 0.95))
    idx[mdisc] = 13
    idx[mdisc & ~sun] = 14
    idx[((dm >= SR - 1) & (dm < SR) & sun) & mdisc] = 15
    if cov > 0.985:
        idx[dm < SR] = 14
        for pa in (2.3, 4.9):
            px, py = int(round(mx + math.cos(pa) * (SR + 0.6))), int(round(my + math.sin(pa) * (SR + 0.6)))
            if 0 <= py - oy < 32 and 0 <= px - ox < 32: idx[py - oy, px - ox] = 12
    # the moon must not be cut by the sprite's edge
    assert not (idx[0].any() or idx[-1].any() or idx[:, 0].any() or idx[:, -1].any()), 'body frame touches its edge'
    return ox, oy, pack4(idx), bool(idx.any())


RINGS = ((0.3, 90), (1.05, 60), (1.57, 120), (2.2, 70), (2.9, 100), (3.6, 55), (4.4, 110), (5.2, 65))


def glow_frames(R):
    """128 x 128 centred on the moon: the corona and the diamond ring as 15 levels, in four 64 x 64 quadrants."""
    SX, SY, mx, my, cov = R['SX'], R['SY'], R['mx'], R['my'], R['cov']
    ox, oy = int(round(mx)) - 64, int(round(my)) - 64
    gy, gx = np.mgrid[oy:oy + 128, ox:ox + 128]
    dm = np.sqrt((gx - mx) ** 2 + (gy - my) ** 2)
    TH2 = B8[gy % 8, gx % 8]
    v = np.zeros((128, 128))
    cstr = float(np.clip((cov - 0.88) / 0.11, 0, 1))
    if cstr > 0:
        rr = np.clip((dm - SR) / SR, 0, None)
        cor = np.exp(-rr * 4.0) * 0.9 + np.exp(-rr * 1.2) * 0.12
        cor = np.where(dm >= SR, cor, 0) * cstr
        cq = np.clip(np.floor(np.clip(cor, 0, 1) * 16 + TH2) / 16, 0, 1)
        v = cq * 0.9
    if 0.88 < cov < 0.995:
        vv = np.array([SX - mx, SY - my]); n = np.linalg.norm(vv) + 1e-6; vv = vv / n
        bx, by = mx + vv[0] * SR * 0.98, my + vv[1] * SR * 0.98
        rb = np.sqrt((gx - bx) ** 2 + (gy - by) ** 2)
        power = float(np.clip(1 - (cov - 0.88) / 0.115, 0, 1) ** 0.7)
        ring = np.exp(-(rb / 2.2) ** 2) * 1.4 + np.exp(-(rb / 7) ** 2) * 0.6
        for a0, ln in RINGS:
            ux, uy = math.cos(a0), math.sin(a0)
            along = (gx - bx) * ux + (gy - by) * uy; perp = np.abs(-(gx - bx) * uy + (gy - by) * ux)
            win = np.clip(1 - (np.abs(along) / 62.0) ** 2, 0, 1)            # the spike ends softly at the sprite's edge
            ring = ring + np.exp(-(perp / 0.7) ** 2) * np.exp(-np.abs(along) / ln) * 0.9 * win
        ring = np.clip(ring * power, 0, 1)
        v = np.maximum(v, np.floor(ring * 12) / 12)
    d = np.sqrt((gx - SX) ** 2 + ((gy - SY) * 1.06) ** 2)
    hide = ((d < SR) & (0.01 < cov < 0.985)) | ((dm < SR) & ((d < SR) | (cov > 0.95)))     # the sun and the moon are drawn over the ring
    v[hide] = 0
    lvl = np.clip(np.round(v * 15), 0, 15).astype(np.uint8)
    q = []
    for qy in (0, 1):
        for qx in (0, 1):
            blk = lvl[qy * 64:(qy + 1) * 64, qx * 64:(qx + 1) * 64]
            q.append((ox + qx * 64, oy + qy * 64, pack4(blk), bool(blk.any())))
    return q


def bloom_quadrants():
    gy, gx = np.mgrid[0:128, 0:128]
    d = np.sqrt((gx - 63.5) ** 2 + ((gy - 63.5) * 1.06) ** 2)
    R = 120 + 40 * 0.27
    b = np.clip(1 - d / R, 0, 1) ** 2.3 * np.clip(1 - (d / 58.0) ** 2, 0, 1) ** 2      # fades to nothing at the sprites' edge (no visible rim)
    f = b * 14
    k = np.floor(f); lvl = np.clip(k + ((f - k) > B8[gy % 8, gx % 8]), 0, 14).astype(np.uint8)
    return [pack4(lvl[qy * 64:(qy + 1) * 64, qx * 64:(qx + 1) * 64]) for qy in (0, 1) for qx in (0, 1)]


def star_list():
    sr = np.random.default_rng(3)
    return [(int(sr.uniform(0, 320)), int(sr.uniform(0, 100)), sr.uniform(0.3, 1.0), sr.uniform(0, 6.28), sr.uniform(0.08, 0.25))
            for _ in range(90)]


def foam_chunks():
    """per line k (offset -3, -7) and chunk c (64 px): 64 x 16 graphics with the line at its place, and the chunk's top y"""
    out = {}
    for k, o in enumerate((-3, -7)):
        for c in range(5):
            yl = np.round(edge[c * 64:(c + 1) * 64]).astype(int) + o
            ymin = int(yl.min())
            g = np.zeros((16, 64), np.uint8)
            for col in range(64): g[yl[col] - ymin + 4, col] = 1 + k
            out[(k, c)] = (ymin - 4, pack4(g))
    return out


# ---------------------------------------------------------------- the tables
def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    out = args[0]; os.makedirs(out, exist_ok=True)
    prev = []
    for a in sys.argv[1:]:
        if a.startswith('--preview='): prev = [int(x) for x in a.split('=')[1].split(',')]
    pic, info = build_picture()
    states = [state(n) for n in range(NTICK)]
    # graphics blob (sprite graphics, deduplicated), 32-byte units
    blob = bytearray(); seen = {}

    def gfx(b):
        b = bytes(b)
        if b not in seen:
            seen[b] = len(blob) // 32; blob.extend(b)
        return seen[b]
    empty64 = gfx(bytes(2048))
    star_g = [gfx(bytes(32))] + [gfx(bytes([v << 4]) + bytes(31)) for v in range(1, 16)]
    foam = foam_chunks()
    foam_g = {key_: gfx(v[1]) for key_, v in foam.items()}
    bloom_g = [gfx(q) for q in bloom_quadrants()]
    stars = star_list()
    recs = {}
    for r in range(NREC):
        R = states[r * REC]
        bx, by, bg, bon = body_frame(R)
        if r % 2 == 0: gq = [(x, y, gfx(g), on) for x, y, g, on in glow_frames(R)]      # the corona changes slowly: a frame every 2 records
        recs[r] = (R, (bx, by, gfx(bg), bon), gq)
    # per tick records
    NSPR = 4 + 1 + 4 + 10 + 90
    tickrec = bytearray()
    pals = []
    for n in range(NTICK):
        S = states[n]; R, body, glow = recs[n // REC]
        pal = palette(S, R, info); pals.append(pal)
        sat = bytearray()

        def spr(x, y, g, f6, f7):
            sat.extend(struct.pack('<hhHBB', x, y, g, f6, f7))
        for (x, y, g, on) in glow: spr(x, y, g, 0x8f if on else 0, 0x83)
        spr(body[0], body[1], body[2], 0x8a if body[3] else 0, 0x02)
        sx_, sy_ = int(round(S['SX'])), int(round(S['SY']))
        for j in range(4): spr(sx_ - 64 + (j & 1) * 64, sy_ - 64 + (j >> 1) * 64, bloom_g[j], 0x8f, 0x81)
        for k in range(2):
            rel = 2.5 * math.sin(S['i30'] * 0.05 + k * 1.7)
            for c in range(5):
                top, _ = foam[(k, c)]
                spr(c * 64, top + int(round(rel)), foam_g[(k, c)], 0x87, 0x44)
        dark = S['dark']
        for (sx, sy, br, phs, sp) in stars:
            show = np.clip((dark - 0.45 - sy / HZ * 0.35) * 3, 0, 1) * br * (0.55 + 0.45 * math.sin(S['i30'] * sp + phs))
            lv = int(round(min(1.0, show) * 15)) if show > 0.02 else 0
            spr(sx, sy, star_g[lv], 0x80 if lv else 0, 0x80)
        assert len(sat) == NSPR * 8
        planar = pal[:, 0].tobytes() + pal[:, 1].tobytes() + pal[:, 2].tobytes()
        tickrec.extend((planar + bytes(sat)).ljust(2048, b'\0'))
    # the REU image
    R_PIC = 0; LEN_PIC = 512 * 256
    R_SPR = R_PIC + LEN_PIC
    R_TICK = (R_SPR + len(blob) + 0xFFFF) & ~0xFFFF
    reu = bytearray(R_TICK) + tickrec
    reu[R_PIC:R_PIC + LEN_PIC] = pic.tobytes()
    reu[R_SPR:R_SPR + len(blob)] = blob
    open(os.path.join(out, 'Eclipse Beach.reu'), 'wb').write(reu)
    inc = ['; made by gen.py', 'R_PIC = $%06x' % R_PIC, 'LEN_PIC = $%06x' % LEN_PIC, 'R_SPR = $%06x' % R_SPR,
           'LEN_SPR = $%06x' % len(blob), 'R_TICK = $%06x' % R_TICK, 'NTICK = %d' % NTICK, 'NSPR = %d' % NSPR,
           'SATLEN = %d' % (NSPR * 8)]
    open(os.path.join(out, 'data.inc'), 'w').write('\n'.join(inc) + '\n')
    print('reu %d bytes: picture %d, sprite graphics %d (%d unique frames), %d ticks x 2048' % (len(reu), LEN_PIC, len(blob), len(seen), NTICK))
    # ---- OctoPaint pictures
    def save_oct(name, px, pal):
        blob_ = mkoct.make_oct(px.tobytes(), [tuple(int(c) for c in r) for r in pal])
        open(os.path.join(out, name), 'wb').write(blob_)
    p0 = pals[0]
    sky = np.zeros((H, W), np.uint8); sky[:HZ] = pic[:HZ, :W]
    sea = np.zeros((H, W), np.uint8); sea[HZ:] = np.where(np.isin(pic[HZ:H, :W], SEA_E), pic[HZ:H, :W], 0)
    beach = np.zeros((H, W), np.uint8); beach[HZ:] = np.where(np.isin(pic[HZ:H, :W], SEA_E), 0, pic[HZ:H, :W])
    save_oct('sky.oct', sky, p0); save_oct('sea.oct', sea, p0); save_oct('beach.oct', beach, p0)
    # sun/moon frames: 30 body frames drawn 10 across (32 x 32), palette of a tick well inside the orange phase
    tk = next(n for n in range(NTICK) if 0.3 < states[n]['cov'] < 0.6)
    sheet = np.zeros((H, W), np.uint8)
    ppal = palette(states[tk], recs[tk // REC][0], info)
    for i in range(30):
        r = int((i + 0.5) / 30 * NREC)
        R = recs[r][0]; _, _, bg, _ = body_frame(R)
        a = np.frombuffer(bg, np.uint8); a = np.stack([a >> 4, a & 15], -1).reshape(32, 32)
        sheet[(i // 10) * 40 + 4:(i // 10) * 40 + 36, (i % 10) * 32:(i % 10) * 32 + 32] = np.where(a > 0, E_BODY + a, 0)
    save_oct('sun frames.oct', sheet, ppal)
    # corona frames: the 128 x 128 glow at the start of the corona, close to totality, at totality
    sheet2 = np.zeros((H, W), np.uint8)
    pk = [n for n in range(NTICK) if states[n]['cov'] > 0.88]
    for j, n in enumerate((pk[0], pk[len(pk) // 4], pk[len(pk) // 2])):
        q = glow_frames(states[n])
        blk = np.zeros((128, 128), np.uint8)
        for i, (x, y, g, on) in enumerate(q):
            a = np.frombuffer(g, np.uint8); a = np.stack([a >> 4, a & 15], -1).reshape(64, 64)
            blk[(i >> 1) * 64:(i >> 1) * 64 + 64, (i & 1) * 64:(i & 1) * 64 + 64] = a
        sub = blk[::2, ::2]                       # a half size overview of each frame (64 x 64)
        sheet2[8:72, j * 100 + 8:j * 100 + 72] = np.where(sub > 0, E_GLOW + sub, 0)
        sheet2[88:152, j * 100 + 8:j * 100 + 72] = np.where(blk[32:96, 32:96] > 0, E_GLOW + blk[32:96, 32:96], 0)
    save_oct('corona frames.oct', sheet2, ppal)
    # ---- previews: the picture as the machine draws it
    for n in prev:
        img = render(pic, pals[n], tickrec, n)
        from PIL import Image
        Image.fromarray(img).save(os.path.join(out, 'preview_%04d.png' % n))


def render(pic, pal, tickrec, n):
    """the picture layer alone with tick n's palette (the sprites are not drawn: the emulator shows the whole)"""
    return np.clip(pal[pic[:H, :W]].astype(float), 0, 255).astype(np.uint8)


if __name__ == '__main__':
    main()
