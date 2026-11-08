#!/usr/bin/env python3
# MONA LISA - the music: "Mille regretz" (Josquin des Prez, early 16th century, public domain), an original arrangement for
# 8 SIDs by Mong00se. The notes are Josquin's four voices as transcribed by the Josquin Research Project (New Josquin
# Edition 28.25; jrp-scores, CC BY-NC 4.0: mille_regretz.krn) - nothing from anyone's arrangement. The PC only prepares
# data: this script renders the arrangement to SID register frames (8 SIDs x 32 bytes a frame) for the 6502 to stream.
#   SID 1 the superius on a bowed lira da braccio (Leonardo's own instrument): a saw, filtered, slow bow, late vibrato
#   SID 2 the altus on a recorder (triangle)          SID 3 the tenor on a viol (pulse, slow PWM)
#   SID 4 the bassus on a bass viol (saw + octave)    SID 5 a lute picking the harmony of all four voices
#   SID 6 a quiet positive organ under the inner voices   SID 7 the superius's echo, a beat later
#   SID 8 a harp, a rising chord at each new phrase
# It builds one voice at a time: the lute and the lira first, then the bass viol, the viol, the recorder, the organ.
# A semibreve (the tactus) is 54 frames - about 56 to the minute.   music.py OUT.bin  -> prints the frame count
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

SB = 54                                     # frames a semibreve
VOICES, END = kern.parse(os.path.join(HERE, 'mille_regretz.krn'))
BASS, TEN, ALT, SUP = VOICES                # the spines: bassus, tenor, altus, superius
LEN = max(END)                              # 80 semibreves
TAILF = 140                                 # the last chord rings on
N = int(LEN * SB) + TAILF
S = Song(N); t = np.arange(N)
F = lambda w: int(round(w * SB))
def note(c, v, f0, f1, hz, w, ad, sr, pw=2048, tail=20):
    if 0 <= f0 < N - 2: S.note(c, v, f0, min(f1, N - 2), hz, w, ad, sr, pw=pw, tail=tail)
def vib(base, delay=16, depth=0.006, rate=6.5):
    return lambda k: base * (1 + (depth * min(1, (k - delay) / 20) * math.sin(2 * math.pi * k / rate) if k > delay else 0))
ENTER = {'lira': 0, 'lute': 0, 'bass': 8, 'viol': 16, 'recorder': 24, 'organ': 32, 'echo': 40}
LAST = LEN - 2                              # the final long chord
def hold(s, l):                             # the last notes hold to the end
    return F(s + l) + (TAILF - 10 if s >= LAST else -3)
# ---- SID 1: the lira (superius)
for k, (s, l, m) in enumerate(SUP):
    if m is None or s < ENTER['lira']: continue
    note(0, k % 2, F(s), hold(s, l), vib(nhz(m)), SAW, 0x58, 0xA9, tail=24)
S.route[:, 0] = 0x03; S.mode[:, 0] = LP; S.res[:, 0] = 4
S.cut[:, 0] = 700 + 260 * np.sin(2 * np.pi * t / 700) ** 2
S.vol[:, 0] = 12
# ---- SID 2: the recorder (altus), SID 3: the viol (tenor), SID 4: the bass viol (bassus)
for k, (s, l, m) in enumerate(ALT):
    if m is None or s < ENTER['recorder']: continue
    note(1, k % 2, F(s), hold(s, l), vib(nhz(m + 12), 20, 0.004, 5.5), TRI, 0x38, 0x99, tail=18)
for k, (s, l, m) in enumerate(TEN):
    if m is None or s < ENTER['viol']: continue
    note(2, k % 2, F(s), hold(s, l), vib(nhz(m), 18, 0.004), PUL, 0x48, 0x99, pw=lambda j: 1600 + 500 * math.sin(j / 23), tail=20)
for k, (s, l, m) in enumerate(BASS):
    if m is None or s < ENTER['bass']: continue
    note(3, 0, F(s), hold(s, l), nhz(m), SAW, 0x48, 0xA9, tail=20)
    note(3, 1, F(s), hold(s, l), nhz(m - 12), TRI, 0x48, 0xA9, tail=20)
S.vol[:, 1] = 10; S.vol[:, 2] = 10; S.vol[:, 3] = 11
S.route[:, 3] = 0x01; S.mode[:, 3] = LP; S.res[:, 3] = 3; S.cut[:, 3] = 520
S.route[:, 2] = 0x03; S.mode[:, 2] = LP; S.res[:, 2] = 2; S.cut[:, 2] = 1100
# fade each one in over its first phrase
for name, c in (('recorder', 1), ('viol', 2), ('bass', 3)):
    f0 = F(ENTER[name]); S.vol[f0:f0 + F(4), c] = np.linspace(2, S.vol[f0 + F(4), c], F(4)).round()
# ---- SID 5: the lute - every crotchet it picks one note of the harmony sounding then (all four voices), bass on the
# minim, then up through the chord and back
def sounding(w):
    out = []
    for sp in VOICES:
        for (s, l, m) in sp:
            if s <= w < s + l and m is not None: out.append(m)
    return sorted(set(out))
q = 0.0; k = 0
while q < LEN - 1e-9:
    ch = sounding(q + 1e-6)
    if ch:
        pat = [0, len(ch) - 1, max(0, len(ch) - 2), len(ch) - 1] if len(ch) > 2 else [0, len(ch) - 1, 0, len(ch) - 1]
        m = ch[pat[k % 4]]
        while m < 52: m += 12
        end = F(q + 0.25) - 1 if q < LAST else N - 20
        note(4, k % 3, F(q), F(q) + 5, nhz(m), PUL, 0x0A, 0x09 if q < LAST else 0x0C, pw=760, tail=40)
    q += 0.25; k += 1
S.route[:, 4] = 0x07; S.mode[:, 4] = LP; S.res[:, 4] = 3; S.cut[:, 4] = 980
S.vol[:, 4] = 11; S.vol[F(32):, 4] = 9
# ---- SID 6: the positive organ - the altus and the tenor an octave up, quiet, from the middle on
for sp, v in ((ALT, 0), (TEN, 1)):
    for (s, l, m) in sp:
        if m is None or s < ENTER['organ']: continue
        note(5, v, F(s), hold(s, l), nhz(m + 12), PUL, 0x29, 0xC6, pw=900, tail=12)
S.vol[:, 5] = 6; f0 = F(ENTER['organ']); S.vol[f0:f0 + F(6), 5] = np.linspace(1, 6, F(6)).round()
# ---- SID 7: the echo - the superius a crotchet later, a soft triangle an octave up
for k, (s, l, m) in enumerate(SUP):
    if m is None or s < ENTER['echo']: continue
    d = F(0.25)
    note(6, k % 2, F(s) + d, hold(s, l) + d, vib(nhz(m + 12), 10, 0.005), TRI, 0x48, 0x78, tail=24)
S.vol[:, 6] = 7
# ---- SID 8: the harp - a rising chord where each new phrase begins, and at the end
for w in (8, 16, 24, 32, 40, 48, 56, 64, 72, LAST):
    ch = sounding(w + 1e-6)
    if not ch: continue
    up = sorted(set([c_ + 12 for c_ in ch] + [ch[-1] + 24]))
    for j, m in enumerate(up[:6]):
        f = F(w) + j * 4
        note(7, j % 3, f, f + 3, nhz(m), TRI, 0x09, 0x0A, tail=60)
S.vol[:, 7] = 9
# the end: everything fades over the last chord
fe = F(LAST)
for c in range(8): S.vol[fe:, c] = (S.vol[fe:, c] * np.linspace(1, 0.35, N - fe)).round()
r = regs_soft(S, hard={4, 7})
r = r[:, [0, 1, 4, 5, 2, 3, 6, 7], :]
out = sys.argv[1] if len(sys.argv) > 1 else 'music.bin'
r.reshape(N * 256).astype(np.uint8).tofile(out)
print(N)
