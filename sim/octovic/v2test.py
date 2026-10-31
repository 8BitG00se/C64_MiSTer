# OctoVIC version 2's check: the maths unit, the blitter (copy, fill, copy-skipping-0, lines), the
# collisions and the raster interrupt - the Verilog (tb) against the reference (ref.py), plus the
# pictures as before.   python3 v2test.py [seed] [busy%] [latmin] [latmax]
import sys, subprocess, random, numpy as np
from PIL import Image
from ref import Octo, NL
seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
busy, latmin, latmax = (int(v) for v in (sys.argv[2:5] if len(sys.argv) > 4 else (30, 6, 40)))
rng = random.Random(seed)
vram = bytearray(16 << 20)
script = []
def W(a, v): script.append(('w', a, v & 255))
def W16(a, v): W(a, v); W(a+1, v >> 8)
def W24(a, v): W(a, v); W(a+1, v >> 8); W(a+2, v >> 16)
def W32(a, v): W16(a, v & 0xFFFF); W16(a+2, v >> 16)
def RD(a): script.append(('r', a))
def WAIT(f, l): script.append(('wait', f, l))
# palette
W(0x19, 0); W(0x1A, 0)
for i in range(256): W(0x1B, (i * 37) & 255); W(0x1C, (i * 91 + 40) & 255); W(0x1D, (255 - i * 13) & 255)
TILES0, MAP0, SAT, SGFX, BL = 0x010000, 0x020000, 0x060000, 0x070000, 0x100000
# layer 0: 256 colours, tiles 1-7 solid-ish, blocks of them here and there (the sprites hit some)
for t in range(1, 8):
    for b in range(64): vram[TILES0 + t*64 + b] = (t * 20 + b) & 255 or 1
for m in range(64*64):
    tx, ty = m % 64, m // 64
    e = rng.randrange(1, 8) if (8 <= tx < 14 and 10 <= ty < 18) or (30 <= tx < 34 and 4 <= ty < 30) else 0
    vram[MAP0 + m*2] = e & 255; vram[MAP0 + m*2 + 1] = e >> 8
# sprites: 12, 32x32 256 colours; some overlap each other, some sit on the layer's blocks, some alone
pos = [(20, 20), (36, 28), (150, 40), (60, 80), (250, 150), (264, 160), (100, 200), (300, 30), (64, 100), (232, 60), (180, 120), (196, 124)]
for j, (X, Y) in enumerate(pos):
    gi = j * 32
    vram[SAT + j*8: SAT + j*8 + 8] = bytes([X & 255, (X >> 8) & 255, Y & 255, (Y >> 8) & 255, gi & 255, gi >> 8, 0x40 | 0x80 | 2 | 8, rng.randrange(3) << 4])
    for b in range(32*32): vram[SGFX + gi*32 + b] = 0 if (b % 32 < 4 and j % 3 == 0) else (j * 17 + b) & 255 or 1
W(0x20, 1 | 2 | 1 << 4 | 1 << 6); W24(0x21, MAP0); W24(0x24, TILES0); W16(0x28, 0); W16(0x2A, 0)
W24(0x13, SAT); W24(0x16, SGFX); W(0x0F, len(pos))
W(0x06, 6); W(0x05, 1 | 8)
# --- the maths unit
mulv = [(1234, 567, 0), (0xFFFF, 0xFFFF, 0), (0xFFFE, 300, 1), (40000, 50000, 1), (0, 7, 0)]
for a_, b_, sg in mulv:
    W(0x58, sg); W16(0x50, a_); W16(0x52, b_)
    for k in range(4): RD(0x54 + k)
divv = [(100000, 7), (0xFFFFFFFF, 0xFFFF), (5, 9), (123456789, 1), (77, 0)]
for n, d in divv:
    W32(0x59, n); W16(0x5D, d)
    W(0x07, 0); W(0x07, 0)                             # (a moment: the divider's 32 clocks)
    for k in range(4): RD(0x60 + k)
    RD(0x64); RD(0x65)
# --- the blitter: a source block with zeros in it, copied, copied skipping 0, filled; lines; and a
#     copy into layer 0's tiles (it shows in the picture)
for r in range(24):
    for c in range(40): vram[BL + r*64 + c] = 0 if (r + c) % 5 == 0 else (r * 7 + c * 3) & 255 or 9
for b in range(64*24): vram[BL + 0x8000 + b] = 0xEE                # (under the skip-0 copy: what shows through)
def blit(op, src, dst, w, h, ss, ds, fill=0, line=None):
    W24(0x70, src); W24(0x73, dst); W16(0x76, w); W16(0x78, h); W16(0x7A, ss & 0xFFFF); W16(0x7C, ds & 0xFFFF); W(0x7E, fill)
    if line: W16(0x66, line[0] & 0xFFFF); W16(0x68, line[1] & 0xFFFF); W16(0x6A, line[2] & 0xFFFF); W16(0x6C, line[3] & 0xFFFF)
    W(0x7F, 1 | op << 1)
    blit.at += 18; WAIT(blit.at // 312, blit.at % 312)   # (a while: then the busy bit must be clear)
    RD(0x08)
blit.at = 30
blit(0, BL + 3, BL + 0x4000 + 5, 37, 21, 64, 80)                     # copy, odd alignment
blit(2, BL, BL + 0x8000, 40, 24, 64, 64)                             # copy, skipping 0
blit(1, 0, BL + 0xC000 + 3, 29, 13, 0, 100, fill=0x5A)               # fill
blit(3, 0, BL + 0x10000, 120, 90, 0, 128, fill=0x77, line=(-5, 3, 130, 70))     # lines, clipped
blit(3, 0, BL + 0x10000, 120, 90, 0, 128, fill=0x78, line=(100, 80, 10, 2))
blit(3, 0, BL + 0x10000, 120, 90, 0, 128, fill=0x79, line=(60, 0, 60, 89))
blit(0, BL, TILES0 + 64, 8, 8, 64, 8)                                # into tile 1 (the picture shows it)
# a bitmap layer (layer 1: a byte a pixel, 512 x 512), drawn on by the blitter - it shows
BMP = 0x200000
W(0x30, 1 | 2 | 8 | 1 << 4 | 1 << 6); W24(0x34, BMP); W16(0x38, 5); W16(0x3A, 3)
blit(1, 0, BMP + 40 * 512 + 100, 60, 30, 0, 512, fill=0x33)
for k in range(6):
    blit(3, 0, BMP, 512, 512, 0, 512, fill=0x40 + k * 9, line=(10 + k * 30, 20, 300 - k * 25, 250 - k * 13))
# --- the raster interrupt
W16(0x80, 120); W(0x83, 15); W(0x82, 1)
WAIT(1, 10); script.append(('irq',)); WAIT(1, 130); script.append(('irq',)); RD(0x83); W(0x83, 1); script.append(('irq',))
W(0x82, 0)
# --- the collisions, frame 2 (frame 1's)
WAIT(2, 100)
for k in range(2):
    W(0x84, k)
    RD(0x85); RD(0x86)
# --- the Verilog
open('vram.bin', 'wb').write(bytes(vram))
with open('script.txt', 'w') as f:
    for op in script:
        if op[0] == 'w': f.write('w %x %x\n' % (op[1], op[2]))
        elif op[0] == 'r': f.write('r %x\n' % op[1])
        elif op[0] == 'irq': f.write('irq\n')
        else: f.write('wait %d %d\n' % (op[1], op[2]))
FR = 4
r = subprocess.run(['./obj2/tb', 'vram.bin', 'script.txt', str(FR), 'out.rgb', str(seed), str(busy), str(latmin), str(latmax), 'vram_out.bin'], capture_output=True, text=True)
lines = r.stdout.split('\n')
reads = [tuple(int(x, 16) for x in l.split()[1:]) for l in lines if l.startswith('R ')]
irqs = [int(l.split()[1]) for l in lines if l.startswith('IRQ ')]
print([l for l in lines if l.startswith('ok')][0])
got = np.fromfile('out.rgb', np.uint8).reshape(-1, NL, 504, 3)
vout = np.fromfile('vram_out.bin', np.uint8)
# --- the reference: the script's writes; reads answered in order, around the frames
o = Octo(vram)
exp_reads = []
fr_done = 0
exp = []
for op in script:
    if op[0] == 'w': o.write(op[1], op[2])
    elif op[0] == 'r':
        if op[1] in (0x85, 0x86):                       # the collisions: after frames 0 and 1
            while fr_done < 2: exp.append(o.frame()); fr_done += 1
        exp_reads.append((op[1], 0 if op[1] == 0x08 else 1 if op[1] == 0x83 else o.read(op[1])))
while fr_done < FR - 1: exp.append(o.frame()); fr_done += 1
bad = 0
for (a, v), (ea, ev) in zip(reads, exp_reads):
    if v != ev: print('  read $%02X: got %02X, want %02X' % (a, v, ev)); bad += 1
print('reads: %d, %d wrong' % (len(reads), sum(1 for (a, v), (ea, ev) in zip(reads, exp_reads) if v != ev)))
if len(reads) != len(exp_reads): print('  (count differs)', len(reads), len(exp_reads)); bad += 1
print('irq:', irqs, '(want [0, 1, 0])'); bad += irqs != [0, 1, 0]
vb = np.frombuffer(bytes(o.vram), np.uint8)
dv = np.nonzero(vb != vout)[0]
print('vram: %d bytes differ' % len(dv), ('first at $%06X' % dv[0]) if len(dv) else ''); bad += len(dv) > 0
for k in (2, 3):
    e, g = exp[k-1], got[k]
    wrong = (e != g).any(-1); wrong[310:] = False
    n = int(wrong.sum()); bad += n > 0
    print('frame %d: %d wrong pixels' % (k, n))
    if k == 3: Image.fromarray(g).resize((1008, 624), Image.NEAREST).save('v2frame.png')
print('collisions', [(hex(a), hex(v)) for a, v in reads if a in (0x85, 0x86)])
print('PASS' if bad == 0 else 'FAIL')
