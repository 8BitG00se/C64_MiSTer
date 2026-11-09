#!/usr/bin/env python3
"""The core's HDMI level from the RTL arithmetic: the SIDs' 18-bit outputs every microsecond (OCTO_SIDRAW8)
   through the OLD mixer (divide by how many SIDs a side, soft limiter) and the NEW one (rtlmodel.run),
   then c64.sv's audio[17:2] into 16 bits, ~48 kHz (20.83 us averages), the MiSTer's DC blocker.
   corecol.py dump.raw onset_us secs -> old pk rms | new pk rms"""
import sys, numpy as np
from rtlmodel import run, route, soft
a = np.fromfile(sys.argv[1], dtype='<i4').reshape(-1, 11)
on = int(sys.argv[2]); secs = float(sys.argv[3])
st = max(0, on - 1000000); a = a[st:on + int((secs + 1.5) * 1e6)]; on -= st   # from a second before the music (memory)
raw = a[:, :8].astype(np.int64); plm = a[:, 10].astype(np.int64)
def old(raw, plm):
    n = len(raw); L = np.zeros(n, np.int64); R = np.zeros(n, np.int64)
    for m in np.unique(plm):
        idx = plm == m
        l, r = route(int(m) & 255, int(m) >> 8 & 1, not (int(m) >> 9 & 1))
        for side, sel in ((L, l), (R, r)):
            s = (raw[idx] * sel).sum(axis=1); k = int(sel.sum())
            s = s if k <= 1 else s >> 1 if k == 2 else s >> 2 if k <= 4 else s >> 3
            side[idx] = s
    vs = np.vectorize(soft); return vs(L), vs(R)
def hdmi(x):
    x = (x >> 2).astype(np.float64)                         # audio_l[17:2]
    n = int(len(x) / (1e6 / 48000)); idx = (np.arange(n + 1) * (1e6 / 48000)).astype(np.int64)
    c = np.concatenate([[0], np.cumsum(x)]); y = (c[idx[1:]] - c[idx[:-1]]) / np.diff(idx)
    out = np.zeros_like(y); xp = yp = 0.0                    # DC_blocker (sys/iir_filter.v)
    for i, v in enumerate(y):
        x0 = v - v / 1024; o = x0 - xp + yp - yp / 512; xp, yp = x0, o; out[i] = o
    return out
def meas(L, R):
    s = int(on / 1e6 * 48000) + 24000; e = s + int(secs * 48000)
    y = np.stack([hdmi(L), hdmi(R)], 1)[s:e]; y = y - y.mean(0)
    return 20 * np.log10(np.abs(y).max() / 32768), 20 * np.log10(np.sqrt((y ** 2).mean()) / 32768)
oL, oR = old(raw, plm); nL, nR, _ = run(raw, plm)
print("%.1f %.1f | %.1f %.1f" % (meas(oL, oR) + meas(nL, nR)))
