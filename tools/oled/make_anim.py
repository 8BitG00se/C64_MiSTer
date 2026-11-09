#!/usr/bin/env python3
# A program's own front-screen animation: a GIF, a video or a folder of frames -> NAME.oled for the tty2oled screen
# (256 x 64, 16 greys), plus a preview (an animated GIF, three times the size, tinted like the acid-green perspex).
#
#   make_anim.py INPUT -o "Night City.oled" [options]
#     INPUT   a .gif / .png (animated or not), a video ffmpeg can read, or a folder of .png/.jpg frames (name order)
#             or a pattern in quotes ("frames/*_hdmi_*.png")
#   options
#     --crop X,Y,W,H     the part of the source picture to show (default: the middle band, 4:1)
#     --shear K          tilt the picture first (column x moves down K*x pixels) so a diagonal lies along the strip
#     --from N --to N    which source frames (default all), --every N  take every Nth one
#     --fps F            how fast the screen plays them (default 25)
#     --bounce           play forwards, then backwards (smooth loops for swings and turns; no extra data)
#     --gamma G          < 1 lifts the darks (default 0.8); --black / --white percentiles for the stretch
#     --levels N         greys used, 2..16 (default 16; fewer = smaller file)
#     --max-kb K         keep the frames under K KB (default 64, about 6 s to send); the clip is cut shorter to fit
#     --steady S         a pixel keeps its grey unless it changes by more than S of a step (default 0.35; 0 off)
#     --still N          the frame shown on a screen without the Octophonic animation firmware (default the middle)
#     --preview FILE     the preview GIF (default NAME_preview.gif beside the .oled)
#
# Put NAME.oled beside the program (NAME.prg / NAME.d64 / NAME.crt) - same name - or as the only .oled in its folder.
# Octophonic Main sends it to the screen when the program runs, and the Octophonic logo comes back when it ends.
#
# The .oled file (all numbers low byte first):
#   0  "OCTOANI1"           8 bytes
#   8  frame time in ms     1 byte  (20..255)
#   9  mode                 1 byte  (0 loop, 1 bounce)
#   10 frames               2 bytes
#   12 data length          4 bytes
#   16 data: per frame a 2-byte length, then PackBits of (this frame XOR the frame before; the first XOR black).
#      Parallax: with the length's top bit set, the frame starts with a count of bands, then per band the first row,
#      the row after the last, and the pixels it moves left (signed); they are moved (black coming in) before the XOR.
#      (Loop mode only - what scrolls off can't come back for bounce.) The length counts everything after it.
#      PackBits as the logo in the firmware: n < 128: the next n+1 bytes as they are; n >= 128: the next byte n-126 times.
#      A picture is 8192 bytes: 64 rows of 128 bytes, two pixels a byte, the left one in the high nibble.
#   16+data: the still picture (8192 bytes, a plain .gsc) for screens running older firmware.
# The screen (8BitG00se/octophonic-tty2oled OCTO4) gets "CMDOANI,<data length>,<frames>,<ms>,<mode>" and the data.
import sys, os, glob, struct, argparse, subprocess, tempfile
import numpy as np
from PIL import Image, ImageSequence

W, H = 256, 64
MAGIC = b'OCTOANI1'


def load_frames(src, a):
    if os.path.isdir(src) or any(c in src for c in '*?['):
        pat = os.path.join(src, '*') if os.path.isdir(src) else src
        files = sorted(f for f in glob.glob(pat) if f.lower().endswith(('.png', '.jpg', '.jpeg', '.bmp')))
        sel = files[a.start:a.end][::a.every]
        return [Image.open(f).convert('RGB') for f in sel]
    if src.lower().endswith(('.gif', '.png', '.webp')):
        im = Image.open(src)
        fr = [f.convert('RGB') for f in ImageSequence.Iterator(im)]
        return fr[a.start:a.end][::a.every]
    with tempfile.TemporaryDirectory() as t:                     # a video: ffmpeg to PNGs first
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', src, os.path.join(t, 'f%05d.png')], check=True)
        files = sorted(glob.glob(os.path.join(t, '*.png')))[a.start:a.end][::a.every]
        return [Image.open(f).convert('RGB') for f in files]


def shear(im, k):                                               # tilt: column x moves down by k*x (a diagonal lies flat)
    a = np.asarray(im); out = np.zeros_like(a); h = a.shape[0]
    for x in range(a.shape[1]):
        d = int(round(k * x))
        if d >= 0: out[d:, x] = a[:h - d, x] if d < h else 0
        else: out[:h + d, x] = a[-d:, x]
    return Image.fromarray(out)


def fit(frames, crop, k=0):
    if k: frames = [shear(f, k) for f in frames]
    w0, h0 = frames[0].size
    if crop:
        x, y, w, h = crop
    else:                                                        # the middle 4:1 band
        w, h = (w0, w0 // 4) if w0 / h0 < 4 else (h0 * 4, h0)
        x, y = (w0 - w) // 2, (h0 - h) // 2
    out = []
    for f in frames:
        g = f.crop((x, y, x + w, y + h)).resize((W, H), Image.LANCZOS)
        # luminance, with saturated colours lifted a little so coloured things don't sink into the dark
        c = np.asarray(g).astype(float)
        lum = 0.299 * c[..., 0] + 0.587 * c[..., 1] + 0.114 * c[..., 2]
        out.append(0.75 * lum + 0.25 * c.max(-1))
    return np.array(out)


def to_greys(v, a):
    lo = np.percentile(v, a.black)
    hi = np.percentile(v, a.white)
    x = np.clip((v - lo) / max(hi - lo, 1), 0, 1) ** a.gamma * (a.levels - 1)
    out = []; prev = None
    for f in x:                                                  # steady: a pixel keeps its grey unless it really moved
        q = np.rint(f)
        if prev is not None and a.steady > 0:
            keep = np.abs(f - prev) < 0.5 + a.steady
            q = np.where(keep, prev, q)
        out.append(q); prev = q
    q = np.array(out)
    return np.rint(q * 15 / (a.levels - 1)).astype(np.uint8)    # always 0..15 on the screen


def pack(g):                                                     # 64 x 256 greys -> 8192 bytes
    return ((g[:, 0::2] << 4) | g[:, 1::2]).astype(np.uint8).tobytes()


def packbits(b):
    out = bytearray(); i = 0; n = len(b)
    while i < n:
        r = 1
        while i + r < n and r < 129 and b[i + r] == b[i]: r += 1
        if r >= 2:
            out += bytes([r + 126, b[i]]); i += r
        else:
            j = i
            while j < n and j - i < 128 and not (j + 1 < n and b[j + 1] == b[j]): j += 1
            if j == i: j = i + 1
            out += bytes([j - i - 1]) + bytes(b[i:j]); i = j
    return bytes(out)


def shift_rows(g, y0, y1, k):                                   # rows y0..y1-1 move k pixels left, black coming in
    g = g.copy()
    if k > 0: g[y0:y1, :W - k] = g[y0:y1, k:]; g[y0:y1, W - k:] = 0
    elif k < 0: g[y0:y1, -k:] = g[y0:y1, :W + k]; g[y0:y1, :-k] = 0
    return g


def find_bands(prev, cur, maxk=8):
    # each row: the move that makes most of it match the frame before; rows with the same move make one band
    ks = []
    for y in range(H):
        best, bk = (prev[y] != cur[y]).sum(), 0
        for k in range(-maxk, maxk + 1):
            if not k: continue
            p = shift_rows(prev[y:y + 1], 0, 1, k)[0]
            c = (p != cur[y]).sum()
            if c < best * 0.7: best, bk = c, k
        ks.append(bk)
    bands = []; y = 0
    while y < H:
        y1 = y
        while y1 < H and ks[y1] == ks[y]: y1 += 1
        if ks[y]: bands.append((y, y1, ks[y]))
        y = y1
    return bands


def encode(frames, bounce=False):
    data = bytearray(); prev = np.zeros((H, W), np.uint8)
    for g in frames:
        best = None
        for bands in ([] if bounce else [find_bands(prev, g)]) + [[]]:
            base = prev
            for (y0, y1, k) in bands: base = shift_rows(base, y0, y1, k)
            x = (np.frombuffer(pack(g), np.uint8) ^ np.frombuffer(pack(base), np.uint8))
            d = packbits(x.tobytes()) if x.any() else b''               # nothing changed: an empty frame (2 bytes)
            if bands:
                d = bytes([len(bands)]) + b''.join(struct.pack('<BBb', *b) for b in bands) + d
                rec = struct.pack('<H', 0x8000 | len(d)) + d
            else:
                rec = struct.pack('<H', len(d)) + d
            if best is None or len(rec) < len(best): best = rec
        data += best
        prev = g
    return bytes(data)


def decode(data, frames, mode):
    # exactly as the firmware's oled_aniframe/oled_aniplay do it: one pass (forwards, and backwards for bounce)
    offs = []; i = 0
    while i + 2 <= len(data):
        offs.append(i); i += 2 + (struct.unpack_from('<H', data, i)[0] & 0x7FFF)
    assert i == len(data) and len(offs) == frames, 'the frames do not add up'
    buf = bytearray(8192); shown = []

    def frame(f):
        nonlocal buf
        i = offs[f]; fl = struct.unpack_from('<H', data, i)[0]; e = i + 2 + (fl & 0x7FFF); i += 2; o = 0
        if fl & 0x8000:
            nb = data[i]; i += 1
            g = unpack(bytes(buf))
            for b in range(nb):
                y0, y1, k = struct.unpack_from('<BBb', data, i); i += 3
                g = shift_rows(g, y0, min(y1, H), k)
            buf = bytearray(pack(g))
        while i < e and o < 8192:
            n = data[i]; i += 1
            if n < 128:
                k = 0
                while k <= n and o < 8192 and i < e: buf[o] ^= data[i]; o += 1; i += 1; k += 1
            else:
                v = data[i]; i += 1; r = n - 126
                if v:
                    for _ in range(r):
                        if o >= 8192: break
                        buf[o] ^= v; o += 1
                else: o += r
        shown.append(bytes(buf))

    for f in range(frames): frame(f)
    if mode == 1:
        for f in range(frames - 1, 0, -1): frame(f)
    return shown


def unpack(b):
    a = np.frombuffer(b, np.uint8).reshape(H, W // 2)
    g = np.empty((H, W), np.uint8); g[:, 0::2] = a >> 4; g[:, 1::2] = a & 15
    return g


def preview(shown, ms, path, scale=3):
    ims = []
    for b in shown:
        g = unpack(b).astype(int)
        rgb = np.stack([g * 8, g * 17, g * 6], -1).astype(np.uint8)          # acid-green perspex tint, as make_card.py
        im = Image.fromarray(rgb).resize((W * scale, H * scale), Image.NEAREST)
        ims.append(im)
    ims[0].save(path, save_all=True, append_images=ims[1:], duration=ms, loop=0, optimize=False, disposal=1)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('input'); p.add_argument('-o', '--out', required=True)
    p.add_argument('--crop'); p.add_argument('--from', dest='start', type=int, default=0)
    p.add_argument('--to', dest='end', type=int); p.add_argument('--every', type=int, default=1)
    p.add_argument('--fps', type=float, default=25); p.add_argument('--bounce', action='store_true')
    p.add_argument('--gamma', type=float, default=0.8); p.add_argument('--black', type=float, default=1)
    p.add_argument('--white', type=float, default=99.7); p.add_argument('--levels', type=int, default=16)
    p.add_argument('--max-kb', type=float, default=64); p.add_argument('--still', type=int)
    p.add_argument('--preview')
    p.add_argument('--shear', type=float, default=0, help='tilt first: column x moves down k*x pixels (straightens a diagonal)')
    p.add_argument('--steady', type=float, default=0.35, help='0 off; higher keeps more pixels still (less flicker, smaller)')
    a = p.parse_args()
    a.levels = max(2, min(16, a.levels))
    crop = tuple(int(v) for v in a.crop.split(',')) if a.crop else None
    src = load_frames(a.input, a)
    if not src: sys.exit('no frames in ' + a.input)
    greys = to_greys(fit(src, crop, a.shear), a)
    ms = int(round(1000 / a.fps)) ; mode = 1 if a.bounce else 0
    greys = greys[:1024]                                         # the screen holds at most 1024 frames
    sel = greys
    data = encode(sel, a.bounce)
    cut = 0
    if len(data) > a.max_kb * 1024:                             # too big: the longest clip that fits (same speed)
        lo, hi = 2, len(sel)
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if len(encode(greys[:mid], a.bounce)) <= a.max_kb * 1024: lo = mid
            else: hi = mid
        sel = greys[:lo]; data = encode(sel, a.bounce); cut = 1
    fms = min(255, max(20, ms))
    n = len(sel)
    still = sel[a.still if a.still is not None else n // 2]
    shown = decode(data, n, mode)
    for k in range(n): assert shown[k] == pack(sel[k]), 'decode mismatch at frame %d' % k
    with open(a.out, 'wb') as f:
        f.write(MAGIC + struct.pack('<BBHI', fms, mode, n, len(data)) + data + pack(still))
    pv = a.preview or os.path.splitext(a.out)[0] + '_preview.gif'
    preview(shown, fms, pv)
    size = os.path.getsize(a.out)
    print('%s: %d frames, %d ms a frame (%.1f fps)%s, %.1f KB (about %.1f s to send at 115200 baud)%s'
          % (os.path.basename(a.out), n, fms, 1000 / fms, ', bounce' if mode else '', size / 1024,
             (len(data) + 40) / 11520, ' - cut to %d of %d frames to fit %g KB' % (n, len(greys), a.max_kb) if cut else ''))
    print('preview: ' + pv)


if __name__ == '__main__':
    main()
