# sim/finescroll: the scene and the script. Layer 0: a 256-colour bitmap whose column u is colour u (u < 240) (the
# palette is OctoVIC's power-on grey ramp), so every pixel says which column it is. Layer 1: a bitmap
# with 4-pixel stripes of colour 245 (see-through between) in its rows 128 on (raster line 179 on). One
# 8x8 sprite of colour 250 at (150, 100). Then 13 steps, a frame each: Q = 0..12 quarter pixels:
#   layer 0  SCROLLX = Q >> 2, L0FINE = Q & 3              (moves left a quarter pixel a step)
#   layer 1  SCROLLX = 2Q >> 2, L1FINE = 2Q & 3            (two quarter pixels a step)
#   sprite   X = 150 + (Q >> 2) (one of 4 sprite tables), SPRFINE = Q & 3   (right a quarter pixel a step)
# Step k is written in frame k+1 at raster line 302 and shows in frame k+2.
#   python3 gen.py vram.bin script.txt
import sys
vram = bytearray(16 << 20)
s = []
def W(a, v): s.append("w %x %x" % (a, v & 255))
def W24(a, v): W(a, v); W(a + 1, v >> 8); W(a + 2, v >> 16)
L1BM, SAT, SGFX = 0x010000, 0x020000, 0x030000
for r in range(256):
    for u in range(256):
        vram[r * 256 + u] = u if u < 240 else u - 128                 # layer 0: colour = column (240-255 kept for layer 1 and the sprite)
        vram[L1BM + r * 256 + u] = 245 if (r >= 128 and u % 16 < 4) else 0
for i in range(4):                                                    # sprite tables: X = 150 + i
    e = (150 + i) | (100 << 16) | (0 << 32) | (1 << 54) | (1 << 55)
    for b in range(8): vram[SAT + i * 0x100 + b] = (e >> (8 * b)) & 255
for b in range(64): vram[SGFX + b] = 250
W(0x05, 0x15)                                                         # on, VIC behind, VIC hidden (backdrop black)
W(0x20, 0x09); W24(0x24, 0)                                           # layer 0: on, bitmap
W(0x30, 0x09); W24(0x34, L1BM)                                        # layer 1: on, bitmap
W24(0x13, SAT); W24(0x16, SGFX); W(0x0F, 1)
for k in range(13):
    s.append("wait %d 302" % (k + 1))
    q0, q1 = k, 2 * k
    W(0x28, q0 >> 2); W(0x29, 0); W(0x27, q0 & 3)
    W(0x38, q1 >> 2); W(0x39, 0); W(0x37, q1 & 3)
    W24(0x13, SAT + (k >> 2) * 0x100); W(0x07, k & 3)
open(sys.argv[1], "wb").write(vram)
open(sys.argv[2], "w").write("\n".join(s) + "\n")
