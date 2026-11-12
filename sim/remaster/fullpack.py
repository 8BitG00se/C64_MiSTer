# LEVEL 2 REMASTER, the whole-C64 run: the frames the real VIC-II gave the unit (sim/rewind tb, mode remaster) are
# checked against the C64's own memory, and a pack is made for them.            (c) 2026 Mong00se
#   fullpack.py FRAMES.l2f CHARGEN.hex OUT.rgb
# 1. every graphics cell's pixels are the glyph of the cell's char code in the charset the VIC reads, and the codes
#    are the screen matrix's (so a cell's first pixel, its row counter and its code are what the unit thinks they are);
# 2. every sprite pixel the VIC drew is a set bit of that sprite's data in RAM at the column and row the unit
#    works out from the sprite's start (so X, row, expansion and the data address are right);
# 3. a pack with art for half of the blocks and sprite frames met (random pixels, with holes), a border table.
import sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import model as M
frames = M.read_l2f(sys.argv[1])
chargen = bytes(int(l, 16) for l in open(sys.argv[2]).read().split())
rng = np.random.default_rng(14)
bad_c = n_c = bad_s = n_s = bad_m = n_m = 0
blocks = {}; sprites = {}; nk = [0, 0]
for f in frames:
    h, w = f['idx'].shape
    cell = f['cell']; fg = (f['gfx'] >> 4) & 1
    # 1: cells against the C64's memory: the cell's pixels are the glyph of its code in the charset the VIC reads
    #    (one of 8 places in one of 4 banks; the char ROM at $1000/$1800 of banks 0 and 2), and the codes are the
    #    screen matrix (one of 16 places). The best place must fit (nearly) every cell - the game changes a few
    #    cells of the screen during the frame, the RAM here is the end of the frame's.
    ram = f['ram']
    ys, xs = np.nonzero((cell != 0xFF) & ((cell & 7) == 0))
    rows = []
    for y, x in zip(ys, xs):
        if x + 8 > w: continue
        rows.append((int(f['code'][y, x]), int(cell[y, x]) >> 3, int(''.join(str(int(b)) for b in fg[y, x:x + 8]), 2)))
    best = 0
    for bank in range(4):
        for cb in range(8):
            base = bank * 16384 + cb * 2048
            mem = chargen[(cb & 1) * 2048:(cb & 1) * 2048 + 2048] if (bank in (0, 2) and cb in (2, 3)) else ram[base:base + 2048]
            best = max(best, sum(1 for c, j, b in rows if mem[c * 8 + j] == b))
    n_c += len(rows); bad_c += len(rows) - best
    # the codes against the screen matrix: text row r = the r-th row whose first line (j = 0) is seen, column by order
    grid = []
    for y in range(h):
        xs2 = np.nonzero((cell[y] != 0xFF) & ((cell[y] & 7) == 0))[0]
        if len(xs2) == 40 and (int(cell[y, xs2[0]]) >> 3) == 0: grid.append([int(f['code'][y, x]) for x in xs2])
    bests = 0
    for bank in range(4):
        for vm in range(16):
            base = bank * 16384 + vm * 1024
            bests = max(bests, sum(1 for r, g in enumerate(grid[:25]) for c, v in enumerate(g) if ram[base + r * 40 + c] == v))
    n_m += 40 * len(grid[:25]); bad_m += 40 * len(grid[:25]) - bests
    # 2: sprite pixels against the sprites' data
    slines, skeys = M.frame_sprites(f)
    kind = f['tag'] >> 8; code = f['tag'] & 255
    ys, xs = np.nonzero(kind == 1)
    for y, x in zip(ys, xs):
        n = int(code[y, x]) & 7; s = slines[y][n]; n_s += 1
        if s is None: bad_s += 1; continue
        k, row, X, xe, behind = s
        col = (x - (X + 8)) >> xe
        pre, data = skeys[k]
        if not (0 <= col < 24): bad_s += 1; continue
        b = (data[row * 3] << 16) | (data[row * 3 + 1] << 8) | data[row * 3 + 2]
        v = (b >> (22 - (col & ~1))) & 3 if pre[0] else ((b >> (23 - col)) & 1)
        if not v: bad_s += 1
    # 3
    _, _, keys = M.frame_cells(f)
    nk[0] += len(keys); nk[1] += len(skeys)
    for k in sorted(keys):
        if k not in blocks and rng.random() < 0.5:
            t = rng.integers(1, 256, 64, dtype=np.uint8); t[rng.random(64) < 0.15] = 0; blocks[k] = t.tobytes()
    for k in sorted(skeys):
        if k not in sprites and rng.random() < 0.6:
            t = rng.integers(1, 256, 504, dtype=np.uint8); t[rng.random(504) < 0.4] = 0; sprites[k] = t.tobytes()
print(f'{len(frames)} frames from the real VIC-II: {n_c} cell rows, {bad_c} not the glyph of their code in the charset; '
      f'{n_m} cells, {bad_m} not the screen matrix\'s code; '
      f'{n_s} sprite pixels, {bad_s} not a set bit of the sprite data at the unit\'s column and row')
b = bytearray(0x3800)
b[0:8] = b'RGB256PK'; b[8] = 2; b[9] = 2
b[0x100:0x300] = bytes(((np.arange(512) // 16) % 16).astype(np.uint8))
b[0x300:0x400] = bytes(rng.integers(0, 14, 256, dtype=np.uint8))
cells = rng.integers(0, 14, 1024, dtype=np.uint8); cells[rng.random(1024) < 0.7] = 0
b[0x400:0x800] = bytes(cells)
b[0x800:0x1800] = bytes(rng.integers(1, 256, 4096, dtype=np.uint8))
pal = rng.integers(0, 256, (8, 256, 4), dtype=np.uint8); pal[:, :, 3] = 0
b[0x1800:0x3800] = pal.tobytes()
border = rng.integers(0, 256, 512, dtype=np.uint8); border[rng.random(512) < 0.5] = 0
open(sys.argv[3], 'wb').write(M.write_pack(bytes(b), blocks, sprites, border.tobytes()))
print(f'pack: {len(blocks)} blocks, {len(sprites)} sprite frames')
ok = n_c > 1000 and n_s > 100 and bad_c * 100 <= n_c and bad_m * 100 <= n_m and bad_s == 0
print('REMASTER_VIC_OK' if ok else 'REMASTER_VIC_FAIL')
sys.exit(0 if ok else 1)
