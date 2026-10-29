# The OctoVIC check: a scene that uses everything, run through the Verilog (tb, cycle by cycle,
# with a DDR3 that is busy and slow at random) and through the reference; every pixel of the
# frames compared. Prints the result, saves the frame and any wrong pixels as pictures.
#   python3 run.py [seed] [busy%] [latmin] [latmax]
import sys, subprocess, random, numpy as np
from PIL import Image
from ref import Octo, NL

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
busy, latmin, latmax = (int(v) for v in (sys.argv[2:5] if len(sys.argv) > 4 else (20, 6, 30)))
rng = random.Random(seed)
vram = bytearray(16 << 20)
script = []                         # ('w', reg, value) or ('wait', frame, line)
def W(a, v): script.append(('w', a, v & 255))
def W24(a, v): W(a, v); W(a+1, v >> 8); W(a+2, v >> 16)
def W16(a, v): W(a, v); W(a+1, v >> 8)

# the palette: 256 colours, a ramp per bank
W(0x19, 0); W(0x1A, 0)
pal = []
for i in range(256):
    b, k = i // 16, i % 16
    c = ((b*53 + k*11) % 256, (b*97 + k*29 + 40) % 256, (255 - b*13 - k*7) % 256)
    pal.append(c); W(0x1B, c[0]); W(0x1C, c[1]); W(0x1D, c[2])
W(0x19, 1); W(0x1A, 2); W(0x1B, 0xF0); W(0x1C, 0x10); W(0x1D, 0x80)          # VIC colour 2 made pink
W(0x19, 2); W(0x1B, 0x20); W(0x1C, 0x00); W(0x1D, 0x30)                       # the backdrop

TILES0, MAP0, TILES1, MAP1 = 0x010000, 0x020000, 0x030000, 0x040000
LS0, SAT, SGFX, COP = 0x050000, 0x060000, 0x070000, 0x080000
# layer 0: 16-colour tiles, a 64x32 map with flips and banks, line scroll
for t in range(64):
    for b in range(32): vram[TILES0 + t*32 + b] = rng.randrange(256) if rng.random() < 0.8 else 0
for m in range(64*32):
    e = rng.randrange(64) | rng.randrange(4) << 10 | rng.randrange(16) << 12
    vram[MAP0 + m*2] = e & 255; vram[MAP0 + m*2 + 1] = e >> 8
for L in range(NL):
    v = int(round(12*np.sin(L/9.0))) & 0xFFFF
    vram[LS0 + 2*L] = v & 255; vram[LS0 + 2*L + 1] = v >> 8
# layer 1: 256-colour tiles, a 32x32 map, most of it empty
for t in range(32):
    for b in range(64): vram[TILES1 + t*64 + b] = rng.randrange(256) if (t and rng.random() < 0.6) else 0
for m in range(32*32):
    e = (rng.randrange(1, 32) if rng.random() < 0.3 else 0) | rng.randrange(4) << 10
    vram[MAP1 + m*2] = e & 255; vram[MAP1 + m*2 + 1] = e >> 8
# sprites: 48, every size, both colour depths, flips, priorities, some off the edges
import os
STRESS = int(os.environ.get('STRESS', '0'))           # STRESS=n: n sprites 64x64, 256 colours, all on the same lines
NS = STRESS or 48
for j in range(NS):
    wc, hc = rng.randrange(4), rng.randrange(4)
    X = rng.randrange(-70, 380); Y = rng.randrange(-60, 230)
    if STRESS: wc, hc, X, Y = 3, 3, (j * 37) % 360 - 30, 60
    a = wc | hc << 2 | rng.randrange(2) << 4 | rng.randrange(2) << 5 | rng.randrange(2) << 6 | (0x80 if rng.random() < 0.9 else 0)
    if STRESS: a |= 0xC0
    a2 = rng.randrange(16) | rng.randrange(3) << 4
    gi = j * 128
    e = [X & 255, (X >> 8) & 255, Y & 255, (Y >> 8) & 255, gi & 255, gi >> 8, a, a2]
    vram[SAT + j*8: SAT + j*8 + 8] = bytes(e)
    w, h = 8 << wc, 8 << hc
    nbytes = (w if a & 0x40 else w // 2) * h
    for b in range(nbytes): vram[SGFX + gi*32 + b] = rng.randrange(256) if rng.random() < 0.7 else 0
# the copper: layer 0's scroll changed at line 120, a palette entry at line 150, back at line 0
cop = [(0, 0x28, 40), (0, 0x29, 0), (0, 0x1A, 0x15), (0, 0x19, 0), (0, 0x1B, pal[0x15][0]), (0, 0x1C, pal[0x15][1]), (0, 0x1D, pal[0x15][2]),
       (120, 0x28, 100), (150, 0x1A, 0x15), (150, 0x1B, 255), (150, 0x1C, 255), (150, 0x1D, 0), (200, 0x2A, 7), (0xFFFF, 0, 0)]
cl = []
for ln, rg, v in cop: cl += [ln & 255, ln >> 8, rg, v]
vram[COP:COP+len(cl)] = bytes(cl)
# some of layer 1's tiles through the data port instead (the VDATA path)
port = [(TILES1 + 64*5 + i, (i*37 + 11) & 255) for i in range(64)]
W24(0x00, port[0][0]); W(0x03, 1)
for a, v in port: W(0x04, v)
# the layers, the sprites, the copper, on
V = rng.random                                   # (the seed varies everything)
W(0x20, 1 | 4*(V() < 0.7) | 1 << 4 | rng.randrange(2) << 6); W24(0x21, MAP0); W24(0x24, TILES0)
W16(0x28, rng.randrange(65536)); W16(0x2A, rng.randrange(65536)); W24(0x2C, LS0)
W(0x30, (V() < 0.9) | 2 | 4*(V() < 0.3)); W24(0x31, MAP1); W24(0x34, TILES1); W16(0x38, rng.randrange(65536)); W16(0x3A, rng.randrange(65536)); W24(0x3C, LS0)
W24(0x13, SAT); W24(0x16, SGFX); W(0x0F, NS if STRESS else rng.choice([NS, NS, 0, 17]))
W24(0x10, COP); W(0x0E, V() < 0.8)
W(0x0C, rng.choice([0, 0, 3, 0xFE])); W(0x0D, rng.choice([0, 0, 2, 0xFF]))
W(0x06, rng.choice([6, 6, 14])); W(0x05, 1 | 2*(V() < 0.5) | (8 if STRESS else rng.choice([8, 8, 4, 0])))

# --- the Verilog
vb = bytearray(vram)
for a, v in port: vb[a] = 0                      # the tb gets them through the port, not the file
open('vram.bin', 'wb').write(bytes(vb))
with open('script.txt', 'w') as f:
    for op in script: f.write('w %x %x\n' % (op[1], op[2]))
FR = 4
r = subprocess.run(['./obj/tb', 'vram.bin', 'script.txt', str(FR), 'out.rgb', str(seed), str(busy), str(latmin), str(latmax)], capture_output=True, text=True)
print(r.stdout.strip(), r.stderr.strip()[:300])
got = np.fromfile('out.rgb', np.uint8).reshape(-1, NL, 504, 3)

# --- the reference: the script's state, then frames
o = Octo(vram)
for op in script: o.write(op[1], op[2])
exp = [o.frame() for _ in range(FR - 1)]
bad = 0
for k in (2, 3):
    e, g = exp[k-1], got[k]
    wrong = (e != g).any(-1)
    n = int(wrong.sum()); bad += n
    print('frame %d: %d wrong pixels%s' % (k, n, '' if not n else ' - first at line %d' % np.nonzero(wrong)[0][0]))
    if k == 3:
        Image.fromarray(g).resize((1008, 624), Image.NEAREST).save('frame.png')
        if n:
            m = g.copy(); m[wrong] = (255, 0, 0)
            Image.fromarray(np.concatenate([m, e], 1)).resize((2016, 624), Image.NEAREST).save('wrong.png')
            ys, xs = np.nonzero(wrong); print('  wrong lines', sorted(set(ys.tolist()))[:20], 'x', sorted(set(xs.tolist()))[:20])
print('PASS' if bad == 0 else 'FAIL')
