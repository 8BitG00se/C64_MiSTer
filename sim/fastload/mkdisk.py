#!/usr/bin/env python3
# (c) 2026 Mong00se
# FAST LOAD (Fix 49) simulation: the test disk. A .d64 with one program on it (laid out as the 1541's
# own SAVE lays a file out: every tenth sector), and the same disk as the core's 1541 gets it - a G64
# image (GCR tracks) in the DDR3, as 64-bit words for $readmemh.
#   mkdisk.py BLOCKS out.prg out.d64 out_g64.hex
import sys, random
SPT = lambda t: 21 if t < 18 else 19 if t < 25 else 18 if t < 31 else 17
OFF = {}; o = 0
for t in range(1, 36): OFF[t] = o; o += SPT(t) * 256
def pos(t, s): return OFF[t] + s * 256

blocks = int(sys.argv[1])
random.seed(49)
# the program: a BASIC line (10 SYS2061 would do nothing useful - it is never run) then fixed pseudo-random bytes
body = bytes([0x0B, 0x08, 0x0A, 0x00, 0x8F, 0x20, 0x46, 0x34, 0x39, 0x00, 0x00, 0x00]) + bytes(random.randrange(256) for _ in range(blocks * 254 - 2 - 12))
prg = bytes([0x01, 0x08]) + body
open(sys.argv[2], 'wb').write(prg)

d = bytearray(174848)
free = {t: [True] * SPT(t) for t in range(1, 36)}
def take(t, s): free[t][s] = False
take(18, 0); take(18, 1)
# the file: from track 17 down, each next sector ten on (the first free one from there), as the DOS does
chain = []; t = 17; s = 0
for i in range(0, len(prg), 254):
    while not any(free[t]): t -= 1; s = 0
    n = SPT(t)
    while not free[t][s % n]: s += 1
    s %= n; take(t, s); chain.append((t, s)); s += 10
for i, (t, s) in enumerate(chain):
    part = prg[i * 254:(i + 1) * 254]; p = pos(t, s)
    if i + 1 < len(chain): d[p], d[p + 1] = chain[i + 1]
    else: d[p], d[p + 1] = 0, len(part) + 1
    d[p + 2:p + 2 + len(part)] = part
# the directory: one entry
p = pos(18, 1); d[p], d[p + 1] = 0, 0xFF
d[p + 2] = 0x82; d[p + 3], d[p + 4] = chain[0]
name = b'FASTLOAD TEST'; d[p + 5:p + 21] = name + b'\xA0' * (16 - len(name))
d[p + 30], d[p + 31] = len(chain) & 255, len(chain) >> 8
# the BAM
p = pos(18, 0); d[p], d[p + 1], d[p + 2] = 18, 1, 0x41
for t in range(1, 36):
    bits = 0
    for s in range(SPT(t)):
        if free[t][s]: bits |= 1 << s
    q = p + 4 * t; d[q] = sum(free[t]); d[q + 1], d[q + 2], d[q + 3] = bits & 255, (bits >> 8) & 255, (bits >> 16) & 255
d[p + 0x90:p + 0xA0] = b'OCTOPHONIC SIM' + b'\xA0\xA0'
d[p + 0xA0:p + 0xAB] = b'\xA0\xA0' + b'49' + b'\xA0' + b'2A' + b'\xA0\xA0\xA0\xA0'
open(sys.argv[3], 'wb').write(d)

# the G64: each track as GCR (sync, header, gap, sync, data, gap), its bytes spread evenly round the track
GCR = [0x0A, 0x0B, 0x12, 0x13, 0x0E, 0x0F, 0x16, 0x17, 0x09, 0x19, 0x1A, 0x1B, 0x0D, 0x1D, 0x1E, 0x15]
def gcr(bs):
    out = bytearray(); acc = 0; n = 0
    for b in bs:
        for nib in (b >> 4, b & 15):
            acc = (acc << 5) | GCR[nib]; n += 5
            while n >= 8: out.append((acc >> (n - 8)) & 255); n -= 8
    assert n == 0; return bytes(out)
TLEN = lambda t: 7692 if t < 18 else 7142 if t < 25 else 6666 if t < 31 else 6250
id1, id2 = d[pos(18, 0) + 0xA2], d[pos(18, 0) + 0xA3]
MAXT = 7928
tracks = {}
for t in range(1, 36):
    n = SPT(t); gap = (TLEN(t) - n * 354) // n; tr = bytearray()
    for s in range(n):
        hdr = bytes([0x08, s ^ t ^ id2 ^ id1, s, t, id2, id1, 0x0F, 0x0F])
        data = bytes(d[pos(t, s):pos(t, s) + 256]); ck = 0
        for b in data: ck ^= b
        tr += b'\xFF' * 5 + gcr(hdr) + b'\x55' * 9 + b'\xFF' * 5 + gcr(bytes([0x07]) + data + bytes([ck, 0, 0])) + b'\x55' * gap
    tr += b'\x55' * (TLEN(t) - len(tr))
    tracks[t] = bytes(tr)
g = bytearray(b'GCR-1541' + bytes([0, 84, MAXT & 255, MAXT >> 8]))
base = 12 + 84 * 8
for h in range(84):
    t = h // 2 + 1
    o = base + (t - 1) * (MAXT + 2) if (h % 2 == 0 and t <= 35) else 0
    g += o.to_bytes(4, 'little')
for h in range(84):
    t = h // 2 + 1
    z = (3 if t < 18 else 2 if t < 25 else 1 if t < 31 else 0) if (h % 2 == 0 and t <= 35) else 0
    g += z.to_bytes(4, 'little')
for t in range(1, 36):
    g += len(tracks[t]).to_bytes(2, 'little') + tracks[t] + b'\x00' * (MAXT - len(tracks[t]))
g += b'\x00' * (-len(g) % 8)
with open(sys.argv[4], 'w') as f:
    for i in range(0, len(g), 8): f.write('%016x\n' % int.from_bytes(g[i:i + 8], 'little'))
print('mkdisk: %d blocks from track %d sector %d, %d bytes; G64 %d bytes (%d words)' % (len(chain), chain[0][0], chain[0][1], len(prg), len(g), len(g) // 8))
