#!/usr/bin/env python3
# (C) 2026 Mong00se
# ODYSSEY - the source to PETSCII for the disk (OCTOCODE's upper/lower case set), as OCTOCODE's a2p.py does, plus the
# PETSCII graphics of the header's art: in the .asm they are the Unicode look-alikes below (in comments, so ACME on
# the PC ignores them); on the disk they are the C64's own characters.
#   petscii.py SOURCE.asm OUT.seq          petscii.py --png SOURCE.asm OUT.png  (the first lines as OCTOCODE shows them)
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
# Unicode -> the screen code in the C64's upper/lower case set (no reverse video: OCTOCODE shows none)
ART = {'─': 0x40, '┼': 0x5B, '│': 0x5D, '◥': 0x5F, '▌': 0x61, '▄': 0x62, '▔': 0x63, '▁': 0x64, '▏': 0x65, '▒': 0x66,
       '▕': 0x67, '◤': 0x69, '├': 0x6B, '▗': 0x6C, '└': 0x6D, '┐': 0x6E, '▂': 0x6F, '┌': 0x70, '┴': 0x71, '┬': 0x72,
       '┤': 0x73, '▎': 0x74, '▍': 0x75, '▀': 0x77, '▃': 0x79, '✓': 0x7A, '▖': 0x7B, '▝': 0x7C, '┘': 0x7D, '▘': 0x7E,
       '▚': 0x7F}
def s2p(sc):
    """the PETSCII byte OCTOCODE shows as screen code sc"""
    if sc < 0x20: return sc + 0x40
    if sc < 0x40: return sc
    if sc < 0x60: return sc + 0x20
    return sc + 0x40
def a2p(c):
    if c in ART: return s2p(ART[c])
    o = ord(c)
    if 'a' <= c <= 'z': return o - 0x20
    if 'A' <= c <= 'Z': return o + 0x80
    if 0x20 <= o <= 0x40: return o
    return {'[': 0x5B, ']': 0x5D, '\\': 0x5C, '^': 0x5E, '_': 0x5F, '{': 0xDB, '}': 0xDD, '|': 0xDC, '~': 0xDE, '`': 0x27, '\t': 0x20}.get(c, 0x3F)
def p2s(b):                                   # OCTOCODE's p2s
    if b < 0x20 or 0x80 <= b < 0xA0 or b == 0xFF: return 0x3F
    if b < 0x40: return b
    if b < 0x60: return b - 0x40
    if b < 0x80: return b - 0x20
    if b < 0xC0: return b - 0x40
    return b & 0x7F
def lines(path):
    s = open(path, encoding='utf-8').read().replace('\r\n', '\n')
    return s.split('\n')[:-1] if s.endswith('\n') else s.split('\n')
if __name__ == '__main__':
    if sys.argv[1] == '--png':
        from PIL import Image
        rom = open(os.path.join(HERE, 'chargen.bin'), 'rb').read() if os.path.exists(os.path.join(HERE, 'chargen.bin')) else \
              open('/home/claude/octophonic-backgrounds/emulator/src/vice/data/C64/chargen-901225-01.bin', 'rb').read()
        L = lines(sys.argv[2])[:int(sys.argv[4]) if len(sys.argv) > 4 else 24]
        img = Image.new('RGB', (40 * 8, len(L) * 8), (0, 0, 0x60))
        px = img.load()
        for r, l in enumerate(L):
            for c, ch in enumerate(l[:40]):
                sc = p2s(a2p(ch))
                for y in range(8):
                    bits = rom[0x800 + sc * 8 + y]
                    for x in range(8):
                        if bits >> (7 - x) & 1: px[c * 8 + x, r * 8 + y] = (0xa9, 0xff, 0x9f)
        img.resize((img.width * 3, img.height * 3), Image.NEAREST).save(sys.argv[3])
    else:
        out = bytearray()
        for l in lines(sys.argv[1]): out += bytes(a2p(c) for c in l) + b'\r'
        open(sys.argv[2], 'wb').write(out)
