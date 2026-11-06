# texture.py - the seamless brick tile of Graffiti Wall as an OctoPaint texture: BRICK.OCT, 320 x 200, 256 colours.
#   texture.py PHOTO OUT.oct          (the photo itself is never committed or put on the card)
import sys, os
import numpy as np
from PIL import Image
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here); sys.path.insert(0, os.path.join(here, '..', 'octopaint'))
import wall, mkoct

t, ang, pk = wall.tile(sys.argv[1])
t = np.clip(t.astype(float) * 0.9, 0, 255).astype(np.uint8)         # as the demo has it
reps = (-(-mkoct.H // t.shape[0]), -(-mkoct.W // t.shape[1]), 1)
pic = np.tile(t, reps)[:mkoct.H, :mkoct.W]                          # the tile repeated to fill 320 x 200
q = Image.fromarray(pic).quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
pal = (q.getpalette() + [0] * 768)[:768]
palette = [tuple(pal[3 * i:3 * i + 3]) for i in range(256)]
open(sys.argv[2], 'wb').write(mkoct.make_oct(bytes(q.tobytes()), palette))
print('%d bytes, tile %dx%d' % (os.path.getsize(sys.argv[2]), t.shape[1], t.shape[0]))
