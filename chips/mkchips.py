#!/usr/bin/env python3
"""Neal's own SID chips as personalities for the Octophonic core (.CHP files).

Reads the SIDWeaver VST's measurements (ChipClones.h: combined waveforms, 4096 positions;
ChipFilters.h: filter cutoff per register high byte) and writes one .CHP per chip:

  $0000-$0FFF  S+T   table, 4096 bytes, indexed by the core's acc_t (saw on: the accumulator)
  $1000-$1FFF  P+T   table, indexed by acc_t (saw off: {msb, triangle-folded low 11 bits})
  $2000-$2FFF  P+S   table, indexed by acc_t (the accumulator)
  $3000-$3FFF  P+S+T table, indexed by acc_t (the accumulator)
  $4000-$47FF  filter curve, 1024 x 16 bits, low byte first, indexed by Fc[10:1]: F0 * 2
  $4800        model: 0 = 6581, 1 = 8580 (writing it switches the personality on)
  $4810-       the chip's name (text, for people; the core ignores it)

usage: python3 mkchips.py <ChipClones.h> <ChipFilters.h> <out dir>
See docs/CHIPS.md for how each table maps.
"""
import re, sys, math, os

def arrays(path, n):
    s = open(path).read()
    out = {}
    for m in re.finditer(r'static constexpr uint(?:8|16)_t (\w+)\[points\]\s*=\s*\{([^}]*)\}', s):
        v = [int(x, 0) for x in re.findall(r'0x[0-9A-Fa-f]+|\d+', m.group(2))]
        assert len(v) == n, (m.group(1), len(v))
        out[m.group(1)] = v
    return out

CHIPS = [  # name, VST symbol stem, model
    ('MOS 6581 5084', 'cmos65815084', 0),
    ('MOS 6581 3184', 'cmos65813184', 0),
    ('CSG 8580R5 3591', 'ccsg8580r53591', 1),
    ('MOS 8580R5 4687', 'cmos8580r54687', 1),
]

def composite(tab, stem, kind):
    """one value per accumulator position (the raw 12-bit position i), pulse high there:
       i >= $800: the square ($800) measurement; $400 <= i < $800: the narrow ($400) one
       (the only width measured with the pulse high there); below $400 nothing was measured
       with the pulse high: 0"""
    sq = tab['%s_%s_square' % (stem, kind)]; na = tab['%s_%s_narrow' % (stem, kind)]
    return [sq[i] if i >= 0x800 else (na[i] if i >= 0x400 else 0) for i in range(4096)]

def fold(j):
    """the raw position whose triangle the core presents as acc_t = j (saw off, no ring mod):
       acc_t = {msb, low11 ^ msb} is its own inverse"""
    msb = j >> 11
    return (msb << 11) | ((j & 0x7FF) ^ (0x7FF if msb else 0))

def tables(tab, stem):
    st = tab[stem + '_triSaw']
    pt = [composite(tab, stem, 'triPulse')[fold(j)] for j in range(4096)]
    ps = composite(tab, stem, 'sawPulse')
    pst = composite(tab, stem, 'triSawPulse')
    return st, pt, ps, pst

# F0 is w0*T << 17 (sid_filter.sv: "a <= F0;   // w0*T << 17"), T = 1 us: F0 = 2*pi*f*2^17/1e6.
# The 8580 path (F0 = 5*Fc + ...) agrees: 12.4 kHz at the top. The 6581 curve slot holds F0 * 2.
K = 2 * math.pi * (1 << 17) / 1e6
def curve(hz256):
    out = []
    for k in range(1024):                 # Fc[10:1]: the register high byte is k >> 2
        a = hz256[k >> 2]; b = hz256[min(255, (k >> 2) + 1)]
        hz = a + (b - a) * (k & 3) / 4
        out.append(min(65535, round(2 * K * hz)))
    return out

def main():
    clones, filters, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
    tab = arrays(clones, 4096); flt = arrays(filters, 256)
    os.makedirs(outdir, exist_ok=True)
    for name, stem, model in CHIPS:
        st, pt, ps, pst = tables(tab, stem)
        cv = curve(flt[stem + '_cutoffHz'])
        b = bytearray(0x4900)
        for t, data in enumerate((st, pt, ps, pst)): b[t * 4096:(t + 1) * 4096] = bytes(data)
        for k, v in enumerate(cv): b[0x4000 + 2 * k] = v & 255; b[0x4001 + 2 * k] = v >> 8
        b[0x4800] = model
        nm = name.encode(); b[0x4810:0x4810 + len(nm)] = nm
        fn = os.path.join(outdir, name.replace(' ', '_') + '.CHP')
        open(fn, 'wb').write(b)
        print(fn, 'model', '8580' if model else '6581', 'sounding S+T/P+T/P+S/P+S+T:',
              [sum(1 for x in d if x) for d in (st, pt, ps, pst)], 'F0x2 at reg 0/128/255:', cv[0], cv[512], cv[1023])

if __name__ == '__main__':
    main()
