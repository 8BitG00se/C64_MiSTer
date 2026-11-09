# A program's OctoVIC writes, made up (no emulator needed), in the emulator's log format (OCTO_DUMP .log:
# frame u32, line u16, register u8, value u8, VDATA address u32) - for replay.py and CI.
#   python3 gen.py vblank OUT.log [frames]    the shooter engine's way: a 48-sprite table uploaded into VDATA
#                                             at REU speed in the vertical blank (lines 300-306), then the
#                                             ship's position patched over it (line 307); one table, new
#                                             positions every frame
#   python3 gen.py flip OUT.log [frames]      Code/sprites' way: two tables, the one not shown written during
#                                             the frame (line 100 on), then SATBASE flipped to it (line 200)
import sys, struct
mode, out = sys.argv[1], sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 12
ev = []; va = [0]
def w(f, l, r, v):
    a = va[0]
    if r <= 2: va[0] = (va[0] & ~(255 << 8 * r)) | (v & 255) << 8 * r
    if r == 4: va[0] = (va[0] + 1) & 0xFFFFFF
    ev.append(struct.pack('<IHBBI', f, l, r, v & 255, a if r == 4 else va[0]))
def vaddr(f, l, a): w(f, l, 0, a); w(f, l, 1, a >> 8); w(f, l, 2, a >> 16); w(f, l, 3, 1)
def entry(f, l, i, k):                       # sprite i in frame k: somewhere new every frame, on, 16x16
    x = (k * 5 + i * 37) % 400 - 32; y = (k * 3 + i * 23) % 300 - 40
    for b in (x & 255, (x >> 8) & 255, y & 255, (y >> 8) & 255, i & 7, 0, 0x85, i & 15): w(f, l, 4, b)
NS = 48
w(0, 0, 0x0F, NS); w(0, 0, 0x16, 0); w(0, 0, 0x17, 0); w(0, 0, 0x18, 5)
if mode == 'vblank':
    w(0, 0, 0x13, 0); w(0, 0, 0x14, 0); w(0, 0, 0x15, 6)
    for f in range(N):
        vaddr(f, 300, 0x060000)
        for i in range(NS): entry(f, 300, i, f)                   # 384 bytes, one a microsecond: lines 300-306
        vaddr(f, 307, 0x060000 + 25 * 8)                          # the ship moved after the table was built
        for b in ((f * 2) & 255, 0, 100, 0): w(f, 307, 4, b)
        w(f, 308, 0x0F, NS)
elif mode == 'flip':
    for f in range(N):
        base = 0x060000 + (f & 1) * 0x200
        vaddr(f, 100, base)
        for i in range(NS): entry(f, 100 + i, i, f)               # (the 6502 is slower: a sprite a line)
        w(f, 200, 0x13, 0); w(f, 200, 0x14, base >> 8); w(f, 200, 0x15, base >> 16)
open(out, 'wb').write(b''.join(ev))
