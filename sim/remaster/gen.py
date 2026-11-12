# LEVEL 2 REMASTER: made-up frames (.l2f), a pack for them and the C64 RAM - every case the unit has:
# scrolled cells, tiles with holes, a cut row, sprites with and without art, expanded, behind graphics,
# multicolour, on top of each other, a border table.   gen.py OUTDIR [seed]          (c) 2026 Mong00se
import sys, os, struct
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import model as M

W, H, LINE0 = 396, 284, 16
rng = np.random.default_rng(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
out = sys.argv[1]

def level1():
    b = bytearray(0x3800)
    b[0:8] = b'RGB256PK'; b[8] = 2; b[9] = 3
    b[0x100:0x300] = bytes(((np.arange(512) // 20) % 16).astype(np.uint8))
    b[0x300:0x400] = bytes(rng.integers(0, 14, 256, dtype=np.uint8))
    cells = rng.integers(0, 14, 1024, dtype=np.uint8); cells[rng.random(1024) < 0.7] = 0
    b[0x400:0x800] = bytes(cells)
    b[0x800:0x1800] = bytes(rng.integers(1, 256, 4096, dtype=np.uint8))
    pal = rng.integers(0, 256, (8, 256, 4), dtype=np.uint8); pal[:, :, 3] = 0
    b[0x1800:0x3800] = pal.tobytes()
    return bytes(b)

chars = rng.integers(0, 256, (48, 8), dtype=np.uint8)       # a small charset: keys repeat
chars[0] = 0
def frame(fno, xs, ys, cut=False, nspr=8):
    idx = np.zeros((H, W), np.uint8); tag = np.full((H, W), 3 << 8, np.int32)
    gfx = np.zeros((H, W), np.uint8); cell = np.full((H, W), 0xFF, np.uint8); code = np.zeros((H, W), np.uint8)
    ram = bytearray(rng.integers(0, 256, 65536, dtype=np.uint8).tobytes())
    bg = int(rng.integers(0, 16)); ec = int(rng.integers(0, 16))
    scr = rng.integers(0, 48, (25, 40)); col = rng.integers(0, 16, (25, 40))
    scr[rng.random((25, 40)) < 0.3] = 0
    # the whole visible picture: border colour, then the window's graphics
    tag[:, :] = 2 << 8; idx[:, :] = ec
    gfx[:, :] = bg
    top = 48 + ys                                    # the first row's first line
    for r in range(25):
        nl = 8 if not (cut and r == 12) else 5       # a cut row: 5 lines, then the next row starts
        for j in range(nl):
            y = top + r * 8 + j - (3 if (cut and r > 12) else 0) - LINE0
            if y < 0 or y >= H: continue
            for c in range(40):
                x = 32 + xs + c * 8
                bits = int(chars[scr[r, c], j])
                for i in range(8):
                    on = (bits >> (7 - i)) & 1
                    gfx[y, x + i] = (int(col[r, c]) if on else bg) | (on << 4)
                    cell[y, x + i] = (j << 3) | i
                    code[y, x + i] = scr[r, c]
    # the window: 40 columns x 200 lines at X0, line 51
    wy0, wy1 = 51 - LINE0, 251 - LINE0
    win = np.zeros((H, W), bool); win[wy0:wy1, 32:352] = True
    idx[win] = gfx[win] & 15
    tag[win] = np.where(cell[win] != 0xFF, code[win].astype(np.int32), 0)
    # sprites
    spr = np.zeros((H, 8, 12), np.uint8)
    mm0, mm1 = int(rng.integers(0, 16)), int(rng.integers(0, 16))
    layer = np.full((H, W), -1, np.int32); lcol = np.zeros((H, W), np.uint8)
    for n in range(nspr - 1, -1, -1):
        X = int(rng.integers(10, 340)); Y = int(rng.integers(40, 240))
        if n == 6: X, Y = sx0 + 6, sy0 + 5               # two on top of each other
        if n == 7: sx0, sy0 = X, Y
        xe, ye, behind, mc = [int(v) for v in rng.integers(0, 2, 4)]
        colr = int(rng.integers(0, 16)); addr = int(rng.integers(0, 1023)) * 64
        data = rng.integers(0, 256, 63, dtype=np.uint8); data[rng.random(63) < 0.3] = 0
        ram[addr:addr + 63] = data.tobytes()
        for row in range(21):
            for rep in range(1 + ye):
                y = Y + 1 + row * (1 + ye) + rep - LINE0
                if y < 0 or y >= H: continue
                first = row == 0 and rep == 0
                spr[y, n] = [1 | (xe << 1) | (behind << 2) | (mc << 3) | (16 if first else 0), row, X & 255, X >> 8,
                             colr, mm0, mm1, 0, addr & 255, addr >> 8, 0, 0]
                bits = (int(data[row * 3]) << 16) | (int(data[row * 3 + 1]) << 8) | int(data[row * 3 + 2])
                for cx in range(24):
                    if mc:
                        v = (bits >> (22 - (cx & ~1))) & 3
                        c2 = [None, mm0, colr, mm1][v]
                    else:
                        c2 = colr if (bits >> (23 - cx)) & 1 else None
                    if c2 is None: continue
                    for e in range(1 + xe):
                        x = X + 8 + cx * (1 + xe) + e
                        if 0 <= x < W:
                            layer[y, x] = n; lcol[y, x] = c2
                            spr_behind[y, x] = behind
    return dict(fno=fno, w=W, h=H, line0=LINE0, x0=32, idx=idx, tag=tag, gfx=gfx, cell=cell, code=code, spr=spr,
                ram=bytes(ram)), layer, lcol

frames = []
spr_behind = None
for fno, (xs, ys, cut) in enumerate([(0, 3, False), (5, 3, False), (7, 0, False), (2, 7, False), (3, 3, True), (0, 3, False)]):
    spr_behind = np.zeros((H, W), np.uint8)
    f, layer, lcol = frame(fno, xs, ys, cut)
    # put the sprites over the picture as the VIC does: not under the border; behind graphics -> only on background
    isb = (f['tag'] >> 8) == 2
    fgb = (f['gfx'] >> 4) & 1
    show = (layer >= 0) & ~isb & ~((spr_behind == 1) & (fgb == 1))
    f['idx'] = np.where(show, lcol, f['idx']).astype(np.uint8)
    f['tag'] = np.where(show, (1 << 8) | layer, f['tag'])
    frames.append(f)
frames[5] = dict(frames[0], fno=5)                  # the first frame again (the learn test: nothing new)
M.write_l2f(os.path.join(out, 'test.l2f'), frames)

# the pack: art for about half of the blocks and sprites met, with holes (0 bytes); a border table
blocks = {}; sprites = {}
for f in frames:
    _, _, keys = M.frame_cells(f)
    for k in sorted(keys):
        if k not in blocks and rng.random() < 0.5:
            t = rng.integers(1, 256, 64, dtype=np.uint8); t[rng.random(64) < 0.15] = 0
            blocks[k] = t.tobytes()
    _, skeys = M.frame_sprites(f)
    for k in sorted(skeys):
        if k not in sprites and rng.random() < 0.6:
            t = rng.integers(1, 256, 504, dtype=np.uint8); t[rng.random(504) < 0.4] = 0
            sprites[k] = t.tobytes()
border = rng.integers(0, 256, 512, dtype=np.uint8); border[rng.random(512) < 0.5] = 0
open(os.path.join(out, 'test.rgb'), 'wb').write(M.write_pack(level1(), blocks, sprites, border.tobytes()))
print(f'gen: {len(frames)} frames, pack with {len(blocks)} blocks and {len(sprites)} sprite frames')
