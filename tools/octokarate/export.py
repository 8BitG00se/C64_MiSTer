#!/usr/bin/env python3
# export.py - Octo Karate build 3: prepares ALL the data octokarate.asm needs (the PC prepares data only):
#   export.py OUTDIR  writes into OUTDIR:  Octo Karate.reu  data.inc  charset.bin  sheets/*.oct  report.txt
# * every distinct drawing of both fighters as OctoVIC sprite cells (256 colours, one palette for both), and per drawing a HURT box
#   set (head, torso, legs) and, for strike drawings, a HIT box, all measured from the pixels (fighters.py)
# * the moves as frame data, the walk/hit/fall sequences, text and the HUD character set
# * the Eclipse Beach stage (stage.py) with the fighters' colours faded by palette each tick, hit sparks and shadows
import sys, os, struct, math
ARGV = list(sys.argv)
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', 'octopaint'))
import fighters as F, stage as S, font, mkoct
sys.argv = ARGV

NG = 16                       # game sprites ahead of the stage's in the sprite table
BOXY = 80                     # the drawing box's top line on screen
ROWS = [(8, 64), (72, 32), (104, 8)]               # sprite rows inside the drawing: (first row, height)
WIN = {'Vic': [(32, 64), (96, 32)], 'Sid': [(0, 64), (64, 32)]}     # columns: (first col, width)
HC = {8: 0, 16: 1, 32: 2, 64: 3}; WC = {8: 0, 16: 1, 32: 2, 64: 3}
NF = 56                       # colours for both fighters


def quantize(cols, wts, k):
    cols = np.array(cols, float); wts = np.array(wts, float)
    if len(cols) <= k: return cols, np.arange(len(cols))
    # start from the heaviest colours, then farthest-point fill, then weighted k-means
    cen = [cols[wts.argmax()]]
    d = ((cols - cen[0]) ** 2).sum(1)
    while len(cen) < k:
        i = (d * np.sqrt(wts)).argmax(); cen.append(cols[i]); d = np.minimum(d, ((cols - cols[i]) ** 2).sum(1))
    cen = np.array(cen)
    for _ in range(30):
        a = ((cols[:, None, :] - cen[None]) ** 2).sum(2).argmin(1)
        for j in range(k):
            m = a == j
            if m.any(): cen[j] = (cols[m] * wts[m, None]).sum(0) / wts[m].sum()
    a = ((cols[:, None, :] - cen[None]) ** 2).sum(2).argmin(1)
    return np.round(cen), a


NPALMAX = 29                  # colours per fighter (the 58 free palette entries are shared by the two fighters)
FADEROWS = 64                 # light levels the loader builds fade tables for
ROWPX = 96                    # one fade row: 32 red, 32 green, 32 blue
FILE_HDR = 256; REC = 64      # fighter file: header bytes, bytes per drawing record
MAXND = 56


def layout_row(a):
    """one sprite row of a drawing (a: bool array rows x cols) -> list of (x0, width) cells (at most 2) covering its pixels, cheapest first"""
    cols = np.where(a.any(0))[0]
    if len(cols) == 0: return []
    x0, x1 = int(cols.min()), int(cols.max()); need = x1 - x0 + 1
    best = None
    for w0 in (8, 16, 32, 64):
        for w1 in (0, 8, 16, 32, 64):
            if w0 + w1 >= need and (best is None or w0 + w1 < best[0] or (w0 + w1 == best[0] and w1 < best[2])): best = (w0 + w1, w0, w1)
    assert best is not None, 'a drawing row is wider than 128 pixels'
    cells = [(x0, best[1])]
    if best[2]: cells.append((x0 + best[1], best[2]))
    return cells


def build_fighter(C, imgs, pal_entries, cen, asg_of, small, hudcol, boxes_fn):
    """-> (file bytes, info dict). The FIGHTER FORMAT is documented in README.md."""
    nm = C['name']; flip = C is F.SID
    blob = bytearray(); seen = {}
    def gfx(b):
        b = bytes(b)
        if b not in seen: seen[b] = len(blob) // 32; blob.extend(b)
        return seen[b]
    recs = bytearray(); box = {}
    for n in F.ORDER:
        im, P1, oc = imgs[(nm, n)]
        a = im[..., 3] > 0
        idx = np.zeros((im.shape[0], im.shape[1] + 64), np.uint8)
        for y, x in zip(*np.where(a)): idx[y, x] = pal_entries[asg_of[tuple(int(v) for v in im[y, x, :3])]]
        ys, xs = np.where(a)
        assert ys.min() >= ROWS[0][0] and ys.max() < ROWS[-1][0] + ROWS[-1][1], (nm, n, ys.min(), ys.max())
        mask = 0; gp = [0] * 6; sdx = [0] * 6; sfl = [0] * 6; sdy = [0] * 6
        for ri, (ry, rh) in enumerate(ROWS):
            for ci, (cx, cw) in enumerate(layout_row(a[ry:ry + rh])):
                s = ci * 3 + ri
                cell = np.zeros((rh, cw), np.uint8); part = idx[ry:ry + rh, cx:cx + cw]; cell[:, :part.shape[1]] = part
                mask |= 1 << s; gp[s] = gfx(cell.tobytes()); sdx[s] = cx; sdy[s] = ry; sfl[s] = 0xC0 | (HC[rh] << 2) | WC[cw]
        hurt, hit = boxes_fn(im, P1, oc, flip, n in F.STRIKES)
        box[n] = (hurt, hit)
        rec = bytearray(REC)
        rec[0] = mask; rec[1] = oc
        for s in range(6): struct.pack_into('<H', rec, 2 + 2 * s, gp[s])
        rec[14] = 1 if hit else 0
        for i, b in enumerate(hurt):
            for j in range(4): rec[16 + i * 4 + j] = b[j] & 255
            assert -128 <= b[0] and b[1] < 128 and 0 <= b[2] <= b[3] < 112, (nm, n, b)
        if hit:
            for j in range(4): rec[28 + j] = hit[j] & 255
            assert -128 <= hit[0] and hit[1] < 128
        for s in range(6): rec[32 + s] = sdx[s]; rec[38 + s] = sfl[s]; rec[44 + s] = sdy[s]
        recs += rec
    nd = len(F.ORDER); assert nd <= MAXND
    # sequences
    seq = bytearray(); moff = []
    for m in F.MOVES:
        moff.append(len(seq)); seq += bytes(F.DID[n] for n, h in m['seq'] for _ in range(h))
    assert len(seq) < 256
    # reach data (measured from the pixels): the guard's forward extent (silhouette, hurt boxes) and each strike's forward tip
    g_im, _, g_oc = imgs[(nm, 'guard')]; ga = g_im[..., 3] > 0; gys, gxs = np.where(ga)
    gbody = int((gxs.max() - g_oc) if not flip else (g_oc - gxs.min()))
    gh = box['guard'][0]
    gfront = int(max(gh[0][1], gh[1][1]) if not flip else -min(gh[0][0], gh[1][0]))
    hdr = bytearray(FILE_HDR)
    hdr[0:4] = b'OKF1'
    hdr[4:12] = bytes(small[c] for c in nm.upper().ljust(8))
    hdr[12] = hudcol; hdr[13] = len(cen); hdr[14] = nd; hdr[15] = len(F.MOVES); hdr[16] = 1 if flip else 0
    struct.pack_into('<H', hdr, 18, len(blob) // 32); struct.pack_into('<H', hdr, 20, len(seq))
    hdr[22] = 1                                                    # the graphics start at 64 KB into the file
    hdr[24] = gbody; hdr[25] = gfront
    for i, e in enumerate(pal_entries): hdr[32 + i] = int(e)
    for i, c in enumerate(cen): hdr[64 + i * 3:67 + i * 3] = bytes(int(v) for v in c)
    std = ['guard', 'bob1', 'bob2', 'block', 'crouch', 'cblock', 'hit1', 'hit2', 'hit3', 'fall1', 'fall2', 'lie'] + F.WALK_NAMES
    for i, n in enumerate(std): hdr[160 + i] = F.DID[n]
    for i, m in enumerate(F.MOVES):
        o = 184 + i * 14; hit = box[m['strike']][1]
        tip = int(hit[1] if not flip else -hit[0])
        vals = [len(F.MOVES[i]['seq_ids']), m['startup'], m['startup'] + m['active'] - 1, m['dmg'], m['hitstop'], m['hitstun'], m['blockstun'],
                m['pushhit'], m['pushblock'], m['level'], tip, 0, 0, F.DID[m['strike']]]
        base = FILE_HDR + nd * REC
        vals[11] = (base + moff[i]) & 255; vals[12] = (base + moff[i]) >> 8
        hdr[o:o + 14] = bytes(vals)
    body = bytes(hdr) + bytes(recs) + bytes(seq)
    assert len(body) <= 65536
    fil = body.ljust(65536, b'\0') + bytes(blob)
    return fil, dict(box=box, gbody=gbody, gfront=gfront, gfx=len(blob) // 32, nd=nd, std=std)


def main():
    out = [a for a in ARGV[1:] if not a.startswith('--')][0]
    os.makedirs(out, exist_ok=True); os.makedirs(os.path.join(out, 'sheets'), exist_ok=True); os.makedirs(os.path.join(out, 'fighters'), exist_ok=True)
    rep = []
    for m in F.MOVES: m['seq_ids'] = [F.DID[n] for n, h in m['seq'] for _ in range(h)]
    # ------------------------------------------------------------------ fighters: render, one palette each
    imgs = {}
    for C in (F.VIC, F.SID):
        for n in F.ORDER: imgs[(C['name'], n)] = F.render_pose(C, n)
    cs, small, bigm, seg = font.build()
    pals = {}
    for C in (F.VIC, F.SID):
        cnt = {}
        for (c, n), (im, P1, oc) in imgs.items():
            if c != C['name']: continue
            a = im[..., 3] > 0
            for p in im[a][:, :3]: cnt[tuple(int(v) for v in p)] = cnt.get(tuple(int(v) for v in p), 0) + 1
        cl = list(cnt); cen, asg = quantize(cl, [cnt[c] for c in cl], NPALMAX)
        ent = S.fighter_entries(len(cen))
        pals[C['name']] = (cen, {c: int(a) for c, a in zip(cl, asg)}, ent)
        rep.append('%s: %d distinct colours -> %d palette entries %s' % (C['name'], len(cl), len(cen), list(map(int, ent))))
    palstage = min(int(e) for n_ in pals for e in pals[n_][2])      # entries below: the stage's (written every tick by the main loop); from here: the fighters' (written by the loader's fade tables only)
    assert sorted(int(e) for n_ in pals for e in pals[n_][2]) == list(range(palstage, palstage + sum(len(pals[n_][2]) for n_ in pals)))
    GOLD, WHITE, VBLUE, SWHITE = 2, 1, 13, 14
    HUDC = {'Vic': VBLUE, 'Sid': SWHITE}
    files = {}; finfo = {}
    for C in (F.VIC, F.SID):
        cen, amap, ent = pals[C['name']]
        files[C['name']], finfo[C['name']] = build_fighter(C, imgs, ent, cen, amap, small, HUDC[C['name']], F.boxes)
        open(os.path.join(out, 'fighters', C['name'].lower() + '.okf'), 'wb').write(files[C['name']])
        rep.append('%s: file %d bytes, %d drawings, %d graphics cells (%d bytes), guard body %d front %d' % (C['name'], len(files[C['name']]), finfo[C['name']]['nd'],
                   finfo[C['name']]['gfx'], finfo[C['name']]['gfx'] * 32, finfo[C['name']]['gbody'], finfo[C['name']]['gfront']))
    fighter_bytes = sum(i['gfx'] * 32 for i in finfo.values())
    boxd = {(nm, n): v for nm, i in finfo.items() for n, v in i['box'].items()}
    # ------------------------------------------------------------------ the stage's cells
    blob = bytearray(); seen = {}
    def gfx(b):
        b = bytes(b)
        if b not in seen:
            seen[b] = len(blob) // 32; blob.extend(b)
        return seen[b]
    EMPTY = gfx(bytes(32))
    # ------------------------------------------------------------------ sparks and shadow (16 colour, bank 0)
    def pack4(a): a = np.asarray(a, np.uint8); return ((a[:, 0::2] << 4) | a[:, 1::2]).tobytes()
    gy, gx = np.mgrid[0:32, 0:32]; dx, dy = gx - 15.5, gy - 15.5
    dd = np.hypot(dx, dy); th = np.arctan2(dy, dx)
    sparks = []
    for R in (7, 12, 15, 11):             # a starburst that grows and breaks up
        lim = R * (0.42 + 0.58 * np.abs(np.cos(th * 4)) ** 1.5)
        f = dd / np.maximum(lim, 0.1)
        v = np.where(f < 0.4, 9, np.where(f < 0.7, 10, np.where(f < 0.9, 11, 12))).astype(np.uint8)
        v[f >= 1.0] = 0
        if R == 11: v[(gx * 7 + gy * 3) % 5 == 0] = 0
        sparks.append(v)
    for R in (6, 10, 13):                 # a blocked hit: a pale ring
        ring = (np.abs(dd - R) < 1.2) & (((th * 8 / math.pi) % 2.0) < 1.5)
        v = np.zeros((32, 32), np.uint8); v[ring] = 13; v[dd < 2.2] = 9 if R < 12 else 0
        sparks.append(v)
    spark_g = [gfx(pack4(v)) for v in sparks]
    sy_, sx_ = np.mgrid[0:16, 0:64]
    e = (((sx_ - 31.5) / 30.0) ** 2 + ((sy_ - 7.5) / 6.5) ** 2)
    sh = np.where(e < 0.7, 14, np.where(e < 1.0, np.where((sx_ + sy_) % 2 == 0, 14, 0), 0)).astype(np.uint8)
    shadow_g = gfx(pack4(sh))
    # ------------------------------------------------------------------ the stage
    pic, info = S.build_picture()
    states = [S.state(n) for n in range(S.NTICK)]
    empty64 = gfx(bytes(2048))
    star_g = [gfx(bytes(32))] + [gfx(bytes([v << 4]) + bytes(31)) for v in range(1, 9)]
    foam = S.foam_chunks(); foam_g = {k: gfx(v[1]) for k, v in foam.items()}
    bloom_g = [gfx(q) for q in S.bloom_quadrants()]
    stars = S.star_list()
    REC = S.REC; NREC = S.NREC
    GLOWEVERY = 2
    recs = {}
    for r in range(NREC):
        R = states[r * REC]
        bx, by, bg, bon = S.body_frame(R)
        if r % GLOWEVERY == 0: gq = [(x, y, gfx(g), on) for x, y, g, on in S.glow_frames(R)]
        recs[r] = (R, (bx, by, gfx(bg), bon), gq)
    NSPR = 4 + 1 + 4 + 10 + 90
    tick = bytearray()
    spal = [None] * S.NTICK
    # the fighters' colours: base RGB, faded by the eclipse's light
    levels = []
    for n in range(S.NTICK):
        St = states[n]; R, body, glow = recs[n // REC]
        pal = S.palette(St, R, info).astype(float)
        f = St['light']
        levels.append(int(round(St['light'] * (FADEROWS - 1))))      # the fighters' colours are faded at run time by the loader's tables
        pal[S.E_SPARK + 0] = (0, 0, 0)
        for i, c in enumerate([(255, 255, 235), (255, 224, 96), (255, 150, 40), (230, 70, 30), (190, 225, 255)]): pal[S.E_SPARK + i] = c
        pal[S.E_SHADOW] = np.array([62, 58, 50]) * (0.35 + 0.65 * f)
        pal = np.clip(np.round(pal), 0, 255).astype(np.uint8); pal[0] = 0
        spal[n] = pal
        sat = bytearray()
        def spr(x, y, g, f6, f7): sat.extend(struct.pack('<hhHBB', x, y, g, f6, f7))
        for (x, y, g, on) in glow: spr(x, y, g, 0x8f if on else 0, 0x83)
        spr(body[0], body[1], body[2], 0x8a if body[3] else 0, 0x02)
        sx_i, sy_i = int(round(St['SX'])), int(round(St['SY']))
        for j in range(4): spr(sx_i - 64 + (j & 1) * 64, sy_i - 64 + (j >> 1) * 64, bloom_g[j], 0x8f, 0x81)
        for kk in range(2):
            rel = 2.5 * math.sin(St['i30'] * 0.05 + kk * 1.7)
            for c in range(5):
                top, _ = foam[(kk, c)]
                spr(c * 64, top + int(round(rel)), foam_g[(kk, c)], 0x87, 0x41)
        dark = St['dark']
        for (sx, sy, br, phs, sp) in stars:
            show = np.clip((dark - 0.45 - sy / S.HZ * 0.35) * 3, 0, 1) * br * (0.55 + 0.45 * math.sin(St['i30'] * sp + phs))
            lv = int(round(min(1.0, show) * 8)) if show > 0.02 else 0
            spr(sx, sy, star_g[lv], 0x80 if lv else 0, 0x80)
        assert len(sat) == NSPR * 8
        planar = pal[:, 0].tobytes() + pal[:, 1].tobytes() + pal[:, 2].tobytes()
        tick.extend((planar + bytes(sat)).ljust(2047, b'\0') + bytes([levels[-1]]))
    stage_bytes = len(blob)
    print('stage', stage_bytes, 'fighters', fighter_bytes)
    assert stage_bytes + fighter_bytes < 65535 * 32, 'sprite graphics do not fit the 2 MB window: %d' % (stage_bytes + fighter_bytes)
    rep.append('sprite graphics %d bytes (fighters %d, stage + sparks %d); window 2 MB = 2097152' % (stage_bytes + fighter_bytes, fighter_bytes, stage_bytes))
    # ------------------------------------------------------------------ the REU image
    al = lambda v: (v + 0xFFFF) & ~0xFFFF
    R_PIC = 0; LEN_PIC = 512 * 256; R_SPR = 0x20000
    R_F0 = al(R_SPR + len(blob)); R_F1 = al(R_F0 + len(files['Vic'])); R_SCR = al(R_F1 + len(files['Sid'])); R_TICK = R_SCR + 0x10000
    reu = bytearray(R_TICK) + tick
    reu[R_PIC:R_PIC + LEN_PIC] = pic.tobytes()
    reu[R_SPR:R_SPR + len(blob)] = blob
    reu[R_F0:R_F0 + len(files['Vic'])] = files['Vic']; reu[R_F1:R_F1 + len(files['Sid'])] = files['Sid']
    open(os.path.join(out, 'Octo Karate.reu'), 'wb').write(reu)
    rep.append('reu %d bytes: picture 128K at 0, stage graphics at $%06x, fighter files at $%06x and $%06x, scratch at $%06x, %d ticks at $%06x' % (len(reu), R_SPR, R_F0, R_F1, R_SCR, S.NTICK, R_TICK))
    # ------------------------------------------------------------------ text and charset
    open(os.path.join(out, 'charset.bin'), 'wb').write(cs)
    def msg(col, row, colour, text, big=False):
        r = bytearray()
        if not big:
            r += bytes([col, row, colour]) + bytes(small[c] for c in text) + b'\xff'
        else:
            for k in (0, 2):
                r += bytes([col, row + (k // 2), colour])
                for c in text: r += bytes([bigm[c][k], bigm[c][k + 1]])
                r += b'\xff'
        return bytes(r)
    def blank(col, row, n, big=False): return msg(col, row, 0, ' ' * n, big)
    M = {}
    bigm_by_code = {small[c]: v for c, v in bigm.items()}
    M['title'] = msg(9, 3, GOLD, 'OCTO KARATE', True)
    M['press'] = msg(15, 6, WHITE, 'PRESS FIRE')
    M['press_off'] = blank(15, 6, 10)
    M['ports'] = msg(1, 8, 12, 'PORT 2 = 1 PLAYER   PORT 1 = 2 PLAYERS')
    M['pg0'] = M['title'] + M['press'] + M['ports']
    M['pg1'] = (msg(15, 3, WHITE, 'CONTROLS') + msg(10, 4, GOLD, 'FIRE: PUNCH') + msg(10, 5, GOLD, 'UP+FIRE: HEAD KICK')
                + msg(10, 6, GOLD, 'FWD+FIRE: BODY KICK') + msg(10, 7, GOLD, 'BACK+FIRE: FRONT KICK') + msg(10, 8, GOLD, 'DOWN+FIRE: SHIN LOW')
                + msg(10, 9, WHITE, 'HOLD BACK: BLOCK') + msg(10, 10, WHITE, 'DOWN+BACK: BLOCK LOW'))
    M['title_off'] = b''.join(blank(1, r, 39) for r in range(3, 13)) + blank(9, 3, 22) + blank(9, 4, 22)
    M['round1'] = msg(13, 7, WHITE, 'ROUND 1', True)
    M['round2'] = msg(13, 7, WHITE, 'ROUND 2', True)
    M['round3'] = msg(9, 7, WHITE, 'FINAL ROUND', True)
    M['fight'] = msg(14, 7, GOLD, 'FIGHT!', True)
    M['ko'] = msg(17, 7, 10, 'K.O.', True)
    M['timeup'] = msg(13, 7, WHITE, 'TIME UP', True)
    M['draw'] = msg(17, 7, WHITE, 'DRAW', True)
    M['banner_off'] = blank(6, 7, 28) + blank(6, 8, 28)
    lab = '1PIC 2GLO 3SUN 4RNG 5STR 6FOM 7FTR 8HUD'
    assert len(lab) <= 40
    # ------------------------------------------------------------------ frame data
    d = []
    def a(*l): d.extend(l)
    a('; made by export.py')
    a('NG = %d' % NG, 'NSPR = %d' % NSPR, 'SATLEN = %d' % (NSPR * 8), 'NTICK = %d' % S.NTICK, 'BOXY = %d' % BOXY)
    a('R_PIC = $%06x' % R_PIC, 'LEN_PIC = $%06x' % LEN_PIC, 'R_SPR = $%06x' % R_SPR, 'LEN_SPR = $%06x' % len(blob), 'R_SCR = $%06x' % R_SCR, 'R_TICK = $%06x' % R_TICK)
    a('G_SPARK = %d' % spark_g[0], 'G_SHADOW = %d' % shadow_g)
    a('SEGCH = %d' % seg)
    sp = ', '.join(str(g_) for g_ in spark_g)
    a('spark_lo !byte ' + ','.join(str(g_ & 255) for g_ in spark_g))
    a('spark_hi !byte ' + ','.join(str(g_ >> 8) for g_ in spark_g))
    def bytes_(label, bs):
        d.append(label)
        for i in range(0, len(bs), 16): d.append('  !byte ' + ','.join(str(int(b) & 255) for b in bs[i:i + 16]))
    d.append('DIG0 = %d' % small['0'])
    # the fighters: where their files are, and the engine-wide animation timing (the fighter data holds everything else)
    a('F0_REU = $%06x' % R_F0, 'F1_REU = $%06x' % R_F1, 'FADE0_REU = $%06x' % R_SCR, 'FADE1_REU = $%06x' % (R_SCR + 0x2000))
    a('VFREE0 = %d' % (len(blob) // 32))
    a('PALSTAGE = %d' % palstage)
    a('NMOVES = 5', 'MAXND = %d' % MAXND, 'FADEROWS = %d' % FADEROWS)
    a('FALL1_T = %d' % F.FALL_SEQ[0][1], 'FALL2_T = %d' % (F.FALL_SEQ[0][1] + F.FALL_SEQ[1][1]), 'FALL3_T = %d' % (sum(h for _, h in F.FALL_SEQ)))
    a('STRIDE = %d' % F.STRIDE)
    # the light levels: fighter colour = base * K / 256 + tint
    kk, tr, tg, tb = [], [], [], []
    for l in range(FADEROWS):
        f = l / (FADEROWS - 1.0); k = 0.30 + 0.70 * f
        kk.append(min(255, int(round(k * 256)))); t = np.array([18, 22, 48]) * (1 - f) * 0.6
        tr.append(int(round(t[0]))); tg.append(int(round(t[1]))); tb.append(int(round(t[2])))
    bytes_('lv_k', kk); bytes_('lv_tr', tr); bytes_('lv_tg', tg); bytes_('lv_tb', tb)
    bt = []
    for code in range(seg): bt += list(bigm_by_code.get(code, (0, 0, 0, 0)))
    bytes_('bigtab', bt)
    bytes_('wins_codes', [small[c] for c in 'WINS'])
    for k, v in M.items(): bytes_('msg_' + k, v + b'\xfe')
    bytes_('rowlo', [(0x0400 + r * 40) & 255 for r in range(25)]); bytes_('rowhi', [(0x0400 + r * 40) >> 8 for r in range(25)])
    bytes_('barcol', [3 + min(7, int(round((16 - n) * 7 / 15.0))) if n else 10 for n in range(17)])
    d.append('bigdig ; 4 codes a digit')
    for dg in '0123456789': d.append('  !byte ' + ','.join(str(c) for c in bigm[dg]))
    bytes_('t_lab', [small[c] for c in lab.ljust(40)])
    bytes_('t_dbg', [small[c] for c in 'LATE 00000 MAX 00000 TOT 00000 OVR 00000'])
    d.append('lstart !byte 0,6,13,19,26,33,40,47'.replace('0,6,13,19,26,33,40,47', ','.join(str(i) for i in label_starts(lab))))
    d.append('lend !byte ' + ','.join(str(i) for i in label_ends(lab)))
    open(os.path.join(out, 'data.inc'), 'w').write('\n'.join(d) + '\n')
    # ------------------------------------------------------------------ report
    rep.append('moves (name level startup active total dmg hitstop hitstun blockstun pushhit pushblock tip):')
    for m in F.MOVES:
        rep.append('  %-12s %s %2d %2d %2d  %2d %d %2d %2d %2d %2d  tip V %d S %d' % (m['name'], 'HML'[m['level']], m['startup'], m['active'], len(m['seq_ids']), m['dmg'], m['hitstop'],
                   m['hitstun'], m['blockstun'], m['pushhit'], m['pushblock'], boxd[('Vic', m['strike'])][1][1], -boxd[('Sid', m['strike'])][1][0]))
    gb = [finfo[n]['gbody'] for n in ('Vic', 'Sid')]; gf = [finfo[n]['gfront'] for n in ('Vic', 'Sid')]
    reach = [[boxd[('Vic', m['strike'])][1][1] + gf[1] - 3, -boxd[('Sid', m['strike'])][1][0] + gf[0] - 3] for m in F.MOVES]
    rep.append('reach (V, S) per move %s; pushgap %d, restgap %d, hover %d' % (reach, min(min(r) for r in reach), gb[0] + gb[1], max(max(r) for r in reach) + 2))
    sheets(out, imgs, pals, rep)
    open(os.path.join(out, 'report.txt'), 'w').write('\n'.join(rep) + '\n'); print('\n'.join(rep))


def label_starts(lab):
    # label groups: "1 PIC", "2 GLOW", ... (each starts at its digit)
    pos = [i for i, c in enumerate(lab) if c.isdigit() and (i == 0 or lab[i - 1] == ' ')]
    return pos


def label_ends(lab):
    pos = label_starts(lab); return [p - 1 for p in pos[1:]] + [len(lab)]


def sheets(out, imgs, pals, rep):
    """the fighters' drawings as OctoPaint pictures (320 x 200, one palette), packed by their outlines"""
    from PIL import Image
    for nm in ('Vic', 'Sid'):
        cen, amap, ent = pals[nm]
        pal = [(70, 74, 92)] + [tuple(int(v) for v in c) for c in cen] + [(0, 0, 0)] * (255 - len(cen))
        pages = []; cur = np.zeros((200, 320), np.uint8); x = y = rowh = 0
        for n in F.ORDER:
            im = imgs[(nm, n)][0]; a = im[..., 3] > 0
            ys, xs = np.where(a); y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            w, h = x1 - x0, y1 - y0
            if x + w > 320: x = 0; y += rowh + 2; rowh = 0
            if y + h > 200: pages.append(cur); cur = np.zeros((200, 320), np.uint8); x = y = rowh = 0
            idx = np.zeros((h, w), np.uint8)
            for yy, xx in zip(*np.where(a[y0:y1, x0:x1])):
                c = im[y0 + yy, x0 + xx, :3]; idx[yy, xx] = 1 + int(((np.array(cen) - c) ** 2).sum(1).argmin())
            cur[y:y + h, x:x + w] = np.where(idx > 0, idx, 0); x += w + 2; rowh = max(rowh, h)
        pages.append(cur)
        for i, pg in enumerate(pages):
            open(os.path.join(out, 'sheets', '%s %d.oct' % (nm.lower(), i + 1)), 'wb').write(mkoct.make_oct(pg.tobytes(), pal))
        rep.append('%s: %d sheet(s)' % (nm, len(pages)))


if __name__ == '__main__':
    main()
