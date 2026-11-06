#!/usr/bin/env python3
"""owsong.py - the Octo Weaver song (.OWS) in Python: the same bytes the 6502 editor and player use (docs/OCTOWEAVER.md).
A song is 14080 bytes in memory (the player's SONG block); the file is 'OWS1' followed by those bytes.
The Windows version will start from this."""
import struct

SONGSIZE = 14080
H_SPEED, H_KEY, H_SCALE, H_CHORDS, H_LEN, H_NAMES, H_DCUT, H_DRES, H_DMV, H_SNAME = 0, 1, 2, 3, 7, 16, 64, 72, 80, 96
SND, PAT, BAR = 256, 768, 768 + 12288
TRI, SAW, PULSE, NOISE, RING, SYNC = 0x10, 0x20, 0x40, 0x80, 4, 2
ONE, UNISON, OCTAVES, POWER, MAJOR, MINOR, DRUMS = range(7)
KEYS = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
SCALES = ['MAJOR', 'MINOR', 'MIN PENT', 'MAJ PENT', 'DORIAN', 'BLUES']
SCALE_NOTES = [[0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 8, 10], [0, 3, 5, 7, 10], [0, 2, 4, 7, 9], [0, 2, 3, 5, 7, 9, 10], [0, 3, 5, 6, 7, 10]]
JOBS = ['PAD', 'LEAD', 'BASS', 'REESE', 'DRUMS', 'HATS', 'BELLS', 'FX']
NOTENAMES = ['C-', 'C#', 'D-', 'D#', 'E-', 'F-', 'F#', 'G-', 'G#', 'A-', 'A#', 'B-']

def note(name):
    """'C-4' / 'F#3' -> 1-96 (C0 = 1)"""
    pc = NOTENAMES.index(name[:2]); return (int(name[2]) * 12) + pc + 1
def note_name(n):
    return NOTENAMES[(n - 1) % 12] + str((n - 1) // 12)

class Song:
    def __init__(s, name='NEW SONG'):
        s.b = bytearray(SONGSIZE)
        s.b[H_SPEED] = 6; s.b[H_KEY] = 9; s.b[H_SCALE] = 1; s.b[H_CHORDS:H_CHORDS + 4] = bytes([0, 5, 3, 4]); s.b[H_LEN] = 32
        for t in range(8):
            s.set_name(t, JOBS[t]); s.b[H_DCUT + t] = 160; s.b[H_DRES + t] = 0x20; s.b[H_DMV + t] = 0x1f
        s.b[H_SNAME:H_SNAME + 16] = name.upper().ljust(16)[:16].encode()
    # --- header
    def set_name(s, t, n): s.b[H_NAMES + 6 * t:H_NAMES + 6 * t + 6] = n.upper().ljust(6)[:6].encode()
    def name(s, t): return s.b[H_NAMES + 6 * t:H_NAMES + 6 * t + 6].decode().rstrip()
    def dial(s, t, cut=None, res=None, mode=None, vol=None):
        if cut is not None: s.b[H_DCUT + t] = cut
        if res is not None: s.b[H_DRES + t] = res << 4
        if mode is not None or vol is not None:
            m = (s.b[H_DMV + t] >> 4) if mode is None else mode; v = (s.b[H_DMV + t] & 15) if vol is None else vol
            s.b[H_DMV + t] = (m << 4) | v
    # --- sounds (1-31)
    def sound(s, n, wave=PULSE, ad=0x09, sr=0xa8, pw=8, pwm=0, vib=0, voicing=ONE, detune=0, arp=0, glide=0, filt=0, wp=(0, 0, 0, 0), fall=0):
        o = SND + 16 * n
        s.b[o:o + 16] = bytes([wave, ad, sr, pw, pwm, vib, voicing, detune, arp, glide, filt, *wp, fall])
    def get_sound(s, n): return bytes(s.b[SND + 16 * n:SND + 16 * n + 16])
    # --- patterns: track t (0-7), pattern p (1-48): 16 notes then 16 sounds
    def pat(s, t, p, steps):
        """steps: list of 16 items: 0 / None (nothing), 'OFF' (stop), 'C-4' or number, or (note, sound) tuples; the sound defaults to the last used"""
        o = PAT + t * 1536 + (p - 1) * 32; last = 1
        for i in range(16):
            x = steps[i] if i < len(steps) else 0
            if isinstance(x, tuple): x, snd = x
            else: snd = None
            if x in (0, None): n = 0
            elif x == 'OFF': n = 255
            elif isinstance(x, str): n = note(x)
            else: n = x
            if snd is not None: last = snd
            s.b[o + i] = n; s.b[o + 16 + i] = last if n not in (0, 255) else 0
    def get_pat(s, t, p):
        o = PAT + t * 1536 + (p - 1) * 32; return bytes(s.b[o:o + 32])
    def set_pat_bytes(s, t, p, data): o = PAT + t * 1536 + (p - 1) * 32; s.b[o:o + 32] = data
    # --- bars
    def bars(s, t, lst): s.b[BAR + t * 128:BAR + t * 128 + len(lst)] = bytes(lst)
    def get_bars(s, t): return bytes(s.b[BAR + t * 128:BAR + t * 128 + 128])
    # --- files
    def to_bytes(s): return bytes(s.b)
    def to_file(s): return b'OWS1' + bytes(s.b)
    @staticmethod
    def from_file(data):
        assert data[:4] == b'OWS1' and len(data) == 4 + SONGSIZE, 'not an OWS1 song'
        x = Song(); x.b = bytearray(data[4:]); return x
    def save(s, path): open(path, 'wb').write(s.to_file())
    @staticmethod
    def load(path): return Song.from_file(open(path, 'rb').read())

def scale_notes(key, scale, lo=1, hi=96):
    """every note 1-96 that is in the scale"""
    pcs = {(key + x) % 12 for x in SCALE_NOTES[scale]}
    return [n for n in range(lo, hi + 1) if (n - 1) % 12 in pcs]
