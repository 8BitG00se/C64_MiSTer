#!/usr/bin/env python3
# (C) 2026 Mong00se
# ODYSSEY - the music: "The Blue Danube" (An der schoenen blauen Donau, Op. 314, Johann Strauss II, 1866-67, public domain),
# arranged by Mong00se from the waltz's own score (the first waltz's theme as Strauss wrote it - its melody, slurs, bass
# and harmony - and a short introduction of our own on its horn call). Slow and floating, the strings legato, the waltz's
# after-beats soft held strings, the bass a gentle cello on the downbeat; out of near-silence (a high string tremolo, a
# horn call) and back into it. No arpeggio chords anywhere.
# One arrangement that opens out:
#   1 SID (stock C64)   voice 1 the 1st violins' melody (a filtered saw, legato, a light late vibrato; the horn call in the
#                       introduction), voice 2 the cellos/basses on the downbeat, voice 3 the violas: the tremolo, then
#                       the after-beats (two soft bowed notes a bar)
#   2 SIDs (stereo)     SID 2 the 2nd violins doubling the melody (a pulse a few cents sharp: an ensemble across the
#                       stereo; an octave down the second time), a held string pad, the harp
#   8 SIDs (Octophonic) SIDs 3-8 the rest of the orchestra, seated left and right: 1st violins (more desks, octaves at
#                       the climaxes, the tremolo), 2nd violins, horns, violas and cellos, flute and oboe (the melody the
#                       second time) and a second harp, basses and timpani (soft rolls at the swells and the end)
# SIDs 1 and 2 are played by the 6502's player (player.asm) from the note lists this script writes (song.asm); SIDs 3-8 are
# rendered here to SID register frames (music8.bin: 6 SIDs x 32 bytes a frame) that the Octophonic streams from the REU.
# Both use the same frame timing (the tempo map below), so they stay together.
#   song.py OUTDIR   -> OUTDIR/song.asm, OUTDIR/music8.bin; prints the length in frames
import sys, os, math
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------------------------------------------------- the score
def M(name):
    """'F#4' -> midi"""
    pc = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}[name[0]]
    k = 1
    if name[1] == '#': pc += 1; k = 2
    return 12 * (int(name[k:]) + 1) + pc
D4, E4, Fs4, G4, Gs4, A4, B4, Cs4 = 62, 64, 66, 67, 68, 69, 71, 61
D5, A5, Fs5, G5, B5, D6 = 74, 81, 78, 79, 83, 86

# The first waltz's theme as Strauss wrote it (checked against the public-domain score - Mutopia's piano edition, Op. 314):
# the pickup D on the third beat; the rising triad slurred (D F#-A), its top note held two beats; then the answering notes
# on the THIRD beat, each struck again on the next downbeat (a''4 | a''2) - not tied. (bar, beat, beats, note, slur): slur
# 1 = no new bow, the pitch moves from the note before.
THEME = [(0, 2, 1, D4, 0),
         (1, 0, 1, D4, 0), (1, 1, 1, Fs4, 1), (1, 2, 1, A4, 1), (2, 0, 2, A4, 0), (2, 2, 1, A5, 0), (3, 0, 2, A5, 0), (3, 2, 1, Fs5, 0),
         (4, 0, 2, Fs5, 0), (4, 2, 1, D4, 0),
         (5, 0, 1, D4, 0), (5, 1, 1, Fs4, 1), (5, 2, 1, A4, 1), (6, 0, 2, A4, 0), (6, 2, 1, A5, 0), (7, 0, 2, A5, 0), (7, 2, 1, G5, 0),
         (8, 0, 2, G5, 0), (8, 2, 1, Cs4, 0),
         (9, 0, 1, Cs4, 0), (9, 1, 1, E4, 1), (9, 2, 1, B4, 1), (10, 0, 2, B4, 0), (10, 2, 1, B5, 0), (11, 0, 2, B5, 0), (11, 2, 1, G5, 0),
         (12, 0, 2, G5, 0), (12, 2, 1, Cs4, 0),
         (13, 0, 1, Cs4, 0), (13, 1, 1, E4, 1), (13, 2, 1, B4, 1), (14, 0, 2, B4, 0), (14, 2, 1, B5, 0), (15, 0, 2, B5, 0), (15, 2, 1, Fs5, 0),
         (16, 0, 2, Fs5, 0), (16, 2, 1, D4, 0),
         (17, 0, 1, D4, 0), (17, 1, 1, Fs4, 1), (17, 2, 1, A4, 1), (18, 0, 2, D5, 0), (18, 2, 1, D6, 0), (19, 0, 2, D6, 0), (19, 2, 1, A5, 0),
         (20, 0, 2, A5, 0), (20, 2, 1, D4, 0),
         (21, 0, 1, D4, 0), (21, 1, 1, Fs4, 1), (21, 2, 1, A4, 1), (22, 0, 2, D5, 0), (22, 2, 1, D6, 0), (23, 0, 2, D6, 0), (23, 2, 1, B5, 0),
         (24, 0, 2, B5, 0), (24, 2, 1, E4, 0),
         (25, 0, 1, E4, 0), (25, 1, 1, G4, 1), (25, 2, 1, B4, 1), (26, 0, 4, B4, 0), (27, 1, 1, Gs4, 0), (27, 2, 1, A4, 1),
         (28, 0, 4, Fs5, 0), (29, 1, 1, D5, 0), (29, 2, 1, Fs4, 1),
         (30, 0, 2, Fs4, 0), (30, 2, 1, E4, 1), (31, 0, 2, B4, 0), (31, 2, 1, A4, 1), (32, 0, 2, D4, 0)]
# the strain's own close (the last time): D. d'' d''
THEME_END = [(32, 0, 1.5, D4, 0), (32, 1.5, 0.5, D5, 0), (32, 2, 1, D5, 0)]

# The harmony and bass of each bar of the theme, from the score's accompaniment (it was wrong in build 1: the A7 starts at
# bar 6, not 8, over an E in the bass; bars 14-17 are D; 18-21 D over F#; 22-24 E minor 7 over G; 25 a walk down E minor;
# 26-27 A7 over E then C#; 28 D, 29 D/F#, 30 G, 31 A7). (chord's pitch classes, bass note(s) (beat, midi))
CH = {'D': [2, 6, 9], 'A7': [9, 1, 4, 7], 'A': [9, 1, 4], 'Em7': [4, 7, 11, 2], 'Em': [4, 7, 11], 'G': [7, 11, 2]}
HARM = {}
for b in range(1, 6): HARM[b] = ('D', [(0, 50)])
for b in range(6, 14): HARM[b] = ('A7', [(0, 52)])
for b in range(14, 18): HARM[b] = ('D', [(0, 50)])
for b in range(18, 22): HARM[b] = ('D', [(0, 54)])
for b in range(22, 25): HARM[b] = ('Em7', [(0, 55)])
HARM[25] = ('Em', [(0, 59), (1, 55), (2, 52)])
HARM[26] = ('A7', [(0, 52)]); HARM[27] = ('A', [(0, 49)]); HARM[28] = ('D', [(0, 50)]); HARM[29] = ('D', [(0, 54)])
HARM[30] = ('G', [(0, 55)]); HARM[31] = ('A7', [(0, 45)]); HARM[32] = ('D', [(0, 50)])

INTRO = 12          # the introduction's bars (its last holds the theme's pickup on its third beat)
P1 = INTRO          # the theme's bar 1, first time
P2 = INTRO + 32     # the theme's bar 1, second time (its bar 0 is the first time's bar 32)
CODA = INTRO + 64   # the coda's first bar
NBARS = CODA + 6    # the coda's 5 bars and a bar of quiet before the loop

def tbar(bar):
    """the theme's bar (1-32) of a song bar, and which time (1, 2); (0, 0) outside the theme"""
    if P1 <= bar < P2: return bar - P1 + 1, 1
    if P2 <= bar < CODA: return bar - P2 + 1, 2
    return 0, 0

def chord(bar):
    tb, _ = tbar(bar)
    if tb: return HARM[tb][0]
    if bar < INTRO: return 'A7' if 6 <= bar < 10 else 'D'
    return 'D'

# ------------------------------------------------------------------------------------------- the tempo map (frames)
# Slower and more floating than a dance waltz (about 1.5 s a bar against build 1's 1.2), the Viennese lilt kept (the
# second beat a touch late here - leaning on it), and rubato: each phrase leans on its long note (the theme's bars 2, 6,
# 10, ...), breathes at the end of each 8 bars, broadens at bars 26 and 28 (the held B and F#), and slows into the close
# the second time. The introduction is slower still, its last bar a long held horn note and the pickup.
def bar_beats(b):
    if b < INTRO:
        if b < 9: return (27, 27, 27)
        if b == 9: return (27, 28, 29)
        if b == 10: return (30, 31, 32)
        return (54, 30, 26)                                     # the horn's A held (a fermata), then the pickup
    tb, tm = tbar(b)
    if tb:
        base = [23.0, 26.0, 24.0]
        k = 1.0
        ph = (tb - 1) % 4
        k *= (0.97, 1.07, 1.0, 1.01)[ph]
        if tb % 8 == 0: k *= 1.05
        if tb in (16, 32): k *= 1.04
        if tb == 26: k *= 1.10
        if tb == 28: k *= 1.12
        if tm == 2:
            if tb == 29: k *= 1.06
            if tb == 30: k *= 1.14
            if tb == 31: k *= 1.26
            if tb == 32: k *= 1.30
        return tuple(int(round(x * k)) for x in base)
    c = b - CODA
    return [(28, 28, 28), (29, 29, 30), (30, 31, 32), (34, 34, 34), (36, 36, 36), (30, 30, 30)][c]

BEATS = [bar_beats(b) for b in range(NBARS)]
BSTART = [0]
for bt in BEATS:
    for f in bt: BSTART.append(BSTART[-1] + f)
NFR = BSTART[-1]
def fr(bar, beat):
    """the frame of a (bar, beat) - beat may be fractional, or past the bar's end"""
    k = bar * 3 + int(math.floor(beat)); x = beat - math.floor(beat)
    k = min(k, len(BSTART) - 2)
    return int(round(BSTART[k] + x * (BSTART[k + 1] - BSTART[k])))

def theme_notes(at, last=False):
    """the theme with its bar 1 at song bar `at` (bar 0, the pickup, at at - 1)"""
    th = THEME[:-1] + (THEME_END if last else THEME[-1:])
    return [(at - 1 + b, bt, d, n, sl) for b, bt, d, n, sl in th]

# the dynamics: 0 (near silence) to 1 (the climax), at song bars
DYN = [(0, 0.0), (1.5, 0.25), (2, 0.4), (6, 0.45), (10, 0.6), (11, 0.7), (INTRO, 0.45), (P1 + 8, 0.5), (P1 + 16, 0.6),
       (P1 + 24, 0.7), (P1 + 31, 0.6), (P2, 0.65), (P2 + 16, 0.8), (P2 + 23, 0.95), (P2 + 25, 1.0), (P2 + 30, 0.9),
       (CODA, 0.6), (CODA + 2, 0.45), (CODA + 4, 0.2), (CODA + 5, 0.0), (NBARS, 0.0)]
def dyn(bar):
    xs = [x for x, _ in DYN]; ys = [y for _, y in DYN]
    return float(np.interp(bar, xs, ys))

def chord_tones(bar, lo, hi):
    pcs = CH[chord(bar)]
    return sorted(n for n in range(lo, hi + 1) if n % 12 in pcs)

# ------------------------------------------------------------------------------------------- the player's parts
# (song bar, beat, beats, note, instrument[, slur])
I_VLN, I_HORN, I_BASS, I_AFT, I_TREM, I_PAD, I_HARP, I_VLN2, I_FLUTE, I_BASSL = range(10)

HORN1 = [(2, 0, 1, D4, 0), (2, 1, 1, Fs4, 1), (2, 2, 1, A4, 1), (3, 0, 3, A4, 0)]             # the theme's own triad
ANS1 = [(4, 1, 1, A5, 0), (4, 2, 1, Fs5, 1), (5, 0, 2.6, D5, 1)]                              # falling back, softly
HORN2 = [(6, 0, 1, Cs4, 0), (6, 1, 1, E4, 1), (6, 2, 1, A4, 1), (7, 0, 3, A4, 0)]             # on the dominant
ANS2 = [(8, 1, 1, G5, 0), (8, 2, 1, 76, 1), (9, 0, 2.6, 73, 1)]
HORN3 = [(10, 0, 1, D4, 0), (10, 1, 1, Fs4, 1), (10, 2, 1, A4, 1), (11, 0, 1.85, A4, 0)]      # home, held, the pickup

def part_melody():
    """SID 1 voice 1: the horn calls, then the 1st violins"""
    ev = [(b, bt, d, n, I_HORN, s) for b, bt, d, n, s in HORN1 + HORN2 + HORN3]
    ev += [(b, bt, d, n, I_FLUTE, s) for b, bt, d, n, s in ANS1 + ANS2]
    ev += [(b, bt, d, n, I_VLN, s) for b, bt, d, n, s in theme_notes(P1)]
    ev += [(b, bt, d, n, I_VLN, s) for b, bt, d, n, s in theme_notes(P2, last=True)]
    # the coda: the horn call once more, the flute's answer, the strings' long D dying away
    ev += [(CODA + 1, 0, 1, D4, I_HORN, 0), (CODA + 1, 1, 1, Fs4, I_HORN, 1), (CODA + 1, 2, 1, A4, I_HORN, 1),
           (CODA + 2, 0, 3, A4, I_HORN, 0), (CODA + 3, 1, 1, A5, I_FLUTE, 0), (CODA + 3, 2, 1, Fs5, I_FLUTE, 1),
           (CODA + 4, 0, 2.7, D5, I_FLUTE, 1)]
    ev.sort(key=lambda e: (e[0], e[1]))
    return ev

def bass_events(bar):
    tb, tm = tbar(bar)
    return HARM[tb][1]

def part_bass():
    """SID 1 voice 2: the cellos and basses - a long low D under the introduction, then a gentle note on each downbeat"""
    ev = [(2, 0, 11.8, 38, I_BASSL), (6, 0, 11.8, 45, I_BASSL), (10, 0, 4.85, 38, I_BASSL)]
    for bar in range(P1 + 1, CODA):
        tb, tm = tbar(bar)
        bn = bass_events(bar)
        for i, (bt, n) in enumerate(bn):
            n = n - 12                                           # the basses' octave: D2-G3
            d = (bn[i + 1][0] - bt - 0.15) if i + 1 < len(bn) else min(1.75, 2.85 - bt)
            ev.append((bar, bt, d, n, I_BASS))
    ev += [(CODA, 0, 2.8, 38, I_BASSL), (CODA + 1, 0, 11.6, 38, I_BASSL)]
    return ev

def aft_pair(bar, lo=54, hi=66):
    """the violas' two after-beat notes: the chord's notes above the bass, near F#3-F#4, the higher first if it is
    a seventh chord (the seventh falls to the third)"""
    ts = chord_tones(bar, lo, hi)
    c = chord(bar)
    pcs = CH[c]
    third = [n for n in ts if n % 12 == pcs[1]]
    fifth = [n for n in ts if n % 12 == pcs[2]]
    a = third[0] if third else ts[0]
    b = fifth[0] if fifth else ts[-1]
    if len(pcs) == 4:
        sev = [n for n in ts if n % 12 == pcs[3]]
        if sev: b = sev[0]
    return a, b

def part_aft():
    """SID 1 voice 3: the violas - the high tremolo out of silence in the introduction, then the waltz's after-beats:
    two soft bowed notes (beats 2 and 3), the second slurred on from the first; held where the music holds"""
    ev = [(0, 0, 3 * 11 + 1.6, A5, I_TREM)]
    for bar in range(P1 + 1, CODA):
        tb, tm = tbar(bar)
        a, b = aft_pair(bar)
        if tb == 32:
            ev.append((bar, 1, 1.8, a, I_AFT, 0)); continue
        ev.append((bar, 1, 1, a, I_AFT, 0))
        ev.append((bar, 2, 0.85, b, I_AFT, 1))
    ev += [(CODA, 1, 1, Fs4 - 12, I_AFT, 0), (CODA, 2, 0.85, A4 - 12, I_AFT, 1),
           (CODA + 1, 0, 3 * 3.5, A5, I_TREM)]
    return ev

def part_vln2():
    """SID 2 voice 1: the 2nd violins - the flute's answers an octave down in the introduction; the melody in unison
    (a few cents sharp, the other side) from the theme's bar 9 the first time; an octave down the second time"""
    ev = []
    for b, bt, d, n, s in theme_notes(P1):
        if b >= P1 + 8: ev.append((b, bt, d, n, I_VLN2, s))
    for b, bt, d, n, s in theme_notes(P2, last=True):
        if b >= P2 - 1 + 1 or bt == 2:
            if b == P2 - 1 and bt == 0: continue
            ev.append((b, bt, d, n - 12, I_VLN2, s))
    ev += [(CODA + 3, 1, 1, A4, I_VLN2, 0), (CODA + 3, 2, 1, Fs4, I_VLN2, 1), (CODA + 4, 0, 2.7, D4, I_VLN2, 1)]
    ev.sort(key=lambda e: (e[0], e[1]))
    out = []; t = -1
    for e in ev:
        if fr(e[0], e[1]) >= t: out.append(e); t = fr(e[0], e[1] + e[2])
    return out

def pad_line(lo, hi, start, end, prefer=None):
    """a held line through the harmony: a chord note held while the chord lasts (at most 4 bars), moving to the next
    chord's nearest note"""
    ev = []; prev = prefer
    bar = start
    while bar < end:
        c = chord(bar); e = bar
        while e < end and chord(e) == c and e - bar < 4: e += 1
        ts = chord_tones(bar, lo, hi)
        n = ts[len(ts) // 2] if prev is None else min(ts, key=lambda x: (abs(x - prev), x))
        ev.append((bar, 0, (e - bar) * 3 - 0.12, n))
        prev = n; bar = e
    return ev

def part_pad():
    """SID 2 voice 2: a held string pad (2nd violins, divisi) under everything, soft"""
    ev = [(b, bt, d, n, I_PAD) for b, bt, d, n in pad_line(62, 74, 6, CODA + 1, 67)]
    ev += [(CODA + 1, 0, 3 * 4 - 0.2, Fs4, I_PAD)]
    return ev

def spread(bar, beat, notes, step, ins=I_HARP, last=1.0):
    return [(bar, beat + k * step, step if k < len(notes) - 1 else last, n, ins) for k, n in enumerate(notes)]

def part_harp():
    """SID 2 voice 3: the harp - a sweep up into the waltz, a spread chord at each phrase's long note the first time,
    on every bar the second time, and in the coda"""
    ev = spread(10, 0, [50, 54, 57, 62, 66, 69, 74, 78, 81, 86], 0.3, last=3.0)
    for bar in range(P1, CODA):
        tb, tm = tbar(bar)
        if tm == 1 and tb % 4 != 2: continue
        if tm == 2 and tb == 32: continue
        ts = chord_tones(bar, 55, 80)
        if tm == 1: ns = ts[:4]
        else: ns = ts[:3] if tb % 2 else ts[1:5]
        ev += spread(bar, 0 if tm == 1 else 0.0, ns, 1 / 3, last=3 - len(ns) / 3 - 0.1)
    ev += spread(CODA, 0, [50, 57, 62, 66, 69, 74, 78, 81], 0.33, last=1.5)
    ev += spread(CODA + 4, 0, [62, 69, 74, 78, 86], 0.4, last=4.0)
    return ev

# ------------------------------------------------------------------------------------------- the 6502 player's data
# instruments: wave, AD, SR, pulse width (x16), PWM speed, vibrato delay (frames), vibrato depth (1 about 20 cents,
# 2 about 10, 3 about 5, 4 about 2.5; 0 none), flags (2 hard restart, 4 tremolo, 8 detuned sharp, 16 through the
# strings' lowpass), gate-off frames before the next note, equaliser peak (0-20)
F_HR, F_TREM, F_DET, F_FILT = 2, 4, 8, 16
INSTR = [
    (0x21, 0x69, 0xF8, 0x80, 0, 22, 3, F_FILT, 2, 20),           # 0 1st violins: a saw, a slow bow, a late light vibrato
    (0x41, 0x88, 0x68, 0x70, 3, 30, 4, F_FILT, 3, 16),           # 1 horn: a mid pulse, a soft attack
    (0x41, 0x39, 0x66, 0x30, 2, 0, 0, F_FILT, 3, 18),            # 2 cellos and basses: a narrow pulse, bowed
    (0x11, 0x99, 0x75, 0x80, 0, 0, 0, F_FILT, 2, 12),            # 3 violas' after-beats: a soft swell, held
    (0x21, 0x44, 0x54, 0x80, 0, 0, 0, F_FILT | F_TREM, 2, 10),   # 4 tremolo: a saw bowed every 2 frames, soft
    (0x21, 0xA8, 0xA9, 0x80, 0, 30, 4, F_FILT, 4, 10),           # 5 string pad: a saw, slow in and out
    (0x11, 0x09, 0x08, 0x80, 0, 0, 0, F_HR, 1, 14),              # 6 harp: a plucked triangle
    (0x21, 0x69, 0xE8, 0x80, 0, 24, 3, F_FILT | F_DET, 2, 16),   # 7 2nd violins: a saw, a few cents sharp
    (0x11, 0x57, 0x68, 0x80, 0, 16, 3, 0, 2, 14),                # 8 flute: a triangle, a little late vibrato
    (0x41, 0xA9, 0x4A, 0x30, 2, 0, 0, F_FILT, 4, 12),            # 9 low strings, held (the pedal)
]
NAMES = ['1st violins', 'horn', 'cellos, basses', 'violas (after-beats)', 'tremolo', 'string pad', 'harp',
         '2nd violins', 'flute', 'low strings held']
VOICES1 = [part_melody(), part_bass(), part_aft()]
VOICES2 = [part_vln2(), part_pad(), part_harp()]

def compile_voice(ev):
    """events -> the player's bytes: $00-$5F note (then frames), $60 rest (then frames), $61 hold on (then frames),
    $62 the next note slurred, $80+i instrument, $FF the end (silent until the song starts again)"""
    out = bytearray(); t = 0; inst = None
    for e in ev:
        bar, bt, d, n, ins = e[:5]; sl = e[5] if len(e) > 5 else 0
        f0 = fr(bar, bt); f1 = min(fr(bar, bt + d), NFR - 1)
        if f0 < t and f0 > t - 3: f0 = t                         # (rounding)
        assert f0 >= t, (bar, bt, f0, t)
        if sl and f0 != t:                                       # a slur needs the note before to run up to it
            sl = 0
        while f0 - t > 0:
            k = min(255, f0 - t); out += bytes([0x60, k]); t += k
        if ins != inst: out.append(0x80 + ins); inst = ins
        if sl: out.append(0x62)
        L = f1 - f0
        if L <= 0: continue
        out += bytes([n - 24, min(255, L)]); t += min(255, L); L -= min(255, L)
        while L > 0:
            k = min(255, L); out += bytes([0x61, k]); t += k; L -= k
    out.append(0xFF)
    return bytes(out)

def tie_slurs(ev):
    """a slurred note's predecessor runs right up to it (no gap), so the bow need not change"""
    ev = list(ev)
    for i in range(1, len(ev)):
        if len(ev[i]) > 5 and ev[i][5]:
            p = ev[i - 1]
            nd = ev[i][0] * 3 + ev[i][1] - (p[0] * 3 + p[1])
            ev[i - 1] = (p[0], p[1], nd) + tuple(p[3:])
    return ev

def freq(n):
    return int(round(440 * 2 ** ((n - 69) / 12) * 16777216 / 985248))

def fcut_table():
    """the strings' lowpass on SIDs 1-2, every 16 frames ($D416): out of near silence in the introduction, opening with
    the swells, closing in the coda"""
    pts = [(0, 0x00), (2, 0x14), (6, 0x20), (10, 0x30), (11, 0x40), (INTRO, 0x5c), (P1 + 16, 0x60), (P1 + 24, 0x64), (P2, 0x60), (P2 + 16, 0x68),
           (P2 + 24, 0x70), (P2 + 30, 0x68), (CODA, 0x58), (CODA + 3, 0x48), (CODA + 5, 0x10), (NBARS, 0x06)]
    xs = [fr(b, 0) if b < NBARS else NFR for b, _ in pts]; ys = [y for _, y in pts]
    n = NFR // 16 + 2
    return [int(round(np.interp(k * 16 + 8, xs, ys))) for k in range(n)]

def phrases():
    """the show's picture changes (show.asm's atcut): the start of each 4 bars of the theme, both times"""
    return [fr(P1 + 4 * k, 0) for k in range(16)]

# the measuring loop: ODY_ONLY="p0,p3,s5" keeps only those parts (p0-p5 the player's voices, s3-s8 the rendered SIDs),
# so each can be recorded and measured on its own in the emulators; unset, everything plays
ONLY = os.environ.get('ODY_ONLY')
ONLY = set(ONLY.split(',')) if ONLY else None

def song_asm(path):
    vs = [compile_voice(tie_slurs(e)) if ONLY is None or 'p%d' % k in ONLY else b'\xff'
          for k, e in enumerate(VOICES1 + VOICES2)]
    L = ['; (C) 2026 Mong00se',
         '; SONG.ASM - The Blue Danube (Johann Strauss II), arranged by Mong00se.',
         '; Made by song.py on the PC (the notes, the timing) - a part of',
         '; ODYSSEY.ASM: F2 on any part builds the whole demo.',
         '; The player (PLAYER.ASM) reads one list a voice: $00-$5F a note (C1 up),',
         '; then how many frames; $60 a rest, $61 hold on (then frames); $62 the',
         '; next note slurred (no new bow); $80+i an instrument; $FF the end.',
         '!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }',
         '!if odyp = 0 {',
         '        !src "odyssey.asm"',
         '} else {',
         'songlen = %d            ; frames, then it starts again' % NFR, '']
    L.append('; instruments: wave, ad, sr, pulse/16, pwm speed, vibrato delay,')
    L.append('; vibrato depth (0 none), flags (2 hard restart, 4 tremolo, 8 sharp,')
    L.append('; 16 filtered), gate off frames before the next note, equaliser peak')
    L.append('instr')
    for k, ins in enumerate(INSTR):
        L.append('        !byte ' + ','.join('$%02x' % (v & 255) for v in ins) + '   ; %d %s' % (k, NAMES[k]))
    L.append('; the show\'s picture changes: the song frames of the theme\'s 4-bar phrases')
    ph = phrases()
    L.append('phtab   !word ' + ','.join('%d' % v for v in ph[:8]))
    L.append('        !word ' + ','.join('%d' % v for v in ph[8:]))
    L.append('; the strings\' lowpass ($D416) every 16 frames: the swells')
    fc = fcut_table()
    L.append('fcut')
    for i in range(0, len(fc), 16): L.append('        !byte ' + ','.join('$%02x' % v for v in fc[i:i + 16]))
    L.append('; the notes C1 up (PAL): low bytes, then high bytes')
    ft = [min(65535, freq(n)) for n in range(24, 24 + 96)]
    for nm, sel in (('freqlo', lambda v: v & 255), ('freqhi', lambda v: v >> 8)):
        L.append(nm)
        for i in range(0, 96, 12): L.append('        !byte ' + ','.join('$%02x' % sel(v) for v in ft[i:i + 12]))
    L.append('; where each voice\'s list starts: SID 1 voices 1-3, then SID 2')
    L.append('vlistlo !byte ' + ','.join('<v%d' % k for k in range(6)))
    L.append('vlisthi !byte ' + ','.join('>v%d' % k for k in range(6)))
    titles = ['SID 1 voice 1: the horn calls, the 1st violins (the melody)', 'SID 1 voice 2: cellos and basses',
              'SID 1 voice 3: the tremolo, the violas\' after-beats', 'SID 2 voice 1: the 2nd violins (the melody)',
              'SID 2 voice 2: the string pad', 'SID 2 voice 3: the harp']
    for k, v in enumerate(vs):
        L.append('; ' + titles[k])
        L.append('v%d' % k)
        for i in range(0, len(v), 16): L.append('        !byte ' + ','.join('$%02x' % b for b in v[i:i + 16]))
    L.append('}')
    open(path, 'w').write('\n'.join(L) + '\n')
    return sum(len(v) for v in vs) + len(fc)

# ------------------------------------------------------------------------------------------- SIDs 3-8 for the Octophonic
SAW, PUL, TRI, NOI = 0x20, 0x40, 0x10, 0x80
LP, BP, HP = 0x10, 0x20, 0x40
CLK = 985248
def nhz(n): return 440 * 2 ** ((n - 69) / 12)

class Orch:
    """SID register frames for 8 SIDs (3 voices each): notes with a gap before the next bow unless slurred, a hard
    restart only where asked (plucks), tremolo bowing, per-SID filter and volume curves"""
    def __init__(s, N):
        s.N = N
        s.freq = np.zeros((N, 8, 3)); s.pw = np.full((N, 8, 3), 2048.0); s.wave = np.zeros((N, 8, 3), int)
        s.gate = np.zeros((N, 8, 3), bool); s.ad = np.zeros((N, 8, 3), int); s.sr = np.zeros((N, 8, 3), int)
        s.hr = np.zeros((N, 8, 3), bool)
        s.cut = np.full((N, 8), 1024.0); s.res = np.zeros((N, 8), int); s.route = np.zeros((N, 8), int)
        s.mode = np.zeros((N, 8), int); s.vol = np.zeros((N, 8))
    def note(s, c, v, f0, f1, hz, wave, ad, sr, pw=2048, tail=40, gap=2, slur=False, hr=False, trem=False):
        f0 = max(0, f0); f1 = min(s.N - 1, f1)
        if f0 >= f1: return
        for f in range(f0, min(s.N, f1 + tail)):
            s.freq[f, c, v] = hz(f - f0) if callable(hz) else hz
            s.pw[f, c, v] = pw(f - f0) if callable(pw) else pw
            s.wave[f, c, v] = wave; s.ad[f, c, v] = ad; s.sr[f, c, v] = sr
        g1 = max(f0 + 1, f1 - gap)
        if trem:
            for f in range(f0, g1): s.gate[f, c, v] = ((f // 2) % 2 == 0)
        else:
            s.gate[f0:g1, c, v] = True
        if slur: s.gate[max(0, f0 - gap - 1):f0, c, v] = True
        if hr: s.hr[f0, c, v] = True
    def regs(s):
        g = s.gate.copy(); ad = s.ad.copy(); sr = s.sr.copy(); wv = s.wave.copy()
        for f, c, v in zip(*np.nonzero(s.hr)):
            for k in (1, 2):                          # hard restart: gate off, ADSR 0 two frames before
                if f - k >= 0: g[f - k, c, v] = False; ad[f - k, c, v] = 0; sr[f - k, c, v] = 0
            if f - 1 >= 0: wv[f - 1, c, v] |= 0x08    # the test bit the frame before
        out = np.zeros((s.N, 8, 32), np.uint8)
        for c in range(8):
            for v in range(3):
                o = v * 7
                fq = np.clip(np.round(s.freq[:, c, v] * 16777216 / CLK), 0, 65535).astype(int)
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

def render8(path):
    """SIDs 3-8 (here 2-7; 0-1 are the player's), seated like an orchestra: odd SIDs left, even right.
       SID 3 L  1st violins: more desks on the melody (a few cents flat), octaves down at the climaxes, the tremolo
       SID 4 R  2nd violins: the melody the second time (a few cents sharp), the tremolo's chord, the after-beats
       SID 5 L  horns: the calls an octave down, held notes at the swells, the triad with the cellos
       SID 6 R  violas and cellos: the after-beats (low), the cellos' rising triads, a cello line the second time
       SID 7 L  flute and oboe on the melody the second time; a second harp
       SID 8 R  basses (with the cellos) on the downbeat, timpani rolls at the swells and the end"""
    N = NFR; S = Orch(N); t = np.arange(N)
    F = fr
    cents = lambda c: 2 ** (c / 1200)
    def vib(n, det=0.0, delay=20, depth=6.0, rate=5.6, ph=0.0):
        base = nhz(n) * cents(det)
        def h(k):
            if k <= delay: return base
            a = min(1.0, (k - delay) / 25.0) * depth
            return base * cents(a * math.sin(2 * math.pi * (k - delay) * rate / 50.0 + ph))
        return h
    def pws(base=1800, sw=500, per=110, ph=0.0):
        return lambda k: base + sw * math.sin(2 * math.pi * k / per + ph)
    def sus(bar, lo=6, hi=12):
        """a sustain level from the dynamics: the swells"""
        return int(round(lo + (hi - lo) * dyn(bar)))
    def strings(c, v, ev, det=0.0, wave=SAW, att=7, rel=9, lo=7, hi=13, vdel=20, vdep=6.0, shift=0, pwb=1800, ph=0.0):
        ev = tie_slurs(ev)
        for e in ev:
            b, bt, d, n = e[:4]; sl = e[5] if len(e) > 5 else 0
            if n is None: continue
            f0, f1 = F(b, bt), F(b, bt + d)
            S.note(c, v, f0, f1, vib(n + shift, det, vdel, vdep, 5.4 + 0.3 * v, ph + v), wave, (att << 4) | 8,
                   (sus(b, lo, hi) << 4) | rel, pw=pws(pwb, 450, 120 + 17 * v, ph + v), tail=60, slur=bool(sl))
    # ---- SID 3 (index 2): 1st violins
    th1 = theme_notes(P1); th2 = theme_notes(P2, last=True)
    mel = [(b, bt, d, n, 0, s) for b, bt, d, n, s in th1 + th2 if b < CODA]
    strings(2, 0, [e for e in mel if e[0] >= P1 + 16], det=-6, att=7)
    oct_dn = [(b, bt, d, n - 12, 0, s) for b, bt, d, n, s in th2 if (P2 + 16 <= b < CODA) and n >= 74]
    strings(2, 1, oct_dn, det=4, att=6, lo=6, hi=11)
    # the tremolo out of silence: high A, then the A an octave below joins; and again in the coda
    S.note(2, 2, 0, F(11, 1.6), nhz(81) * cents(-4), SAW, 0x44, 0x54, trem=True, tail=30)
    S.note(2, 1, F(1, 0), F(11, 1.6), nhz(69) * cents(5), SAW, 0x44, 0x44, trem=True, tail=30)
    S.note(2, 2, F(CODA + 1, 0), F(CODA + 4, 2), nhz(81) * cents(-4), SAW, 0x44, 0x44, trem=True, tail=30)
    S.route[:, 2] = 7; S.mode[:, 2] = LP; S.res[:, 2] = 2
    # ---- SID 4 (index 3): 2nd violins
    S.note(3, 1, F(0, 1.5), F(11, 1.6), nhz(74) * cents(3), SAW, 0x44, 0x44, trem=True, tail=30)
    S.note(3, 2, F(1, 1.0), F(6, 0), nhz(78) * cents(-3), SAW, 0x44, 0x44, trem=True, tail=30)
    S.note(3, 2, F(6, 0), F(10, 0), nhz(79) * cents(-3), SAW, 0x44, 0x44, trem=True, tail=30)
    S.note(3, 2, F(10, 0), F(11, 1.6), nhz(78) * cents(-3), SAW, 0x44, 0x44, trem=True, tail=30)
    strings(3, 0, [e for e in mel if e[0] >= P1 + 8], det=5, wave=PUL, att=7, pwb=1700)
    # after-beats on the right, an octave up from the violas' (2nd violins), the second time and at the swells
    for bar in range(P1 + 1, CODA):
        tb, tm = tbar(bar)
        if tm == 1 and tb < 17: continue
        a, b = aft_pair(bar, 62, 74)
        if tb == 32: continue
        S.note(3, 1, F(bar, 1), F(bar, 2), vib(a, 3, 30, 3), PUL, 0x88, (sus(bar, 8, 12) << 4) | 6, pw=pws(1500, 400), gap=2)
        S.note(3, 2, F(bar, 1), F(bar, 2), vib(b, -3, 30, 3), PUL, 0x88, (sus(bar, 8, 12) << 4) | 6, pw=pws(1700, 400), gap=2)
        S.note(3, 1, F(bar, 2), F(bar, 2.85), vib(a, 3, 30, 3), PUL, 0x88, (sus(bar, 8, 12) << 4) | 6, pw=pws(1500, 400), gap=0, slur=False)
        S.note(3, 2, F(bar, 2), F(bar, 2.85), vib(b, -3, 30, 3), PUL, 0x88, (sus(bar, 8, 12) << 4) | 6, pw=pws(1700, 400), gap=0)
    S.route[:, 3] = 7; S.mode[:, 3] = LP; S.res[:, 3] = 2
    # ---- SID 5 (index 4): horns
    for b, bt, d, n, s in HORN2 + HORN3:
        S.note(4, 0, F(b, bt), F(b, bt + d), vib(n - 12, -3, 30, 3), PUL, 0x88, 0x68, pw=pws(1900, 200, 200), slur=bool(s), tail=50)
    for b, bt, d, n, s in [(CODA + 1, 0, 1, D4, 0), (CODA + 1, 1, 1, Fs4, 1), (CODA + 1, 2, 1, A4, 1), (CODA + 2, 0, 3, A4, 0)]:
        S.note(4, 0, F(b, bt), F(b, bt + d), vib(n - 12, -3, 30, 3), PUL, 0x88, 0x68, pw=pws(1900, 200, 200), slur=bool(s), tail=50)
    # the rising triads with the cellos, the first time (Strauss gives them to cellos and horns)
    for b, bt, d, n, s in th1:
        tb, _ = tbar(b)
        if n <= 71 and b >= P1:
            S.note(4, 1, F(b, bt), F(b, bt + d), vib(n - 12, 2, 30, 3), PUL, 0x78, 0x88, pw=pws(2000, 150, 200), slur=bool(s), tail=40)
    # held horn notes at the swells (the chord's root and fifth)
    for bar in list(range(P1 + 16, P1 + 32, 4)) + list(range(P2, CODA, 2)):
        tb, tm = tbar(bar)
        if tb >= 31: continue
        ts = chord_tones(bar, 57, 69)
        c = chord(bar); r = [n for n in ts if n % 12 == CH[c][0]] or ts[:1]; f5 = [n for n in ts if n % 12 == CH[c][2]] or ts[-1:]
        ln = 4 if tm == 1 else 2
        S.note(4, 2, F(bar, 0), F(bar + ln, 0) - 3, vib(r[0], 0, 40, 2), PUL, 0x98, (sus(bar, 8, 12) << 4) | 9, pw=2000, tail=60)
        if tm == 2:
            S.note(4, 1, F(bar, 0), F(bar + ln, 0) - 3, vib(f5[0], 3, 40, 2), PUL, 0x98, (sus(bar, 8, 12) << 4) | 9, pw=2000, tail=60)
    S.route[:, 4] = 7; S.mode[:, 4] = LP; S.res[:, 4] = 1
    # ---- SID 6 (index 5): violas (after-beats, low) and cellos
    for bar in range(P1 + 1, CODA):
        tb, tm = tbar(bar)
        a, b = aft_pair(bar, 50, 62)
        if tb == 32:
            S.note(5, 0, F(bar, 1), F(bar, 2.8), vib(a, -4, 30, 3), SAW, 0x88, (sus(bar, 8, 12) << 4) | 7, gap=2); continue
        for v, nn in ((0, a), (1, b)):
            S.note(5, v, F(bar, 1), F(bar, 2), vib(nn, (-4, 4)[v], 30, 3), SAW, 0x88, (sus(bar, 8, 12) << 4) | 6, gap=2)
            S.note(5, v, F(bar, 2), F(bar, 2.85), vib(nn, (-4, 4)[v], 30, 3), SAW, 0x88, (sus(bar, 8, 12) << 4) | 6, gap=0)
    # cellos: the rising triads an octave down (both times), and in the second time a long line through the harmony
    cel = [(b, bt, d, n - 12, 0, s) for b, bt, d, n, s in th1 + th2 if n <= 71 and b < CODA]
    strings(5, 2, cel, det=-3, att=6, lo=7, hi=11, vdep=5)
    S.note(5, 2, F(6, 0), F(10, 0), vib(49, 0, 30, 4), SAW, 0xA8, 0x69, tail=60)
    S.note(5, 2, F(10, 0), F(11, 1.8), vib(50, 0, 30, 4), SAW, 0xA8, 0x79, tail=60)
    S.route[:, 5] = 7; S.mode[:, 5] = LP; S.res[:, 5] = 2
    # ---- SID 7 (index 6): flute and oboe, the second time; a second harp
    fl = tie_slurs([(b, bt, d, n, 0, s) for b, bt, d, n, s in th2 if b >= P2 - 1 and not (b == P2 - 1 and bt == 0)])
    for b, bt, d, n, _, s in fl:
        nn = n + 12
        S.note(6, 0, F(b, bt), F(b, bt + d), vib(nn, 2, 14, 7, 5.0), TRI, 0x58, (sus(b, 8, 12) << 4) | 8, slur=bool(s), tail=40)
        if b >= P2 + 8:
            S.note(6, 1, F(b, bt), F(b, bt + d), vib(n, -2, 18, 5, 5.2), PUL, 0x68, (sus(b, 5, 8) << 4) | 7, pw=900, slur=bool(s), tail=30)
    for b, bt, d, n, s in ANS1 + ANS2 + [(CODA + 3, 1, 1, A5, 0), (CODA + 3, 2, 1, Fs5, 1), (CODA + 4, 0, 2.7, D5, 1)]:
        S.note(6, 0, F(b, bt), F(b, bt + d), vib(n + 12, 2, 14, 6, 5.0), TRI, 0x68, 0x58, slur=bool(s), tail=40)
    for e in part_harp():
        b, bt, d, n, _ = e
        S.note(6, 2, F(b, bt), F(b, bt + d), nhz(n - 12) * cents(3), TRI, 0x09, 0x09, gap=1, hr=True, tail=40)
    S.route[:, 6] = 2; S.mode[:, 6] = BP | LP; S.res[:, 6] = 1
    # ---- SID 8 (index 7): basses (with the cellos, the other side) and timpani
    for bar in range(P1 + 1, CODA):
        bn = bass_events(bar)
        for i, (bt, n) in enumerate(bn):
            d = (bn[i + 1][0] - bt - 0.15) if i + 1 < len(bn) else min(1.75, 2.85 - bt)
            S.note(7, 0, F(bar, bt), F(bar, bt + d), nhz(n - 12) * cents(4), PUL, 0x39, (sus(bar, 6, 9) << 4) | 7, pw=pws(1400, 300, 150), tail=40)
            S.note(7, 1, F(bar, bt), F(bar, bt + d), nhz(n) * cents(-3), SAW, 0x49, (sus(bar, 5, 8) << 4) | 7, tail=40)
    S.note(7, 0, F(6, 0), F(10, 0), nhz(33), PUL, 0xA8, 0x59, pw=1200, tail=60)
    S.note(7, 0, F(10, 0), F(11, 1.8), nhz(38), PUL, 0x98, 0x79, pw=1200, tail=60)
    S.note(7, 0, F(CODA, 0), F(CODA + 4, 2.5), nhz(38), PUL, 0x98, 0x89, pw=1200, tail=60)
    def roll(b0, b1, n, s0, s1):
        """a soft timpani roll: a pitched triangle bowed fast, its level swelling from s0 to s1"""
        f0, f1 = F(*b0), F(*b1)
        seg = 12
        for f in range(f0, f1, seg):
            s = int(round(s0 + (s1 - s0) * (f - f0) / max(1, f1 - f0)))
            S.note(7, 2, f, min(f1, f + seg) + 2, lambda k, h=nhz(n): h * (1 + 0.004 * math.sin(k)), TRI, 0x22, (s << 4) | 3, trem=True, gap=0, tail=20)
    roll((10, 0), (11, 0.9), 38, 3, 10)
    roll((P2 + 22, 0), (P2 + 24, 0), 40, 4, 11)
    roll((P2 + 27, 0), (P2 + 28, 0), 38, 4, 10)
    roll((CODA + 3, 0), (CODA + 5, 0), 38, 8, 2)
    S.mode[:, 7] = LP
    # the filters follow the dynamics (the swells open them), the volumes balance the sections
    d = np.array([dyn(b) for b in np.interp(t, BSTART[::3], list(range(NBARS + 1)))])
    base = {2: 520, 3: 560, 4: 480, 5: 500, 6: 700, 7: 360}
    for c, b0 in base.items(): S.cut[:, c] = b0 + 420 * d
    # out of near silence: the tremolo's SIDs open from a closed filter through the introduction
    ramp = np.interp(t, [0, F(2, 0), F(6, 0), F(INTRO, 0)], [0.0, 0.45, 0.8, 1.0])
    for c in (2, 3): S.cut[:, c] *= ramp
    S.route[:, 7] = 3
    vols = {2: 10, 3: 10, 4: 9, 5: 10, 6: 10, 7: 11}
    for c, v in vols.items(): S.vol[:, c] = v
    if ONLY is not None:
        for c in range(2, 8):
            if 's%d' % (c + 1) not in ONLY: S.gate[:, c, :] = False; S.hr[:, c, :] = False
    r = S.regs()[:, 2:8, :]
    r.reshape(N * 6 * 32).astype(np.uint8).tofile(path)

def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    nb = song_asm(os.path.join(out, 'song.asm'))
    render8(os.path.join(out, 'music8.bin'))
    print(NFR)
    sys.stderr.write('song: %d frames (%.1f s), %d bytes of song data\n' % (NFR, NFR / 50.0, nb))

if __name__ == '__main__':
    main()
