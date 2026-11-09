#!/usr/bin/env python3
"""Vectors for the GHDL test of rtl/sid_mix.vhd, and the check of its output against the integer model.
   mixvec.py gen vec.txt exp.txt     - the vectors, and what the model says the mix gives
   mixvec.py check exp.txt out.txt   - compare (exit 1 on any difference)
 The model is rtlmodel.py's maths (bit for bit the emulator's mix_us, checked on real dumps) plus the
 parts the emulator has not got: OctoSID FX (an FX SID adds at half) and the reset (full gain)."""
import sys, math, random
T, FS, GMAX = 98304, 131071, 0x28000000

def soft(x):
    if x > T: return min(T + ((x - T) >> 2), FS)
    if x < -T: return max(-T + ((x + T) >> 2), -FS)
    return x

class Mix:
    def __init__(s): s.dc = [0, 0]; s.g = GMAX
    def us(s, reset, quad, oct_, played, fxm, o):
        pl = played | 1; fx = 0
        if fxm & 1 and not pl >> 1 & 1: fx |= 2
        if fxm & 2 and not pl >> 2 & 1: fx |= 4
        if fxm & 2 and not pl >> 3 & 1: fx |= 8
        pl |= fx
        sl = sr = fl = fr = 0
        for c in range(8):
            if c % 2 == 0: onl, onr = True, not pl >> (c + 1) & 1
            else: onr, onl = True, not pl >> (c - 1) & 1
            if (c >= 2 and not quad) or (c >= 4 and not oct_) or not pl >> c & 1: onl = onr = False
            if fx >> c & 1:
                if onl: fl += o[c]
                if onr: fr += o[c]
            else:
                if onl: sl += o[c]
                if onr: sr += o[c]
        if reset: s.g = GMAX
        y = []
        for k, sm in enumerate((sl + (fl >> 1), sr + (fr >> 1))):
            h = sm - (s.dc[k] >> 14); s.dc[k] += h
            v = (h * (s.g >> 13)) >> 16
            y.append(max(-2097152, min(2097151, v)))
        if y[0] > T or y[0] < -T or y[1] > T or y[1] < -T: s.g -= s.g >> 7
        else: s.g += (GMAX - s.g) >> 21
        if reset: s.g = GMAX
        return soft(y[0]), soft(y[1])

def gen(vf, ef):
    rnd = random.Random(28)
    m = Mix(); fv = open(vf, "w"); fe = open(ef, "w")
    # (microseconds, quad, oct, played, fx, amplitude per SID, 6581-like offset, reset at start)
    plan = [(20000, 1, 1, 0x01, 0, [1.0] + [0] * 7, 40000, 0),             # one SID in the middle
            (30000, 1, 1, 0xFF, 0, [1.0] * 8, 40000, 0),                    # eight SIDs, loud: the gain comes down
            (30000, 1, 1, 0xFF, 0, [0.2] * 8, 10000, 0),                    # then quiet: it creeps back
            (20000, 1, 1, 0x0F, 0, [1, .5, .8, .3, 0, 0, 0, 0], 30000, 1),  # a reset, four SIDs
            (20000, 1, 1, 0x01, 3, [1, 1, 1, 1, 0, 0, 0, 0], 20000, 0),     # OctoSID FX on SIDs 2-4
            (20000, 1, 1, 0x05, 1, [1, 1, 1, 1, 0, 0, 0, 0], 20000, 0),     # FX chorus, SID 3 played
            (15000, 1, 0, 0xFF, 0, [1.0] * 8, 30000, 0),                    # four-SID mode
            (15000, 0, 0, 0xFF, 0, [1.0] * 8, 30000, 0),                    # OCTOPHONIC off (the mix runs on)
            (30000, 1, 1, 0xA5, 0, [1, .7, .4, 1, .9, .1, .6, 1], 45000, 0)]  # a SID whose partner never played
    t = 0
    for n, quad, oct_, played, fxm, amp, off, rst in plan:
        ph = [rnd.random() for _ in range(8)]; fr = [60 + 400 * rnd.random() for _ in range(8)]
        for i in range(n):
            o = []
            for c in range(8):
                saw = ((t * fr[c] / 1e6 + ph[c]) % 1.0) * 2 - 1
                o.append(max(-131072, min(131071, int(off * (amp[c] > 0) + amp[c] * 45000 * saw + rnd.randint(-200, 200)))))
            r = 1 if rst and i < 3 else 0
            fv.write("%d %d %d %d %d %s\n" % (r, quad, oct_, played, fxm, " ".join(map(str, o))))
            fe.write("%d %d\n" % m.us(r, quad, oct_, played, fxm, o))
            t += 1

def check(ef, of):
    e = open(ef).read().split("\n"); o = open(of).read().split("\n")
    e = [x for x in e if x.strip()]; o = [x for x in o if x.strip()]
    bad = [i for i in range(min(len(e), len(o))) if e[i].split() != o[i].split()]
    print("sid_mix (GHDL) vs the integer model: %d microseconds, %d differ" % (len(o), len(bad) + abs(len(e) - len(o))))
    for i in bad[:5]: print("  us %d: model %s, VHDL %s" % (i, e[i], o[i]))
    lo = [int(x.split()[0]) for x in o]; print("  output range %d..%d" % (min(lo), max(lo)))
    sys.exit(1 if bad or len(e) != len(o) else 0)

if __name__ == "__main__":
    {"gen": gen, "check": check}[sys.argv[1]](sys.argv[2], sys.argv[3])
