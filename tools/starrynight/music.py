# STARRY NIGHT build 2 - the music: Erik Satie, Gymnopedie No. 1 (1888, public domain), arranged for 8 SIDs by Mong00se.
# Written from Satie's own score (the bars below) - not from any recording or other arrangement. The PC only prepares data:
# this script renders the arrangement to SID register frames (2520 frames, exactly the camera loop, 8 SIDs x 32 bytes:
# registers $00-$18 and zeros) -> music.bin; the 6502 plays them from the REU, 4 DMA transfers of 64 bytes a frame.
#
#   SID 1 (n=0) melody: pulse + triangle, slow attack, delayed vibrato, tiny slides      SID 2 (n=1) bass: soft triangle (+ octave)
#   SID 3 (n=2) chords: soft pulses, gentle PWM, low-passed                              SID 4 (n=3) string pad: filtered saws
#   SID 5 (n=4) harp: plucked arpeggios                                                 SID 6 (n=5) horns: warm filtered pulse
#   SID 7 (n=6) soft timpani (wavetable)                                                SID 8 (n=7) shimmer: high quiet stars
#
# Lent et douloureux, 3/4: a beat is 42 frames (71.6 a minute), a bar 126, the loop 20 bars = 2520 frames.
# The score used (bar numbers as in the printed score):
#   bars 1-4    the accompaniment alone: G major 7 (bass G2 on beat 1, chord B3 D4 F#4 on beats 2-3) and D major 7 (D2; A3 C#4 F#4)
#   bars 5-12   the first melody phrase: 5 rest F#5 A5 | 6 G5 F#5 C#5 | 7 B4 C#5 D5 | 8 A4 (dotted half) | 9-12 F#4 held (tied)
#   bars 13-19  the second phrase: 13-16 as 5-8 | 17 C#5 | 18 F#5 | 19 E5 (dotted halves)
#   bar 20      the accompaniment only (D major 7), resolving; the melody's continuation after bar 19 is NOT invented here.
# Picture sync (frames): 25-185 wipe in, 185 title, 385 glide, 585 pan, 1685 zoom into the moon, 1835 hold, 1935 zoom out,
# 2185 credit, 2360 wipe out, 2460 black. Bars: 1 = 0, 2 = 126, 5 = 504 (melody enters at 546), 13 = 1512, 14 = 1638 (the zoom
# starts on its beat 2 = 1680), 16 = 1890, 19 = 2268, 20 = 2394.
# No pitch bends, no detuned doubles; every SID follows the bar's chord (checked by clashes() below).
# SID technique: hard restart (gate off and ADSR 0 two frames before a note, test bit the frame before), envelopes, PWM,
# filter sweeps, delayed vibrato, slides, a wavetable drum. All notes have rung out by the last frame, and the SID volumes
# are the same on the last frame as on the first, so the loop point makes no click.
import math, sys
import numpy as np
CLK = 985248
N = 2520; BEAT = 42; BAR = 126
def fr(hz): return max(0, min(65535, int(round(hz * 16777216 / CLK))))
def nhz(n): return 440 * 2 ** ((n - 69) / 12)
SAW, PUL, TRI, NOI = 0x20, 0x40, 0x10, 0x80
LP, BP, HP = 0x10, 0x20, 0x40
def bf(bar, beat=0.0): return (bar - 1) * BAR + int(round(beat * BEAT))

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
        for f in range(f0 + len(steps), min(s.N, f0 + glen + 40)):
            s.freq[f, c, v] = last[1]; s.pw[f, c, v] = last[2]; s.wave[f, c, v] = last[0]; s.ad[f, c, v] = ad; s.sr[f, c, v] = sr
    def regs(s):
        g = s.gate.copy(); ad = s.ad.copy(); sr = s.sr.copy(); wv = s.wave.copy()
        rise = g[1:] & ~g[:-1]
        for f, c, v in zip(*np.nonzero(rise)):
            f += 1                                   # the frame the gate comes on
            assert f >= 3, 'a note may not start in the first frames of the loop'
            for k in (1, 2):                         # hard restart: gate off, ADSR 0 two frames before
                g[f - k, c, v] = False; ad[f - k, c, v] = 0; sr[f - k, c, v] = 0
            wv[f - 1, c, v] |= 0x08                  # the test bit the frame before
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

def vib(k, delay=22, ramp=18, depth=0.0025, per=9.6):
    """delayed vibrato: 1.0 for the first `delay` frames (0.45 s), then growing to +-depth (0.25 %, 4 cents) at 5.2 Hz"""
    return 1 + depth * math.sin(2 * math.pi * k / per) * min(1.0, max(0.0, (k - delay) / ramp))

def curve(pts):
    t = np.arange(N)
    return np.interp(t, [p[0] for p in pts], [p[1] for p in pts])

# ----------------------------------------------------------------------------------------------- the score
# G major 7 on odd bars, D major 7 on even bars (bar 20 is a D bar, so the loop goes D major 7 -> G major 7)
def is_g(bar): return bar % 2 == 1
BASS = {True: 43, False: 38}                      # G2, D2
CHORD = {True: (59, 62, 66), False: (57, 61, 66)} # B3 D4 F#4 | A3 C#4 F#4
# the melody: (bar, beat, length in beats, midi)   F#5 78, A5 81, G5 79, C#5 73, B4 71, D5 74, A4 69, F#4 66, E5 76
PHRASE1 = [(5, 1, 1, 78), (5, 2, 1, 81), (6, 0, 1, 79), (6, 1, 1, 78), (6, 2, 1, 73), (7, 0, 1, 71), (7, 1, 1, 73), (7, 2, 1, 74),
           (8, 0, 3, 69), (9, 0, 12, 66)]
PHRASE2 = [(13, 1, 1, 78), (13, 2, 1, 81), (14, 0, 1, 79), (14, 1, 1, 78), (14, 2, 1, 73), (15, 0, 1, 71), (15, 1, 1, 73), (15, 2, 1, 74),
           (16, 0, 3, 69), (17, 0, 3, 73), (18, 0, 3, 78), (19, 0, 3, 76)]
MELODY = PHRASE1 + PHRASE2

def build():
    S = Song(N); t = np.arange(N)
    # ================================================================ SID 1 (n=0): the melody
    c = 0
    S.route[:, c] = 0x07; S.mode[:, c] = LP; S.res[:, c] = 0
    S.cut[:, c] = 1900 + 250 * np.sin(t / 150.0)                 # the pulses (voices 0,1) are rounded off a little
    prev_end, prev_n = -99, None
    for i, (bar, beat, ln, n) in enumerate(MELODY):
        f0 = bf(bar, beat); dur = int(ln * BEAT)
        f1 = f0 + dur - (5 if ln <= 1 else (8 if ln <= 3 else 20))
        def hz(k, n=n):                                           # no pitch bends: every note is on its pitch from the first frame
            return nhz(n) * vib(k, delay=22 if n > 70 else 30)
        v = i % 3                                                 # three voices in turn: each note's release rings under the next
        S.note(c, v, f0, f1, hz, PUL, 0x68, 0xD9, pw=lambda k, i=i: 1900 + 450 * math.sin(k / 19.0 + i), tail=45)
        prev_end, prev_n = f0 + dur, n
    S.vol[:, c] = 15
    # ================================================================ SID 2 (n=1): the bass
    c = 1
    S.vol[:, c] = 15
    for bar in range(1, 21):
        f0 = bf(bar) + (3 if bar == 1 else 0)
        r = BASS[is_g(bar)]
        ln = 62 if bar < 20 else 80
        S.note(c, 0, f0, f0 + ln, nhz(r), TRI, 0x39, 0xB8 if bar != 20 else 0xB9, tail=40)
        S.note(c, 1, f0, f0 + ln - 4, nhz(r + 12), TRI, 0x39, 0x88, tail=40)
        S.note(c, 2, f0 + 1, f0 + ln - 8, nhz(r + 24), TRI, 0x39, 0x48, tail=40)      # two octaves up: a phone speaker hears the bass by this
    # ================================================================ SID 3 (n=2): the chords
    c = 2
    S.route[:, c] = 0x07; S.mode[:, c] = LP; S.res[:, c] = 2
    S.cut[:, c] = 1250 + 350 * np.sin(t / 120.0)
    S.vol[:, c] = 9
    for bar in range(1, 21):
        g = is_g(bar)
        for v, n in enumerate(CHORD[g]):
            f0 = bf(bar, 1) + 2 * v + (1 if v == 2 else 0)
            f1 = bf(bar + 1) - 8 if bar < 20 else bf(20, 1) + 56
            sus = 0x6 if bar < 13 or bar > 17 else 0x7
            S.note(c, v, f0, f1, nhz(n), PUL, 0x38, (sus << 4) | 0x8,
                   pw=lambda k, v=v, bar=bar: 2048 + 520 * math.sin(k / 23.0 + v * 2.1 + bar), tail=22)
    # ================================================================ SID 4 (n=3): the string pad (filtered saws)
    c = 3
    S.route[:, c] = 0x07; S.mode[:, c] = LP; S.res[:, c] = 4
    swell = np.interp(t, [0, 400, 1300, 1500, 1700, 1935, 2185, 2400, 2519], [0, 0, .25, .7, 1.0, 1.0, .35, 0, 0])
    # build 4 (Neal: a slight 'drilling' on the right): the filter was nearly open, so the saws' upper harmonics beat against
    # each other ~12 Hz (D4's 5th vs F#4's 4th harmonic). The filter now sits low (about 1-2 kHz) and still breathes.
    S.cut[:, c] = 200 + 70 * np.sin(2 * np.pi * t / 252.0 - 1.2) + 160 * swell
    # D4 and F#4 are in both chords, so two voices hold them all through; the third voice breathes the bar's colour (B3 / A3)
    S.note(c, 0, 96, 2430, lambda k: nhz(62), SAW, 0xB0, 0xA0 | 0xB, tail=90)
    S.note(c, 1, 100, 2430, lambda k: nhz(66), TRI, 0xB0, 0xA0 | 0xB, tail=90)           # build 4: triangle (fewer harmonics to beat)
    for bar in range(1, 20):
        f0 = bf(bar) + 2
        if bar < 2: continue
        f1 = f0 + 80 if bar < 19 else f0 + 60
        S.note(c, 2, f0, f1, nhz(59 if is_g(bar) else 57), SAW, 0xA0, 0xA0 | 0x9, tail=40)
    S.note(c, 2, bf(20) + 2, bf(20) + 60, nhz(57), SAW, 0xA0, 0xA0 | 0x9, tail=50)
    padvol = np.interp(t, [0, 120, 400, 1300, 1500, 1700, 1935, 2200, 2400, 2519], [6, 6, 9, 10, 12, 15, 15, 11, 7, 6])
    S.vol[:, c] = padvol
    # ================================================================ SID 5 (n=4): the harp
    c = 4
    S.route[:, c] = 0x07; S.mode[:, c] = LP; S.res[:, c] = 1
    S.vol[:, c] = 6                                          # build 3: much quieter (was 15)
    HARP = {True: [55, 62, 66, 71, 74, 78], False: [50, 57, 61, 66, 69, 73]}      # G3 D4 F#4 B4 D5 F#5 | D3 A3 C#4 F#4 A4 C#5
    plucks = []
    def ripple(bar, beat, lo, hi, gap=5, up=True, off=0):
        notes = HARP[is_g(bar)][lo:hi]
        if not up: notes = notes[::-1]
        f = bf(bar, beat) + off
        for j, n in enumerate(notes):
            plucks.append((f + gap * j, n))
    # build 3 (Neal: the arp was out of place and too loud): only a few slow, soft ripples - the entrance and the swell
    ripple(2, 1.5, 0, 4, gap=9)                              # the title shows: the harp enters, softly
    ripple(14, 0, 0, 4, gap=9); ripple(16, 0, 0, 4, gap=9)   # the swell into the moon zoom
    ripple(20, 0.2, 0, 5, gap=9)                            # the last slow ripple, resolving on D major 7
    plucks.sort()
    hv = 0
    ctrig = np.zeros(N)
    for f, n in plucks:
        if f > N - 80: continue
        S.note(c, hv % 3, f, f + 8, nhz(n), PUL, 0x08, 0x0A,
               pw=lambda k, n=n: 1500 + 700 * min(1.0, k / 20.0), tail=60)
        hv += 1
        ctrig[f:] += np.exp(-np.arange(N - f) / 14.0)
    S.cut[:, c] = 700 + 800 * np.clip(ctrig, 0, 1.6)             # each pluck opens the filter, then it closes
    # ================================================================ SID 6 (n=5): the horns (the melody an octave down, second phrase)
    c = 5
    S.route[:, c] = 0x07; S.mode[:, c] = LP; S.res[:, c] = 3
    S.cut[:, c] = 950 + 200 * np.sin(t / 90.0)
    S.vol[:, c] = np.interp(t, [0, 1500, 1512, 1700, 1935, 2200, 2400, 2519], [10, 10, 11, 15, 15, 12, 10, 10])
    prev_end, prev_n = -99, None
    for i, (bar, beat, ln, n) in enumerate(PHRASE2):
        f0 = bf(bar, beat) + 2; dur = int(ln * BEAT)
        f1 = f0 + dur - (8 if ln <= 1 else 14)
        m = n - 12
        def hz(k, m=m):
            return nhz(m) * vib(k, delay=26, depth=0.0020)
        v = i % 3
        S.note(c, v, f0, f1, hz, PUL, 0x88, 0xA9, pw=lambda k, i=i: 1400 + 350 * math.sin(k / 25.0 + i), tail=45)
        prev_end, prev_n = f0 + dur - 2, m
    # ================================================================ SID 7 (n=6): soft timpani
    c = 6
    S.vol[:, c] = 15
    def timp(f, hzv, v=0):
        steps = [(NOI, 2400, 0x800), (PUL, hzv, 0x600), (TRI, hzv, 0)]            # a noise click, then the pitch itself (no drop)
        S.drum(c, v, f, steps, 0x0A, 0x0A, 14)
    D3, G3 = 146.83, 196.0
    timp(bf(13), G3); timp(bf(14, 1), D3, 1); timp(bf(15), G3); timp(bf(16), D3, 1)
    timp(bf(17), G3, 0); timp(bf(20) + 12, D3, 1)
    # ================================================================ SID 8 (n=7): the shimmer - high quiet stars
    c = 7
    S.route[:, c] = 0; S.mode[:, c] = 0
    S.vol[:, c] = 12
    STAR = {True: [90, 95, 98, 102, 78 + 12], False: [86, 90, 93, 97, 102]}        # F#6 B6 D7 F#7.. | D6 F#6 A6 C#7 F#7
    rng = np.random.default_rng(1888)
    stars = []
    dens = lambda bar: 0 if bar < 3 else (1 if bar < 5 else (2 if bar < 13 else (3 if bar < 17 else (2 if bar < 20 else 1))))
    for bar in range(3, 21):
        d = dens(bar); g = is_g(bar)
        # slots in the bar (frames): d twinkles, away from the downbeat, nothing in the last 70 frames of the loop
        slots = sorted(rng.choice([21, 36, 52, 63, 78, 94, 105], size=d, replace=False))
        for sl in slots:
            f = (bar - 1) * BAR + int(sl)
            if f > N - 70: continue
            tones = STAR[g]
            pat = rng.permutation(len(tones))[:3]
            n0 = tones[int(pat[0])]
            stars.append((f, n0, 0))
            stars.append((f + 9, tones[int(pat[1])], 1))
            if d >= 2: stars.append((f + 18, tones[int(pat[2])], 2))
    for f, n, e in sorted(stars):
        v = int(rng.integers(0, 3)) if False else e
        sus = (0x9, 0x6, 0x3)[e]
        S.note(c, v, f, f + 3, nhz(n), TRI, 0x00, (sus << 4) | 0x9, tail=50)
    S.bad = clashes(S)
    return S.regs()

def clashes(S):
    """every sounding (gated) pitched voice, per frame, must be in the bar's chord or be the melody note (the horns: an octave below it)"""
    bad = set()
    mel = {}
    for bar, beat, ln, n in MELODY:
        for f in range(bf(bar, beat), bf(bar, beat) + int(ln * BEAT)): mel[f] = n % 12
    for f in range(N):
        bar = f // BAR + 1
        ch = {n % 12 for n in ((43, 47, 50, 54) if is_g(bar) else (50, 54, 57, 61))}
        for c in range(8):
            for v in range(3):
                if S.gate[f, c, v] and S.wave[f, c, v] != NOI and S.freq[f, c, v] > 0:
                    pc = int(round(12 * math.log2(S.freq[f, c, v] / 440) + 69)) % 12
                    if pc not in ch and mel.get(f) != pc and mel.get(f - 6) != pc: bad.add((f, c, v, pc))
    return sorted(bad)

if __name__ == '__main__':
    r = build()
    out = sys.argv[1] if len(sys.argv) > 1 else 'music.bin'
    r = r[:, [0, 1, 4, 5, 2, 3, 6, 7], :]               # the order of the DMA windows: SID 0,1 | 4,5 | 2,3 | 6,7
    r.reshape(N * 256).tofile(out)
    print('music: %d frames x 8 SIDs x 32 bytes = %d bytes -> %s' % (N, N * 256, out))
