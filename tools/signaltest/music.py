#!/usr/bin/env python3
# SIGNAL TEST - the sound: a level tone, the 8 SIDs called out one by one, then "Moonlit Valley" (an original tune
# for 8 SIDs, 24 voices, by Mong00se). The PC only prepares data: SID register frames (8 SIDs x 32 bytes a frame, in the
# order the 6502's 4 DMA transfers put them in the SIDs' windows) and a meter level for each SID each frame (0-16).
#   A  frames 0-249      the level tone: all 24 voices, full volume, an A minor chord - as loud as the tune gets
#   B  frames 250-849    SID 1 .. SID 8 alone, 75 frames each, a rising chord a step higher each time
#   C  frames 850-       the tune: 125 bpm (a beat 24 frames, a bar 96), A minor, Am F C G, 34 bars
#      SID 1 drums (kick, snare, hats)   SID 2 bass (pumping octaves, filtered)   SID 3 arpeggio (16ths, pulse)
#      SID 4 pad (3 saws, filter opening)   SID 5 lead (+ harmony at the end)   SID 6 the lead's echo
#      SID 7 bells (sparkles)   SID 8 effects (crashes, risers, toms)
import math, os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
_s = open(os.path.join(HERE, '..', 'greatwave', 'music.py')).read()
exec(_s[:_s.index('# ------------------------------------------------------------------------------------------------- the form')])

TONE = 250; IDENT = 75; FC = TONE + 8 * IDENT          # the tune starts at frame 850
BEAT = 24; BAR = 96; NBARS = 34
N = FC + NBARS * BAR
SECTIONS = [0, TONE] + [TONE + k * IDENT for k in range(1, 8)] + [FC]   # where the status line changes

def regs_soft(S, hard):
    """Song.regs, the hard restart only on the SIDs in `hard`; the others glide (one frame of gate off)"""
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
                if f >= 2 and S.gate[f - 2, c, v]: g[f - 1, c, v] = False
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

# ---- the meters: each SID's loudness from its envelopes (the SID's ADSR timing, simulated) x its volume
ATT = [2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000]   # ms, 0 to full
def meters(r):
    lev = np.zeros((r.shape[0], 8))
    for c in range(8):
        vol = (r[:, c, 24] & 15) / 15.0
        best = np.zeros(r.shape[0])
        for v in range(3):
            o = v * 7; e = 0.0; ph = 'r'; pg = 0
            for f in range(r.shape[0]):
                g = r[f, c, o + 4] & 1; w = r[f, c, o + 4] & 0xF0
                a, d = r[f, c, o + 5] >> 4, r[f, c, o + 5] & 15
                s_, rl = (r[f, c, o + 6] >> 4) / 15.0, r[f, c, o + 6] & 15
                if g and not pg: ph = 'a'
                if not g: ph = 'r'
                for _ in range(4):                               # 5 ms steps
                    if ph == 'a':
                        e += 5.0 / ATT[a]
                        if e >= 1: e = 1.0; ph = 'd'
                    elif ph == 'd':
                        e = max(s_, e - 5.0 / (3 * ATT[d]) * 2.5)
                    else:
                        e = max(0.0, e - 5.0 / (3 * ATT[rl]) * 2.5)
                pg = g
                best[f] = max(best[f], e if w else 0)
        lev[:, c] = best * vol
    m = np.clip(np.round(np.sqrt(lev) * 16), 0, 16).astype(int)
    out = np.zeros_like(m)
    for f in range(len(m)):                                      # the bars fall back one step a frame
        out[f] = m[f] if f == 0 else np.maximum(m[f], out[f - 1] - 1)
    return out.astype(np.uint8)

def build():
    S = Song(N)
    S.vol[:, :] = 15
    # ================================================================ A: the level tone
    chord = [45, 52, 57, 60, 64, 69, 72, 76]                     # A2 .. E5, one SID a note, 3 voices a little detuned
    for c in range(8):
        for v in range(3):
            S.note(c, v, 0, TONE - 12, nhz(chord[c] + (12 if v == 2 else 0)) * (1 + 0.0015 * (v - 1)), SAW, 0x20, 0xF4, tail=10)
    # ================================================================ B: each SID alone, a step higher each time
    steps = [0, 2, 3, 5, 7, 8, 10, 12]                            # A minor scale up
    for c in range(8):
        f0 = TONE + c * IDENT; root = 57 + steps[c]
        for v, iv in enumerate((0, 4, 7)):                        # a major chord, voice by voice
            S.note(c, v, f0 + v * 6, f0 + IDENT - 14, nhz(root + iv), PUL if v == 1 else SAW, 0x10, 0xC6, pw=1800, tail=12)
    # ================================================================ C: Moonlit Valley
    def F(bar, beat=0.0): return FC + int(round(bar * BAR + beat * BEAT))
    PROG = [('Am', 45, (57, 60, 64)), ('F', 41, (53, 57, 60)), ('C', 48, (55, 60, 64)), ('G', 43, (55, 59, 62))]
    def chord_at(bar): return PROG[(bar // 2) % 4]
    END = 32                                                      # bars 32-33: the last chord
    # ---- SID 1: drums
    def kick(f): S.drum(0, 0, f, [(NOI, 900, 0), (TRI, 160, 0), (TRI, 120, 0), (TRI, 95, 0), (TRI, 78, 0), (TRI, 66, 0), (TRI, 58, 0)], 0x08, 0x00, 7)
    def snare(f): S.drum(0, 1, f, [(NOI, 5200, 0), (PUL, 260, 0x800), (NOI, 4200, 0), (NOI, 3800, 0), (NOI, 3400, 0)], 0x09, 0x00, 6)
    def hat(f, op=False): S.drum(0, 2, f, [(NOI, 12000, 0), (NOI, 11000, 0)], 0x04 if not op else 0x08, 0x00, 2 if not op else 5)
    for bar in range(END):
        for b in range(4):
            if bar >= 4: kick(F(bar, b))
            if bar >= 8 and b in (1, 3): snare(F(bar, b))
            if bar >= 8:
                hat(F(bar, b + 0.5), op=True)
                if bar >= 16: hat(F(bar, b + 0.25)); hat(F(bar, b + 0.75))
        if bar == 3: kick(F(bar, 2)); kick(F(bar, 2.5)); kick(F(bar, 3)); kick(F(bar, 3.5))
    kick(F(END)); snare(F(END))
    # ---- SID 2: bass - octave 8ths, low-pass, the filter breathing
    for bar in range(4, END):
        _, root, _ = chord_at(bar)
        for k in range(8):
            n = root + (12 if k % 2 else 0)
            S.note(1, k % 2, F(bar, k * 0.5), F(bar, k * 0.5) + 10, nhz(n), SAW, 0x05, 0xA8, tail=4)
        S.note(1, 2, F(bar), F(bar, 3.8), nhz(root - 12), TRI, 0x08, 0xF8, tail=4)           # the sub
    S.note(1, 2, F(END), F(END + 1.5), nhz(45 - 12), TRI, 0x08, 0xF8, tail=60)
    S.note(1, 0, F(END), F(END + 1.5), nhz(45), SAW, 0x08, 0xF8, tail=60)
    t = np.arange(N)
    S.route[:, 1] = 3; S.mode[:, 1] = LP; S.res[:, 1] = 9
    S.cut[:, 1] = 420 + 260 * (0.5 + 0.5 * np.sin(2 * np.pi * (t - FC) / (BAR * 2)))
    # ---- SID 3: the arpeggio - 16ths up the chord, pulse sweeping; an echo on voice 1 three 16ths later
    for bar in range(0, END):
        _, _, ch = chord_at(bar)
        pat = [ch[0] + 12, ch[1] + 12, ch[2] + 12, ch[0] + 24, ch[2] + 12, ch[1] + 12]
        for k in range(16):
            f = F(bar, k * 0.25); n = pat[(bar * 16 + k) % 6]
            pwf = lambda q, f=f: 600 + 1500 * (0.5 + 0.5 * math.sin((f + q) / 40.0))
            S.note(2, 0, f, f + 4, nhz(n), PUL, 0x00, 0x86, pw=pwf, tail=2)
            if bar >= 8: S.note(2, 1, f + 18, f + 22, nhz(n), PUL, 0x00, 0x64, pw=pwf, tail=2)
    S.route[:, 2] = 3; S.mode[:, 2] = LP; S.res[:, 2] = 4
    S.cut[:, 2] = np.clip(300 + (t - FC) * 0.9, 300, 1500)                   # opens over the intro
    # ---- SID 4: the pad - the chord on 3 saws, slow, low-passed
    for bar in range(0, END, 2):
        _, _, ch = chord_at(bar)
        for v in range(3):
            S.note(3, v, F(bar), F(bar + 2) - 3, nhz(ch[v]) * (1 + 0.002 * (v - 1)), SAW, 0x8A, 0xC9, tail=20)
    for v, n in enumerate((57, 60, 64)):
        S.note(3, v, F(END), F(END + 1.6), nhz(n), SAW, 0x6A, 0xC9, tail=70)
    S.route[:, 3] = 7; S.mode[:, 3] = LP; S.res[:, 3] = 6
    S.cut[:, 3] = 500 + 450 * (0.5 - 0.5 * np.cos(2 * np.pi * (t - FC) / (BAR * 8)))
    # ---- SID 5: the lead; SID 6 its echo (a dotted 8th later, a triangle)
    MEL_A = [[(0, 1.5, 76), (1.5, .5, 74), (2, 1, 72), (3, 1, 74), (4, 2, 76), (6, 2, 69)],
             [(0, 1.5, 72), (1.5, .5, 74), (2, 1, 76), (3, 1, 77), (4, 3, 76), (7, 1, 72)],
             [(0, 1.5, 79), (1.5, .5, 77), (2, 1, 76), (3, 1, 74), (4, 2, 72), (6, 1, 74), (7, 1, 76)],
             [(0, 2, 74), (2, 1, 71), (3, 1, 67), (4, 4, 74)]]
    MEL_B = [[(0, .5, 81), (.5, .5, 79), (1, 1, 76), (2, .5, 79), (2.5, .5, 81), (3, 1, 84), (4, 3, 83), (7, 1, 81)],
             [(0, 1, 77), (1, 1, 81), (2, 1, 84), (3, 1, 81), (4, 2, 79), (6, 2, 77)],
             [(0, .5, 79), (.5, .5, 81), (1, 1, 79), (2, 1, 76), (3, 1, 72), (4, 2, 76), (6, 2, 79)],
             [(0, 1, 83), (1, 1, 81), (2, 1, 79), (3, 1, 74), (4, 3, 79), (7, 1, 76)]]
    SCALE = [57, 59, 60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83, 84, 86, 88, 89, 91]
    def third_below(n):
        i = SCALE.index(n) if n in SCALE else min(range(len(SCALE)), key=lambda k: abs(SCALE[k] - n))
        return SCALE[max(0, i - 2)]
    def vibr(hz):
        return lambda k: hz * (1 + 0.004 * math.sin(2 * math.pi * k / 8.0) * min(1, max(0, (k - 10) / 12.0)))
    def lead(bar0, mel, up=0, harm=False):
        for ph, notes in enumerate(mel):
            for (b, l, n) in notes:
                f0 = F(bar0 + ph * 2, b); f1 = f0 + max(6, int(l * BEAT) - 2); m = n + up
                S.note(4, 0, f0, f1, vibr(nhz(m)), PUL, 0x14, 0xB8, pw=lambda k: 1000 + 700 * math.sin(k / 9.0), tail=10)
                if harm: S.note(4, 1, f0, f1, vibr(nhz(third_below(m))), SAW, 0x14, 0x98, tail=10)
                S.note(5, ph % 2, f0 + 18, f1 + 18, vibr(nhz(m + 12)), TRI, 0x14, 0x88, tail=16)
    lead(8, MEL_A); lead(16, MEL_B); lead(24, MEL_A, up=12, harm=True)
    S.note(4, 0, F(END), F(END + 1.6), vibr(nhz(81)), PUL, 0x14, 0xB8, pw=1400, tail=70)
    S.note(4, 1, F(END), F(END + 1.6), vibr(nhz(76)), SAW, 0x14, 0x98, tail=70)
    # ---- SID 7: bells - off-beat sparkles from bar 16
    for bar in range(16, END):
        _, _, ch = chord_at(bar)
        for k, b in enumerate((0.75, 1.75, 2.5, 3.75)):
            n = ch[(bar + k) % 3] + 24
            S.note(6, k % 3, F(bar, b), F(bar, b) + 3, nhz(n), TRI, 0x00, 0x09, tail=40)
    # ---- SID 8: effects - crashes at each new section, a rising noise before them, a tom fill into the last part
    def crash(f): S.drum(7, 0, f, [(NOI, 9000, 0), (NOI, 7600, 0), (NOI, 7000, 0)], 0x0B, 0x00, 3)
    for b in (8, 16, 24, END): crash(F(b))
    for b in (7, 15, 23):
        f0 = F(b); S.note(7, 1, f0, f0 + BAR - 4, lambda k: 1500 + k * 90, NOI, 0xB0, 0xF0, tail=4)
    for k, b in enumerate((3.0, 3.25, 3.5, 3.75)):
        f = F(23, b); S.drum(7, 2, f, [(NOI, 2600, 0), (TRI, 260 - 40 * k, 0), (TRI, 220 - 40 * k, 0), (TRI, 190 - 35 * k, 0), (TRI, 170 - 30 * k, 0)], 0x07, 0x00, 6)
    S.route[:, 7] = 2; S.mode[:, 7] = HP | LP; S.cut[:, 7] = 1600; S.res[:, 7] = 2
    # the end: everything fades over the last chord
    fe = F(END)
    for c in range(8): S.vol[fe:, c] = np.round(S.vol[fe:, c] * np.linspace(1, 0.2, N - fe))
    S.vol[TONE - 12:TONE, :] = 15
    r = regs_soft(S, hard={0, 1, 2, 6, 7})
    m = meters(r)
    stream = r[:, [0, 1, 4, 5, 2, 3, 6, 7], :]                     # into the DMA order (D400 D420 D480 D4A0 D500 D520 D580 D5A0)
    return stream, m

if __name__ == '__main__':
    st, m = build()
    print(N, st.shape, 'meters max', m.max(axis=0))
