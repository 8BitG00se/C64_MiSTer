# GRAFFITI WALL - the data for graffiti.asm (Python only prepares data; the demo itself is 6502).
#   gen.py OUT_DIR PHOTO [--check x.png] [--text-preview x.png]  ->  Graffiti Wall.reu, data.inc
# Layout (REU offset = VRAM offset for the parts the 6502 copies up in 64 KB runs):
#   $000000 letter tiles (256 colours)      $040000 shadow tiles (the same numbers: tile n of both is one pair)
#   $080000 the text layer's map, 256 x 32 tiles (empty; the 6502 fills columns in as the text scrolls)
#   $090000 sprite graphics: the wall, 6 x 4 blocks of 64 x 64, then the sprite table (7 x 5 sprites, priority 2)
# and REU only: R_TEXT (the text as map columns: 16 words a column, 32 bytes) and R_PAL (768 palette bytes).
import sys, os, math
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wall, font

NWALL = 190                  # palette 1..190: the wall
PL = NWALL                   # letter index i (1..34) -> palette PL + i
PS = PL + 2 * font.NG + 2    # shadow level k (1..8) -> palette PS + k
TEXT = "OCTOPHONIC 64 ... 8 SIDS ... OCTOVIC 256 ... SPRAYED ON NEAL'S WALL ... MONG00SE WOZ ERE ... "
LEAD = 40                    # blank columns before the text (and so after it, going round)
ROW0 = 14                    # the text's first map row (rows 14-29 of 32)

def main():
    out = sys.argv[1]; photo = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    # ---- the wall
    t, ang, pk = wall.tile(photo)
    t = np.clip(t.astype(float) * 0.9, 0, 255).astype(np.uint8)
    TWD, THT = t.shape[1], t.shape[0]
    assert TWD == 384 and THT == 256
    q = Image.fromarray(t).quantize(NWALL, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
    wp = np.array(q.getpalette()[:3 * NWALL], np.uint8).reshape(-1, 3)
    widx = np.array(q).astype(np.uint8) + 1                       # 1..190 (0 is see-through)
    if '--check' in sys.argv:
        pal_w = np.vstack([np.zeros((1, 3), np.uint8), wp])
        pic = pal_w[widx]
        Image.fromarray(np.tile(pic, (3, 3, 1))).save(sys.argv[sys.argv.index('--check') + 1])
    # ---- the letters
    G = font.glyphs()
    cells = []; seed = 1
    for ch in TEXT:
        L, S = font.draw_glyph(ch, G, 100 + ord(ch)); cells.append((L, S))
    Lb = np.concatenate([np.zeros((font.CELLH, LEAD * 8), np.uint8)] + [c[0] for c in cells], 1)
    Sb = np.concatenate([np.zeros((font.CELLH, LEAD * 8), np.uint8)] + [c[1] for c in cells], 1)
    T = Lb.shape[1] // 8
    NR = font.CELLH // 8
    pairs = {}; order = []
    colw = bytearray()
    for c in range(T):
        for r in range(NR):
            lt = Lb[r * 8:r * 8 + 8, c * 8:c * 8 + 8]; st = Sb[r * 8:r * 8 + 8, c * 8:c * 8 + 8]
            key = lt.tobytes() + st.tobytes()
            if not lt.any() and not st.any(): n = 0
            else:
                if key not in pairs: pairs[key] = len(pairs) + 1; order.append(key)
                n = pairs[key]
            colw += ((n & 1023) | ((n >> 10) << 12)).to_bytes(2, 'little')
    NT = len(pairs) + 1
    assert NT < 16384 and T < 2048
    ltiles = bytearray(64 * NT); stiles = bytearray(64 * NT)
    for key, n in pairs.items():
        lt = np.frombuffer(key[:64], np.uint8); st = np.frombuffer(key[64:], np.uint8)
        ltiles[n * 64:n * 64 + 64] = bytes(np.where(lt > 0, lt + PL, 0).astype(np.uint8))
        stiles[n * 64:n * 64 + 64] = bytes(np.where(st > 0, st + PS, 0).astype(np.uint8))
    if '--text-preview' in sys.argv:
        pal = np.zeros((256, 3), np.uint8)
        for i, c in font.palette().items(): pal[PL + i] = c
        bgp = np.tile(np.vstack([np.zeros((1, 3), np.uint8), wp])[widx], (1, Lb.shape[1] // 384 + 1, 1))[:font.CELLH, :Lb.shape[1]]
        img = np.clip(bgp.astype(float) - np.roll(np.roll(Sb, 7, 0), 7, 1)[..., None] * 9, 0, 255)
        m = Lb > 0; img[m] = pal[PL + Lb[m]]
        Image.fromarray(img.astype(np.uint8)).crop((LEAD * 8 - 8, 0, LEAD * 8 + 1500, font.CELLH)).save(sys.argv[sys.argv.index('--text-preview') + 1])
    # ---- the palette
    pal = np.zeros((256, 3), np.uint8)
    pal[1:NWALL + 1] = wp
    for i, c in font.palette().items(): pal[PL + i] = c
    for k in range(1, 9): pal[PS + k] = (k * 9, k * 9, k * 9)       # taken away from the wall (see-through mode 3)
    # ---- the wall as sprite graphics: 64 x 64 blocks, 6 across, 4 down
    V_LT, V_ST, V_MAP, V_SPR = 0x000000, 0x040000, 0x080000, 0x090000
    assert 64 * NT <= 0x40000
    gfx = bytearray(24 * 4096)
    for jb in range(4):
        for ib in range(6):
            blk = widx[jb * 64:jb * 64 + 64, ib * 64:ib * 64 + 64]
            gfx[(jb * 6 + ib) * 4096:(jb * 6 + ib + 1) * 4096] = blk.tobytes()
    V_SAT = V_SPR + 0x18000
    sat = bytearray()
    for j in range(5):
        for k in range(7):
            x = -32 + 64 * k; y = -35 + 64 * j
            g = ((j % 4) * 6 + (k % 6)) * 128
            sat += bytes([x & 255, (x >> 8) & 255, y & 255, (y >> 8) & 255, g & 255, g >> 8, 0xCF, 0x20])
    NSPR = 35
    R_TEXT = 0x0B0000; R_PAL = 0x0C0000
    reu = bytearray(R_PAL + 0x1000)
    reu[V_LT:V_LT + len(ltiles)] = ltiles
    reu[V_ST:V_ST + len(stiles)] = stiles
    reu[V_SPR:V_SPR + len(gfx)] = gfx; reu[V_SAT:V_SAT + len(sat)] = sat
    reu[R_TEXT:R_TEXT + len(colw)] = colw
    reu[R_PAL:R_PAL + 768] = bytes(pal[:, 0]) + bytes(pal[:, 1]) + bytes(pal[:, 2])
    open(os.path.join(out, 'Graffiti Wall.reu'), 'wb').write(reu)
    bob = [12 + int(round(3 * math.sin(2 * math.pi * i / 128))) for i in range(128)]
    inc = ['; made by gen.py - do not edit',
           'V_LT = $%06x' % V_LT, 'LEN_LT = $%06x' % (64 * NT), 'V_ST = $%06x' % V_ST, 'LEN_ST = $%06x' % (64 * NT),
           'V_MAP = $%06x' % V_MAP, 'LEN_MAP = $%06x' % 0x4000,
           'V_SPR = $%06x' % V_SPR, 'V_SAT = $%06x' % V_SAT, 'LEN_SPR = $%06x' % (0x18000 + len(sat)), 'NSPR = %d' % NSPR,
           'R_TEXT = $%06x' % R_TEXT, 'NCOL = %d' % T, 'ROW0 = %d' % ROW0, 'R_PAL = $%06x' % R_PAL,
           'bobtab', '  !byte ' + ','.join(str(b) for b in bob)]
    open(os.path.join(out, 'data.inc'), 'w').write('\n'.join(inc) + '\n')
    print('wall angle %.2f, bed joints %s; text %d columns (%d px), %d unique tile pairs; REU %d bytes; sprites %d' % (ang, list(pk), T, T * 8, NT, len(reu), NSPR))

main()
