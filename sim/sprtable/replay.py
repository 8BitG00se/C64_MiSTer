# SPRITE TABLE REPLAY: a program's OctoVIC writes, logged by the emulator (OCTO_DUMP=prefix -> prefix.log),
# replayed through OctoVIC's RTL (sim/sprtable/tb, cycle by cycle, DDR3 busy and slow at random) - and for
# every frame the sprite table the RTL draws with is compared with the one the emulator draws with
# (the emulator: the 1024 bytes at SATBASE copied when it draws line 0, as the beam finishes line 309).
#   python3 replay.py RUN E0 NFRAMES OUTDIR [busy% latmin latmax seed]        prints PASS / FAIL
import sys, os, subprocess, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE + '/../octovic')
import ref
run, E0, N, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
busy, lmin, lmax, seed = (int(x) for x in (sys.argv[5:9] if len(sys.argv) > 8 else (30, 6, 40, 1)))
NS = int(os.environ.get('SATN', '64'))
os.makedirs(out, exist_ok=True)
ev = np.fromfile(run + '.log', np.dtype([('f', '<u4'), ('l', '<u2'), ('r', 'u1'), ('v', 'u1'), ('a', '<u4')]))
key = ev['f'].astype(np.int64) * 1000 + ev['l']
e0 = int(np.searchsorted(key, E0 * 1000))
vram = bytearray(16 << 20); o = ref.Octo(vram)
pre = ev[:e0]; w = pre['r'] == 4
np.frombuffer(vram, np.uint8)[pre['a'][w] & 0xFFFFFF] = pre['v'][w]          # (VDATA in bulk)
for x in pre[~w]:
    if x['r'] == 0x7F: o.r[0x7F] = int(x['v'])
    else: o.write(int(x['r']), int(x['v']))
k = np.where(pre['r'] <= 4)[0]
if len(k) and pre['r'][k[-1]] == 4: o.vaddr = (int(pre['a'][k[-1]]) + o.vinc) & 0xFFFFFF
open(out + '/vram.bin', 'wb').write(vram)
L = ['w 19 0', 'w 1a 0']
for c in o.pal: L += ['w 1b %x' % (c >> 16), 'w 1c %x' % ((c >> 8) & 255), 'w 1d %x' % (c & 255)]
L += ['w 19 1', 'w 1a 0']
for c in o.vpal: L += ['w 1b %x' % (c >> 16), 'w 1c %x' % ((c >> 8) & 255), 'w 1d %x' % (c & 255)]
b = o.backdrop; L += ['w 19 2', 'w 1b %x' % (b >> 16), 'w 1c %x' % ((b >> 8) & 255), 'w 1d %x' % (b & 255), 'w 19 %x' % o.palsel]
for r in sorted(o.r):
    if r in (0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x7F, 0x5E, 0x83) or r <= 4: continue
    L.append('w %x %x' % (r, o.r[r]))
# the VRAM address as it was (the program may be part way through a run of VDATA writes)
L += ['w 0 %x' % (o.vaddr & 255), 'w 1 %x' % ((o.vaddr >> 8) & 255), 'w 2 %x' % (o.vaddr >> 16), 'w 3 %x' % o.vinc]
L.append('wait 0 0')
last = None
for x in ev[e0:]:
    f = int(x['f']) - E0; l = int(x['l'])
    if f >= N: break
    if (f, l) != last: L.append('wait %d %d' % (f, l)); last = (f, l)
    L.append('w %x %x' % (int(x['r']), int(x['v'])))
L.append('r b2')                          # LOST: VDATA writes the RTL dropped (its write queue full)
open(out + '/script.txt', 'w').write('\n'.join(L) + '\n')

# the emulator's tables: VRAM and SATBASE as they were when it drew each frame's line 0
exp = {}
vr = bytearray(vram); sat = o.r.get(0x13, 0) | o.r.get(0x14, 0) << 8 | o.r.get(0x15, 0) << 16
snap = lambda: bytes(vr[((sat & ~7) + i) & 0xFFFFFF] for i in range(NS * 8))
exp[0] = snap()
for x in ev[e0:]:
    f = int(x['f']) - E0; l = int(x['l'])
    if f >= N: break
    while len(exp) <= f + (l >= 310):                             # frame k+1's table: copied as line 309 of frame k ends
        exp[len(exp)] = snap()
    r, v = int(x['r']), int(x['v'])
    if r == 4: vr[int(x['a']) & 0xFFFFFF] = v
    elif r in (0x13, 0x14, 0x15): sh = 8 * (r - 0x13); sat = (sat & ~(255 << sh)) | v << sh
res = subprocess.run([HERE + '/obj/tb', out + '/vram.bin', out + '/script.txt', str(N), out + '/pic.rgb',
                      str(seed), str(busy), str(lmin), str(lmax)], capture_output=True, text=True,
                     env=dict(os.environ, VICKEY='1', SATN=str(NS)))
got = {}
for ln in res.stdout.splitlines():
    if ln.startswith('SAT '):
        _, f, i, X, Y, g, c = ln.split(); got.setdefault(int(f), []).append((int(X), int(Y), int(g), int(c)))
def dec(bs):
    a = np.frombuffer(bs, '<u2').reshape(-1, 4).astype(int)
    return [(int(np.int16(e[0])), int(np.int16(e[1])), int(e[2]), int(e[3])) for e in a]
rep = []; bad = 0
for f in range(1, N):                     # (frame 0's table was copied before the replay began)
    if f not in got or f not in exp: continue
    e, g = dec(exp[f]), got[f]
    # which emulator frame's table did the RTL show? (same frame = right; an older one = a stale table)
    seen = next((k for k in range(f, max(0, f - 8), -1) if k in exp and dec(exp[k]) == g), None)
    ok = e == g; bad += not ok
    nd = sum(a != b for a, b in zip(e, g)); di = [i for i, (a, b) in enumerate(zip(e, g)) if a != b]
    rep.append('frame %3d: %s  sprite 0 at (%d,%d), the emulator (%d,%d)%s' % (f, 'same' if ok else 'DIFFERENT (%d of %d sprites)' % (nd, len(e)) + str(di[:12]), g[0][0], g[0][1], e[0][0], e[0][1],
               '' if ok else ('  - the RTL shows frame %d\'s table' % seen if seen is not None else '  - a table the emulator never had')))
lost = [ln.split()[2] for ln in res.stdout.splitlines() if ln.startswith('R b2')]
rep.append('%s: %d of %d frames with a different sprite table (DDR3 busy %d%%, %d-%d clocks%s), VDATA writes lost: %s' % ('PASS' if bad == 0 else 'FAIL', bad, len(rep), busy, lmin, lmax,
           ', stalled %s' % os.environ['STALL'] if os.environ.get('STALL') else '', int(lost[-1], 16) if lost else 'not read (script not finished)'))
open(out + '/report.txt', 'w').write('\n'.join(rep) + '\n'); print('\n'.join(rep))
if not os.environ.get('KEEP'):
    for fn in ('vram.bin', 'pic.rgb'):
        try: os.remove(out + '/' + fn)
        except OSError: pass
sys.exit(1 if bad else 0)
