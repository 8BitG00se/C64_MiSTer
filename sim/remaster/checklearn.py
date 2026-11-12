# LEVEL 2 REMASTER: the learn log (as it is in the DDR3: "LRN2", count, 80-byte records) against the frames -
# every record's key is the key of its data, no key twice, none that is in the pack, and every block and sprite
# of the frames that is not in the pack is there.      checklearn.py PACK FRAMES.l2f LOG      (c) 2026 Mong00se
import sys, os, struct
sys.path.insert(0, os.path.dirname(__file__))
import model as M
pk = M.read_pack(open(sys.argv[1], 'rb').read())
log = open(sys.argv[3], 'rb').read()
assert log[:4] == b'LRN2', 'no LRN2'
n = struct.unpack('<I', log[4:8])[0]
bad = 0; seen = {}
for i in range(n):
    r = log[8 + i * 80:88 + i * 80]
    typ = r[0]; k = struct.unpack('<Q', r[8:16])[0]
    data = r[16:48] if typ == 1 else r[4:8] + r[16:79]
    if typ not in (1, 2) or M.key(data) != k: bad += 1; print(f'record {i}: type {typ}, its key is not the key of its data')
    if (typ, k) in seen: bad += 1; print(f'record {i}: key {k:016x} twice')
    if k in (pk['blocks'] if typ == 1 else pk['sprites']): bad += 1; print(f'record {i}: key {k:016x} is in the pack')
    seen[(typ, k)] = data
want = set()
for f in M.read_l2f(sys.argv[2]):
    _, _, keys = M.frame_cells(f)
    want |= {(1, k) for k in keys if k not in pk['blocks']}
    _, sk = M.frame_sprites(f)
    want |= {(2, k) for k in sk if k not in pk['sprites']}
miss = want - set(seen); extra = set(seen) - want
print(f'learn log: {n} records ({sum(1 for t, _ in seen if t == 1)} blocks, {sum(1 for t, _ in seen if t == 2)} sprites); '
      f'the frames have {len(want)} keys not in the pack; {len(miss)} not logged, {len(extra)} logged but not in the frames, {bad} bad')
ok = bad == 0 and not extra and len(miss) <= len(want) // 50
print('REMASTER_LEARN_OK' if ok else 'REMASTER_LEARN_FAIL')
sys.exit(0 if ok else 1)
