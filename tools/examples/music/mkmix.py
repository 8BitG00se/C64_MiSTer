#!/usr/bin/env python3
"""Crystal Harbour on all eight SIDs: patch the SIDWeaver tune's SID stores.

usage: mkmix.py harbour.bin OUT.bin OUT-stubs.inc
Every store to a SID 1 register ($D400-$D418) in the tune's player is replaced by a JSR to a
small stub (assembled into player_mix.asm at $C000 + n*$20) that does the same store, then
copies it to SIDs 5-8 and keeps the equaliser's events. The stub order below must be the one in
the .inc this script writes. The tune's own code is not changed in any other way.
"""
import sys
src, outbin, outinc = sys.argv[1:4]
d = bytearray(open(src, 'rb').read())
LOAD = 0x1000
# (address, kind, register offset): kind y = STA $D4kk,Y  a = STA $D4kk
# (the two STA $D418 at $1094 and $10A6 are the tune's sample player in its NMI: far too hot to touch)
sites = [(0x11e3, 'y', 5), (0x11e6, 'y', 6), (0x11eb, 'y', 4), (0x12e8, 'y', 5), (0x12ee, 'y', 6),
         (0x1404, 'y', 0), (0x1409, 'y', 1), (0x1414, 'y', 0), (0x141b, 'y', 1), (0x1420, 'y', 2),
         (0x1425, 'y', 3), (0x144e, 'y', 4),
         (0x1598, 'a', 0x16), (0x159d, 'a', 0x15), (0x15a4, 'a', 0x17)]
inc = []
for n, (a, kind, k) in enumerate(sites):
    o = a - LOAD
    want = (0x99 if kind == 'y' else 0x8d, k, 0xd4)
    if tuple(d[o:o + 3]) != want:
        sys.exit('mkmix: %04x is not the store it should be: %s' % (a, d[o:o + 3].hex()))
    stub = 0xc000 + n * 0x20
    d[o:o + 3] = bytes((0x20, stub & 255, stub >> 8))      # JSR stub
    inc.append('        * = $%04x\n        +stub%s $%02x' % (stub, kind, k))
open(outbin, 'wb').write(d)
open(outinc, 'w').write('\n'.join(inc) + '\n')
