# sim/finescroll: a picture of the steps (each sub-pixel drawn 3 wide, each line 12 high): for every step,
# a strip of line 154 (the sprite) and line 250 (layer 1's stripes over layer 0), new core above, old below.
#   python3 pics.py q1.rgb old.rgb outdir     -> outdir/finescroll.png
import sys, zlib, struct, numpy as np
W, H = 504 * 4, 312
q1 = np.fromfile(sys.argv[1], np.uint8).reshape(-1, H, W, 3)
old = np.fromfile(sys.argv[2], np.uint8).reshape(-1, H, W, 3)
rows = []
x0, x1 = 4 * 176, 4 * 236
for k in range(13):
    for f in (q1, old):
        for line in (154, 250):
            strip = f[k + 2, line, x0:x1]
            rows.append(np.repeat(np.repeat(strip[None], 10, 0), 3, 1))
        rows.append(np.full((2, (x1 - x0) * 3, 3), 60 if f is q1 else 0, np.uint8))
    rows.append(np.full((6, (x1 - x0) * 3, 3), (255, 0, 0), np.uint8))
img = np.concatenate(rows, 0)
def png(path, a):
    h, w, _ = a.shape
    raw = b"".join(b"\0" + a[y].tobytes() for y in range(h))
    def ch(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + ch(b"IDAT", zlib.compress(raw, 9)) + ch(b"IEND", b""))
png(sys.argv[3] + "/finescroll.png", img)
print("picture:", sys.argv[3] + "/finescroll.png", img.shape)
