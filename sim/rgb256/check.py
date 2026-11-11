# C64RGB 256 (Fix 60): the RTL's pixels against the model in tools/rgb256/rgb256.py   (c) 2026 Mong00se
# check.py PACK TAGS RTLOUT [PNG]: every pixel of every frame and palette must match; PNG: stock | RTL palettes
import sys, os
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../tools/rgb256'))
import rgb256 as R
pk = R.read_pack(open(sys.argv[1], 'rb').read())
frames = R.read_tags(sys.argv[2])
raw = np.fromfile(sys.argv[3], np.uint8)
npal = max(1, pk['npal'])
o = 0; bad = 0; total = 0; rows = []
for fno, idx, tag in frames:
    h, w = idx.shape
    x, y = R.coords(h, w)
    tiles = [R.stock(idx)]
    for p in range(npal):
        got = raw[o:o + h * w * 3].reshape(h, w, 3); o += h * w * 3
        want = R.recolour(pk, idx, tag, x, y, p)
        d = (got != want).any(-1)
        bad += int(d.sum()); total += h * w
        if d.any():
            yy, xx = np.argwhere(d)[0]
            print(f'frame {fno} palette {p + 1}: {int(d.sum())} pixels differ, first at x={xx} line={yy + 16}: '
                  f'RTL {got[yy, xx].tolist()} model {want[yy, xx].tolist()} (index {idx[yy, xx]}, tag {tag[yy, xx]:#x})')
        tiles.append(got)
    rows.append(np.concatenate([np.pad(t, ((4, 4), (4, 4), (0, 0)), constant_values=20) for t in tiles], 1))
if len(sys.argv) > 4:
    from PIL import Image
    Image.fromarray(np.concatenate(rows, 0)).save(sys.argv[4])
print(f'{total} pixels (frames x palettes), {bad} differ from the model')
print('RGB256_SIM_OK' if bad == 0 and total else 'RGB256_SIM_FAIL')
sys.exit(0 if bad == 0 and total else 1)
