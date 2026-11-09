#!/usr/bin/env python3
"""The level table: each test in the emulator (pcm), VICE reSID and VICE reSID-fp (vref on the same writes)."""
import sys, struct, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meas import meas
emudir = sys.argv[1]; names = sys.argv[2:]
def onset_of(sidw):
    d = open(sidw, 'rb').read()
    for i in range(len(d) // 9):
        fr, ln, a, v = struct.unpack('<IHHB', d[i*9:i*9+9])
        if v and fr > 160: return int((fr * 19656 + ln * 63) / 985248 * 48000)
    return 0
print("%-10s | %-22s | %-22s | %-22s" % ("test", "emulator pk/rms", "VICE reSID pk/rms", "VICE reSID-fp pk/rms"))
for n in names:
    on = onset_of(f"{emudir}/{n}.sidw")
    e = meas(f"{emudir}/{n}.pcm")
    r = meas(f"{emudir}/vice/{n}.resid.pcm", onset=on); f = meas(f"{emudir}/vice/{n}.fp.pcm", onset=on)
    fmt = lambda m: "%6.1f %6.1f %s" % (m[0], m[1], ("clip%d" % m[2]) if m[2] else "")
    print("%-10s | %-22s | %-22s | %-22s" % (n, fmt(e), fmt(r), fmt(f)))
