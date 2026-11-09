#!/usr/bin/env python3
"""peak / RMS dBFS of a stereo s16 48 kHz .pcm, from 0.5 s after the sound starts, for SECS seconds.
   meas.py file.pcm [SECS] [SKIP]  -> prints  peak_dBFS rms_dBFS clip_count"""
import sys, numpy as np
def meas(fn, secs=4.0, skip=0.5, onset=None):
    x = np.fromfile(fn, dtype='<i2').reshape(-1, 2).astype(np.float64)
    if onset is None:
        a = np.abs(x).max(axis=1)
        idx = np.nonzero(a > 300)[0]
        if len(idx) == 0: return (-200, -200, 0, 0)
        onset = idx[0]
    s = onset + int(skip * 48000); e = s + int(secs * 48000)
    y = x[s:e]
    if len(y) == 0: return (-200, -200, 0, 0)
    y = y - y.mean(axis=0)      # the DC (a 6581's offset) is not loudness
    pk = np.abs(y).max(); rms = np.sqrt((y ** 2).mean())
    clip = int((np.abs(x[s:e]) >= 32767).sum())
    db = lambda v: 20 * np.log10(max(v, 1e-9) / 32768)
    return (db(pk), db(rms), clip, onset)
if __name__ == "__main__":
    a = sys.argv
    r = meas(a[1], float(a[2]) if len(a) > 2 else 4.0, float(a[3]) if len(a) > 3 else 0.5)
    print("%.1f %.1f %d" % r[:3])
