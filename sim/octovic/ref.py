# OctoVIC's reference: docs/OCTOVIC.md in Python, pixel for pixel. A scene is VRAM plus a
# script of register writes; render() gives the picture the chip should put out for a frame.
import numpy as np

RW, FIRST, LAST, NL = 396, 16, 299, 312
TB_PAL = [(0,0,0),(255,255,255),(129,51,56),(117,206,200),(142,60,151),(86,172,77),(46,44,155),(237,241,113),
          (142,80,41),(85,56,0),(196,108,113),(74,74,74),(123,123,123),(169,255,159),(112,109,235),(178,178,178)]
C64 = [0x000000,0xFFFFFF,0x68372B,0x70A4B2,0x6F3D86,0x588D43,0x352879,0xB8C76F,
       0x6F4F25,0x433900,0x9A6759,0x444444,0x6C6C6C,0x9AD284,0x6C5EB5,0x959595]

def vic_colour(R, y):
    if R < 32 or R >= 352 or y < 51 or y >= 251: return 14
    cx, cy = (R-32)//8, (y-51)//8
    if (cx*3+cy*5) % 11 == 0 and ((R+y) & 2): return 1
    if cx == 5 and cy == 3: return 2
    return 6

def s16(v): v &= 0xFFFF; return v-0x10000 if v & 0x8000 else v
def s8(v): v &= 0xFF; return v-0x100 if v & 0x80 else v

class Octo:
    def __init__(s, vram):
        s.vram = vram                                   # bytearray, 16MB
        s.r = {}                                        # the plain registers
        s.pal = [(i << 16) | (i << 8) | i for i in range(256)]
        s.vpal = list(C64); s.backdrop = 0
        s.vaddr = 0; s.vinc = 1; s.palidx = 0; s.palr = 0; s.palg = 0; s.palsel = 0
        s.sat = bytes(1024)
        # version 2
        s.divq = 0; s.divr = 0
        s.acc_ss = 0; s.acc_sl = 0; s.coll_ss = 0; s.coll_sl = 0
    def g(s, n, d=0): return s.r.get(n, d)
    def g24(s, n): return s.g(n) | s.g(n+1) << 8 | s.g(n+2) << 16
    def g16(s, n): return s.g(n) | s.g(n+1) << 8
    def write(s, a, v, cpu=True):
        v &= 255
        if a <= 4:
            if not cpu: return
            if a <= 2: s.vaddr = (s.vaddr & ~(0xFF << 8*a)) | v << 8*a
            elif a == 3: s.vinc = v
            else: s.vram[s.vaddr & 0xFFFFFF] = v; s.vaddr = (s.vaddr + s.vinc) & 0xFFFFFF
            return
        if a == 0x0F: v = min(v, 128)
        s.r[a] = v
        if a == 0x5E:                                   # the divider (the chip: 32 clocks - done before the CPU looks)
            n = s.g(0x59) | s.g(0x5A) << 8 | s.g(0x5B) << 16 | s.g(0x5C) << 24; d = s.g16(0x5D)
            s.divq, s.divr = (0xFFFFFFFF, n & 0xFFFF) if d == 0 else (n // d, n % d)
        if a == 0x7F and v & 1: s.blit((v >> 1) & 3)
        if a == 0x83: s.r[0x83] = 0                     # (flags: the chip's - not modelled here)
        if 0x10 <= a <= 0x15 or 0x40 <= a <= 0x4B: s.anim = [0, 0, 0, 0, 0, 0]   # cop off, k, d; sat off, k, d
        if a == 0x19: s.palsel = v & 3
        if a == 0x1A: s.palidx = v
        if a == 0x1B: s.palr = v
        if a == 0x1C: s.palg = v
        if a == 0x1D:
            c = s.palr << 16 | s.palg << 8 | v
            if s.palsel == 0: s.pal[s.palidx] = c
            elif s.palsel == 1: s.vpal[s.palidx & 15] = c
            else: s.backdrop = c
            s.palidx = (s.palidx + 1) & 255
        s.r[a] = v
    def v16(s, a): return s.vram[a & 0xFFFFFF] | s.vram[(a+1) & 0xFFFFFF] << 8

    # --- version 2: what reads give back (the maths unit, the collisions)
    def read(s, a):
        ma, mb = s.g16(0x50), s.g16(0x52)
        if a in (0x54, 0x55, 0x56, 0x57):
            m = (s16(ma) * s16(mb)) & 0xFFFFFFFF if s.g(0x58) & 1 else ma * mb
            return (m >> 8*(a - 0x54)) & 255
        if 0x60 <= a <= 0x63: return (s.divq >> 8*(a - 0x60)) & 255
        if a in (0x64, 0x65): return (s.divr >> 8*(a - 0x64)) & 255
        if a == 0x1F: return 2
        if a in (0x85, 0x86):
            c = s.coll_ss if a == 0x85 else s.coll_sl
            return (c >> 8*(s.g(0x84) & 15)) & 255
        return s.g(a)
    # --- the blitter (the chip takes its time; here it is done at once)
    def blit(s, op):
        g24, g16 = s.g24, s.g16
        src, dst, w, h, ss, ds, fill = g24(0x70), g24(0x73), g16(0x76), g16(0x78), s16(g16(0x7A)), s16(g16(0x7C)), s.g(0x7E)
        V = s.vram
        if op == 3:
            x, y, x1, y1 = s16(g16(0x66)), s16(g16(0x68)), s16(g16(0x6A)), s16(g16(0x6C))
            dx, dy = abs(x1 - x), -abs(y1 - y); sx = 1 if x1 >= x else -1; sy = 1 if y1 >= y else -1; err = dx + dy
            while True:
                if 0 <= x < w and 0 <= y < h: V[(dst + y * g16(0x7C) + x) & 0xFFFFFF] = fill
                if x == x1 and y == y1: break
                e2 = 2 * err
                if e2 >= dy: err += dy; x += sx
                if e2 <= dx: err += dx; y += sy
            return
        for r in range(h):
            for c in range(w):
                a_s, a_d = (src + r*ss + c) & 0xFFFFFF, (dst + r*ds + c) & 0xFFFFFF
                v = fill if op == 1 else V[a_s]
                if op == 2 and v == 0: continue
                V[a_d] = v

    # --- one raster line into a buffer of RW (None = see-through)
    def line(s, L):
        buf = [None]*RW
        own = [0]*RW                                    # version 2: b8 a layer pixel, b7 a sprite's, b0-6 which
        xadj, yadj = s8(s.g(0x0C)), s8(s.g(0x0D))
        y = L - 51 - yadj
        sx0 = -32 - xadj
        def layer(k):
            b = 0x20 + 16*k; lc = s.g(b)
            if not lc & 1: return
            bpp8 = lc & 2; mw = 32 << ((lc >> 4) & 3); mh = 32 << ((lc >> 6) & 3)
            mapb, tileb = s.g24(b+1), s.g24(b+4)
            ls = s16(s.v16(s.g24(b+12) + 2*L)) if lc & 4 else 0
            vy = (y + s.g16(b+10)) & 0xFFFF
            vx0 = (sx0 + s.g16(b+8) + ls) & 0xFFFF
            ty = vy & 7; mr = (vy >> 3) & (mh-1)
            if lc & 8:                                  # version 2: a bitmap layer, a byte a pixel
                rowa = tileb + ((vy & (mh*8 - 1)) * mw * 8)
                for R in range(RW):
                    vx = (vx0 + R) & 0xFFFF
                    pix = s.vram[(rowa + (vx & (mw*8 - 1))) & 0xFFFFFF]
                    if pix:
                        buf[R] = s.pal[pix]
                        if own[R] & 0x80: s.acc_sl |= 1 << (own[R] & 0x7F)
                        own[R] |= 0x100
                return
            for R in range(RW):
                vx = (vx0 + R) & 0xFFFF
                mc = (vx >> 3) & (mw-1)
                e = s.v16(mapb + ((mr * mw) + mc) * 2)
                tile, hf, vf, bank = e & 0x3FF, (e >> 10) & 1, (e >> 11) & 1, e >> 12
                row = 7-ty if vf else ty
                c = vx & 7; c = 7-c if hf else c
                if bpp8: pix = s.vram[(tileb + (tile | bank << 10)*64 + row*8 + c) & 0xFFFFFF]; idx = pix
                else:
                    bb = s.vram[(tileb + tile*32 + row*4 + c//2) & 0xFFFFFF]
                    pix = bb >> 4 if c % 2 == 0 else bb & 15; idx = bank*16 + pix
                if pix:
                    buf[R] = s.pal[idx]
                    if own[R] & 0x80: s.acc_sl |= 1 << (own[R] & 0x7F)
                    own[R] |= 0x100
        def sprites(p):
            n = s.g(0x0F); gfx0 = s.g24(0x16); hits = []
            for j in range(n):
                e = s.sat[j*8:j*8+8]
                X, Y = s16(e[0] | e[1] << 8), s16(e[2] | e[3] << 8)
                a, a2 = e[6], e[7]
                w, h = 8 << (a & 3), 8 << ((a >> 2) & 3)
                r = y - Y
                if a & 0x80 and (a2 >> 4) & 3 == p and 0 <= r < h and X + w > sx0 and X < sx0 + RW and len(hits) < 64:
                    hits.append(j)
            for j in reversed(hits):
                e = s.sat[j*8:j*8+8]
                X, Y, gi = s16(e[0] | e[1] << 8), s16(e[2] | e[3] << 8), e[4] | e[5] << 8
                a, a2 = e[6], e[7]
                w, h = 8 << (a & 3), 8 << ((a >> 2) & 3)
                hf, vf, bpp8, bank = (a >> 4) & 1, (a >> 5) & 1, (a >> 6) & 1, a2 & 15
                r = y - Y; rr = h-1-r if vf else r
                bpr = w if bpp8 else w // 2
                ra = gfx0 + gi*32 + rr*bpr
                for sc in range(w):
                    R = X + 32 + xadj + (w-1-sc if hf else sc)
                    if bpp8: pix = s.vram[(ra + sc) & 0xFFFFFF]; idx = pix
                    else:
                        bb = s.vram[(ra + sc//2) & 0xFFFFFF]
                        pix = bb >> 4 if sc % 2 == 0 else bb & 15; idx = bank*16 + pix
                    if pix and 0 <= R < RW:
                        buf[R] = s.pal[idx]
                        if own[R] & 0x80: s.acc_ss |= 1 << j | 1 << (own[R] & 0x7F)
                        if own[R] & 0x100: s.acc_sl |= 1 << j
                        own[R] = (own[R] & 0x100) | 0x80 | j
        if s.g(0x0F): sprites(2)
        layer(0)
        if s.g(0x0F): sprites(1)
        layer(1)
        if s.g(0x0F): sprites(0)
        return buf

    # --- a frame: the copper and the sprite table as the chip does them, then the picture
    def frame(s):
        pic = np.zeros((NL, 504, 3), np.uint8)
        lines = {}; bd = {}; ck = {}
        if not hasattr(s, 'anim'): s.anim = [0, 0, 0, 0, 0, 0]
        an = s.anim
        cop = (s.g24(0x10) + an[0]) & 0xFFFFFF
        satb = (s.g24(0x13) + an[3]) & 0xFFFFFF
        # the animation moves on (this frame shows where it was)
        for o, stp, n, dv in ((0, 0x40, 0x43, 0x45), (3, 0x46, 0x49, 0x4B)):
            div = s.g(dv)
            if div:
                if an[o+2] + 1 >= div:
                    an[o+2] = 0
                    if an[o+1] + 1 >= (s.g(n) | s.g(n+1) << 8): an[o+1] = 0; an[o] = 0
                    else: an[o+1] += 1; an[o] = (an[o] + s.g24(stp)) & 0xFFFFFF
                else: an[o+2] += 1
        for L in range(NL):
            if s.g(0x0E) & 1:
                while True:
                    e = s.vram[cop:cop+4]
                    ln = e[0] | e[1] << 8
                    if ln == 0xFFFF or ln > L: break
                    if e[2] > 4: s.write(e[2], e[3], cpu=False)
                    cop += 4
            if L == 0:
                s.sat = bytes(s.vram[satb & ~7: (satb & ~7) + 1024])
                s.coll_ss, s.coll_sl, s.acc_ss, s.acc_sl = s.acc_ss, s.acc_sl, 0, 0     # version 2: last frame's collisions
            if FIRST <= L <= LAST and s.g(0x05) & 1: lines[L] = s.line(L)
            bd[L] = s.backdrop                          # the backdrop as it was when the line was drawn
            ck[L] = (s.g(0x05), s.g(0x06) & 15)        # and CTRL and KEY
        for yy in range(NL):
            ctrl, key = ck[yy]
            buf = lines.get(yy)
            for R in range(504):
                vi = vic_colour(R, yy)
                vc = s.vpal[vi] if ctrl & 2 else (TB_PAL[vi][0] << 16 | TB_PAL[vi][1] << 8 | TB_PAL[vi][2])
                lp = buf[R] if (buf is not None and R < RW) else None
                if not ctrl & 1: c = vc
                elif ctrl & 4: c = lp if lp is not None else vc
                elif ctrl & 8 and vi == key: c = lp if lp is not None else bd[yy]
                else: c = vc
                pic[yy, R] = (c >> 16, (c >> 8) & 255, c & 255)
        return pic
