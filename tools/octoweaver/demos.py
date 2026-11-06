#!/usr/bin/env python3
"""demos.py - the three Octo Weaver Lite demo songs, written with owsong.py (original notes, made for this).
   python3 demos.py OUTDIR          writes DARK DRIVE.ows, OCEAN LIGHTS.ows, SKIP ROPE.ows
Each song: 8 tracks = 8 SIDs, each SID one job; the SHAPE entrance (track n comes in at bar 2n); under two minutes."""
import os, sys
from owsong import *

NAMES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
def nn(name):
    """'A-4' 'C#5' 'G#3' 'Bb2' -> note 1-96 (C0 = 1)"""
    pc = NAMES[name[0]]
    if name[1] == '#': pc += 1
    elif name[1] == 'b': pc -= 1
    return int(name[2]) * 12 + pc + 1
def root(pc, octv): return octv * 12 + pc + 1

def pat(s, t, p, notes, snd):
    """notes: {step: 'A-4' | number | 'OFF' | ('A-4', sound)}; snd = the default sound of the pattern"""
    steps = [0] * 16
    for k, v in notes.items():
        if isinstance(v, tuple): steps[k] = (nn(v[0]) if isinstance(v[0], str) and v[0] != 'OFF' else v[0], v[1])
        elif isinstance(v, str) and v != 'OFF': steps[k] = (nn(v), snd)
        elif v == 'OFF': steps[k] = 'OFF'
        else: steps[k] = (v, snd)
    s.pat(t, p, steps)

def shape(s, t, lens, first, plan):
    """bar list of track t: bar b (>= first) plays pattern plan(b), 0 = silent"""
    s.bars(t, [plan(b) if b >= first else 0 for b in range(lens)])

def finish(s, names, roles, tsnd, cuts, ress, modes, vols, lfos):
    for t in range(8):
        s.set_name(t, names[t]); s.b[H_ROLE + t] = roles[t]; s.b[H_TSND + t] = tsnd[t]
        s.dial(t, cut=cuts[t], res=ress[t], mode=modes[t], vol=vols[t], lfo=lfos[t])
    return s

# ====================================================================================================== DARK DRIVE
def dark_drive():
    """A minor, 125 bpm, Am F Dm E.  REESE DRUMS BASS PAD HATS LEAD BELLS FX: a track every 2 bars, 48 bars = 92 s."""
    s = Song('DARK DRIVE'); s.b[H_SPEED] = 6; s.b[H_KEY] = 9; s.b[H_SCALE] = 1; s.b[H_CHORDS:H_CHORDS + 4] = bytes([0, 5, 3, 4]); s.b[H_LEN] = 48
    KICK, SNARE, HAT, BASS, REESE, PADM, PADJ, LEAD, BELL, RISE, ZAP, BASS2 = range(1, 13)
    s.sound(KICK, wave=TRI, ad=0x06, sr=0x00, voicing=DRUMS, wp=(NOISE, NOISE, 0, 0), fall=10)
    s.sound(SNARE, wave=NOISE, ad=0x05, sr=0x00, voicing=DRUMS, detune=5, wp=(NOISE, 0, 0, 0))
    s.sound(HAT, wave=NOISE, ad=0x02, sr=0x00, voicing=UNISON, detune=7)
    s.sound(BASS, wave=PULSE, ad=0x06, sr=0xc5, pw=4, voicing=UNISON, detune=3)
    s.sound(REESE, wave=SAW, ad=0x2a, sr=0xf9, voicing=UNISON, detune=11, filt=1)
    s.sound(PADM, wave=PULSE, ad=0x6a, sr=0xc9, pw=8, pwm=4, voicing=MINOR)
    s.sound(PADJ, wave=PULSE, ad=0x6a, sr=0xc9, pw=8, pwm=4, voicing=MAJOR)
    s.sound(LEAD, wave=PULSE, ad=0x09, sr=0xca, pw=5, pwm=3, vib=3, voicing=UNISON, detune=4)
    s.sound(BELL, wave=PULSE, ad=0x08, sr=0xa8, pw=8, voicing=OCTAVES)
    s.sound(RISE, wave=NOISE, ad=0xc0, sr=0xf8, filt=1)
    s.sound(ZAP, wave=PULSE, ad=0x07, sr=0x00, pw=8, fall=12)
    s.sound(BASS2, wave=PULSE, ad=0x07, sr=0xa5, pw=3)
    pcs = [9, 5, 2, 4]                                  # Am F Dm E
    pm = [PADM, PADJ, PADM, PADJ]                       # the pad's voicing for each chord (F and E are major)
    # --- T0 DRUMS (SID 1): sparse kick, backbeat snare
    k = 'A-1'
    d = {1: {0: k, 8: ('C-3', SNARE), 11: k}, 2: {0: k, 6: k, 8: ('C-3', SNARE), 14: k}, 3: {0: k, 8: ('C-3', SNARE), 11: k},
         4: {0: k, 8: ('C-3', SNARE), 10: k, 12: ('C-3', SNARE), 14: ('C-3', SNARE), 15: ('C-3', SNARE)}}
    d[5] = {0: k, 4: k, 8: ('C-3', SNARE), 10: k, 12: k}                          # B: busier kick
    d[6] = {0: k, 3: k, 6: k, 8: ('C-3', SNARE), 11: k, 14: k}
    d[7] = d[5]; d[8] = {0: k, 8: ('C-3', SNARE), 10: k, 12: ('C-3', SNARE), 13: ('C-3', SNARE), 14: ('C-3', SNARE), 15: ('C-3', SNARE)}
    for p, st in d.items(): pat(s, 1, p, st, KICK)
    # --- T1 BASS (SID 2): driving eighths with octave pops
    for i, pc in enumerate(pcs):
        r = root(pc, 1); o = r + 12
        pat(s, 2, 1 + i, {0: r, 2: r, 4: r, 6: o, 8: r, 10: r, 12: r, 14: o}, BASS)
        pat(s, 2, 5 + i, {0: r, 3: r, 6: o, 8: r, 10: r, 11: o, 14: r, 15: o}, BASS)
    # --- T2 REESE (SID 3): a held saw stack, the filter breathes (LFO)
    for i, pc in enumerate(pcs):
        r = root(pc, 2)
        pat(s, 0, 1 + i, {0: r, 12: r + 7}, REESE)
        pat(s, 0, 5 + i, {0: r, 6: r + 12, 8: r, 14: r + 7}, REESE)
    # --- T3 PAD (SID 4): the chord held a bar
    for i, pc in enumerate(pcs):
        r = root(pc, 3)
        pat(s, 3, 1 + i, {0: r}, pm[i]); pat(s, 3, 5 + i, {0: r, 8: r}, pm[i])
    # --- T4 HATS (SID 5): light offbeats
    pat(s, 4, 1, {2: 'C-6', 6: 'C-6', 10: 'C-6', 14: 'C-6'}, HAT)
    pat(s, 4, 2, {2: 'C-6', 6: 'C-6', 10: 'C-6', 13: 'C-6', 14: 'C-6'}, HAT)
    pat(s, 4, 3, {2: 'C-6', 6: 'C-6', 10: 'C-6', 14: 'C-6'}, HAT)
    pat(s, 4, 4, {2: 'C-6', 6: 'C-6', 10: 'C-6', 12: 'C-6', 13: 'C-6', 14: 'C-6', 15: 'C-6'}, HAT)
    pat(s, 4, 5, {0: 'C-6', 2: 'C-6', 4: 'C-6', 6: 'C-6', 8: 'C-6', 10: 'C-6', 12: 'C-6', 14: 'C-6'}, HAT)
    # --- T5 LEAD (SID 6): the hook, then its answer
    hook = [{0: 'E-5', 3: 'C-5', 6: 'A-4', 8: 'C-5', 10: 'E-5', 14: 'OFF'},
            {0: 'F-5', 3: 'C-5', 6: 'A-4', 8: 'C-5', 10: 'F-5', 14: 'OFF'},
            {0: 'D-5', 3: 'A-4', 6: 'F-4', 8: 'A-4', 10: 'D-5', 14: 'OFF'},
            {0: 'G#4', 3: 'B-4', 6: 'E-5', 8: 'B-4', 10: 'G#4', 14: 'OFF'}]
    ans = [{0: 'A-5', 4: 'G-5', 6: 'E-5', 8: 'C-5', 12: 'E-5', 14: 'OFF'},
           {0: 'A-5', 4: 'C-6', 6: 'A-5', 8: 'F-5', 12: 'A-5', 14: 'OFF'},
           {0: 'F-5', 2: 'A-5', 4: 'F-5', 6: 'D-5', 8: 'A-4', 12: 'D-5', 14: 'OFF'},
           {0: 'E-5', 2: 'G#5', 4: 'B-5', 8: 'G#5', 10: 'E-5', 12: 'B-4', 14: 'OFF'}]
    for i in range(4): pat(s, 5, 1 + i, hook[i], LEAD); pat(s, 5, 5 + i, ans[i], LEAD)
    # --- T6 BELLS (SID 7): sparse sparkles on chord tones
    bl = [('E-6', 'A-5'), ('C-6', 'A-5'), ('A-5', 'F-5'), ('G#5', 'B-5')]
    for i in range(4):
        pat(s, 6, 1 + i, {0: bl[i][0], 11: bl[i][1]}, BELL)
        pat(s, 6, 5 + i, {0: bl[i][0], 6: bl[i][1], 11: bl[i][0], 14: bl[i][1]}, BELL)
    # --- T7 FX (SID 8): a riser every 8 bars (pattern 1), a zap (2)
    pat(s, 7, 1, {0: 'C-5', 15: 'OFF'}, RISE)
    pat(s, 7, 2, {0: ('A-6', ZAP), 4: ('E-6', ZAP), 8: ('A-5', ZAP)}, ZAP)
    pat(s, 7, 3, {0: 'C-5'}, RISE)
    # --- the bars: SHAPE (track n from bar 2n), then the sections
    L = 48
    def chord(b): return b % 4
    def A(b): return 1 + chord(b)
    def B(b): return 5 + chord(b)
    shape(s, 1, L, 2, lambda b: (8 if b == 47 else 4 if b % 8 == 7 else B(b) if 24 <= b < 32 else 0 if 32 <= b < 36 else A(b)))
    shape(s, 2, L, 4, lambda b: (0 if 32 <= b < 34 else B(b) if 24 <= b < 32 or b >= 40 else A(b)))
    shape(s, 0, L, 0, lambda b: (B(b) if 24 <= b < 32 or b >= 40 else A(b)))
    shape(s, 3, L, 6, lambda b: A(b))
    shape(s, 4, L, 8, lambda b: (0 if 32 <= b < 36 else 5 if 24 <= b < 32 else 4 if b % 8 == 7 else A(b)))
    shape(s, 5, L, 10, lambda b: (0 if 32 <= b < 36 else B(b) if 24 <= b < 32 or b >= 40 else A(b)))
    shape(s, 6, L, 12, lambda b: (B(b) if 24 <= b < 32 or b >= 36 else A(b)))
    shape(s, 7, L, 14, lambda b: (1 if b in (14, 22, 30, 34, 38) else 2 if b % 8 == 0 and b >= 16 else 0))
    return finish(s, ['REESE', 'DRUMS', 'BASS', 'PAD', 'HATS', 'LEAD', 'BELLS', 'FX'], [3, 4, 2, 0, 5, 1, 6, 7], [REESE, KICK, BASS, PADM, HAT, LEAD, BELL, RISE],
                  cuts=[70, 160, 160, 160, 160, 160, 160, 90], ress=[9, 2, 2, 2, 2, 2, 2, 8], modes=[1] * 8, vols=[15, 15, 15, 14, 12, 14, 12, 12],
                  lfos=[(3, 10), None, None, None, None, None, None, (2, 12)])

# ====================================================================================================== OCEAN LIGHTS
def ocean_lights():
    """D major, 83 bpm (slow), D Bm G A: wide pads, a gentle pulse lead, sparkling lights; waves of noise.  32 bars = 92 s."""
    s = Song('OCEAN LIGHTS'); s.b[H_SPEED] = 9; s.b[H_KEY] = 2; s.b[H_SCALE] = 0; s.b[H_CHORDS:H_CHORDS + 4] = bytes([0, 5, 3, 4]); s.b[H_LEN] = 32
    PAD, SUB, STR, LEAD, PLUCK, LIGHT, WAVE, SOFT, KICK, SHK = range(1, 11)
    s.sound(PAD, wave=PULSE, ad=0xa8, sr=0xaa, pw=8, pwm=3, voicing=UNISON, detune=6)
    s.sound(SUB, wave=TRI, ad=0x58, sr=0xc9, voicing=UNISON, detune=2)
    s.sound(STR, wave=SAW, ad=0xb9, sr=0xc9, voicing=MAJOR, filt=1)
    s.sound(LEAD, wave=PULSE, ad=0x6a, sr=0xcb, pw=5, pwm=2, vib=4, voicing=UNISON, detune=4)
    s.sound(PLUCK, wave=PULSE, ad=0x08, sr=0x00, pw=4, arp=2, voicing=UNISON, detune=3)
    s.sound(LIGHT, wave=TRI, ad=0x07, sr=0x9a, voicing=OCTAVES)
    s.sound(WAVE, wave=NOISE, ad=0xca, sr=0xfa, filt=1)
    s.sound(SOFT, wave=NOISE, ad=0x07, sr=0x00, filt=1)
    s.sound(KICK, wave=TRI, ad=0x07, sr=0x00, voicing=DRUMS, wp=(NOISE, 0, 0, 0), fall=8)
    s.sound(SHK, wave=NOISE, ad=0x04, sr=0x00, voicing=UNISON, detune=6)
    pcs = [2, 11, 7, 9]                                 # D Bm G A
    deg = [0, 5, 3, 4]
    # T0 PAD: a wide chord a bar (root + fifth + octave from the unison pair on two notes)
    for i, pc in enumerate(pcs):
        r = root(pc, 3); pat(s, 0, 1 + i, {0: r, 8: r + 7}, PAD); pat(s, 0, 5 + i, {0: r + 12, 8: r + 7 + 12}, PAD)
    # T1 SUB: long roots
    for i, pc in enumerate(pcs):
        r = root(pc, 1); pat(s, 1, 1 + i, {0: r, 10: r + 7}, SUB); pat(s, 1, 5 + i, {0: r, 6: r + 12, 10: r + 7, 14: r + 12}, SUB)
    # T2 STRINGS: slow major triads high up, a second pad
    for i, pc in enumerate(pcs):
        r = root(pc, 4); pat(s, 2, 1 + i, {0: r}, STR)
    # T3 LEAD: gentle pulse melody (D major pentatonic)
    mel = [{0: 'A-4', 4: 'F#4', 8: 'A-4', 12: 'B-4'}, {0: 'D-5', 6: 'B-4', 10: 'A-4', 14: 'F#4'}, {0: 'B-4', 4: 'D-5', 8: 'G-4', 12: 'B-4'}, {0: 'A-4', 5: 'C#5', 8: 'E-5', 14: 'OFF'}]
    mel2 = [{0: 'F#5', 4: 'E-5', 8: 'D-5', 12: 'A-4'}, {0: 'D-5', 4: 'F#5', 8: 'A-5', 14: 'OFF'}, {0: 'G-5', 4: 'D-5', 8: 'B-4', 12: 'D-5'}, {0: 'E-5', 6: 'C#5', 10: 'A-4', 14: 'OFF'}]
    for i in range(4): pat(s, 3, 1 + i, mel[i], LEAD); pat(s, 3, 5 + i, mel2[i], LEAD)
    # T4 PLUCK: arpeggios (the arp is the sound's: a major chord at 50 Hz), on the beat
    for i, pc in enumerate(pcs):
        r = root(pc, 4); pat(s, 4, 1 + i, {0: r, 4: r, 8: r, 12: r}, PLUCK); pat(s, 4, 5 + i, {0: r, 3: r, 6: r, 8: r, 11: r, 14: r}, PLUCK)
    # T5 LIGHTS: sparkles
    lt = [('F#6', 'A-6'), ('D-6', 'B-5'), ('B-5', 'D-6'), ('E-6', 'C#6')]
    for i in range(4): pat(s, 5, 1 + i, {2: lt[i][0], 9: lt[i][1]}, LIGHT); pat(s, 5, 5 + i, {2: lt[i][0], 5: lt[i][1], 9: lt[i][0], 13: lt[i][1]}, LIGHT)
    # T6 WAVES: noise swells, each over two bars (a swell in, a long fade)
    pat(s, 6, 1, {0: 'C-4', 14: 'OFF'}, WAVE); pat(s, 6, 2, {0: 'C-3', 14: 'OFF'}, WAVE)
    # T7 PERC: a soft kick and a shaker (sparse)
    pat(s, 7, 1, {0: ('A-1', KICK), 8: ('A-1', KICK), 4: ('C-6', SHK), 12: ('C-6', SHK)}, KICK)
    pat(s, 7, 2, {0: ('A-1', KICK), 8: ('A-1', KICK), 4: ('C-6', SHK), 6: ('C-6', SHK), 10: ('C-6', SHK), 12: ('C-6', SHK), 14: ('C-6', SHK)}, KICK)
    L = 32
    def A(b): return 1 + b % 4
    def B(b): return 5 + b % 4
    shape(s, 0, L, 0, lambda b: B(b) if 16 <= b < 24 else A(b))
    shape(s, 1, L, 2, lambda b: B(b) if 16 <= b < 24 else A(b))
    shape(s, 2, L, 4, A)
    shape(s, 3, L, 6, lambda b: 0 if 24 <= b < 26 else B(b) if 20 <= b < 24 or b >= 28 else A(b))
    shape(s, 4, L, 8, lambda b: B(b) if 16 <= b < 24 else A(b))
    shape(s, 5, L, 10, lambda b: B(b) if 16 <= b < 28 else A(b))
    shape(s, 6, L, 12, lambda b: 1 if b % 4 == 0 else 2 if b % 4 == 2 else 0)
    shape(s, 7, L, 14, lambda b: 0 if 24 <= b < 28 else 2 if b >= 28 else 1)
    return finish(s, ['PAD', 'SUB', 'STRING', 'LEAD', 'PLUCK', 'LIGHTS', 'WAVES', 'PERC'], [0, 2, 0, 1, 6, 6, 7, 4], [PAD, SUB, STR, LEAD, PLUCK, LIGHT, WAVE, KICK],
                  cuts=[160, 160, 120, 160, 160, 160, 100, 160], ress=[2, 2, 5, 2, 2, 2, 6, 2], modes=[1] * 8, vols=[15, 15, 13, 14, 13, 11, 12, 12],
                  lfos=[None, None, (2, 8), None, None, None, (1, 14), None])

# ====================================================================================================== SKIP ROPE
def skip_rope():
    """C major, 150 bpm, C Am F G.  SID 1 and 2 are the two ropes (noise slaps between each other's beats), then the rest join.  48 bars = 77 s."""
    s = Song('SKIP ROPE'); s.b[H_SPEED] = 5; s.b[H_KEY] = 0; s.b[H_SCALE] = 0; s.b[H_CHORDS:H_CHORDS + 4] = bytes([0, 5, 3, 4]); s.b[H_LEN] = 48
    ROPEL, ROPER, BASS, CLAP, CHANT, STAB, BELL, BLIP, KICK, WHIS = range(1, 11)
    s.sound(ROPEL, wave=NOISE, ad=0x04, sr=0x00, voicing=UNISON, detune=6)
    s.sound(ROPER, wave=NOISE, ad=0x05, sr=0x00, voicing=UNISON, detune=9)
    s.sound(BASS, wave=PULSE, ad=0x06, sr=0xb5, pw=6, voicing=UNISON, detune=2)
    s.sound(CLAP, wave=NOISE, ad=0x05, sr=0x00, voicing=DRUMS, detune=5, wp=(NOISE, 0, 0, 0))
    s.sound(CHANT, wave=PULSE, ad=0x05, sr=0xa6, pw=7, pwm=2, voicing=UNISON, detune=3)
    s.sound(STAB, wave=PULSE, ad=0x05, sr=0x60, pw=8, voicing=MAJOR)
    s.sound(BELL, wave=TRI, ad=0x07, sr=0x9a, voicing=OCTAVES)
    s.sound(BLIP, wave=PULSE, ad=0x06, sr=0x00, pw=4, fall=6, voicing=UNISON, detune=3)
    s.sound(KICK, wave=TRI, ad=0x05, sr=0x00, voicing=DRUMS, wp=(NOISE, NOISE, 0, 0), fall=10)
    s.sound(WHIS, wave=TRI, ad=0x4a, sr=0xa8, glide=10)
    pcs = [0, 9, 5, 7]                                  # C Am F G
    # T0 / T1: the two ropes: quarter-note slaps; the second lands on the offbeat between the first's
    pat(s, 0, 1, {0: ('C-3', ROPEL), 4: ('C-3', ROPEL), 8: ('C-3', ROPEL), 12: ('C-3', ROPEL)}, ROPEL)
    pat(s, 0, 2, {0: ('C-3', ROPEL), 4: ('C-3', ROPEL), 8: ('C-3', ROPEL), 10: ('C-3', ROPEL), 12: ('C-3', ROPEL), 14: ('C-3', ROPEL)}, ROPEL)
    pat(s, 1, 1, {2: ('G-4', ROPER), 6: ('G-4', ROPER), 10: ('G-4', ROPER), 14: ('G-4', ROPER)}, ROPER)
    pat(s, 1, 2, {2: ('G-4', ROPER), 6: ('G-4', ROPER), 10: ('G-4', ROPER), 11: ('G-4', ROPER), 14: ('G-4', ROPER), 15: ('G-4', ROPER)}, ROPER)
    # T2 BASS: bouncy
    for i, pc in enumerate(pcs):
        r = root(pc, 2); pat(s, 2, 1 + i, {0: r, 3: r, 6: r + 12, 8: r, 11: r, 14: r + 12}, BASS)
        pat(s, 2, 5 + i, {0: r, 2: r + 12, 4: r, 6: r + 12, 8: r, 10: r + 12, 12: r + 7, 14: r + 12}, BASS)
    # T3 CLAP: claps on 2 and 4, a kick below on 1
    pat(s, 3, 1, {0: ('A-1', KICK), 4: ('C-3', CLAP), 8: ('A-1', KICK), 12: ('C-3', CLAP)}, CLAP)
    pat(s, 3, 2, {0: ('A-1', KICK), 4: ('C-3', CLAP), 8: ('A-1', KICK), 10: ('A-1', KICK), 12: ('C-3', CLAP), 14: ('C-3', CLAP), 15: ('C-3', CLAP)}, CLAP)
    # T4 CHANT: a pulse melody, three short notes and a long, like a skipping chant
    ch = [{0: 'E-5', 2: 'E-5', 4: 'G-5', 8: 'E-5', 10: 'D-5', 12: 'C-5', 14: 'OFF'},
          {0: 'E-5', 2: 'E-5', 4: 'A-5', 8: 'G-5', 10: 'E-5', 12: 'C-5', 14: 'OFF'},
          {0: 'C-5', 2: 'C-5', 4: 'F-5', 8: 'E-5', 10: 'D-5', 12: 'C-5', 14: 'OFF'},
          {0: 'D-5', 2: 'D-5', 4: 'G-5', 8: 'F-5', 10: 'E-5', 12: 'D-5', 14: 'OFF'}]
    ch2 = [{0: 'G-5', 2: 'G-5', 4: 'C-6', 6: 'B-5', 8: 'G-5', 12: 'E-5', 14: 'OFF'},
           {0: 'A-5', 2: 'A-5', 4: 'C-6', 6: 'B-5', 8: 'A-5', 12: 'E-5', 14: 'OFF'},
           {0: 'A-5', 2: 'A-5', 4: 'C-6', 6: 'A-5', 8: 'F-5', 12: 'C-5', 14: 'OFF'},
           {0: 'B-5', 2: 'B-5', 4: 'D-6', 6: 'C-6', 8: 'B-5', 12: 'G-5', 14: 'OFF'}]
    for i in range(4): pat(s, 4, 1 + i, ch[i], CHANT); pat(s, 4, 5 + i, ch2[i], CHANT)
    # T5 STAB: chord stabs on the offbeat
    for i, pc in enumerate(pcs):
        r = root(pc, 3); pat(s, 5, 1 + i, {2: r, 6: r, 10: r, 14: r}, STAB); pat(s, 5, 5 + i, {2: r, 3: r, 6: r, 10: r, 11: r, 14: r}, STAB)
    # T6 BELLS
    bl = [('E-6', 'C-6'), ('C-6', 'A-5'), ('A-5', 'C-6'), ('B-5', 'D-6')]
    for i in range(4): pat(s, 6, 1 + i, {0: bl[i][0], 8: bl[i][1]}, BELL); pat(s, 6, 5 + i, {0: bl[i][0], 4: bl[i][1], 8: bl[i][0], 12: bl[i][1]}, BELL)
    # T7 BLIPS: ping-pong zaps and a whistle
    pat(s, 7, 1, {6: ('C-6', BLIP), 14: ('G-5', BLIP)}, BLIP)
    pat(s, 7, 2, {0: ('C-5', WHIS), 8: ('G-5', WHIS), 15: 'OFF'}, WHIS)
    L = 48
    def A(b): return 1 + b % 4
    def B(b): return 5 + b % 4
    shape(s, 0, L, 0, lambda b: 2 if b % 8 == 7 or 32 <= b < 40 else 1)
    shape(s, 1, L, 2, lambda b: 2 if b % 8 == 7 or 32 <= b < 40 else 1)
    shape(s, 2, L, 4, lambda b: 0 if 28 <= b < 30 else B(b) if 24 <= b < 40 else A(b))
    shape(s, 3, L, 6, lambda b: 2 if b % 4 == 3 else 1)
    shape(s, 4, L, 8, lambda b: 0 if 36 <= b < 38 else B(b) if 24 <= b < 32 or b >= 40 else A(b))
    shape(s, 5, L, 10, lambda b: 0 if 36 <= b < 38 else (B(b) if 24 <= b < 36 else A(b)))
    shape(s, 6, L, 12, lambda b: B(b) if 16 <= b < 24 or b >= 32 else A(b))
    shape(s, 7, L, 14, lambda b: 2 if b in (23, 31, 39, 47) else 1 if b % 2 == 0 else 0)
    return finish(s, ['ROPE L', 'ROPE R', 'BASS', 'CLAPS', 'CHANT', 'STABS', 'BELLS', 'BLIPS'], [4, 5, 2, 4, 1, 0, 6, 7], [ROPEL, ROPER, BASS, CLAP, CHANT, STAB, BELL, BLIP],
                  cuts=[160] * 8, ress=[2] * 8, modes=[1] * 8, vols=[15, 15, 15, 15, 14, 12, 12, 12], lfos=[None] * 8)

SONGS = [('DARK DRIVE', dark_drive), ('OCEAN LIGHTS', ocean_lights), ('SKIP ROPE', skip_rope)]

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')
    os.makedirs(out, exist_ok=True)
    for name, fn in SONGS:
        sg = fn(); sg.save(os.path.join(out, name + '.ows'))
        used = [sum(1 for b in sg.get_bars(t)[:sg.b[H_LEN]] if b) for t in range(8)]
        secs = sg.b[H_LEN] * 16 * sg.b[H_SPEED] / 50.1245
        print('%-13s %d bars, %.0f s, bars played per track %s' % (name, sg.b[H_LEN], secs, used))
