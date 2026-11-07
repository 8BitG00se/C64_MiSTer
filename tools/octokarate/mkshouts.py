#!/usr/bin/env python3
# mkshouts.py - Neal's own kiai shouts (sounds/kiai1.wav, kiai2.wav, recorded by him) made into 80s game samples:
# the small-speaker band, pitched up 2 semitones, pushed hard, a hard start and a quick end ("snappy", his pick: test 3 no. 3),
# then 4 bits at 6236 Hz (the CIA timer: 985248 / 158), two samples a byte (high nibble first), played by the NMI into the
# SID volume registers. Writes OUT/shouts.bin (shout 0 at 0, shout 1 at $1000) and prints their lengths for data.inc.
import sys, numpy as np, scipy.io.wavfile as w, scipy.signal as s
OUT = sys.argv[1]; RATE = 985248 / 158
def prep(fn):
    sr, a = w.read(fn); a = a.astype(np.float64) / 32768
    a = s.resample(a, int(len(a) / 2 ** (2 / 12)))
    b, c = s.butter(2, [300 / (sr / 2), 3400 / (sr / 2)], 'band'); a = s.lfilter(b, c, a)
    a = np.tanh(a / np.abs(a).max() * 3.0); a /= np.abs(a).max()
    n = len(a); e = np.ones(n); t = int(0.45 * n); e[t:] = np.linspace(1, 0, n - t) ** 2
    a = a * e
    idx = (np.arange(int(len(a) * RATE / sr)) * sr / RATE).astype(int)        # no smoothing filter: the 80s crunch
    q = np.clip(np.round((a[idx] * 0.5 + 0.5) * 15), 0, 15).astype(np.uint8)
    q = np.concatenate([q, np.array([8, 8, 8, 8], np.uint8)])                                    # end on the middle level (no click)
    if len(q) % 2: q = np.append(q, np.uint8(8)).astype(np.uint8)
    q = q.astype(np.uint8); return ((q[0::2] << 4) | q[1::2]).astype(np.uint8).tobytes()
blob = bytearray(0x2000); lens = []
for i, fn in enumerate(('sounds/kiai1.wav', 'sounds/kiai2.wav')):
    d = prep(fn); assert len(d) <= 0xF00, len(d)
    blob[i * 0x1000:i * 0x1000 + len(d)] = d; lens.append(len(d))
open(OUT + '/shouts.bin', 'wb').write(blob)
print('SHOUT0_N = %d' % lens[0]); print('SHOUT1_N = %d' % lens[1])
