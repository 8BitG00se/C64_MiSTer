# LEVEL 2 REMASTER: the RTL's pixels against the model (sim/remaster/model.py)        (c) 2026 Mong00se
# check.py PACK FRAMES.l2f RTL.rgb [palette] [on] [PNG] [MODEL.rgb: another model's answer to check too]
import sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import model as M
pk = M.read_pack(open(sys.argv[1], 'rb').read())
frames = M.read_l2f(sys.argv[2])
raw = np.fromfile(sys.argv[3], np.uint8)
pal = int(sys.argv[4]) if len(sys.argv) > 4 else 0
on = len(sys.argv) <= 5 or sys.argv[5] != '0'
other = np.fromfile(sys.argv[7], np.uint8) if len(sys.argv) > 7 and sys.argv[7] else None
o = 0; bad = 0; total = 0; rows = []; obad = 0
for f in frames:
    h, w = f['idx'].shape
    got = raw[o:o + h * w * 3].reshape(h, w, 3)
    want = M.model(pk, f, pal, on)
    d = (got != want).any(-1)
    bad += int(d.sum()); total += h * w
    if d.any():
        ys, xs = np.nonzero(d)
        print(f"frame {f['fno']}: {int(d.sum())} pixels differ, lines {ys.min() + f['line0']}-{ys.max() + f['line0']}, x {xs.min()}-{xs.max()}; "
              f"first x={xs[0]} line={ys[0] + f['line0']}: RTL {got[ys[0], xs[0]].tolist()} model {want[ys[0], xs[0]].tolist()} "
              f"(index {f['idx'][ys[0], xs[0]]}, tag {f['tag'][ys[0], xs[0]]:#x}, cell {f['cell'][ys[0], xs[0]]:#x})")
    if other is not None:
        ot = other[o:o + h * w * 3].reshape(h, w, 3)
        e = (got != ot).any(-1); obad += int(e.sum())
        if e.any():
            ys, xs = np.nonzero(e)
            print(f"frame {f['fno']}: {int(e.sum())} pixels differ from the pack tool's model, first x={xs[0]} line={ys[0] + f['line0']}")
    o += h * w * 3
    if len(sys.argv) > 6 and sys.argv[6]:
        l1 = M.model(pk, f, pal, False)
        mark = got.copy(); mark[d] = (255, 0, 255)
        rows.append(np.concatenate([np.pad(t, ((4, 4), (4, 4), (0, 0)), constant_values=20) for t in (l1, got, mark)], 1))
if rows:
    from PIL import Image
    Image.fromarray(np.concatenate(rows[:4], 0)).save(sys.argv[6])
print(f'{total} pixels, {bad} differ from the model' + (f', {obad} from the pack tool\'s model' if other is not None else ''))
ok = bad == 0 and obad == 0 and total > 0
print('REMASTER_SIM_OK' if ok else 'REMASTER_SIM_FAIL')
sys.exit(0 if ok else 1)
