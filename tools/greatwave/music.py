# GREAT WAVE - the music: "Soran Bushi" (traditional Japanese fishermen's song, public domain), an original arrangement for
# 8 SIDs by Mong00se. The PC only prepares data: this script renders the arrangement to SID register frames
# (2550 frames, exactly the camera loop, 8 SIDs x 32 bytes: registers $00-$18 and zeros) -> music.bin; the 6502 plays them
# from the REU, 4 DMA transfers of 64 bytes a frame (the SIDs' 32-byte windows are side by side).
#   SID 1 taiko (wavetable drums)       SID 2 small drums, rim, clicks     SID 3 rowing bass (D and A on the beat)
#   SID 4 koto (plucked pulses)         SID 5 shakuhachi-like lead         SID 6 harmony / answer lead
#   SID 7 pad (filtered saws)           SID 8 the sea (filtered noise, kept low and minimal)
# 120 bpm: a beat is 25 frames, a bar 100. Key D minor pentatonic (D F G A C).
# SID technique here: hard restart (gate off and ADSR 0 two frames before a note, test bit the frame before), wavetable
# drums (noise frame, then pulse/triangle dropping), PWM, 50 Hz arpeggios, delayed vibrato, slides, filter sweeps.
import math, sys
import numpy as np
CLK = 985248
N = 2550; BEAT = 25; BAR = 100
def fr(hz): return max(0, min(65535, int(round(hz * 16777216 / CLK))))
def nhz(n): return 440 * 2 ** ((n - 69) / 12)
SAW, PUL, TRI, NOI = 0x20, 0x40, 0x10, 0x80
LP, BP, HP = 0x10, 0x20, 0x40
PENT = [0, 3, 5, 7, 10]                  # D F G A C above D
def pent_down(n, steps):
    """n (midi, in D minor pentatonic) moved down by steps of the scale"""
    r = (n - 62) % 12; o = (n - 62) // 12
    i = PENT.index(r) if r in PENT else min(range(5), key=lambda k: abs(PENT[k] - r))
    j = o * 5 + i - steps
    return 62 + (j // 5) * 12 + PENT[j % 5]

class Song:
    def __init__(s, N):
        s.N = N
        s.freq = np.zeros((N, 8, 3)); s.pw = np.full((N, 8, 3), 2048.0); s.wave = np.zeros((N, 8, 3), int)
        s.gate = np.zeros((N, 8, 3), bool); s.ad = np.zeros((N, 8, 3), int); s.sr = np.zeros((N, 8, 3), int)
        s.cut = np.full((N, 8), 1024.0); s.res = np.zeros((N, 8), int); s.route = np.zeros((N, 8), int)
        s.mode = np.zeros((N, 8), int); s.vol = np.zeros((N, 8))
    def note(s, c, v, f0, f1, hz, wave, ad, sr, pw=2048, tail=30):
        f0 = max(0, f0); f1 = min(s.N, f1)
        if f0 >= f1: return
        for f in range(f0, min(s.N, f1 + tail)):
            h = hz(f - f0) if callable(hz) else hz
            p = pw(f - f0) if callable(pw) else pw
            s.freq[f, c, v] = h; s.pw[f, c, v] = p; s.wave[f, c, v] = wave; s.ad[f, c, v] = ad; s.sr[f, c, v] = sr
        s.gate[f0:f1, c, v] = True
    def drum(s, c, v, f0, steps, ad, sr, glen):
        """a wavetable: steps = [(wave, hz, pw)] one per frame; the gate is on for glen frames"""
        for k, (w, h, p) in enumerate(steps):
            f = f0 + k
            if 0 <= f < s.N:
                s.freq[f, c, v] = h; s.pw[f, c, v] = p; s.wave[f, c, v] = w; s.ad[f, c, v] = ad; s.sr[f, c, v] = sr
        for k in range(glen):
            if 0 <= f0 + k < s.N: s.gate[f0 + k, c, v] = True
        last = steps[-1]
        for f in range(f0 + len(steps), min(s.N, f0 + glen + 20)):
            s.freq[f, c, v] = last[1]; s.pw[f, c, v] = last[2]; s.wave[f, c, v] = last[0]; s.ad[f, c, v] = ad; s.sr[f, c, v] = sr
    def regs(s):
        g = s.gate.copy(); ad = s.ad.copy(); sr = s.sr.copy(); wv = s.wave.copy()
        rise = g[1:] & ~g[:-1]
        for f, c, v in zip(*np.nonzero(rise)):
            f += 1                                   # the frame the gate comes on
            for k in (1, 2):                         # hard restart: gate off, ADSR 0 two frames before
                if f - k >= 0: g[f - k, c, v] = False; ad[f - k, c, v] = 0; sr[f - k, c, v] = 0
            if f - 1 >= 0: wv[f - 1, c, v] |= 0x08   # the test bit the frame before
        out = np.zeros((s.N, 8, 32), np.uint8)
        for c in range(8):
            for v in range(3):
                o = v * 7
                fq = np.array([fr(h) for h in s.freq[:, c, v]])
                pw = np.clip(s.pw[:, c, v], 0, 4095).astype(int)
                out[:, c, o] = fq & 255; out[:, c, o + 1] = fq >> 8
                out[:, c, o + 2] = pw & 255; out[:, c, o + 3] = pw >> 8
                out[:, c, o + 4] = (wv[:, c, v] & 0xFE) | g[:, c, v]
                out[:, c, o + 5] = ad[:, c, v]; out[:, c, o + 6] = sr[:, c, v]
            ct = np.clip(s.cut[:, c], 0, 2047).astype(int)
            out[:, c, 21] = ct & 7; out[:, c, 22] = ct >> 3
            out[:, c, 23] = (s.res[:, c] << 4) | s.route[:, c]
            out[:, c, 24] = s.mode[:, c] | np.clip(np.round(s.vol[:, c]), 0, 15).astype(int)
        return out

# ------------------------------------------------------------------------------------------------- the form (bars of 100 frames)
# 0-3 intro | 4-7 A | 8-11 B | 12 chant | 13-16 A' (lead an octave up, harmony) | 17-20 B' | 21 turn | 22-23 chant | 24-25 outro
A_MEL = [[(0, 1, 69), (1, .5, 69), (1.5, .5, 72), (2, 1, 69), (3, 1, 67)],
         [(0, .5, 69), (.5, .5, 69), (1, .5, 67), (1.5, .5, 69), (2, 1, 72), (3, 1, 69)],
         [(0, 1, 74), (1, .5, 72), (1.5, .5, 69), (2, .5, 67), (2.5, .5, 69), (3, 1, 67)],
         [(0, .5, 65), (.5, .5, 67), (1, 1, 69), (2, 2, 62)]]
B_MEL = [[(0, .5, 62), (.5, .5, 65), (1, 1, 67), (2, 1, 69), (3, 1, 69)],
         [(0, .5, 72), (.5, .5, 69), (1, .5, 67), (1.5, .5, 65), (2, 2, 67)],
         [(0, 1, 69), (1, 1, 72), (2, .5, 74), (2.5, .5, 72), (3, 1, 69)],
         [(0, .5, 67), (.5, .5, 69), (1, .5, 67), (1.5, .5, 65), (2, 2, 62)]]
CHANT = [0, .5, 2, 2.5]
def ef(bar, beat): return int(round(bar * BAR + beat * BEAT))

def build():
    S = Song(N); t = np.arange(N)
    # ----- dynamics (master volumes by frame): the picture's story
    pts = [(0, .80), (25, .8), (185, .95), (385, .85), (615, .80), (1500, 1.0), (1615, .62), (1700, .62), (1715, 1.0), (1865, .9),
           (1965, .85), (2215, 1.0), (2390, 1.0), (2490, .45), (2520, .55), (2549, .85)]
    dyn = np.interp(t, [p[0] for p in pts], [p[1] for p in pts])
    # ----- SID 1: taiko
    def don(f, big=1.0, v=0, soft=False):
        top = 230 if big > 1 else 190
        steps = [(NOI, 2400, 0x800), (PUL, top, 0x800), (PUL, top * .72, 0x800), (TRI, top * .52, 0), (TRI, top * .40, 0), (TRI, top * .33, 0),
                 (TRI, top * .29, 0), (TRI, 60, 0), (TRI, 52, 0)]
        S.drum(0, v, f, steps, 0x08 if not soft else 0x06, 0x00, 12 if not soft else 8)
    def ka(f):
        S.drum(0, 2, f, [(NOI, 6500, 0), (PUL, 420, 0x400), (PUL, 330, 0x400), (TRI, 270, 0)], 0x04, 0x00, 5)
    def roll(f0, f1, v0=0):
        f = f0; k = 0; iv = 12.0
        while f < f1:
            don(int(f), 1.0, v=(k % 2), soft=True); k += 1
            iv = max(4.5, iv * 0.9); f += iv
    # ----- SID 2: small drums
    def rim(f): S.drum(1, 0, f, [(NOI, 7000, 0), (PUL, 1100, 0x400), (TRI, 800, 0), (TRI, 650, 0)], 0x03, 0x00, 4)
    def tick(f, v=1): S.drum(1, v, f, [(NOI, 9000, 0), (NOI, 6500, 0)], 0x02, 0x00, 2)
    def tom(f): S.drum(1, 2, f, [(NOI, 3000, 0), (PUL, 330, 0x800), (PUL, 250, 0x800), (TRI, 200, 0), (TRI, 160, 0), (TRI, 140, 0)], 0x05, 0x00, 7)
    # ----- SID 3: rowing bass
    def bass(f, n, ln=19, oct_up=True):
        S.note(2, 0, f, f + ln, nhz(n), PUL, 0x06, 0x96, pw=lambda k: 1400 + 500 * math.sin(k / 5.0), tail=8)
        if oct_up: S.note(2, 1, f, f + ln - 3, nhz(n + 12), SAW, 0x05, 0x84, tail=6)
    S.route[:, 2] = 3; S.mode[:, 2] = LP; S.res[:, 2] = 3; S.cut[:, 2] = 520 + 200 * np.sin(t / 60.0)
    # ----- SID 4: koto
    def pluck(f, n, ln=9, v=0):
        S.note(3, v, f, f + ln, nhz(n), PUL, 0x07, 0x05,                      # build 3: no pitch bend on the pluck
               pw=lambda k: 900 + 500 * min(1, k / 12.0), tail=14)
    KSET = {'d': [62, 65, 69, 74], 'g': [67, 69, 74, 79], 'c': [67, 72, 74, 79], 'a': [65, 69, 72, 77]}
    kn = lambda n: n + 12 if n < 72 else n
    def koto_bar(bar, chord, dens):
        ns = [n for n in KSET[chord]]
        if dens == 'q':
            for i, ix in enumerate([0, 2, 1, 3]): pluck(ef(bar, i), kn(ns[ix]), v=i % 3)
        elif dens == 'h':
            pluck(ef(bar, 0), kn(ns[0]), v=0); pluck(ef(bar, 2), kn(ns[2]), v=1)
        else:
            for i, ix in enumerate([0, 2, 1, 3, 2, 3, 1, 2]): pluck(ef(bar, i * .5), kn(ns[ix]), 7, v=i % 3)
    S.route[:, 3] = 7; S.mode[:, 3] = LP; S.res[:, 3] = 2; S.cut[:, 3] = 1500
    # ----- SID 5 / 6: leads
    def lead(c, f0, ln, n, prev, vib=True, v=0, breath=True, ad=0x35, sr=0xA6, wave=PUL, pwb=1700, gl=2):
        f1 = f0 + max(5, int(ln * BEAT) - 3)
        start = n                                                       # build 3: no slides into notes (they read as out of tune)
        def hz(k):
            sl = (n - start) * (1 - min(1, k / 3.0)) if start != n else 0
            vb = (1 + 0.0025 * math.sin(2 * math.pi * k / 9.0) * min(1, max(0, (k - 12) / 14.0))) if vib else 1
            return nhz(n - sl) * vb
        S.note(c, v, f0, f1, hz, wave, ad, sr, pw=lambda k: pwb + 700 * math.sin(k / 7.0 + c))
        if breath and ln >= .5:
            S.note(c, 1, f0, f0 + 4, 3600, NOI, 0x04, 0x00, tail=6)
        # build 3: no detuned double on the lead (it sounded sour)
    S.route[:, 4] = 2; S.mode[:, 4] = BP; S.res[:, 4] = 5; S.cut[:, 4] = 900
    S.route[:, 5] = 0
    def play_mel(bar0, mel, shift, c, harm=None, delay=0):
        prev = None
        for b, bar in enumerate(mel):
            for beat, ln, n in bar:
                f0 = ef(bar0 + b, beat) + delay
                m = n + shift
                if c == 5 and harm is not None: m = harm(n) + shift
                lead(c, f0, ln, m, prev if beat != 0 or b else None, v=0, breath=(c == 4),
                     ad=0x35 if c == 4 else 0x46, sr=0xA6 if c == 4 else 0x96,
                     wave=PUL if c == 4 else TRI, pwb=1700 if c == 4 else 2048)
                prev = m
    # ----- SID 7: pad
    S.route[:, 6] = 7; S.mode[:, 6] = LP; S.res[:, 6] = 5
    S.cut[:, 6] = 420 + 330 * (0.5 + 0.5 * np.sin(t / 80.0))
    CH = {'D': [50, 57, 65], 'G': [55, 62, 69], 'C': [48, 55, 62], 'Dh': [50, 57, 62]}
    def pad(b0, b1, ch):
        for v, n in enumerate(CH[ch]):
            S.note(6, v, b0 * BAR + 2, b1 * BAR - 4, nhz(n), SAW, 0x98, 0xE8, tail=40)
    # ----- SID 8: the sea
    S.route[:, 7] = 3; S.mode[:, 7] = LP; S.res[:, 7] = 0
    S.note(7, 0, 0, N, 3300, NOI, 0x00, 0xF0)
    S.note(7, 1, 0, N, 1100, NOI, 0x00, 0xF0)
    S.cut[:, 7] = 230 + 170 * np.sin(t / 90.0) + 120 * np.sin(t / 37.0 + 1)
    sea = 1.3 + 0 * t.astype(float)
    for c0, wd, hgt in ((100, 90, 2.4), (950, 200, 1.6), (2440, 70, 2.6), (40, 40, 1.0)):
        sea += hgt * np.exp(-((t - c0) / wd) ** 2)
    sea *= np.where((t > 400) & (t < 2380), 0.8, 1.0)
    sea += 1.0 * np.exp(-((t - 2549) / 45.0) ** 2)                       # the sea holds on into the loop point
    S.vol[:, 7] = sea

    # ================= the arrangement
    # -- intro (bars 0-3): sea, a drone, taiko, the roll into the title
    don(0, 1.3)
    don(50, soft=True); don(100); don(150, soft=True)
    roll(150, 184); don(185, 1.5, v=0); ka(185); rim(185)
    for b in (1, 2, 3):
        pass
    pad(0, 2, 'D'); pad(2, 4, 'G')
    S.note(2, 2, 25, 395, nhz(26), TRI, 0x58, 0xE8, tail=30)       # the low drone
    for f in (200, 300): don(f);
    for f in (250, 350): don(f, soft=True)
    for b, (n1, n2) in ((2, (74, 69)), (3, (69, 67))):
        pluck(ef(b, 0), n1, 12); pluck(ef(b, 2), n2, 12, v=1)
    for b in (2, 3):
        for i in (1, 3): bass(ef(b, i), 38 if b == 2 else 45, 18, oct_up=False)
    tick(ef(3, 3.5)); tick(ef(3, 2.5))
    # -- A, B, A', B' : bars 4-7, 8-11, 13-16, 17-20
    rows = [(4, 'A', 0), (8, 'B', 0), (13, 'A', 1), (17, 'B', 1)]
    chordsA = ['D', 'D', 'G', 'D']; chordsB = ['D', 'G', 'D', 'D']
    # build 3: every SID on the same chord in each bar (the koto played G and F chords over the pad's D before)
    chordsA = ['D', 'D', 'G', 'D']; chordsB = ['D', 'G', 'D', 'D']
    kA = ['d', 'd', 'g', 'd']; kB = ['d', 'g', 'd', 'd']
    for b0, part, second in rows:
        mel = A_MEL if part == 'A' else B_MEL
        shift = 12 if (second and part == 'A') else 0
        play_mel(b0, mel, shift, 4)
        if second:
            hm = (lambda n: n) if part == 'A' else (lambda n: pent_down(n, 2))
            play_mel(b0, mel, 0, 5, harm=hm, delay=0)
        ch = chordsA if part == 'A' else chordsB
        for b in range(4):
            bb = b0 + b
            # rowing bass: D and A on the beat (A on beats 2 and 4 of the call, D on 1 and 3)
            for i in range(4):
                g = ch[b] == 'G'
                bass(ef(bb, i), (43 if g else 38) if i % 2 == 0 else (50 if g else 45), 19)
            if b % 2 == 0 and not second:
                pass
            # taiko / small drums
            don(ef(bb, 0)); don(ef(bb, 2), soft=True)
            if b % 2 == 1: don(ef(bb, 3.5), soft=True)
            for i in (1, 3): rim(ef(bb, i))
            if part == 'B' or second:
                for i in range(8): tick(ef(bb, i * .5 + .25), v=1)
            # koto
            dens = 'h' if (part == 'A' and not second) else ('q' if part == 'A' else 'e')
            koto_bar(bb, (kA if part == 'A' else kB)[b], dens)
        for b in range(4): pad(b0 + b, b0 + b + 1, ch[b])
    # -- chants: bar 12, and bars 22-23 (the credit), a shout in both channels
    def chant(bar, big=False):
        for b in CHANT:
            f = ef(bar, b)
            S.note(4, 0, f, f + 8, nhz(74), PUL, 0x00, 0xA3, pw=2048, tail=8)
            S.note(5, 0, f, f + 8, nhz(74 if not big else 86), PUL, 0x00, 0x93, pw=1400, tail=8)
            S.note(4, 2, f, f + 6, nhz(62), SAW, 0x00, 0x83, tail=6)
            don(f, 1.3 if b in (0, 2) else 1.0, v=int(b * 2) % 2); rim(f)
            S.note(2, 0, f, f + 8, nhz(38), PUL, 0x00, 0xA3, pw=2048, tail=6)
        for i in range(8): tick(ef(bar, i * .5 + .25))
        S.note(6, 0, bar * BAR + 2, bar * BAR + BAR - 4, nhz(50), SAW, 0x08, 0xF8, tail=20)
        S.note(6, 1, bar * BAR + 2, bar * BAR + BAR - 4, nhz(57), SAW, 0x08, 0xF8, tail=20)
        S.note(6, 2, bar * BAR + 2, bar * BAR + BAR - 4, nhz(62), SAW, 0x08, 0xF8, tail=20)
        for i in range(8): pluck(ef(bar, i * .5), (74, 69, 65, 69, 74, 77, 74, 69)[i], 6, v=i % 3)
    chant(12); chant(22, True); chant(23, True)
    # -- the big hit as the zoom into Fuji starts, the turn before the chants
    don(1715, 1.6, v=1); don(1715, 1.6, v=0); ka(1715); rim(1715); tom(1715)
    # Fuji hold (1615-1715): the call thins out - quieter via the dynamics curve (taiko roll only at the end)
    roll(1680, 1714)
    # bar 21: a turn - koto run and a taiko roll into the chant
    for i in range(10): pluck(2100 + int(i * 8), (62, 65, 67, 69, 72, 74, 77, 79, 81, 86)[i], 9, v=i % 3)
    roll(2150, 2199);
    for i in range(4): bass(ef(21, i), 38 if i % 2 == 0 else 45, 19)
    # -- the crest build: from bar 8 the dynamics curve rises; extra toms on the pan up the crest (frames ~ 900-1100)
    for f in range(1000, 1200, 25): tom(f)
    # -- outro (bars 24-25): resolve to D, a last long note, loop back into the sea and the first don
    don(2400, 1.4); ka(2400); rim(2400)
    S.note(4, 0, 2402, 2475, lambda k: nhz(74) * (1 + 0.005 * math.sin(2 * math.pi * k / 9.0) * min(1, max(0, (k - 12) / 14.0))), PUL, 0x35, 0xA9, pw=lambda k: 1700 + 600 * math.sin(k / 8), tail=40)
    S.note(5, 0, 2405, 2475, nhz(69), TRI, 0x46, 0x99, tail=40)
    pad(24, 25, 'Dh')
    S.note(2, 0, 2402, 2470, nhz(38), PUL, 0x06, 0xA8, pw=1800, tail=40)
    for f in (2430, 2460): pluck(f, 74, 12);
    pluck(2490, 62, 14, v=1); pluck(2520, 74, 12, v=2)
    don(2500, soft=True); roll(2518, 2537)                  # a soft roll into the downbeat of the loop
    S.mode[:, 3] = LP
    # ----- master volumes: base level of each SID x the picture's story
    base = [14, 10, 13, 11, 15, 11, 8, 0]
    for c in range(7): S.vol[:, c] = base[c] * dyn
    S.vol[:, 7] = np.clip(S.vol[:, 7], 0, 15)                  # the sea has its own curve (not the story's)
    return S.regs()

if __name__ == '__main__':
    r = build()
    out = sys.argv[1] if len(sys.argv) > 1 else 'music.bin'
    r = r[:, [0, 1, 4, 5, 2, 3, 6, 7], :]               # the order of the DMA windows: SID 0,1 | 4,5 | 2,3 | 6,7
    r.reshape(N * 256).tofile(out)
    print('music: %d frames x 8 SIDs x 32 bytes = %d bytes -> %s' % (N, N * 256, out))
