#!/usr/bin/env python3
# mkoct.py - the .OCT picture format for OctoPaint (Octophonic 64): make, read, convert, and the example pictures.
# Original work by Mong00se.
#
#   mkoct.py examples DIR             draw TESTCARD.OCT and PALETTE.OCT into DIR
#   mkoct.py to-oct  IN.png OUT.oct   a picture (PNG, BMP, ...) to .OCT, 320 x 200 (see below)
#   mkoct.py to-png  IN.oct OUT.png   .OCT to PNG
#   mkoct.py csum   IN.oct            the picture's checksum, as OctoPaint's debug overlay (D) shows it
#   mkoct.py check                    self test of the run-length packing
#   add --raw to write the pixels unpacked (packing 0)
#
# .OCT version 1 (all of it is also in docs/OCTOPAINT.md):
#   0  4  "OCT1"
#   4  2  width,  little endian (320)
#   6  2  height  (200)
#   8  1  bits per pixel (8)
#   9  1  packing: 0 none, 1 run-length
#   10 768 palette, 256 x (R, G, B)
#   778 .. pixels, row 0 first, left to right, packed over the whole picture (rows are not separate)
#
# Run-length packing, exactly as the 6502 does it (a single pass, no looking ahead past the byte in hand):
#   a run of 3 or more equal bytes (at most 130) becomes a repeat packet: control byte 128 + (n - 3), then the byte
#   everything else is gathered into literal packets of at most 128 bytes: control byte (count - 1), then the bytes
# A literal packet is written as soon as a repeat packet needs to follow it, when it has 128 bytes, and at the end.
import struct, sys, os, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkpal

W, H = 320, 200


def rle(data):
    out = bytearray()
    lit = bytearray()
    rb, rc = None, 0

    def flush_lit():
        if lit:
            out.append(len(lit) - 1)
            out.extend(lit)
            lit.clear()

    def end_run():
        if rc >= 3:
            flush_lit()
            out.append(128 + rc - 3)
            out.append(rb)
        else:
            for _ in range(rc):
                lit.append(rb)
                if len(lit) == 128:
                    flush_lit()

    for b in data:
        if rc and b == rb and rc < 130:
            rc += 1
        else:
            if rc:
                end_run()
            rb, rc = b, 1
    if rc:
        end_run()
    flush_lit()
    return bytes(out)


def unrle(data, n):
    out = bytearray()
    i = 0
    while len(out) < n:
        c = data[i]
        i += 1
        if c < 128:
            out += data[i:i + c + 1]
            i += c + 1
        else:
            out += bytes([data[i]]) * (c - 125)
            i += 1
    if len(out) != n:
        raise ValueError('packed data overshoots the picture')
    return bytes(out)


def make_oct(pixels, palette, w=W, h=H, pack=True):
    assert len(pixels) == w * h and len(palette) == 256
    head = b'OCT1' + struct.pack('<HHBB', w, h, 8, 1 if pack else 0)
    pal = bytes(c for rgb in palette for c in rgb)
    return head + pal + (rle(pixels) if pack else bytes(pixels))


def read_oct(blob):
    if blob[:4] != b'OCT1':
        raise ValueError('not an OCT1 file')
    w, h, bpp, pk = struct.unpack('<HHBB', blob[4:10])
    if bpp != 8 or pk > 1:
        raise ValueError('unsupported bpp/packing')
    pal = [tuple(blob[10 + 3 * i:13 + 3 * i]) for i in range(256)]
    body = blob[778:]
    px = unrle(body, w * h) if pk else bytes(body[:w * h])
    return w, h, pal, px


def csum(pixels):
    """The 16-bit checksum the 6502 computes over the canvas (debug overlay): crc = rotate left 1 of (crc xor pixel)."""
    c = 0
    for v in pixels:
        c = ((c ^ v) & 0xFFFF) << 1
        c = (c & 0xFFFF) | (c >> 16)
    return c


# ---------------------------------------------------------------------------------------------------- pictures
class Canvas:
    def __init__(self, c=0):
        self.p = bytearray([c]) * (W * H)

    def put(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.p[y * W + x] = c

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.put(xx, yy, c)

    def frame(self, x, y, w, h, c):
        self.rect(x, y, w, 1, c); self.rect(x, y + h - 1, w, 1, c)
        self.rect(x, y, 1, h, c); self.rect(x + w - 1, y, 1, h, c)

    def circle(self, cx, cy, r, c, fill=False):
        for y in range(-r, r + 1):
            for x in range(-r, r + 1):
                d = x * x + y * y
                if (d <= r * r) if fill else (r * r - r <= d <= r * r + r):
                    self.put(cx + x, cy + y, c)


def testcard():
    """An original test card: colour bars, ramps, a grid, circles."""
    cv = Canvas(11)                                 # dark grey ground
    # frame and a 20-pixel grid
    for x in range(0, W, 20):
        cv.rect(x, 0, 1, H, 12)
    for y in range(0, H, 20):
        cv.rect(0, y, W, 1, 12)
    cv.frame(0, 0, W, H, 1)
    cv.frame(2, 2, W - 4, H - 4, 15)
    # eight colour bars, the C64-like entries
    bars = [1, 7, 3, 5, 4, 2, 6, 15]
    bw = 36
    for i, c in enumerate(bars):
        cv.rect(16 + i * bw, 12, bw, 56, c)
    # a strip of the hue ramps, one per bar (the brightest ramp step varies down the bar)
    for i in range(8):
        for s in range(16):
            cv.rect(16 + i * bw, 72 + s * 2 - 0, bw, 2, 16 + 16 * (i * 14 // 8) + s)
    # the grey ramp, 16 steps
    for s in range(16):
        cv.rect(16 + s * 18, 108, 18, 16, 240 + s)
    # circles: concentric rings in one hue ramp
    cx, cy = 160, 160
    for r in range(34, 0, -2):
        cv.circle(cx, cy, r, 16 + 16 * 3 + (34 - r) // 3 + 4, fill=True)
    for r in (10, 20, 30):
        cv.circle(cx, cy, r, 1)
    # cross hair
    cv.rect(cx - 38, cy, 77, 1, 1)
    cv.rect(cx, cy - 38, 1, 77, 1)
    # corner circles, as a geometry check
    for (x, y) in ((40, 160), (280, 160)):
        cv.circle(x, y, 22, 1)
        cv.circle(x, y, 14, 7)
        cv.circle(x, y, 6, 2, fill=True)
    return cv.p


def palchart():
    """All 256 colours: a 16 x 16 grid, entry n at column n % 16, row n // 16; swatches 18 x 12."""
    cv = Canvas(0)
    cv.frame(0, 0, W, H, 240 + 15)
    x0, y0 = (W - 16 * 18) // 2, (H - 16 * 12) // 2
    for n in range(256):
        cv.rect(x0 + (n % 16) * 18, y0 + (n // 16) * 12, 18, 12, n)
    # a thin white frame round the grid (drawn outside the swatches)
    cv.frame(x0 - 2, y0 - 2, 16 * 18 + 4, 16 * 12 + 4, 255)
    return cv.p


# ---------------------------------------------------------------------------------------------------- conversions
def to_oct(src, dst, pack=True):
    from PIL import Image
    im = Image.open(src)
    if im.size != (W, H):
        im = im.convert('RGB').resize((W, H), Image.LANCZOS)
    if im.mode != 'P':
        im = im.convert('RGB').quantize(256, method=Image.MEDIANCUT, dither=Image.NONE)
    pal = im.getpalette() or []
    pal = (pal + [0] * 768)[:768]
    palette = [tuple(pal[3 * i:3 * i + 3]) for i in range(256)]
    open(dst, 'wb').write(make_oct(bytes(im.tobytes()), palette, pack=pack))


def to_png(src, dst):
    from PIL import Image
    w, h, pal, px = read_oct(open(src, 'rb').read())
    im = Image.frombytes('P', (w, h), px)
    im.putpalette([c for rgb in pal for c in rgb])
    im.save(dst)


def check():
    random.seed(7)
    cases = [b'', b'\x05', b'\x05' * 2, b'\x05' * 3, b'\x05' * 130, b'\x05' * 131, b'\x05' * 132, bytes(range(256)) * 2,
             bytes(range(128)), bytes(range(129))]
    for _ in range(300):
        n = random.choice([1, 5, 50, 300, 2000])
        k = random.choice([2, 3, 6, 256])
        cases.append(bytes(random.choice([random.randrange(k)] * 3 + [random.randrange(256)]) for _ in range(n)))
    for d in cases:
        r = rle(d)
        assert unrle(r, len(d)) == d
    pal = mkpal.table()
    for pic in (testcard(), palchart()):
        assert read_oct(make_oct(pic, pal))[3] == bytes(pic)
    print('ok: %d packing cases, 2 pictures' % len(cases))


def main(a):
    raw = '--raw' in a
    a = [x for x in a if x != '--raw']
    if len(a) >= 1 and a[0] == 'check':
        check()
    elif len(a) == 2 and a[0] == 'examples':
        pal = mkpal.table()
        os.makedirs(a[1], exist_ok=True)
        for name, pic in (('TESTCARD.OCT', testcard()), ('PALETTE.OCT', palchart())):
            blob = make_oct(pic, pal, pack=not raw)
            open(os.path.join(a[1], name), 'wb').write(blob)
            print(name, len(blob), 'bytes')
    elif len(a) == 2 and a[0] == 'csum':
        print('%04X' % csum(read_oct(open(a[1], 'rb').read())[3]))
    elif len(a) == 3 and a[0] == 'to-oct':
        to_oct(a[1], a[2], pack=not raw)
    elif len(a) == 3 and a[0] == 'to-png':
        to_png(a[1], a[2])
    else:
        print(__doc__ if __doc__ else open(__file__).read().split('\n\n')[0])
        sys.exit(1)


if __name__ == '__main__':
    main(sys.argv[1:])
