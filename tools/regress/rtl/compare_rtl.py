#!/usr/bin/env python3
# OCTOPHONIC 64 - OLD-SOFTWARE REGRESSION TEST (Fix 69): compare the two RTL sides.          (c) 2026 Mong00se
#   compare_rtl.py LAST_OUT NEW_OUT REPORT_DIR
# Per run (boot, code-stock, ...): every frame's picture CRC and the SID registers at the end of every frame;
# identical / changed (side-by-side PNG of the first changed frame) / crashed (fewer frames, or the testbench
# failed) / could not run. Ends with PASS or FAIL (exit 1 on FAIL).
import os, sys
import numpy as np
from PIL import Image, ImageDraw

W, H = 512, 320
PAL = np.array([(0,0,0),(255,255,255),(129,51,56),(117,206,200),(142,60,151),(86,172,77),(46,44,155),(237,241,113),
                (142,80,41),(85,56,0),(196,108,113),(74,74,74),(123,123,123),(169,255,159),(112,109,235),(178,178,178)], np.uint8)

def load(d, n):
    p = os.path.join(d, n + '.txt')
    if not os.path.exists(p): return None
    F = {}
    for ln in open(p):
        s = ln.split()
        if s and s[0] == 'F': F[int(s[1])] = (s[2], s[3], s[4])
    return F

def frame(d, n, k):
    p = os.path.join(d, n + '.bin')
    with open(p, 'rb') as f:
        f.seek(k * W * H); b = f.read(W * H)
    if len(b) < W * H: return None
    a = np.frombuffer(b, np.uint8).reshape(H, W)
    img = PAL[a & 15].copy(); img[(a & 0x80) != 0] = (24, 24, 24)
    return img

def main():
    A, B, O = sys.argv[1:4]
    os.makedirs(O, exist_ok=True)
    names = sorted({f[:-3] for d in (A, B) for f in os.listdir(d) if f.endswith('.rc')})
    L = []; P = lambda s='': (L.append(s), print(s))
    P('OCTOPHONIC 64 - OLD-SOFTWARE REGRESSION TEST (Fix 69): whole-C64 RTL (Verilator)        (c) 2026 Mong00se')
    for side, d in (('last core', A), ('new core ', B)):
        rm = open(os.path.join(d, 'roms.md5')).read().split() if os.path.exists(os.path.join(d, 'roms.md5')) else ['?']
        P('%s: %s  (rom.hex md5 %s)' % (side, d, rm[0]))
    P()
    bad = []
    if not names:
        P('NO RUNS: neither side produced anything (see the build logs)'); bad.append('all')
    for n in names:
        fa, fb = load(A, n), load(B, n)
        rca = open(os.path.join(A, n + '.rc')).read().strip() if os.path.exists(os.path.join(A, n + '.rc')) else 'none'
        rcb = open(os.path.join(B, n + '.rc')).read().strip() if os.path.exists(os.path.join(B, n + '.rc')) else 'none'
        if fa is None or rca != '0':
            P('%-16s COULD NOT RUN on the last core (rc %s) - nothing to compare with' % (n, rca)); bad.append(n); continue
        if fb is None or rcb != '0':
            P('%-16s CRASHED     the new core\'s run failed (rc %s)' % (n, rcb)); bad.append(n); continue
        common = sorted(set(fa) & set(fb))
        pic = [k for k in common if fa[k][0] != fb[k][0]]
        sid = [k for k in common if fa[k][1] != fb[k][1]]
        if len(fb) < len(fa) - 1:
            P('%-16s CRASHED     the new core stopped after %d of %d frames' % (n, len(fb), len(fa))); bad.append(n); continue
        if not pic and not sid and len(fa) == len(fb):
            P('%-16s IDENTICAL   %d frames: every picture and the SID registers at every frame end the same' % (n, len(fa))); continue
        bad.append(n)
        P('%-16s CHANGED     %d frames' % (n, len(common)))
        if pic:
            k = pic[0]
            P('%16s   picture: %d frames differ, first frame %d, last %d' % ('', len(pic), k, pic[-1]))
            a, b = frame(A, n, k), frame(B, n, k)
            if a is not None and b is not None:
                m = np.any(a != b, axis=2)
                d = np.zeros_like(a); d[m] = (255, 0, 255)
                im = Image.new('RGB', (3 * W + 16, H + 16), (20, 20, 40))
                for i, x in enumerate((a, b, d)): im.paste(Image.fromarray(x), (i * (W + 8), 16))
                dr = ImageDraw.Draw(im)
                for i, t in enumerate(('LAST CORE (RTL)', 'NEW CORE (RTL)', 'WHAT CHANGED (magenta)')): dr.text((i * (W + 8) + 4, 3), t, fill=(255, 255, 255))
                pth = os.path.join(O, '%s - first changed frame %d.png' % (n, k)); im.save(pth)
                P('%16s   side by side: %s (%d pixels)' % ('', os.path.basename(pth), int(m.sum())))
        if sid:
            P('%16s   SID registers differ at the end of %d frames, first frame %d' % ('', len(sid), sid[0]))
        if len(fa) != len(fb): P('%16s   frames: last core %d, new core %d' % ('', len(fa), len(fb)))
    P()
    P(('FAIL - not the same: ' + ', '.join(bad)) if bad else 'PASS - every RTL run is identical to the last core')
    open(os.path.join(O, 'REPORT.txt'), 'w').write('\n'.join(L) + '\n')
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    main()
