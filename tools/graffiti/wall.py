# the brick tile: Neal's own photo -> a seamless 192 x 128 tile (two courses of 64, a few bricks)
import numpy as np, cv2
TW, CH, E = 192, 64, 7          # tile size, course height, rows of mortar kept beyond each bed joint (to blend)

def prep(photo):
    im = cv2.imread(photo).astype(np.float32)
    h, w = im.shape[:2]
    small = cv2.resize(cv2.cvtColor(im.astype(np.uint8), cv2.COLOR_BGR2HSV)[..., 1].astype(np.float32), (w // 4, h // 4), interpolation=cv2.INTER_AREA)
    best = None                                              # straighten: the angle that makes the mortar lines sharpest
    for a in np.arange(-4, 4.01, 0.25):
        M = cv2.getRotationMatrix2D((w / 8, h / 8), a, 1)
        r = cv2.warpAffine(small, M, (w // 4, h // 4))[60:-60, 60:-60]
        v = r.mean(1).var()
        if best is None or v > best[0]: best = (v, a)
    M = cv2.getRotationMatrix2D((w / 2, h / 2), best[1], 1)
    im = cv2.warpAffine(im, M, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT)
    lum = im.mean(2)                                         # even out the lighting: divide by a heavy blur, keep the mean
    bl = cv2.GaussianBlur(lum, (0, 0), 140)
    im *= (lum.mean() / bl)[..., None]
    sat = cv2.cvtColor(np.clip(im, 0, 255).astype(np.uint8), cv2.COLOR_BGR2HSV)[..., 1].astype(np.float32)
    p = cv2.GaussianBlur(sat[:, 200:-200].mean(1).reshape(-1, 1), (1, 0), 6).ravel()
    from scipy.signal import find_peaks
    pk, _ = find_peaks(-p, distance=200, prominence=8)       # the bed joints (mortar = least saturated)
    return im, pk, best[1]

def course(im, y0, y1, x0, x1, m=60):
    """one course, bed joint centre to bed joint centre, one brick pitch from head joint centre to head joint centre,
    made periodic across by a cross-fade over m columns; scaled to TW x (CH + 2E)"""
    h = y1 - y0
    ext = int(round(E * h / CH))
    S = im[y0 - ext:y1 + ext, x0:x1 + m]
    W0 = x1 - x0
    O = S[:, :W0].copy()
    wgt = ((np.arange(m) + 0.5) / m)[None, :, None]
    O[:, :m] = wgt * S[:, :m] + (1 - wgt) * S[:, W0:W0 + m]
    return cv2.resize(O, (TW, CH + 2 * E), interpolation=cv2.INTER_AREA)

def tile(photo):
    """4 courses of 64 rows, 2 bricks of 192 across: a tile 384 x 256 that repeats both ways"""
    im, pk, ang = prep(photo)
    # bricks: (bed joint above, bed joint below, head joint left, head joint right) - read off the straightened photo
    br = [course(im, pk[1], pk[2], 232, 1165), course(im, pk[2], pk[3], 625, 1535),
          course(im, pk[3], pk[4], 435, 1290), course(im, pk[4], pk[5], 228, 1035)]
    rows = []
    for r in range(4):
        a = br[r]; b = br[(r + 2) % 4][:, ::-1]               # the other brick of the course: another course's, turned round
        row = np.concatenate([a, b], 1)
        if r % 2: row = np.roll(row, TW // 2, axis=1)         # running bond: every other course half a brick along
        rows.append(row)
    nr = len(rows); H = nr * CH
    def band(X, Y):                                          # X above Y: blend the mortar either side of their bed joint
        a = X[CH:CH + 2 * E]; b = Y[0:2 * E]
        w = ((np.arange(2 * E) + 0.5) / (2 * E))[:, None, None]
        return (1 - w) * a + w * b
    t = np.concatenate([r[E:E + CH] for r in rows], 0)
    for r in range(nr):
        X, Y = rows[r], rows[(r + 1) % nr]
        bd = band(X, Y); y = (r + 1) * CH
        if r + 1 < nr: t[y - E:y + E] = bd
        else: t[H - E:] = bd[:E]; t[:E] = bd[E:]
    t = np.clip(t, 0, 255)
    return t[..., ::-1].astype(np.uint8), ang, pk                # RGB

def check_seams(t):
    d = lambda a, b: float(np.abs(a.astype(float) - b.astype(float)).mean())
    return d(t[:, 0], t[:, -1]), d(t[0], t[-1])
