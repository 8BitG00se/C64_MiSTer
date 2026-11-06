#!/usr/bin/env python3
"""ftab.inc: the frequency table the player and the editor use. Index i is note i-12 (clamped to 1..96), so voice offsets
of -12 .. +36 semitones never leave the table.  PAL clock."""
import sys
CLOCK = 985248.0
def reg(n):
    n = max(1, min(96, n))
    f = 440.0 * 2 ** ((n + 11 - 69) / 12.0)
    return min(65535, int(round(f * 16777216.0 / CLOCK)))
def make(path):
    ft = [reg(i - 12) for i in range(0, 12 + 96 + 37)]
    with open(path, 'w') as o:
        o.write('; made by mktab.py - note frequency table (PAL), index = note + 12\n')
        o.write('ftlo\n' + '\n'.join('        !byte ' + ', '.join(str(v & 255) for v in ft[i:i + 16]) for i in range(0, len(ft), 16)) + '\n')
        o.write('fthi\n' + '\n'.join('        !byte ' + ', '.join(str(v >> 8) for v in ft[i:i + 16]) for i in range(0, len(ft), 16)) + '\n')

def eqtab(path):
    """eqtab.inc: the eq's envelope model - level steps per 50 Hz frame (8.8 fixed, 255.0 = 65280) for the SID's attack and decay/release times"""
    A = [2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000]
    D = [6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000]
    st = lambda T: min(65280, int(65280 * 20 / T))
    a = [st(t) for t in A]; d = [st(t) for t in D]
    with open(path, 'w') as o:
        o.write('; made by mktab.py\natk_lo !byte ' + ', '.join(str(v & 255) for v in a) + '\natk_hi !byte ' + ', '.join(str(v >> 8) for v in a) + '\n')
        o.write('dec_lo !byte ' + ', '.join(str(v & 255) for v in d) + '\ndec_hi !byte ' + ', '.join(str(v >> 8) for v in d) + '\n')

if __name__ == '__main__':
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    make(os.path.join(here, 'ftab.inc')); eqtab(os.path.join(here, 'eqtab.inc'))
