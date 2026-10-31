# the measured value at every raw position for each table and width (what OSC3 should read)
import sys, re
sys.path.insert(0, '../../chips'); import mkchips
tab = mkchips.arrays(sys.argv[1], 4096)
stem = sys.argv[2]; out = bytearray()
for k in ('triSaw', 'triPulse', 'sawPulse', 'triSawPulse'):
    for w in ('narrow', 'square', 'wide'):
        out += bytes(tab[stem + '_triSaw'] if k == 'triSaw' else tab['%s_%s_%s' % (stem, k, w)])
open(sys.argv[3], 'wb').write(out)
