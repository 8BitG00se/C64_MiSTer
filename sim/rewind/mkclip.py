#!/usr/bin/env python3
# REWIND simulation: the simulated picture (tb.cpp's frames.bin: 512 x 320 bytes a frame - the VIC's
# colour index, the on-screen REWIND, the blanking) as an MP4 and a sheet of stills.
#   mkclip.py frames.bin out.mp4 sheet.png [first frame] [frames]           (c) 2026 Mong00se
import subprocess, sys
import numpy as np
from PIL import Image
W, H = 512, 320
PAL = np.array([(0,0,0),(255,255,255),(129,51,56),(117,206,200),(142,60,151),(86,172,77),(46,44,155),(237,241,113),
                (142,80,41),(85,56,0),(196,108,113),(74,74,74),(123,123,123),(169,255,159),(112,109,235),(178,178,178)], np.uint8)
OSD = {1:(0,0,255),2:(0,255,0),3:(0,255,255),4:(255,0,0),5:(255,0,255),6:(255,255,0),7:(255,255,255)}
raw = np.fromfile(sys.argv[1], np.uint8)
n = len(raw) // (W * H)
fr = raw[:n * W * H].reshape(n, H, W)
a = int(sys.argv[4]) if len(sys.argv) > 4 else 0
b = min(n, a + int(sys.argv[5])) if len(sys.argv) > 5 else n
fr = fr[a:b]
vis = (fr[len(fr) // 2] & 0x80) == 0                       # what is not blanking, from a frame in the middle
ys, xs = np.where(vis)
y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
x1 -= (x1 - x0) & 1; y1 -= (y1 - y0) & 1
def colour(f):
    img = PAL[f & 15]
    o = (f >> 4) & 7
    for k, c in OSD.items(): img[o == k] = c
    return img[y0:y1, x0:x1]
w, h = x1 - x0, y1 - y0
ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (w, h), "-r", "50",
                       "-i", "-", "-vf", "scale=%d:%d:flags=neighbor" % (w * 2, h * 2), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", sys.argv[2]],
                      stdin=subprocess.PIPE)
for f in fr: ff.stdin.write(colour(f).tobytes())
ff.stdin.close(); ff.wait()
# stills: 12 frames evenly through the clip
k = [int(i * (len(fr) - 1) / 11) for i in range(12)]
sheet = Image.new("RGB", (w * 4, h * 3))
for i, j in enumerate(k): sheet.paste(Image.fromarray(colour(fr[j])), ((i % 4) * w, (i // 4) * h))
sheet.save(sys.argv[3])
print("mkclip: %d frames %dx%d -> %s, %s" % (len(fr), w, h, sys.argv[2], sys.argv[3]))
