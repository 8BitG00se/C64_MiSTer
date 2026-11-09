#!/usr/bin/env python3
"""Bit-exact model of the core's NEW mixer (rtl/sid_mix.vhd, Fix 28), written from the VHDL,
   checked against the emulator's OCTO_SIDRAW8 dump (per microsecond: 8 SID outputs as the mixer
   takes them - 0 when not played - then the emulator's mix L, R).
   rtlmodel.py dump.raw   -> mismatches, the gain's lowest per half second, and the 1 MHz core output (.core.npy)"""
import sys, numpy as np
T, FS = 98304, 131071
GMAX = 0x28000000

def soft(x):
    if x > T:
        y = T + ((x - T) >> 2)
        return FS if y > FS else y
    if x < -T:
        y = -T + ((x + T) >> 2)
        return -FS if y < -FS else y
    return x

def route(pl, oct_, quad=1):
    onl = []; onr = []
    for c in range(8):
        if c % 2 == 0: l, r = True, not (pl >> (c + 1) & 1)
        else: r, l = True, not (pl >> (c - 1) & 1)
        if (c >= 2 and not quad) or (c >= 4 and not oct_) or not (pl >> c & 1): l = r = False
        onl.append(l); onr.append(r)
    return np.array(onl), np.array(onr)

def run(raw, plm):
    """raw: (n, 8) SID outputs; plm: (n,) played mask | 256 for eight SIDs (| 512: OCTOPHONIC off)"""
    n = len(raw)
    sl = np.zeros(n, np.int64); sr = np.zeros(n, np.int64)
    for m in np.unique(plm):
        idx = plm == m
        l, r = route(int(m) & 255, int(m) >> 8 & 1, not (int(m) >> 9 & 1))
        sl[idx] = (raw[idx] * l).sum(axis=1); sr[idx] = (raw[idx] * r).sum(axis=1)
    dc = [0, 0]; g = GMAX
    outL = np.zeros(n, np.int64); outR = np.zeros(n, np.int64); gt = np.zeros(n, np.uint32)
    SL = sl.tolist(); SR = sr.tolist(); P = plm.tolist(); RL = raw[:, 0].tolist(); RR = raw[:, 1].tolist()
    oL = [0] * n; oR = [0] * n; G = [0] * n
    for i in range(n):
        y0 = y1 = 0
        for k in (0, 1):
            s = SL[i] if k == 0 else SR[i]
            # cycle 1: h = sum - dc(37 downto 14); dc <= dc + h
            h = s - (dc[k] >> 14)
            dc[k] += h
            # cycle 2: y = (h * gain(31 downto 13))(43 downto 16), clamped to 22 bits
            v = (h * (g >> 13)) >> 16
            if v > 2097151: v = 2097151
            elif v < -2097152: v = -2097152
            if k == 0: y0 = v
            else: y1 = v
        # cycle 3: the limiter, and the gain for the next microsecond
        over = y0 > T or y0 < -T or y1 > T or y1 < -T
        g = g - (g >> 7) if over else g + ((GMAX - g) >> 21)
        if P[i] >> 9 & 1: oL[i] = RL[i]; oR[i] = RR[i]   # OCTOPHONIC off: the first pair as it was (the mixer runs on)
        else: oL[i] = soft(y0); oR[i] = soft(y1)
        G[i] = g
    return np.array(oL), np.array(oR), np.array(G, dtype=np.uint64)

if __name__ == "__main__":
    a = np.fromfile(sys.argv[1], dtype='<i4').reshape(-1, 11)
    L, R, gt = run(a[:, :8].astype(np.int64), a[:, 10].astype(np.int64))
    mm = int((L != a[:, 8]).sum() + (R != a[:, 9]).sum())
    print("microseconds %d  mismatches %d" % (len(a), mm))
    if mm:
        i = int(np.nonzero((L != a[:, 8]) | (R != a[:, 9]))[0][0]); print("first at", i, L[i], a[i, 8], R[i], a[i, 9])
    g = gt / 2 ** 29
    sec = len(g) // 1000000
    print("gain per 0.5 s:", " ".join("%.3f" % g[j * 500000:(j + 1) * 500000].min() for j in range(len(g) // 500000)))
    np.save(sys.argv[1] + ".core.npy", np.stack([L, R]))
