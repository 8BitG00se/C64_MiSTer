#!/usr/bin/env python3
# A front-screen card for the tty2oled screen: 256 x 64, 16 greys, saved as a .gsc (8192 bytes, two pixels a byte,
# the left one in the high nibble) plus a preview tinted like the acid-green perspex.
#   make_card.py geometry  ->  GeometrySings.gsc, GeometrySings_preview.png
# The Geometry Sings card: the showcase's finale curve (the word a -> aab, b -> b drawn with turns of 80 degrees, in
# ninths of a circle) beside the title, shaded light to dark like a raster bar.
import sys, math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont
W, H, S = 256, 64, 4
def nine_fold(n=2047):
    w = 'a'
    while len(w) < n: w = ''.join({'a': 'aab', 'b': 'b'}[c] for c in w)
    h = 0; x = y = 0.0; pts = [(0.0, 0.0)]
    for c in w[:n]:
        h = (h + (2 if c == 'a' else -2)) % 9
        x += math.cos(2 * math.pi * h / 9); y += math.sin(2 * math.pi * h / 9); pts.append((x, y))
    return np.array(pts)
def card(lines, art, out):
    im = Image.new('L', (W * S, H * S), 0); d = ImageDraw.Draw(im)
    p = art; lo, hi = p.min(0), p.max(0); sp = hi - lo
    L = min(76 * S / sp[0], 58 * S / sp[1]); off = np.array([4 * S, 3 * S]) - lo * L + (np.array([76, 58]) * S - sp * L) / 2
    q = p * L + off
    for i in range(len(q) - 1):
        d.line([tuple(q[i]), tuple(q[i + 1])], fill=int(90 + 165 * i / len(q)), width=S)
    fb = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
    if not os.path.exists(fb): fb = '/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'
    f1 = ImageFont.truetype(fb, 15 * S); f2 = ImageFont.truetype(fb, 7 * S)
    for txt, y in zip(lines[:2], (6, 24)):
        tmp = Image.new('L', (W * S, 18 * S), 0); ImageDraw.Draw(tmp).text((0, 0), txt, font=f1, fill=255)
        a = np.asarray(tmp).astype(float); grad = np.linspace(255, 120, a.shape[0])[:, None]
        im.paste(Image.fromarray((a / 255 * grad).astype(np.uint8)), (88 * S, y * S), Image.fromarray(a.astype(np.uint8)))
    d.text((88 * S, 48 * S), lines[2], font=f2, fill=150)
    g = np.clip((np.asarray(im.resize((W, H), Image.LANCZOS)).astype(int) * 15 + 127) // 255, 0, 15).astype(np.uint8)
    open(out + '.gsc', 'wb').write(((g[:, 0::2] << 4) | g[:, 1::2]).astype(np.uint8).tobytes())
    Image.fromarray(np.stack([g * 8, g * 17, g * 6], -1).astype(np.uint8)).resize((W * 3, H * 3), Image.NEAREST).save(out + '_preview.png')
if __name__ == '__main__':
    if sys.argv[1:] == ['geometry']:
        card(['GEOMETRY', 'SINGS', 'OCTOPHONIC 64  .  8 SIDS'], nine_fold(), 'GeometrySings')
