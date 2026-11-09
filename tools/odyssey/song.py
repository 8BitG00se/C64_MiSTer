#!/usr/bin/env python3
# (C) 2026 Mong00se. All rights reserved.
# ODYSSEY - the music: "The Blue Danube" (An der schoenen blauen Donau, Op. 314, Johann Strauss II, 1866-67, public domain),
# arranged by Mong00se from the waltz's own melody and harmony (the first waltz's theme, its introduction's horn call).
# One arrangement that opens out:
#   1 SID (stock C64)   voice 1 the melody (a bowed pulse, vibrato), voice 2 the bass ("oom"), voice 3 the "pah-pah" chords
#                       (a 50 Hz arpeggio - the C64's own way to play a chord on one voice)
#   2 SIDs (stereo)     SID 2 adds a string pad (two voices) and a harp (the third), on the right
#   8 SIDs (Octophonic) SIDs 3-8 add high strings, horns, flute, bells, cellos, timpani and pizzicato basses
# SIDs 1 and 2 are played by the 6502's player (player.asm) from the note lists this script writes (song.asm); SIDs 3-8 are
# rendered here to SID register frames (music8.bin: 6 SIDs x 32 bytes a frame) that the Octophonic streams from the REU.
# Both use the same frame timing (the tempo map below), so they stay together.
#   song.py OUTDIR   -> OUTDIR/song.asm, OUTDIR/music8.bin; prints the length in frames
import sys, os, math
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------------------------------------------------- the score
D4, E4, Fs4, G4, Gs4, A4, B4, Cs4 = 62, 64, 66, 67, 68, 69, 71, 61
D5, A5, Fs5, G5, B5, D6 = 74, 81, 78, 79, 83, 86

# the first waltz's theme (bar, beat, beats, note); bar 0 holds the pickup on its third beat
THEME = [(0, 2, 1, D4),
         (1, 0, 1, D4), (1, 1, 1, Fs4), (1, 2, 1, A4), (2, 0, 2, A4), (2, 2, 1, A5), (3, 0, 2, A5), (3, 2, 1, Fs5),
         (4, 0, 2, Fs5), (4, 2, 1, D4),
         (5, 0, 1, D4), (5, 1, 1, Fs4), (5, 2, 1, A4), (6, 0, 2, A4), (6, 2, 1, A5), (7, 0, 2, A5), (7, 2, 1, G5),
         (8, 0, 2, G5), (8, 2, 1, Cs4),
         (9, 0, 1, Cs4), (9, 1, 1, E4), (9, 2, 1, B4), (10, 0, 2, B4), (10, 2, 1, B5), (11, 0, 2, B5), (11, 2, 1, G5),
         (12, 0, 2, G5), (12, 2, 1, Cs4),
         (13, 0, 1, Cs4), (13, 1, 1, E4), (13, 2, 1, B4), (14, 0, 2, B4), (14, 2, 1, B5), (15, 0, 2, B5), (15, 2, 1, Fs5),
         (16, 0, 2, Fs5), (16, 2, 1, D4),
         (17, 0, 1, D4), (17, 1, 1, Fs4), (17, 2, 1, A4), (18, 0, 2, D5), (18, 2, 1, D6), (19, 0, 2, D6), (19, 2, 1, A5),
         (20, 0, 2, A5), (20, 2, 1, D4),
         (21, 0, 1, D4), (21, 1, 1, Fs4), (21, 2, 1, A4), (22, 0, 2, D5), (22, 2, 1, D6), (23, 0, 2, D6), (23, 2, 1, B5),
         (24, 0, 2, B5), (24, 2, 1, E4),
         (25, 0, 1, E4), (25, 1, 1, G4), (25, 2, 1, B4), (26, 0, 4, B4), (27, 1, 1, Gs4), (27, 2, 1, A4),
         (28, 0, 4, Fs5), (29, 1, 1, D5), (29, 2, 1, Fs4),
         (30, 0, 2, Fs4), (30, 2, 1, E4), (31, 0, 2, B4), (31, 2, 1, A4), (32, 0, 2, D4)]
# the harmony of each bar of the theme (root, the chord's notes as pitch classes above it)
CH = {'D': (2, [0, 4, 7]), 'A7': (9, [0, 4, 7, 10]), 'Em': (4, [0, 3, 7]), 'E7': (4, [0, 4, 7, 10]), 'D/A': (2, [0, 4, 7])}
HARM = ['D'] * 8 + ['A7'] * 8 + ['D'] * 8 + ['Em', 'Em', 'Em', 'E7', 'D/A', 'D/A', 'A7', 'A7', 'D']   # bars 0-32

INTRO = 8           # the introduction's bars (its last is the theme's bar 0, the pickup)
P1 = INTRO          # the theme's bar 1, first time
P2 = INTRO + 32     # the theme's bar 1, second time (its bar 0 is the first time's bar 32)
CODA = INTRO + 64   # the coda's first bar
NBARS = CODA + 5    # the coda's 4 bars and a bar of quiet before the loop

def harm(bar):
    """the chord of a song bar"""
    if bar < INTRO: return 'D'
    if bar < P2: return HARM[bar - INTRO + 1]
    if bar < CODA: return HARM[bar - P2 + 1] if bar - P2 + 1 <= 32 else 'D'
    return 'D'

# ------------------------------------------------------------------------------------------- the tempo map (frames)
# a Viennese waltz: the second beat a little early (19, 21, 20 = 60 frames a bar); the introduction slower and even; a
# ritardando into the last bar of the second time, and the coda broad
BEATS = []
for b in range(NBARS):
    if b < INTRO - 1: BEATS.append((23, 23, 23))
    elif b == INTRO - 1: BEATS.append((23, 22, 21))
    elif b in (P2 + 29,): BEATS.append((21, 22, 23))
    elif b in (P2 + 30,): BEATS.append((24, 25, 27))
    elif b == P2 + 31: BEATS.append((30, 30, 30))
    elif b >= CODA: BEATS.append((25, 25, 25))
    else: BEATS.append((19, 21, 20))
BSTART = [0]
for bt in BEATS:
    for f in bt: BSTART.append(BSTART[-1] + f)
NFR = BSTART[-1]
def fr(bar, beat):
    """the frame of a (bar, beat) - beat may be fractional"""
    k = bar * 3 + int(math.floor(beat)); x = beat - math.floor(beat)
    k = min(k, len(BSTART) - 2)
    return int(round(BSTART[k] + x * (BSTART[k + 1] - BSTART[k])))

def theme_notes(at):
    """the theme with its bar 1 at song bar `at` (bar 0, the pickup, at at - 1)"""
    return [(at - 1 + b, bt, d, n) for b, bt, d, n in THEME]

# ------------------------------------------------------------------------------------------- the parts (song bar, beat, beats, note, instrument)
I_MEL, I_HORN, I_BASS, I_PAH, I_TREM, I_PAD, I_HARP, I_PED = range(8)
def part_melody():
    ev = []
    # the introduction's horn call, as Strauss's horns give it before the waltz: D F# A, A - A A - F# F# - D
    call = [(2, 0, 1, D4), (2, 1, 1, Fs4), (2, 2, 1, A4), (3, 0, 3, A4), (4, 1, 1, A4), (4, 2, 1, A4),
            (5, 1, 1, Fs4), (5, 2, 1, Fs4), (6, 0, 3, D4)]
    ev += [(b, bt, d, n, I_HORN) for b, bt, d, n in call]
    first = theme_notes(P1)
    ev += [(b, bt, d, n, I_MEL) for b, bt, d, n in first]
    # bar 32 of the first time is bar 0 of the second: D held two beats, then the pickup D
    second = theme_notes(P2)
    ev += [(b, bt, d, n, I_MEL) for b, bt, d, n in second]
    # the coda: up the D major chord to a long D, the last bar of the second time's D ringing into it
    ev += [(CODA, 1, 1, A4, I_MEL), (CODA, 2, 1, D5, I_MEL), (CODA + 1, 0, 3, Fs5, I_MEL), (CODA + 2, 0, 5.5, D5, I_MEL)]
    ev.sort(key=lambda e: (e[0], e[1]))
    return ev

def bass_note(bar, alt):
    root = CH[harm(bar)][0]
    if harm(bar) == 'D/A': root = 9
    n = root + (7 if alt else 0)
    n = 40 + (n - 40) % 12          # E2 to D#3: low, but the narrow pulse keeps it on phone speakers
    return n

def part_bass():
    ev = [(0, 0, 23.5, 50 - 12, I_PED)]                     # the introduction: a D pedal, very low
    prev = None; alt = False
    for bar in range(INTRO, CODA):
        h = harm(bar)
        alt = (h == prev) and not alt
        prev = h
        if bar == P2 - 1 or bar == CODA - 1:                    # the theme's last bar: D on the beat, held
            ev.append((bar, 0, 2, 50 - 12 + 12, I_BASS)); continue
        ev.append((bar, 0, 1, bass_note(bar, alt), I_BASS))
    ev += [(CODA, 0, 1, 50, I_BASS), (CODA + 1, 0, 1, 45, I_BASS), (CODA + 2, 0, 6, 38, I_PED)]
    return ev

def pah_chord(bar):
    """the chord's notes for the pah-pah, between F#3 and E4"""
    root, pcs = CH[harm(bar)]
    ns = sorted(set(54 + ((root + p - 54) % 12) for p in pcs))
    return ns

def part_pah():
    ev = [(0, 0, 3 * 7 - 0.4, A4 - 12, I_TREM)]                  # the introduction: a shimmer on A (Strauss's tremolo)
    for bar in range(INTRO, CODA):
        if bar == P2 - 1 or bar == CODA - 1:
            ev.append((bar, 1, 1, tuple(pah_chord(bar)), I_PAH)); continue
        for bt in (1, 2):
            ev.append((bar, bt, 1, tuple(pah_chord(bar)), I_PAH))
    for bar in (CODA, CODA + 1):
        for bt in (1, 2): ev.append((bar, bt, 1, tuple(pah_chord(bar)), I_PAH))
    ev.append((CODA + 2, 0, 6, tuple(pah_chord(CODA)), I_PAD))
    return ev

def part_pad(which):
    """SID 2, voices 1 and 2: held strings - the chord's third and fifth (the seventh where there is one), changing
    with the harmony; quiet in the first time, fuller in the second"""
    ev = []
    if which == 0: ev.append((0, 0, 3 * 6.5, Fs4, I_PAD))
    else: ev.append((1, 0, 3 * 5.5, A4, I_PAD))
    bar = INTRO
    while bar < CODA + 3:
        h = harm(bar); e = bar
        while e < CODA + 3 and harm(e) == h and e - bar < 4: e += 1
        root, pcs = CH[h]
        tones = sorted(set(60 + ((root + p - 60) % 12) for p in pcs[1:]))   # third, fifth (seventh) above middle C
        n = tones[0] if which == 0 else tones[-1]
        if bar >= CODA: n = (Fs4, A4)[which]
        ev.append((bar, 0 if which == 0 else 0.5, (e - bar) * 3 - (0 if which == 0 else 0.5), n, I_PAD))
        bar = e
    return ev

def part_harp():
    """SID 2, voice 3: the harp - a roll up the chord at the start of each phrase in the first time, rippling up and
    down the chord in quavers all through the second"""
    ev = [(6, 0, 0.5, D4, I_HARP), (6, 0.5, 0.5, Fs4, I_HARP), (6, 1, 0.5, A4, I_HARP), (6, 1.5, 0.5, D5, I_HARP),
          (6, 2, 1, Fs5, I_HARP)]
    for bar in range(INTRO, CODA + 2):
        root, pcs = CH[harm(bar)]
        ns = sorted(set(62 + ((root + p - 62) % 12) for p in pcs))
        ns = ns + [n + 12 for n in ns]
        if bar < P2:
            if (bar - INTRO) % 4 == 0:
                for k in range(4): ev.append((bar, k * 0.5, 0.5, ns[k], I_HARP))
        else:
            pat = [0, 1, 2, 3, 2, 1] if bar % 2 == 0 else [1, 2, 3, 4, 3, 2]
            for k in range(6): ev.append((bar, k * 0.5, 0.5, ns[min(pat[k], len(ns) - 1)], I_HARP))
    ev.append((CODA + 2, 0, 6, D5, I_HARP))
    return ev

# ------------------------------------------------------------------------------------------- the 6502 player's data
# instruments: wave, AD, SR, pulse width (x16), PWM speed (signed), vibrato delay, vibrato depth (shift: 0 none), flags
# (1 arpeggio, 2 hard restart), gate-off frames before the next note, equaliser peak (0-20)
INSTR = [
    (0x41, 0x27, 0xA9, 0x50, 10, 14, 8, 2, 3, 20),   # 0 melody: a bowed pulse, vibrato after a moment
    (0x41, 0x86, 0xA9, 0x80, 4, 18, 9, 2, 4, 16),    # 1 horn: a broad pulse, a slow attack
    (0x41, 0x0A, 0x00, 0x28, 0, 0, 0, 2, 2, 20),     # 2 bass: a narrow pulse, plucked
    (0x41, 0x05, 0x00, 0x60, 24, 0, 0, 3, 2, 12),    # 3 pah: the chord, arpeggiated every frame, short
    (0x41, 0xA0, 0xC9, 0x20, 48, 30, 9, 0, 6, 12),   # 4 tremolo: a fast-sweeping pulse that swells
    (0x21, 0xA0, 0xB9, 0x80, 0, 26, 9, 0, 6, 12),    # 5 pad: a soft saw, slow in and out
    (0x11, 0x09, 0x00, 0x80, 0, 0, 0, 2, 1, 16),     # 6 harp: a plucked triangle
    (0x41, 0x90, 0xF9, 0x30, 6, 0, 0, 0, 8, 10),     # 7 pedal: a long low pulse that swells
]
VOICES1 = [part_melody(), part_bass(), part_pah()]
VOICES2 = [part_pad(0), part_pad(1), part_harp()]

def compile_voice(ev, shapes):
    """events -> the player's bytes: $00-$5F note (then frames), $60 rest (then frames), $61 hold on (then frames),
    $80+i instrument, $A0+k chord shape, $FF the end (silent until the song starts again)"""
    out = bytearray(); t = 0; inst = None; shape = None
    for bar, bt, d, n, ins in ev:
        f0 = fr(bar, bt); f1 = fr(bar, bt + d) if bar * 3 + bt + d <= NBARS * 3 else NFR
        f1 = min(f1, NFR - 1)
        assert f0 >= t, (bar, bt, f0, t)
        while f0 - t > 0:
            k = min(255, f0 - t); out += bytes([0x60, k]); t += k
        if ins != inst: out.append(0x80 + ins); inst = ins
        if isinstance(n, tuple):
            sh = tuple(x - n[0] for x in n)
            sh = (sh + sh[-1:] * 4)[:4] if len(sh) == 4 else (sh + (12,))[:4]
            if sh not in shapes: shapes.append(sh)
            k = shapes.index(sh)
            if k != shape: out.append(0xA0 + k); shape = k
            n = n[0]
        L = f1 - f0
        out += bytes([n - 24, min(255, L)]); t += min(255, L); L -= min(255, L)
        while L > 0:
            k = min(255, L); out += bytes([0x61, k]); t += k; L -= k
    out.append(0xFF)
    return bytes(out)

def freq(n):
    return int(round(440 * 2 ** ((n - 69) / 12) * 16777216 / 985248))

def song_asm(path):
    shapes = []
    vs = [compile_voice(e, shapes) for e in VOICES1 + VOICES2]
    L = ['; (C) 2026 Mong00se. All rights reserved.',
         '; SONG.ASM - The Blue Danube (Johann Strauss II), arranged by Mong00se.',
         '; Made by song.py on the PC (the notes, the timing) - a part of',
         '; ODYSSEY.ASM: F2 on any part builds the whole demo.',
         '; The player (PLAYER.ASM) reads one list a voice: $00-$5F a note (C1 up),',
         '; then how many frames; $60 a rest, $61 hold on (then frames); $80+i an',
         '; instrument, $A0+k a chord (the arpeggio); $FF the end.',
         '!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }',
         '!if odyp = 0 {',
         '        !src "odyssey.asm"',
         '} else {',
         'songlen = %d            ; frames, then it starts again' % NFR, '']
    L.append('; instruments: wave, ad, sr, pulse/16, pwm speed, vibrato delay,')
    L.append('; vibrato depth (0 none), flags (1 arp, 2 hard restart), gate off')
    L.append('; frames before the next note, equaliser peak')
    names = ['melody', 'horn', 'bass', 'pah (chords)', 'tremolo', 'string pad', 'harp', 'pedal']
    L.append('instr')
    for k, ins in enumerate(INSTR):
        L.append('        !byte ' + ','.join('$%02x' % (v & 255) for v in ins) + '   ; %d %s' % (k, names[k]))
    L.append('; the chords for the arpeggio: 4 steps above the note')
    L.append('shapes')
    for sh in shapes: L.append('        !byte ' + ','.join('%d' % v for v in sh))
    L.append('; the notes C1 up (PAL): low bytes, then high bytes')
    ft = [min(65535, freq(n)) for n in range(24, 24 + 96)]
    for nm, sel in (('freqlo', lambda v: v & 255), ('freqhi', lambda v: v >> 8)):
        L.append(nm)
        for i in range(0, 96, 12): L.append('        !byte ' + ','.join('$%02x' % sel(v) for v in ft[i:i + 12]))
    L.append('; where each voice\'s list starts: SID 1 voices 1-3, then SID 2')
    L.append('vlistlo !byte ' + ','.join('<v%d' % k for k in range(6)))
    L.append('vlisthi !byte ' + ','.join('>v%d' % k for k in range(6)))
    titles = ['SID 1 voice 1: the melody', 'SID 1 voice 2: the bass', 'SID 1 voice 3: the chords',
              'SID 2 voice 1: the strings (low)', 'SID 2 voice 2: the strings (high)', 'SID 2 voice 3: the harp']
    for k, v in enumerate(vs):
        L.append('; ' + titles[k])
        L.append('v%d' % k)
        for i in range(0, len(v), 16): L.append('        !byte ' + ','.join('$%02x' % b for b in v[i:i + 16]))
    L.append('}')
    open(path, 'w').write('\n'.join(L) + '\n')
    return sum(len(v) for v in vs), len(shapes)

# ------------------------------------------------------------------------------------------- SIDs 3-8 for the Octophonic
def render8(path):
    _s = open(os.path.join(HERE, '..', 'greatwave', 'music.py')).read()
    g = {}
    exec(_s[:_s.index('# ------------------------------------------------------------------------------------------------- the form')], g)
    Song, nhz, SAW, PUL, TRI, NOI, LP, BP = g['Song'], g['nhz'], g['SAW'], g['PUL'], g['TRI'], g['NOI'], g['LP'], g['BP']
    N = NFR; S = Song(N); t = np.arange(N)
    def vib(base, delay=16, depth=0.005, rate=7.0):
        return lambda k: base * (1 + (depth * min(1, (k - delay) / 20) * math.sin(2 * math.pi * k / rate) if k > delay else 0))
    def note(c, v, f0, f1, hz, w, ad, sr, pw=2048, tail=24):
        if 0 <= f0 < N - 2 and f1 > f0: S.note(c, v, f0, min(f1, N - 2), hz, w, ad, sr, pw=pw, tail=tail)
    F = lambda bar, bt: fr(bar, bt)
    # SID 3 (index 0 here): high strings - the chord's notes an octave up, filtered saws, a slow swell each phrase
    bar = 0
    while bar < CODA + 3:
        h = harm(bar); e = bar
        while e < CODA + 3 and harm(e) == h and e - bar < 4: e += 1
        root, pcs = CH[h]
        tones = sorted(set(74 + ((root + p - 74) % 12) for p in pcs))[:3]
        if bar >= P1 or bar >= 2:
            for v, n in enumerate(tones):
                note(0, v, F(bar, 0) + v, F(e, 0) - 2, vib(nhz(n), 20, 0.004, 6.5), SAW, 0x98, 0xA9, tail=30)
        bar = e
    S.route[:, 0] = 7; S.mode[:, 0] = LP; S.res[:, 0] = 3
    S.cut[:, 0] = 520 + 280 * (0.5 + 0.5 * np.sin(2 * np.pi * t / (60 * 8)))
    S.vol[:, 0] = np.where(t < F(P2, 0), 7, 10)
    # SID 4: horns - the call doubled an octave down in the introduction; in the waltz, held chord notes on each
    # phrase's first bar, and the "pom-pom" answers in the second time
    for b, bt, d, n, ins in part_melody():
        if ins == I_HORN:
            note(1, 0, F(b, bt), F(b, bt + d) - 3, vib(nhz(n - 12), 20, 0.003), PUL, 0x86, 0xA9, pw=2000, tail=20)
    for bar in range(P1, CODA, 4):
        root, pcs = CH[harm(bar)]
        for v, p in enumerate(pcs[:2]):
            n = 55 + ((root + p - 55) % 12)
            note(1, 1 + v, F(bar, 0), F(bar + 2, 0) - 4, nhz(n), PUL, 0x76, 0x88, pw=1800, tail=24)
    S.route[:, 1] = 7; S.mode[:, 1] = LP; S.res[:, 1] = 2; S.cut[:, 1] = 900; S.vol[:, 1] = 7
    # SID 5: flute - the melody an octave up in the second time (from its third phrase on, the whole melody)
    k = 0
    for b, bt, d, n, ins in part_melody():
        if ins == I_MEL and b >= P2 - 1 and b < CODA + 3:
            nn = n + 12 if n < 80 else n
            note(2, k % 2, F(b, bt), F(b, bt + d) - 2, vib(nhz(nn), 12, 0.006, 6.0), TRI, 0x46, 0x98, tail=16); k += 1
    S.vol[:, 2] = 10
    # SID 6: bells - the "pom-pom" answers (the melody's high notes) as glockenspiel pings, both times; stars in the
    # introduction
    k = 0
    for b, bt, d, n, ins in part_melody():
        if ins == I_MEL and n >= 78:
            note(3, k % 3, F(b, bt), F(b, bt) + 3, nhz(n + 12), TRI, 0x09, 0x0A, tail=50)
            note(3, (k + 1) % 3, F(b, bt) + 1, F(b, bt) + 3, nhz(n + 24) * 1.003, TRI, 0x07, 0x07, tail=30); k += 2
    for i, (b, bt) in enumerate([(0, 1.5), (1, 0.5), (1, 2), (3, 1), (4, 0), (5, 2), (6, 1)]):
        n = [93, 90, 98, 93, 86, 90, 98][i]
        note(3, i % 3, F(b, bt), F(b, bt) + 3, nhz(n), TRI, 0x09, 0x0B, tail=60)
    S.vol[:, 3] = 6
    # SID 7: cellos - a counter-melody in the second time, long notes walking through the harmony (the chord's third,
    # moving to the next chord's nearest note); the low strings' D in the introduction
    note(4, 0, F(0, 0), F(6, 0), nhz(50), SAW, 0xA0, 0xC9, tail=40)
    prev = 54
    for bar in range(P2, CODA + 2, 2):
        root, pcs = CH[harm(bar)]
        cand = [48 + ((root + p - 48) % 12) for p in pcs] + [60 + ((root + p - 60) % 12) for p in pcs]
        n = min(cand, key=lambda c: (abs(c - prev), c))
        note(4, (bar // 2) % 2, F(bar, 0), F(bar + 2, 0) - 3, vib(nhz(n), 24, 0.005, 6.2), SAW, 0x66, 0xA9, tail=20)
        prev = n
    S.route[:, 4] = 3; S.mode[:, 4] = LP; S.res[:, 4] = 3; S.cut[:, 4] = 700; S.vol[:, 4] = 9
    # SID 8: timpani on the phrase starts (rolls in the introduction and the coda) and pizzicato basses on beat 1
    def timp(f, n, soft=False):
        S.drum(5, 0, f, [(NOI, 600, 0), (TRI, nhz(n) * 1.06, 0), (TRI, nhz(n) * 1.02, 0), (TRI, nhz(n), 0)], 0x09 if not soft else 0x07, 0x00, 10)
    f = F(0, 0)
    while f < F(2, 0): timp(int(f), 38, soft=True); f += 5
    for bar in range(P1, CODA, 4): timp(F(bar, 0), 38 if harm(bar) in ('D', 'D/A') else 33)
    f = F(CODA + 2, 0)
    while f < F(CODA + 3, 0): timp(int(f), 38, soft=True); f += 4
    for bar in range(P2, CODA):
        n = bass_note(bar, False) - 12
        note(5, 1, F(bar, 0), F(bar, 0) + 6, nhz(n + 12), PUL, 0x09, 0x00, pw=1000, tail=20)
    S.vol[:, 5] = 8
    # fades: everything comes up through the introduction and rings out in the coda
    fin = np.interp(t, [0, F(2, 0), F(INTRO, 0), N], [0.4, 0.7, 1, 1])
    fout = np.interp(t, [0, F(CODA + 2, 0), N - 30, N], [1, 1, 0.3, 0])
    for c in range(6): S.vol[:, c] = np.round(S.vol[:, c] * fin * fout)
    S.wave = S.wave  # (as built)
    r = S.regs()[:, :6, :]
    r.reshape(N * 6 * 32).astype(np.uint8).tofile(path)

def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    nb, ns = song_asm(os.path.join(out, 'song.asm'))
    render8(os.path.join(out, 'music8.bin'))
    print(NFR)
    sys.stderr.write('song: %d frames (%.1f s), %d bytes of note lists, %d chord shapes\n' % (NFR, NFR / 50.0, nb, ns))

if __name__ == '__main__':
    main()
