#!/usr/bin/env python3
# THE LAST SUPPER - the music: "Ave Maria ... virgo serena" (Josquin des Prez, c. 1485, public domain), its first two
# verses (to "nova replet laetitia"), an original arrangement for 8 SIDs by Mong00se: a small chapel. The notes are
# Josquin's four voices as transcribed by the Josquin Research Project (New Josquin Edition 23.6; jrp-scores,
# CC BY-NC 4.0: ave_maria.krn) - nothing from anyone's arrangement. The PC only prepares data: SID register frames
# (8 SIDs x 32 bytes a frame) for the 6502 to stream from the REU.
#   SID 1-4 the four voices sung by a "choir": two pulse waves a voice, a little apart, breathing (slow PWM), soft attack
#   SID 5 a chamber organ joining the choir in the second verse (8', the three upper voices)
#   SID 6 the organ's pedal (the bassus, 16' and 8')     SID 7 two recorders over the top line, from the second verse
#   SID 8 a small bell at the start of each verse and on the last chord
# The motet builds itself: the voices come in one after another in imitation (soprano, alto, tenor, bass).
# A semibreve is 46 frames (about 65 to the minute).   music.py OUT.bin  -> prints the frame count
import math, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
_s = open(os.path.join(HERE, '..', 'greatwave', 'music.py')).read()
exec(_s[:_s.index('# ------------------------------------------------------------------------------------------------- the form')])
sys.path.insert(0, HERE)
import kern

def regs_soft(S, hard):
    """Song.regs, but the hard restart (gate off and ADSR 0 before a note) only on the SIDs in `hard`; the others glide
    from note to note through their own release (one frame of gate off, the envelope kept)"""
    g = S.gate.copy(); ad = S.ad.copy(); sr = S.sr.copy(); wv = S.wave.copy()
    rise = g[1:] & ~g[:-1]
    for f, c, v in zip(*np.nonzero(rise)):
        if c not in hard: continue
        f += 1
        for k in (1, 2):
            if f - k >= 0: g[f - k, c, v] = False; ad[f - k, c, v] = 0; sr[f - k, c, v] = 0
        if f - 1 >= 0: wv[f - 1, c, v] |= 0x08
    for c in range(8):
        if c in hard: continue
        for v in range(3):
            r = np.nonzero(S.gate[1:, c, v] & ~S.gate[:-1, c, v])[0] + 1
            for f in r:
                if f - 1 >= 0 and S.gate[f - 2 if f >= 2 else 0, c, v]: g[f - 1, c, v] = False
    out = np.zeros((S.N, 8, 32), np.uint8)
    for c in range(8):
        for v in range(3):
            o = v * 7
            fq = np.array([fr(h) for h in S.freq[:, c, v]])
            pw = np.clip(S.pw[:, c, v], 0, 4095).astype(int)
            out[:, c, o] = fq & 255; out[:, c, o + 1] = fq >> 8
            out[:, c, o + 2] = pw & 255; out[:, c, o + 3] = pw >> 8
            out[:, c, o + 4] = (wv[:, c, v] & 0xFE) | g[:, c, v]
            out[:, c, o + 5] = ad[:, c, v]; out[:, c, o + 6] = sr[:, c, v]
        ct = np.clip(S.cut[:, c], 0, 2047).astype(int)
        out[:, c, 21] = ct & 7; out[:, c, 22] = ct >> 3
        out[:, c, 23] = (S.res[:, c] << 4) | S.route[:, c]
        out[:, c, 24] = S.mode[:, c] | np.clip(np.round(S.vol[:, c]), 0, 15).astype(int)
    return out

SB = 46
CUT = 104                                   # the end of the second verse: the motet's own cadence on C
TAILF = 190                                 # the last chord, held and fading
ALL, _ = kern.parse(os.path.join(HERE, 'ave_maria.krn'))
FINAL = {0: 48, 1: 60, 2: 55, 3: 72}        # bassus C, tenor C, altus G, superius C - the chord the cadence lands on
VOICES = []
for i, sp in enumerate(ALL):               # every note up to the cadence (cut there), then the last chord
    v = [(s, min(l, CUT - s), m) for (s, l, m) in sp if s < CUT]
    v.append((CUT, 0, FINAL[i])); VOICES.append(v)
BASS, TEN, ALT, SUP = VOICES                # the spines: bassus, tenor, altus, superius
N = int(CUT * SB) + TAILF
S = Song(N); t = np.arange(N)
F = lambda w: int(round(w * SB))
def note(c, v, f0, f1, hz, w, ad, sr, pw=2048, tail=20):
    if 0 <= f0 < N - 2: S.note(c, v, f0, min(f1, N - 2), hz, w, ad, sr, pw=pw, tail=tail)
def end_of(s, l): return N - 12 if s >= CUT else F(s + l) - 2
VERSE2 = 60
# ---- SID 1-4: the choir - each voice two pulse waves, a little apart (a section of singers, not one), breathing
for c, sp, oc in ((3, SUP, 0), (2, ALT, 0), (1, TEN, 0), (0, BASS, 0)):
    for k, (s, l, m) in enumerate(sp):
        if m is None: continue
        f0, f1 = F(s), end_of(s, l)
        v = (k % 2) * 1
        note(c, v, f0, f1, nhz(m + oc), PUL, 0x68, 0xB9, pw=lambda j, c=c: 1700 + 600 * math.sin(j / 31 + c), tail=22)
        note(c, 2, f0, f1, nhz(m + oc) * 1.004, PUL, 0x88, 0x99, pw=lambda j, c=c: 2300 + 500 * math.sin(j / 37 + c), tail=22)
    S.route[:, c] = 0x07; S.mode[:, c] = LP; S.res[:, c] = 4
    S.cut[:, c] = (560 + 120 * c) + 160 * np.sin(2 * np.pi * t / (620 + 90 * c)) ** 2
    S.vol[:, c] = 12
S.vol[:, 0] = 13
# ---- SID 5: the chamber organ (8') under the three upper voices, from the second verse; SID 6 its pedal
for v, sp in enumerate((SUP, ALT, TEN)):
    for (s, l, m) in sp:
        if m is None or s < VERSE2: continue
        note(4, v, F(s), end_of(s, l), nhz(m), PUL, 0x19, 0xD6, pw=900, tail=10)
for (s, l, m) in BASS:
    if m is None or s < VERSE2 - 4: continue
    note(5, 0, F(s), end_of(s, l), nhz(m - 12), TRI, 0x29, 0xD8, tail=12)
    note(5, 1, F(s), end_of(s, l), nhz(m), PUL, 0x29, 0xC8, pw=1100, tail=12)
S.vol[:, 4] = 7; S.vol[:, 5] = 10
for c, n0 in ((4, VERSE2), (5, VERSE2 - 4)):
    f0 = F(n0); S.vol[f0:f0 + F(4), c] = np.linspace(1, S.vol[f0 + F(4), c], F(4)).round()
# ---- SID 7: two recorders over the top line (an octave up, then a third below it), from the second verse, soft
for k, (s, l, m) in enumerate(SUP):
    if m is None or s < VERSE2 + 8: continue
    note(6, k % 2, F(s), end_of(s, l), (lambda b: (lambda j: b * (1 + (0.004 * math.sin(2 * math.pi * j / 6) if j > 20 else 0))))(nhz(m + 12)), TRI, 0x38, 0x99, tail=16)
S.vol[:, 6] = 6
# ---- SID 8: a small bell at each verse and on the last chord (hum, prime, minor tierce)
def bell(f, hz):
    for v, p in enumerate((0.5, 1.0, 1.189)): note(7, v, f, f + 3, hz * p, TRI, 0x0A, 0x9B, tail=120)
for w in (0, VERSE2, CUT): bell(F(w), nhz(84))
S.vol[:, 7] = 9
# the end: everything fades over the last chord
fe = F(CUT)
for c in range(8): S.vol[fe:, c] = (S.vol[fe:, c] * np.linspace(1, 0.3, N - fe)).round()
r = regs_soft(S, hard={7})
r = r[:, [0, 1, 4, 5, 2, 3, 6, 7], :]
out = sys.argv[1] if len(sys.argv) > 1 else 'music.bin'
r.reshape(N * 256).astype(np.uint8).tofile(out)
print(N)
