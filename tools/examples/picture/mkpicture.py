#!/usr/bin/env python3
# SUNSET - draws the picture (320x200, original: Octophonic 64 / Mong00se), cuts it to 255 colours
# and packs it in runs for viewer.asm: sunset.png, sunset.pal (255 x RGB), sunset.rle
#   python3 mkpicture.py [outdir]
import sys, os, math
from PIL import Image, ImageDraw, ImageFont
out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
W, H = 320, 200
im = Image.new('RGB', (W, H)); d = ImageDraw.Draw(im)
for y in range(0, 120):
    t = y / 119
    d.line([(0, y), (W, y)], fill=(int(20 + t * 200), int(10 + t * 60), int(70 + t * 40 * (1 - t) * 4)))
cx, cy, r = 160, 95, 52
for y in range(cy - r, cy + r):
    if y >= 120: break
    dx = int(math.sqrt(max(0, r * r - (y - cy) ** 2))); t = (y - (cy - r)) / (2 * r)
    if y > cy and ((y - cy) // 5) % 2 == 1 and (y - cy) > 4: continue
    d.line([(cx - dx, y), (cx + dx, y)], fill=(255, int(230 - 150 * t), int(90 - 60 * t)))
def ridge(base, amp, f, ph, col):
    pts = [(0, H)] + [(x, base - amp * (0.6 * math.sin(x * f + ph) + 0.4 * math.sin(x * f * 2.3 + ph * 1.7))) for x in range(0, W + 1, 2)] + [(W, H)]
    d.polygon(pts, fill=col)
ridge(112, 14, 0.03, 0.5, (70, 30, 90)); ridge(118, 8, 0.05, 2.0, (45, 20, 70))
for y in range(120, H):
    t = (y - 120) / 80
    d.line([(0, y), (W, y)], fill=(int(20 + 10 * t), int(5 + 5 * t), int(40 + 20 * t)))
for i in range(-20, 21):
    d.line([(160 + i * 8, 120), (160 + i * 60, H)], fill=(240, 60, 200))
for k in range(1, 14):
    y = int(120 + 80 * (1 - 1 / (1 + k * 0.35))); d.line([(0, y), (W, y)], fill=(240, 60, 200))
f = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 26)
txt = 'OCTOPHONIC 64'; tw = d.textlength(txt, font=f)
d.text(((W - tw) / 2 + 2, 12), txt, font=f, fill=(30, 0, 40)); d.text(((W - tw) / 2, 10), txt, font=f, fill=(120, 240, 255))
im.save(os.path.join(out, 'sunset.png'))
q = im.quantize(colors=255, dither=Image.Dither.NONE)
pal = q.getpalette()[:255 * 3]; px = [p + 1 for p in q.tobytes()]
o = bytearray(); i = 0; n = len(px)
while i < n:
    j = i
    while j < n and j - i < 127 and px[j] == px[i] and (j // W) == (i // W): j += 1
    if j - i >= 3: o += bytes([j - i, px[i]]); i = j; continue
    k = i; lit = []
    while k < n and len(lit) < 127:
        jj = k
        while jj < n and jj - k < 3 and px[jj] == px[k] and (jj // W) == (k // W): jj += 1
        if jj - k >= 3: break
        lit.append(px[k]); k += 1
    o += bytes([128 + len(lit)]) + bytes(lit); i = k
o += bytes([0])
open(os.path.join(out, 'sunset.rle'), 'wb').write(o); open(os.path.join(out, 'sunset.pal'), 'wb').write(bytes(pal))
print('sunset: %d bytes packed' % len(o))
