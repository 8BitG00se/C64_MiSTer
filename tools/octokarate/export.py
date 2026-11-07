#!/usr/bin/env python3
# export.py - Octo Karate build 2: prepares ALL the data octokarate.asm needs (the PC prepares data only):
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


def main():
    out = [a for a in ARGV[1:] if not a.startswith('--')][0]
    os.makedirs(out, exist_ok=True); os.makedirs(os.path.join(out, 'sheets'), exist_ok=True)
    rep = []
    # ------------------------------------------------------------------ fighters: render, one palette
    imgs = {}
    for C in (F.VIC, F.SID):
        for n in F.ORDER: imgs[(C['name'], n)] = F.render_pose(C, n)
    cnt = {}
    for (c, n), (im, P1, oc) in imgs.items():
        a = im[..., 3] > 0
        for p in im[a][:, :3]: cnt[tuple(int(v) for v in p)] = cnt.get(tuple(int(v) for v in p), 0) + 1
    cl = list(cnt); cen, asg = quantize(cl, [cnt[c] for c in cl], NF)
    amap = {c: int(a) for c, a in zip(cl, asg)}
    rep.append('fighter colours: %d distinct -> %d' % (len(cl), len(cen)))
    FE = S.fighter_entries(len(cen))                 # palette entry of each fighter colour
    # ------------------------------------------------------------------ cells and tables
    blob = bytearray(); seen = {}
    def gfx(b):
        b = bytes(b)
        if b not in seen:
            seen[b] = len(blob) // 32; blob.extend(b)
        return seen[b]
    EMPTY = gfx(bytes(32))
    tabs = {}; boxd = {}
    for C in (F.VIC, F.SID):
        nm = C['name']; flip = C is F.SID
        tab = bytearray()
        for n in F.ORDER:
            im, P1, oc = imgs[(nm, n)]
            idx = np.zeros(im.shape[:2], np.uint8)
            a = im[..., 3] > 0
            for y, x in zip(*np.where(a)): idx[y, x] = FE[amap[tuple(int(v) for v in im[y, x, :3])]]
            # nothing may lie outside the window
            wmin = WIN[nm][0][0]; wmax = WIN[nm][1][0] + WIN[nm][1][1]
            ys, xs = np.where(a)
            assert xs.min() >= wmin and xs.max() < wmax, (nm, n, xs.min(), xs.max())
            assert ys.min() >= ROWS[0][0], (nm, n, ys.min())
            mask = 0; gw = []
            for ci, (cx, cw) in enumerate(WIN[nm]):
                for ri, (ry, rh) in enumerate(ROWS):
                    cell = idx[ry:ry + rh, cx:cx + cw]
                    s = ci * 3 + ri
                    if cell.any(): mask |= 1 << s; gw.append(gfx(cell.tobytes()))
                    else: gw.append(EMPTY)
            hurt, hit = F.boxes(im, P1, oc, flip, n in F.STRIKES)
            boxd[(nm, n)] = (hurt, hit)
            rec = bytearray(32)
            rec[0] = mask; rec[1] = oc
            for s in range(6): struct.pack_into('<H', rec, 2 + 2 * s, gw[s])
            rec[14] = 1 if hit else 0
            for i, b in enumerate(hurt):
                for j in range(4): rec[16 + i * 4 + j] = b[j] & 255
            if hit:
                for j in range(4): rec[28 + j] = hit[j] & 255
                assert -128 <= hit[0] and hit[1] < 128
            for b in hurt: assert -128 <= b[0] and b[1] < 128 and 0 <= b[2] <= b[3] < 112, (nm, n, b)
            tab += rec
        tabs[nm] = bytes(tab)
    fighter_bytes = len(blob)
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
    cenarr = np.array(cen, float)
    for n in range(S.NTICK):
        St = states[n]; R, body, glow = recs[n // REC]
        pal = S.palette(St, R, info).astype(float)
        f = St['light']; k = 0.30 + 0.70 * f
        lit = np.clip(cenarr * k + np.array([18, 22, 48]) * (1 - f) * 0.6, 0, 255)
        pal[FE] = lit
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
        tick.extend((planar + bytes(sat)).ljust(2048, b'\0'))
    assert len(blob) < 65535 * 32, 'sprite graphics do not fit the 2 MB window: %d' % len(blob)
    rep.append('sprite graphics %d bytes (fighters %d, stage + sparks %d); window 2 MB' % (len(blob), fighter_bytes, len(blob) - fighter_bytes))
    # ------------------------------------------------------------------ the REU image
    al = lambda v: (v + 0xFFFF) & ~0xFFFF
    R_PIC = 0; LEN_PIC = 512 * 256; R_SPR = 0x20000
    R_SCR = al(R_SPR + len(blob)); R_TICK = R_SCR + 0x10000
    reu = bytearray(R_TICK) + tick
    reu[R_PIC:R_PIC + LEN_PIC] = pic.tobytes()
    reu[R_SPR:R_SPR + len(blob)] = blob
    open(os.path.join(out, 'Octo Karate.reu'), 'wb').write(reu)
    rep.append('reu %d bytes: picture 128K at 0, sprite graphics at $%06x, scratch at $%06x, %d ticks at $%06x' % (len(reu), R_SPR, R_SCR, S.NTICK, R_TICK))
    # ------------------------------------------------------------------ text and charset
    cs, small, bigm, seg = font.build()
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
    GOLD, WHITE, VBLUE, SWHITE = 2, 1, 13, 14
    M = {}
    M['title'] = msg(9, 3, GOLD, 'OCTO KARATE', True)
    M['press'] = msg(15, 6, WHITE, 'PRESS FIRE')
    M['press_off'] = blank(15, 6, 10)
    M['ports'] = msg(1, 7, 11 if False else 12, 'PORT 2 = 1 PLAYER   PORT 1 = 2 PLAYERS')
    M['ctl'] = (msg(1, 8, GOLD, 'FIRE: PUNCH') + msg(21, 8, GOLD, 'UP+FIRE: HEAD KICK') + msg(1, 9, GOLD, 'FWD+FIRE: BODY KICK')
                + msg(21, 9, GOLD, 'DOWN+FIRE: SHIN LOW') + msg(1, 10, GOLD, 'BACK+FIRE: FRONT KICK')
                + msg(1, 11, 12, 'HOLD BACK: BLOCK') + msg(1, 12, 12, 'DOWN+BACK: BLOCK LOW'))
    M['title_off'] = b''.join(blank(1, r, 39) for r in range(3, 13)) + blank(9, 3, 22) + blank(9, 4, 22)
    M['round'] = msg(13, 7, WHITE, 'ROUND 1', True)
    M['fight'] = msg(14, 7, GOLD, 'FIGHT!', True)
    M['ko'] = msg(17, 7, 10, 'K.O.', True)
    M['timeup'] = msg(13, 7, WHITE, 'TIME UP', True)
    M['vicwins'] = msg(12, 7, VBLUE, 'VIC WINS', True)
    M['sidwins'] = msg(12, 7, SWHITE, 'SID WINS', True)
    M['draw'] = msg(17, 7, WHITE, 'DRAW', True)
    M['banner_off'] = blank(10, 7, 20) + blank(10, 8, 20)
    M['names'] = msg(1, 0, VBLUE, 'VIC') + msg(36, 0, SWHITE, 'SID')
    lab = '1PIC 2GLO 3SUN 4RNG 5STR 6FOM 7FTR 8HUD'
    assert len(lab) <= 40
    # ------------------------------------------------------------------ frame data
    d = []
    def a(*l): d.extend(l)
    a('; made by export.py')
    a('NG = %d' % NG, 'NSPR = %d' % NSPR, 'SATLEN = %d' % (NSPR * 8), 'NTICK = %d' % S.NTICK, 'BOXY = %d' % BOXY)
    a('R_PIC = $%06x' % R_PIC, 'LEN_PIC = $%06x' % LEN_PIC, 'R_SPR = $%06x' % R_SPR, 'LEN_SPR = $%06x' % len(blob), 'R_SCR = $%06x' % R_SCR, 'R_TICK = $%06x' % R_TICK)
    a('G_SPARK = %d' % spark_g[0], 'G_SHADOW = %d' % shadow_g)
    a('ND = %d' % len(F.ORDER))
    for n in F.ORDER: a('D_%s = %d' % (n.upper(), F.DID[n]))
    a('SEGCH = %d' % seg)
    sp = ', '.join(str(g_) for g_ in spark_g)
    a('spark_lo !byte ' + ','.join(str(g_ & 255) for g_ in spark_g))
    a('spark_hi !byte ' + ','.join(str(g_ >> 8) for g_ in spark_g))
    def bytes_(label, bs):
        d.append(label)
        for i in range(0, len(bs), 16): d.append('  !byte ' + ','.join(str(int(b) & 255) for b in bs[i:i + 16]))
    bytes_('dtab_vic', tabs['Vic']); bytes_('dtab_sid', tabs['Sid'])
    d.append('DIG0 = %d' % small['0'])
    # sprite slots per fighter: dx (box left to sprite left), flags
    SL = {}
    for nm in ('Vic', 'Sid'):
        dxs, dys, fl = [], [], []
        for ci, (cx, cw) in enumerate(WIN[nm]):
            for ri, (ry, rh) in enumerate(ROWS):
                dxs.append(cx); dys.append(ry); fl.append(0xC0 | (HC[rh] << 2) | WC[cw])
        SL.setdefault('dx', []).extend(dxs); SL.setdefault('dy', []).extend(dys); SL.setdefault('fl', []).extend(fl)
    bytes_('slotdx', SL['dx']); bytes_('slotdy', SL['dy']); bytes_('slotfl', SL['fl'])
    # moves
    mv = F.MOVES; NM = len(mv)
    a('NMOVES = %d' % NM)
    seqs = []
    for i, m in enumerate(mv): seqs.append([F.DID[n] for n, h in m['seq'] for _ in range(h)])
    bytes_('mv_len', [len(s) for s in seqs]); bytes_('mv_act0', [m['startup'] for m in mv]); bytes_('mv_act1', [m['startup'] + m['active'] - 1 for m in mv])
    bytes_('mv_dmg', [m['dmg'] for m in mv]); bytes_('mv_hs', [m['hitstop'] for m in mv]); bytes_('mv_hstun', [m['hitstun'] for m in mv])
    bytes_('mv_bstun', [m['blockstun'] for m in mv]); bytes_('mv_pushh', [m['pushhit'] for m in mv]); bytes_('mv_pushb', [m['pushblock'] for m in mv])
    bytes_('mv_level', [m['level'] for m in mv])
    # reach (px between the fighters' axes at which the tip meets the body in guard) for AI
    gv = boxd[('Vic', 'guard')][0]; gs = boxd[('Sid', 'guard')][0]
    reachV, reachS = [], []
    for m in mv:
        hv = boxd[('Vic', m['strike'])][1]; hs_ = boxd[('Sid', m['strike'])][1]
        reachV.append(hv[1] - min(gs[0][0], gs[1][0]) - 3); reachS.append(-hs_[0] + max(gv[0][1], gv[1][1]) - 3)
    bytes_('mv_reachv', reachV); bytes_('mv_reachs', reachS)
    push = max(gv[1][1] - gs[1][0], gv[0][1] - gs[0][0]) + 8
    a('PUSHGAP = %d' % push)
    for i, s in enumerate(seqs): bytes_('mv_seq%d' % i, s)
    d.append('mv_seq_lo !byte ' + ','.join('<mv_seq%d' % i for i in range(NM)))
    d.append('mv_seq_hi !byte ' + ','.join('>mv_seq%d' % i for i in range(NM)))
    bytes_('walk_ids', [F.DID[n] for n in F.WALK_NAMES])
    a('FALL1_T = %d' % F.FALL_SEQ[0][1], 'FALL2_T = %d' % (F.FALL_SEQ[0][1] + F.FALL_SEQ[1][1]), 'FALL3_T = %d' % (sum(h for _, h in F.FALL_SEQ)))
    a('STRIDE = %d' % F.STRIDE)
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
    rep.append('PUSHGAP %d  reach V %s S %s' % (push, reachV, reachS))
    rep.append('frame data (name level startup active total dmg hitstop hitstun blockstun pushhit pushblock):')
    for m, s in zip(mv, seqs):
        rep.append('  %-12s %s %2d %2d %2d  %2d %d %2d %2d %2d %2d' % (m['name'], 'HML'[m['level']], m['startup'], m['active'], len(s), m['dmg'], m['hitstop'], m['hitstun'], m['blockstun'], m['pushhit'], m['pushblock']))
    sheets(out, imgs, cen, rep)
    open(os.path.join(out, 'report.txt'), 'w').write('\n'.join(rep) + '\n'); print('\n'.join(rep))


def label_starts(lab):
    # label groups: "1 PIC", "2 GLOW", ... (each starts at its digit)
    pos = [i for i, c in enumerate(lab) if c.isdigit() and (i == 0 or lab[i - 1] == ' ')]
    return pos


def label_ends(lab):
    pos = label_starts(lab); return [p - 1 for p in pos[1:]] + [len(lab)]


def sheets(out, imgs, cen, rep):
    """the fighters' drawings as OctoPaint pictures (320 x 200, one palette), packed by their outlines"""
    from PIL import Image
    pal = [(70, 74, 92)] + [tuple(int(v) for v in c) for c in cen] + [(0, 0, 0)] * (255 - len(cen))
    for nm in ('Vic', 'Sid'):
        pages = []; cur = np.zeros((200, 320), np.uint8); x = y = rowh = 0; cnt = 0
        for n in F.ORDER:
            im = imgs[(nm, n)][0]; a = im[..., 3] > 0
            ys, xs = np.where(a); y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            w, h = x1 - x0, y1 - y0
            if x + w > 320: x = 0; y += rowh + 2; rowh = 0
            if y + h > 200: pages.append(cur); cur = np.zeros((200, 320), np.uint8); x = y = rowh = 0
            idx = np.zeros((h, w), np.uint8)
            for yy, xx in zip(*np.where(a[y0:y1, x0:x1])):
                c = im[y0 + yy, x0 + xx, :3]; idx[yy, xx] = 1 + int(((cen - c) ** 2).sum(1).argmin())
            cur[y:y + h, x:x + w] = np.where(idx > 0, idx, 0); x += w + 2; rowh = max(rowh, h)
        pages.append(cur)
        for i, pg in enumerate(pages):
            open(os.path.join(out, 'sheets', '%s %d.oct' % (nm.lower(), i + 1)), 'wb').write(mkoct.make_oct(pg.tobytes(), pal))
        rep.append('%s: %d sheet(s)' % (nm, len(pages)))


if __name__ == '__main__':
    main()
