# LEVEL 2 REMASTER (Build 14): the model of rtl/remaster.sv + rtl/rgb256.sv, straight from docs/RGB256.md
# "Level 2" - the pack (version 2), the key, the frames for the simulation (.l2f) and what each pixel shows.
#   python3 model.py PACK.rgb FRAMES.l2f OUT.rgb [palette] [level2 on: 1/0]       (c) 2026 Mong00se
import sys, struct
import numpy as np

SIZE1 = 0x3800
X0, Y0, OUTSIDE = 32, 51, 1000
POLY = 0x42F0E1EBA9EA3693
M64 = 0xFFFFFFFFFFFFFFFF
_T = []
for _i in range(256):
    _c = _i << 56
    for _ in range(8):
        _c = ((_c << 1) ^ POLY) & M64 if _c >> 63 else (_c << 1) & M64
    _T.append(_c)

def key(data):
    """CRC-64, polynomial $42F0E1EBA9EA3693, start all ones, MSB first, no final XOR"""
    c = M64
    for b in data:
        c = _T[((c >> 56) ^ b) & 255] ^ ((c << 8) & M64)
    return c
assert key(b"123456789") == 0x9D13A61C0E5B0FF5 and key(bytes(32)) == 0xCF3354C179E0A56C

# --------------------------------------------------------------------------- the pack
def read_pack(data):
    a = np.frombuffer(data[:SIZE1], np.uint8)
    pk = dict(npal=data[9], band=a[0x100:0x300] & 15, charcls=a[0x300:0x400] & 15, cellcls=a[0x400:0x800] & 15,
              remap=a[0x800:0x1800], pal=a[0x1800:0x3800].reshape(8, 256, 4)[:, :, :3],
              blocks={}, sprites={}, border=np.zeros(512, np.uint8), l2=False)
    if len(data) >= 0x3840 and data[0x3800:0x3804] == b'LVL2':
        _, boff, nb, soff, ns, broff, flen, nblk, nspr = struct.unpack('<9I', data[0x3804:0x3828])
        pk['l2'] = True; pk['nb'] = nb; pk['ns'] = ns
        if broff: pk['border'] = np.frombuffer(data[broff:broff + 512], np.uint8)
        for b in range(1 << nb):
            for w in range(2):
                o = boff + b * 144 + w * 72
                k = struct.unpack('<Q', data[o:o + 8])[0]
                if k: pk['blocks'].setdefault(k, np.frombuffer(data[o + 8:o + 72], np.uint8))
        for b in range(1 << ns):
            for w in range(2):
                o = soff + b * 1024 + w * 512
                k = struct.unpack('<Q', data[o:o + 8])[0]
                if k: pk['sprites'].setdefault(k, np.frombuffer(data[o + 8:o + 512], np.uint8))
    return pk

def table(items, entry, nmin):
    """items {key: bytes}: a table of 2-entry buckets, grown until every key has a place"""
    n = nmin
    while True:
        while len(items) * 4 > (2 << n): n += 1
        t = bytearray((entry * 2) << n); used = {}
        for k, v in items.items():
            b = k & ((1 << n) - 1); w = used.get(b, 0)
            if w == 2 or k == 0: break
            o = b * entry * 2 + w * entry
            t[o:o + 8] = struct.pack('<Q', k); t[o + 8:o + 8 + len(v)] = bytes(v); used[b] = w + 1
        else:
            return n, bytes(t)
        n += 1

def write_pack(level1, blocks, sprites, border=None, nb=10, ns=4):
    """level1: the first $3800 bytes; blocks {key: 64 bytes}; sprites {key: 504 bytes}; border: 512 bytes"""
    nb, bt = table(blocks, 72, nb)
    ns, stb = table(sprites, 512, ns)
    boff = 0x3A40; soff = boff + len(bt); flen = soff + len(stb)
    h = bytearray(0x40)
    h[0:4] = b'LVL2'
    h[4:40] = struct.pack('<9I', 0, boff, nb, soff, ns, 0x3840 if border is not None else 0, flen, len(blocks), len(sprites))
    l1 = bytearray(level1[:SIZE1]); l1[8] = 2
    return bytes(l1) + bytes(h) + bytes(border if border is not None else bytes(512)) + bt + stb

# --------------------------------------------------------------------------- the frames
def read_l2f(path):
    d = open(path, 'rb').read(); o = 0; out = []
    while o + 32 <= len(d):
        magic, fno, w, h, line0, x0, _, _ = struct.unpack('<4s7I', d[o:o + 32]); o += 32
        assert magic == b'L2F1'
        n = w * h
        f = dict(fno=fno, w=w, h=h, line0=line0, x0=x0)
        f['idx'] = np.frombuffer(d[o:o + n], np.uint8).reshape(h, w); o += n
        f['tag'] = np.frombuffer(d[o:o + 2 * n], '<u2').reshape(h, w).astype(np.int32); o += 2 * n
        f['gfx'] = np.frombuffer(d[o:o + n], np.uint8).reshape(h, w); o += n
        f['cell'] = np.frombuffer(d[o:o + n], np.uint8).reshape(h, w); o += n
        f['code'] = np.frombuffer(d[o:o + n], np.uint8).reshape(h, w); o += n
        f['spr'] = np.frombuffer(d[o:o + 96 * h], np.uint8).reshape(h, 8, 12); o += 96 * h
        f['ram'] = d[o:o + 65536]; o += 65536
        out.append(f)
    return out

def write_l2f(path, frames):
    with open(path, 'wb') as fo:
        for f in frames:
            fo.write(struct.pack('<4s7I', b'L2F1', f['fno'], f['w'], f['h'], f['line0'], f['x0'], 0, 0))
            fo.write(f['idx'].astype(np.uint8).tobytes()); fo.write(f['tag'].astype('<u2').tobytes())
            fo.write(f['gfx'].astype(np.uint8).tobytes()); fo.write(f['cell'].astype(np.uint8).tobytes())
            fo.write(f['code'].astype(np.uint8).tobytes())
            fo.write(f['spr'].astype(np.uint8).tobytes()); fo.write(bytes(f['ram']))

# --------------------------------------------------------------------------- the keys of a frame
def frame_cells(f):
    """-> tile ids per pixel: cellmap[y][x] = (key, j*8+i) for pixels of whole cells; also the list of keys with their bytes"""
    h, w = f['cell'].shape
    cell = f['cell']; gfx = f['gfx'] & 15
    starts = []
    for y in range(h):
        row = cell[y]
        xs = np.nonzero((row != 0xFF) & ((row & 7) == 0))[0]
        j = (int(row[xs[0]]) >> 3) & 7 if len(xs) == 40 else -1
        ok = len(xs) == 40 and all(xs + 7 < w)
        starts.append((xs if ok else None, j))
    keymap = np.zeros((h, w), np.uint64); off = np.full((h, w), -1, np.int32); keys = {}
    y = 0
    while y + 8 <= h:
        if all(starts[y + j][0] is not None and starts[y + j][1] == j for j in range(8)):
            for c in range(40):
                px = np.stack([gfx[y + j, starts[y + j][0][c]:starts[y + j][0][c] + 8] for j in range(8)])
                kb = bytes(((px[:, 0::2] << 4) | px[:, 1::2]).astype(np.uint8).reshape(-1).tolist())
                k = key(kb); keys[k] = kb
                for j in range(8):
                    x = starts[y + j][0][c]
                    keymap[y + j, x:x + 8] = k; off[y + j, x:x + 8] = j * 8 + np.arange(8)
            y += 8
        else:
            y += 1
    return keymap, off, keys

def sprite_key(rec, ram):
    mc = (int(rec[0]) >> 3) & 1
    a = int(rec[8]) | (int(rec[9]) << 8)
    data = bytes([(ram[(a + i) & 0xFFFF]) for i in range(63)])
    pre = bytes([mc, int(rec[4]) & 15, (int(rec[5]) & 15) if mc else 0, (int(rec[6]) & 15) if mc else 0])
    return key(pre + data), pre, data

def frame_sprites(f):
    """-> per line, per sprite: None or (key, row, X, xexp, behind); and the keys met {key: (pre, data)}"""
    h = f['h']; cur = [None] * 8; lines = []; keys = {}
    for y in range(h):
        ln = []
        for n in range(8):
            r = f['spr'][y, n]
            if not (r[0] & 1): ln.append(None); continue
            if (r[0] & 16) or cur[n] is None:
                k, pre, data = sprite_key(r, f['ram']); cur[n] = k; keys[k] = (pre, data)
            ln.append((cur[n], int(r[1]), int(r[2]) | (int(r[3]) << 8), (r[0] >> 1) & 1, (r[0] >> 2) & 1))
        lines.append(ln)
    return lines, keys

# --------------------------------------------------------------------------- what each pixel shows
def level1_slot(pk, idx, kind, code, x, y):
    idx = idx.astype(np.int32); kind = kind.astype(np.int32); code = code.astype(np.int32)
    dx, dy = x - X0, y - Y0
    inwin = (dx >= 0) & (dx < 320) & (dy >= 0) & (dy < 200)
    cellno = np.where(inwin, (dy >> 3) * 40 + (dx >> 3), OUTSIDE)
    cc = pk['cellcls'][cellno]
    cls = np.minimum(np.where(cc != 0, cc, pk['charcls'][code]), 13).astype(np.int32)
    band = pk['band'][y & 511].astype(np.int32)
    group = np.where(kind == 1, 0xF0 | (code & 7), np.where(kind == 2, 0xE0 | band, (cls << 4) | band))
    return pk['remap'][(group << 4) | (idx & 15)]

def model(pk, f, palette=0, on=True):
    h, w = f['idx'].shape
    y, x = np.mgrid[0:h, 0:w]; y = y + f['line0']
    idx = f['idx'] & 15; kind = f['tag'] >> 8; code = f['tag'] & 255
    gcol = f['gfx'] & 15; fg = (f['gfx'] >> 4) & 1
    on = on and pk['l2']
    keymap, off, _ = frame_cells(f)
    slines, _ = frame_sprites(f)
    ccode = np.where(f['cell'] != 0xFF, f['code'], 0)        # (graphics outside a cell: code 0)
    under = level1_slot(pk, gcol, np.zeros_like(kind), ccode, x, y).astype(np.int32)
    if on:
        for k in np.unique(keymap):
            if k and int(k) in pk['blocks']:
                t = pk['blocks'][int(k)]
                msk = keymap == k
                tv = t[off[msk]]
                u = under[msk]; u[tv != 0] = tv[tv != 0]; under[msk] = u
    out = under.copy()
    spr_l1 = level1_slot(pk, idx, kind, code, x, y)
    for yy in range(h):
        ln = slines[yy]
        repl = [on and s is not None and s[0] in pk['sprites'] for s in ln]
        vs = kind[yy] == 1; m = code[yy] & 7
        m_repl = np.array(repl)[m] & vs
        # the VIC's sprite pixels of sprites with no art stay the VIC's
        keep = vs & ~m_repl
        out[yy][keep] = spr_l1[yy][keep]
        done = np.zeros(w, bool)
        for n in range(8):
            if not repl[n]: continue
            k, row, X, xe, behind = ln[n]
            fr = pk['sprites'][k]
            col = (np.arange(w) - (X + 8)) >> xe
            inb = (col >= 0) & (col < 24)
            fv = np.where(inb, fr[row * 24 + np.clip(col, 0, 23)], 0)
            ok = inb & (fv != 0) & ~done & ((behind == 0) | (fg[yy] == 0)) & (~vs | m_repl | (n < m))
            out[yy][ok] = fv[ok]; done |= ok
    bl = level1_slot(pk, idx, kind, code, x, y)
    bt = pk['border'][y & 511] if on else np.zeros_like(y)
    out = np.where(kind == 2, np.where(bt != 0, bt, bl), out)
    rgb = pk['pal'][palette & 7][out].astype(np.uint8)
    rgb[kind == 3] = 0
    return rgb

if __name__ == '__main__':
    pk = read_pack(open(sys.argv[1], 'rb').read())
    pal = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    on = (len(sys.argv) <= 5) or sys.argv[5] != '0'
    with open(sys.argv[3], 'wb') as fo:
        for f in read_l2f(sys.argv[2]):
            fo.write(model(pk, f, pal, on).tobytes())
