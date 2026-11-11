#!/usr/bin/env python3
# C64RGB 256 - the recolour pack tool (Fix 60)                       (c) 2026 Mong00se
#
# Makes a recolour pack (.rgb) for an old 16-colour C64 game from a short, readable description
# (.txt), and shows what it will look like before it goes on the card. The pack format and the
# description are in docs/RGB256.md. Quick start (a few minutes a game):
#
#   1. grab some frames of the game (the Octophonic emulator runs it and keeps what the VIC drew):
#        python3 rgb256.py grab mygame.crt --frames 3000,4500 --joy "4000:16,4030:0" --out mygame
#      -> mygame.tags (the frames, for the tool) and mygame_<frame>.png (with a grid: raster lines,
#         the 40x25 screen cells, sprite numbers) to read the numbers off.
#      (No emulator? Any 384x272 / 396x284 / 320x200 screenshot in the stock palette works too:
#         python3 rgb256.py grab shot1.png shot2.png --out mygame   - sprites and chars then unknown.)
#   2. a starting description with three palettes, made from the colours the game uses:
#        python3 rgb256.py starter mygame.tags > mygame.txt
#   3. edit mygame.txt (colours, gradients over line ranges, areas, chars, sprites), then
#        python3 rgb256.py preview mygame.txt mygame.tags     -> mygame_preview.png (before | each palette)
#        python3 rgb256.py make mygame.txt                    -> mygame.rgb (put it beside the game)
#
# The colour a pixel gets depends only on what the core knows while drawing it: its C64 colour,
# the raster line, the screen cell, the char code, or the sprite - so the pack never moves a pixel.

import os, re, sys, struct, subprocess, tempfile
import numpy as np

# the core's palette (Colodore, the OSD's default) - "same" in a description means this colour
STOCK = [0x000000, 0xFFFFFF, 0x813338, 0x75CEC8, 0x8E3C97, 0x56AC4D, 0x2E2C9B, 0xEDF171,
         0x8E5029, 0x553800, 0xC46C71, 0x4A4A4A, 0x7B7B7B, 0xA9FF9F, 0x706DEB, 0xB2B2B2]
NAMES = ['black', 'white', 'red', 'cyan', 'purple', 'green', 'blue', 'yellow', 'orange', 'brown',
         'lightred', 'darkgrey', 'grey', 'lightgreen', 'lightblue', 'lightgrey']
ALIAS = {'pink': 10, 'darkgray': 11, 'gray': 12, 'midgrey': 12, 'midgray': 12, 'lightgray': 15,
         'violet': 4, 'lightred': 10, 'grey1': 11, 'grey2': 12, 'grey3': 15}

SIZE = 0x3800
X0, Y0 = 32, 51                    # the window's first pixel (raster X as tagged) and first line
OUTSIDE = 1000                     # the cell table's entry for outside the 40x25 window

# --------------------------------------------------------------------------- the pack file
def pack_bytes(npal, names, band, charcls, cellcls, remap, pals, title=''):
    b = bytearray(SIZE)
    b[0:8] = b'RGB256PK'
    b[8] = 1
    b[9] = npal
    for i, n in enumerate(names[:8]):
        e = n.encode('ascii', 'replace')[:15]
        b[0x10 + i * 16:0x10 + i * 16 + len(e)] = e
    t = title.encode('ascii', 'replace')[:31]
    b[0x90:0x90 + len(t)] = t
    c = b'(c) 2026 Mong00se - C64RGB 256'
    b[0xC0:0xC0 + len(c)] = c
    b[0x100:0x300] = bytes(band)
    b[0x300:0x400] = bytes(charcls)
    b[0x400:0x800] = bytes(cellcls)
    b[0x800:0x1800] = bytes(remap)
    for p in range(8):
        for s in range(256):
            r, g, bl = pals[p][s] if p < len(pals) else pals[0][s]
            o = 0x1800 + (p * 256 + s) * 4
            b[o:o + 4] = bytes((r, g, bl, 0))
    return bytes(b)

def read_pack(data):
    assert data[:8] == b'RGB256PK' and len(data) == SIZE, 'not a C64RGB 256 pack'
    a = np.frombuffer(data, np.uint8)
    return dict(npal=data[9], band=a[0x100:0x300] & 15, charcls=a[0x300:0x400] & 15,
                cellcls=a[0x400:0x800] & 15, remap=a[0x800:0x1800],
                pal=a[0x1800:0x3800].reshape(8, 256, 4)[:, :, :3])

# --------------------------------------------------------------------------- the model
# exactly what rtl/rgb256.sv does (sim/rgb256 checks the RTL against this, pixel for pixel)
def recolour(pk, idx, tag, x, y, palette):
    """idx: colour indices, tag: (kind << 8) | code, x/y: raster X and line of each pixel."""
    kind = tag >> 8
    code = tag & 255
    dx, dy = x - X0, y - Y0
    inwin = (dx >= 0) & (dx < 320) & (dy >= 0) & (dy < 200)
    cell = np.where(inwin, (dy >> 3) * 40 + (dx >> 3), OUTSIDE)
    cc = pk['cellcls'][cell]
    cls = np.where(cc != 0, cc, pk['charcls'][code])
    cls = np.minimum(cls, 13)
    band = pk['band'][y & 511]
    group = np.where(kind == 1, 0xF0 | (code & 7), np.where(kind == 2, 0xE0 | band, (cls << 4) | band))
    slot = pk['remap'][(group << 4) | (idx & 15)]
    rgb = pk['pal'][palette & 7][slot].astype(np.uint8)
    rgb[kind == 3] = 0
    return rgb

def stock(idx):
    p = np.array([[(c >> 16) & 255, (c >> 8) & 255, c & 255] for c in STOCK], np.uint8)
    return p[idx & 15]

# --------------------------------------------------------------------------- frames
W, H, LINE0 = 396, 284, 16         # the emulator's picture: raster X 0-395, lines 16-299

def read_tags(path):
    d = open(path, 'rb').read()
    out = []
    o = 0
    while o + 16 <= len(d):
        fno, w, h, _ = struct.unpack('<4I', d[o:o + 16]); o += 16
        idx = np.frombuffer(d[o:o + w * h], np.uint8).reshape(h, w); o += w * h
        tag = np.frombuffer(d[o:o + 2 * w * h], '<u2').reshape(h, w).astype(np.int32); o += 2 * w * h
        out.append((fno, idx, tag))
    return out

def write_tags(path, frames):
    with open(path, 'wb') as f:
        for fno, idx, tag in frames:
            h, w = idx.shape
            f.write(struct.pack('<4I', fno, w, h, X0))
            f.write(idx.astype(np.uint8).tobytes())
            f.write(tag.astype('<u2').tobytes())

def coords(h, w):
    y, x = np.mgrid[0:h, 0:w]
    return x, y + LINE0

def frame_from_png(path):
    """a screenshot in the stock palette (or close to it): colour indices; tags unknown (graphics,
    char 0), the border found as the colour all round the 40x25 window."""
    from PIL import Image
    im = np.asarray(Image.open(path).convert('RGB')).astype(int)
    p = np.array([[(c >> 16) & 255, (c >> 8) & 255, c & 255] for c in STOCK])
    # other emulators' palettes: nearest colour
    dist = ((im[:, :, None, :] - p[None, None, :, :]) ** 2).sum(-1)
    idx = dist.argmin(-1).astype(np.uint8)
    h, w = idx.shape
    full = np.zeros((H, W), np.uint8)
    if (w, h) == (320, 200):
        full[Y0 - LINE0:Y0 - LINE0 + 200, X0:X0 + 320] = idx
    else:            # 384x272 (VICE-style) or 396x284: centre on the window
        ox, oy = X0 + 160 - w // 2, (Y0 - LINE0) + 100 - h // 2
        full[max(oy, 0):max(oy, 0) + min(h, H), max(ox, 0):max(ox, 0) + min(w, W)] = idx[:H, :W]
    tag = np.zeros((H, W), np.int32)
    x, y = coords(H, W)
    win = (x >= X0) & (x < X0 + 320) & (y >= Y0) & (y < Y0 + 200)
    tag[~win] = 0x200
    return full, tag

# --------------------------------------------------------------------------- the description
def colour_index(word):
    w = word.strip().lower().replace(' ', '').replace('_', '')
    if w.isdigit() and int(w) < 16: return int(w)
    if w in NAMES: return NAMES.index(w)
    if w in ALIAS: return ALIAS[w]
    raise ValueError(f'unknown C64 colour "{word}" (names: {", ".join(NAMES)} or 0-15)')

def parse_rgb(s, ci):
    s = s.strip().lower()
    if s in ('same', 'stock', 'keep'): c = STOCK[ci]; return ((c >> 16) & 255, (c >> 8) & 255, c & 255)
    m = re.fullmatch(r'#?([0-9a-f]{6})', s)
    if m: v = int(m.group(1), 16); return ((v >> 16) & 255, (v >> 8) & 255, v & 255)
    m = re.fullmatch(r'(\d+)\s*[, ]\s*(\d+)\s*[, ]\s*(\d+)', s)
    if m: return tuple(min(255, int(g)) for g in m.groups())
    try:
        c = STOCK[colour_index(s)]; return ((c >> 16) & 255, (c >> 8) & 255, c & 255)
    except ValueError:
        pass
    raise ValueError(f'not a colour: "{s}" (#rrggbb, r,g,b, a C64 colour name, or same)')

def rng(s, lo, hi):
    out = set()
    for part in s.split(','):
        part = part.strip()
        if not part: continue
        if '-' in part:
            a, b = part.split('-', 1); a, b = int(a, 0), int(b, 0)
        else:
            a = b = int(part, 0)
        if a > b: a, b = b, a
        if a < lo or b > hi: raise ValueError(f'{part}: outside {lo}-{hi}')
        out.update(range(a, b + 1))
    return out

class Section:
    def __init__(self, head, lineno):
        self.head, self.lineno = head, lineno
        self.lines = None          # set of raster lines, or None (any)
        self.cells = None          # set of cells (area), or None
        self.chars = None          # set of char codes, or None
        self.sprites = None        # set of sprite numbers
        self.border = False
        self.everywhere = False
        self.rules = []            # (colour index, [per palette: (rgb_a, rgb_b or None)])
        h = head.lower()
        if h.strip() == 'everywhere': self.everywhere = True; return
        m = re.search(r'lines\s+([\d,\s-]+)', h)
        if m: self.lines = rng(m.group(1), 0, 311)
        m = re.search(r'area\s+cols\s+([\d,\s-]+?)\s+rows\s+([\d,\s-]+)', h)
        if m:
            cs, rs = rng(m.group(1), 0, 39), rng(m.group(2), 0, 24)
            self.cells = {r * 40 + c for r in rs for c in cs}
        elif 'outside' in h:
            self.cells = {OUTSIDE}
        m = re.search(r'chars\s+([\d,\s-]+)', h)
        if m: self.chars = rng(m.group(1), 0, 255)
        m = re.search(r'sprites?\s+([\d,\s-]+)', h)
        if m: self.sprites = rng(m.group(1), 0, 7)
        if re.search(r'\bborder\b', h): self.border = True
        if self.cells is not None and self.chars is not None:
            raise ValueError(f'line {lineno}: [{head}] - a section is an area OR chars, not both')
        if not (self.lines or self.cells or self.chars or self.sprites or self.border):
            raise ValueError(f'line {lineno}: [{head}] - what does it apply to? (everywhere, lines, area, chars, sprite, border)')

def parse(text):
    meta = {'name': '', 'palettes': ['Palette 1']}
    secs = []
    cur = None
    for n, raw in enumerate(text.splitlines(), 1):
        # comments: a line starting with #, or " # ..." after a rule (#rrggbb colours have no space after the #)
        line = '' if raw.lstrip().startswith('#') else re.sub(r'\s#(\s.*)?$', '', raw).strip()
        if not line: continue
        if line.startswith('['):
            cur = Section(line.strip('[] '), n); secs.append(cur); continue
        if ':' in line and cur is None:
            k, v = line.split(':', 1)
            k = k.strip().lower()
            if k == 'palettes': meta['palettes'] = [p.strip() for p in v.split(',') if p.strip()][:8]
            else: meta[k] = v.strip()
            continue
        if '=' not in line:
            raise ValueError(f'line {n}: "{raw.strip()}" - expected colour = value')
        if cur is None: cur = Section('everywhere', n); secs.append(cur)
        k, v = line.split('=', 1)
        cols = [colour_index(c) for c in re.split(r'[,/]', k) if c.strip()]
        per = [p.strip() for p in v.split('|')]
        for ci in cols:
            vals = []
            for p in per:
                if '..' in p:
                    a, b = p.split('..', 1); vals.append((parse_rgb(a, ci), parse_rgb(b, ci)))
                else:
                    vals.append((parse_rgb(p, ci), None))
            cur.rules.append((ci, vals))
    return meta, secs

def compile_pack(text):
    meta, secs = parse(text)
    npal = len(meta['palettes'])
    # --- classes: each area or chars section is a class (1-13)
    cellcls = [0] * 1024
    charcls = [0] * 256
    clsof = {}
    for s in secs:
        key = ('cells', frozenset(s.cells)) if s.cells is not None else ('chars', frozenset(s.chars)) if s.chars is not None else None
        if key is None or key in clsof: continue
        if len(clsof) >= 13: raise ValueError(f'line {s.lineno}: more than 13 different areas/char sets')
        c = len(clsof) + 1
        clsof[key] = c
        for i in key[1]:
            if key[0] == 'cells': cellcls[i] = c
            else: charcls[i] = c
    # --- bands: 16 at most, cut where line ranges start and end; gradients get the spare ones
    cuts = {0, 312}
    grads = []
    for s in secs:
        if s.lines:
            lo, hi = min(s.lines), max(s.lines)
            cuts.update((lo, hi + 1))
            if any(v[1] is not None for _, vals in s.rules for v in vals): grads.append((lo, hi + 1))
        elif any(v[1] is not None for _, vals in s.rules for v in vals):
            cuts.update((Y0, Y0 + 200)); grads.append((Y0, Y0 + 200))
    cuts = sorted(cuts)
    segs = list(zip(cuts[:-1], cuts[1:]))
    if len(segs) > 16: raise ValueError(f'{len(segs)} different line ranges - 16 at most (fewer [lines] cuts)')
    ingrad = [any(g0 <= a and b <= g1 for g0, g1 in grads) for a, b in segs]
    spare = 16 - len(segs)
    glen = sum(b - a for (a, b), g in zip(segs, ingrad) if g)
    pieces = []
    for (a, b), g in zip(segs, ingrad):
        k = 1
        if g and glen: k = 1 + int(spare * (b - a) / glen)
        k = max(1, min(k, b - a))
        for j in range(k): pieces.append((a + (b - a) * j // k, a + (b - a) * (j + 1) // k))
    while len(pieces) > 16:                       # rounding: merge the two shortest neighbours in a gradient
        i = min(range(len(pieces) - 1), key=lambda i: pieces[i + 1][1] - pieces[i][0])
        pieces[i:i + 2] = [(pieces[i][0], pieces[i + 1][1])]
    band = [0] * 512
    for bi, (a, b) in enumerate(pieces):
        for l in range(a, b): band[l] = bi
    # --- each group and colour: its colour in each palette (later sections win)
    def value(vals, p, s, b):
        v = vals[p] if p < len(vals) else vals[-1]
        if v[1] is None: return v[0]
        lo, hi = (min(s.lines), max(s.lines)) if s.lines else (Y0, Y0 + 199)
        a, z = pieces[b]
        t = 0.0 if hi == lo else min(1.0, max(0.0, ((a + z - 1) / 2 - lo) / (hi - lo)))
        return tuple(int(round(v[0][i] + (v[1][i] - v[0][i]) * t)) for i in range(3))
    def applies(s, kind, cls, b, spr):
        a, z = pieces[b] if b is not None else (0, 0)
        if s.lines is not None and kind != 1 and not any(l in s.lines for l in range(a, z)): return False
        if s.everywhere: return True
        if kind == 1: return s.sprites is not None and spr in s.sprites
        if kind == 2:
            return s.border or (s.lines is not None and s.cells is None and s.chars is None and s.sprites is None)
        if s.sprites is not None or s.border and s.cells is None and s.chars is None: return False
        if s.cells is not None or s.chars is not None:
            key = ('cells', frozenset(s.cells)) if s.cells is not None else ('chars', frozenset(s.chars))
            return clsof[key] == cls
        return s.lines is not None
    table = {}
    for g in range(256):
        if g >= 0xF8: kind, cls, b, spr = 1, 0, None, g & 7
        elif g >= 0xF0: kind, cls, b, spr = 1, 0, None, g & 7
        elif g >= 0xE0: kind, cls, b, spr = 2, 0, g & 15, 0
        else: kind, cls, b, spr = 0, g >> 4, g & 15, 0
        if b is not None and b >= len(pieces): b = len(pieces) - 1
        for ci in range(16):
            c = STOCK[ci]
            col = [((c >> 16) & 255, (c >> 8) & 255, c & 255)] * npal
            for s in secs:
                if not applies(s, kind, cls, b, spr): continue
                for rci, vals in s.rules:
                    if rci == ci: col = [value(vals, p, s, b) for p in range(npal)]
            table[(g, ci)] = tuple(col)
    # --- slots: the different colours (a colour = its look in every palette); 256 at most
    uniq = sorted(set(table.values()))
    shift = 0
    while len(uniq) > 256:                        # too many: round them until they fit
        shift += 1
        rnd = lambda t: tuple(tuple(min(255, (x >> shift << shift) + (1 << shift >> 1)) for x in rgb) for rgb in t)
        table = {k: rnd(v) for k, v in table.items()}
        uniq = sorted(set(table.values()))
    slot = {v: i for i, v in enumerate(uniq)}
    remap = [slot[table[(g, ci)]] for g in range(256) for ci in range(16)]
    pals = [[uniq[s][p] if s < len(uniq) else (0, 0, 0) for s in range(256)] for p in range(npal)]
    data = pack_bytes(npal, meta['palettes'], band, charcls, cellcls, remap, pals, meta.get('name', ''))
    info = dict(slots=len(uniq), bands=len(pieces), classes=len(clsof), rounded=shift, palettes=meta['palettes'])
    return data, info

# --------------------------------------------------------------------------- pictures
def font():
    # a tiny 3x5 font for the grid's numbers
    F = {'0': '111101101101111', '1': '010110010010111', '2': '111001111100111', '3': '111001111001111',
         '4': '101101111001001', '5': '111100111001111', '6': '111100111101111', '7': '111001001001001',
         '8': '111101111101111', '9': '111101111001111', 'S': '111100111001111', '-': '000000111000000'}
    return F

def text(img, s, x, y, col):
    F = font()
    for i, ch in enumerate(s):
        g = F.get(ch)
        if not g: continue
        for k, bit in enumerate(g):
            if bit == '1':
                yy, xx = y + k // 3, x + i * 4 + k % 3
                if 0 <= yy < img.shape[0] and 0 <= xx < img.shape[1]: img[yy, xx] = col

def grid_png(idx, tag, path, scale=3):
    from PIL import Image
    h, w = idx.shape
    pic = np.repeat(np.repeat(stock(idx), scale, 0), scale, 1).copy()
    x, y = coords(h, w)
    for r in range(26):                       # the cells: rows 0-24, columns 0-39 of the window
        yy = (Y0 - LINE0 + r * 8) * scale
        if 0 <= yy < pic.shape[0]: pic[yy, X0 * scale:(X0 + 320) * scale] //= 2
    for c in range(41):
        xx = (X0 + c * 8) * scale
        pic[(Y0 - LINE0) * scale:(Y0 - LINE0 + 200) * scale, min(xx, pic.shape[1] - 1)] //= 2
    for r in range(25):
        text(pic, str(r), 2, (Y0 - LINE0 + r * 8) * scale + 2, (255, 255, 0))
    for c in range(0, 40, 2):
        text(pic, str(c), (X0 + c * 8) * scale + 2, (Y0 - LINE0) * scale - 8, (255, 255, 0))
    for l in range(LINE0, LINE0 + h, 10):     # raster lines down the right
        yy = (l - LINE0) * scale
        pic[yy, -12 * scale:-1] = (255, 255, 255)
        text(pic, str(l), pic.shape[1] - 12 * scale - 14, yy + 1, (255, 255, 255))
    kind = tag >> 8
    for s in range(8):                        # each sprite: a box and its number
        m = (kind == 1) & ((tag & 7) == s)
        if not m.any(): continue
        ys, xs = np.where(m)
        x0, x1, y0, y1 = xs.min() * scale, xs.max() * scale + scale - 1, ys.min() * scale, ys.max() * scale + scale - 1
        pic[y0, x0:x1] = pic[y1, x0:x1] = (255, 0, 255)
        pic[y0:y1, x0] = pic[y0:y1, x1] = (255, 0, 255)
        text(pic, 'S' + str(s), x0, max(0, y0 - 7), (255, 0, 255))
    Image.fromarray(pic).save(path)

def preview(pk, frames, path, names, scale=2):
    from PIL import Image
    rows = []
    for fno, idx, tag in frames:
        h, w = idx.shape
        x, y = coords(h, w)
        tiles = [stock(idx)] + [recolour(pk, idx, tag, x, y, p) for p in range(max(1, pk['npal']))]
        rows.append(np.concatenate([np.pad(t, ((4, 4), (4, 4), (0, 0)), constant_values=20) for t in tiles], 1))
    pic = np.concatenate(rows, 0)
    Image.fromarray(np.repeat(np.repeat(pic, scale, 0), scale, 1)).save(path)

# --------------------------------------------------------------------------- the starter
def hexc(c): return '#%02x%02x%02x' % tuple(int(max(0, min(255, v))) for v in c)

def tone(rgb, sat=1.0, bright=1.0, warm=0.0):
    r, g, b = [v / 255 for v in rgb]
    m = (r + g + b) / 3
    r, g, b = [m + (v - m) * sat for v in (r, g, b)]
    r, g, b = r * bright, g * bright, b * bright
    r, b = r + warm * 0.08, b - warm * 0.08
    return [v * 255 for v in (r, g, b)]

def starter(frames, title):
    """a first description from the frames: three palettes for every colour the game uses, the
    window's most used colours as gradients down the screen, sprites a little brighter."""
    used = np.zeros(16, int)
    sprused = {}
    bgcount = np.zeros(16, int)
    for fno, idx, tag in frames:
        kind = tag >> 8
        used += np.bincount(idx.ravel(), minlength=16)
        bgcount += np.bincount(idx[kind == 0].ravel(), minlength=16)
        for s in range(8):
            m = (kind == 1) & ((tag & 7) == s)
            if m.any(): sprused[s] = sorted(set(np.unique(idx[m]).tolist()))
    present = [i for i in range(16) if used[i]]
    top = [i for i in np.argsort(-bgcount) if bgcount[i] and i != 0][:3]
    rgb = lambda i: ((STOCK[i] >> 16) & 255, (STOCK[i] >> 8) & 255, STOCK[i] & 255)
    L = []
    L.append(f'name: {title}')
    L.append('palettes: Rich, Warm, Night')
    L.append('')
    L.append('# Each line: C64 colour = Rich | Warm | Night   (#rrggbb, r,g,b, a C64 colour name, or same)')
    L.append('# A gradient: #top .. #bottom  (over the section\'s lines; the whole screen if none given)')
    L.append('# Sections: [everywhere] [lines 51-130] [area cols 0-39 rows 0-2] [chars 64-127] [sprite 0] [border]')
    L.append('# Later sections win. Lines: 51 is the top of the 25-row screen, 250 its bottom (the grab\'s grid).')
    L.append('')
    L.append('[everywhere]')
    for i in present:
        c = rgb(i)
        if i == 0: L.append(f'{NAMES[i]:10} = same'); continue          # black stays black (the screen's edge)
        L.append(f'{NAMES[i]:10} = {hexc(tone(c, 1.35, 1.05))} | {hexc(tone(c, 1.15, 1.0, 1.0))} | {hexc(tone(c, 0.7, 0.55, -1.0))}')
    if top:
        L.append('')
        L.append('# the screen\'s main colours, darker towards the bottom (depth)')
        L.append('[lines 51-250]')
        for i in top:
            c = rgb(i)
            L.append(f'{NAMES[i]:10} = {hexc(tone(c, 1.4, 1.15))} .. {hexc(tone(c, 1.3, 0.75))} | '
                     f'{hexc(tone(c, 1.2, 1.1, 1.5))} .. {hexc(tone(c, 1.1, 0.7, 1.0))} | '
                     f'{hexc(tone(c, 0.8, 0.7, -1.5))} .. {hexc(tone(c, 0.6, 0.35, -1.5))}')
    for s, cols in sorted(sprused.items()):
        L.append('')
        L.append(f'[sprite {s}]')
        for i in cols:
            if i == 0: continue
            c = rgb(i)
            L.append(f'{NAMES[i]:10} = {hexc(tone(c, 1.4, 1.15))} | {hexc(tone(c, 1.2, 1.1, 0.5))} | {hexc(tone(c, 1.0, 0.9, -0.5))}')
    L.append('')
    L.append('# the border: keep it as the game has it (or give it colours / a gradient here)')
    L.append('[border]')
    L.append('black      = same')
    return '\n'.join(L) + '\n'

# --------------------------------------------------------------------------- grab
def find_emulator():
    for p in (os.environ.get('OCTO_EMU', ''), os.path.join(os.path.dirname(__file__), 'x64sc'), 'x64sc'):
        if p and (os.path.isfile(p) or p == 'x64sc'): return p
    return 'x64sc'

def grab(args):
    """grab GAME --frames a,b,c [--joy "frame:value,..."] [--keys ...] [--out NAME] [--emu PATH] [--config vicerc]
       or grab shot1.png shot2.png --out NAME"""
    out = opt(args, '--out', 'game')
    files = [a for a in args if not a.startswith('--') and a not in opts_values(args)]
    pngs = [f for f in files if f.lower().endswith('.png')]
    if pngs:
        frames = []
        for i, f in enumerate(pngs):
            idx, tag = frame_from_png(f)
            frames.append((i, idx, tag))
        write_tags(out + '.tags', frames)
    else:
        game = files[0]
        fr = [int(f) for f in opt(args, '--frames', '3000').split(',')]
        last = max(fr) + 2
        env = dict(os.environ, OCTO_TAGDUMP=out + '.tags', OCTO_TAGFRAMES=','.join(map(str, fr)))
        if opt(args, '--joy', ''): env['OCTO_JOY'] = opt(args, '--joy', '')
        if opt(args, '--keys', ''): env['OCTO_KEYS'] = opt(args, '--keys', '')
        cmd = [opt(args, '--emu', find_emulator())]
        if opt(args, '--config', ''): cmd += ['-config', opt(args, '--config', '')]
        cmd += ['-sounddev', 'dummy', '-warp', '-limitcycles', str(last * 19656)]
        ext = game.lower().rsplit('.', 1)[-1]
        cmd += ['-cartcrt', game] if ext == 'crt' else ['-autostart', game]
        print('running:', ' '.join(cmd))
        subprocess.run(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        frames = read_tags(out + '.tags')
    for fno, idx, tag in frames:
        grid_png(idx, tag, f'{out}_{fno:05d}.png')
        print(f'{out}_{fno:05d}.png')
    print(f'{out}.tags: {len(frames)} frames')

def opt(args, name, default):
    return args[args.index(name) + 1] if name in args else default

def opts_values(args):
    return {args[i + 1] for i, a in enumerate(args) if a.startswith('--') and i + 1 < len(args)}

# --------------------------------------------------------------------------- main
def main(argv):
    if len(argv) < 2 or argv[1] in ('-h', '--help', 'help'):
        print(__doc__ or open(__file__).read().split('\nimport')[0]); return 0
    cmd, args = argv[1], argv[2:]
    if cmd == 'make':
        src = args[0]
        out = opt(args, '-o', os.path.splitext(src)[0] + '.rgb')
        data, info = compile_pack(open(src).read())
        open(out, 'wb').write(data)
        print(f'{out}: {info["slots"]} colours of 256, {info["bands"]} line bands, {info["classes"]} areas/char sets, '
              f'palettes: {", ".join(info["palettes"])}' + (f' (colours rounded by {info["rounded"]} bits to fit)' if info['rounded'] else ''))
    elif cmd == 'preview':
        src, tags = args[0], args[1]
        out = opt(args, '-o', os.path.splitext(src)[0] + '_preview.png')
        data = open(src, 'rb').read() if src.lower().endswith('.rgb') else compile_pack(open(src).read())[0]
        pk = read_pack(data)
        preview(pk, read_tags(tags), out, [])
        print(out)
    elif cmd == 'starter':
        frames = read_tags(args[0])
        sys.stdout.write(starter(frames, opt(args, '--name', os.path.splitext(os.path.basename(args[0]))[0])))
    elif cmd == 'grab':
        grab(args)
    else:
        print('commands: grab, starter, make, preview (see the top of this file)'); return 1
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
