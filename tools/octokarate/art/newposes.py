# Octo Karate: the extra poses (block, crouch, crouch block, fall, lying), built the same way as moves.py's poses.
# exec'd after moves.py / fight.py's first part: G, upper, lean, setj, lerpJ, mv, LEG, HIT are already defined.
def ik(hip, ank, l1, l2, z=0.0, side=1):
    """knee position for a leg: thigh l1, shin l2, the knee bending forward (+x) for side=1, backward for side=-1"""
    dx, dy = ank[0] - hip[0], ank[1] - hip[1]
    d = math.hypot(dx, dy); d = min(d, l1 + l2 - 0.01)
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d); h = math.sqrt(max(0.0, l1 * l1 - a * a))
    ux, uy = dx / d, dy / d
    px, py = -uy, ux                                   # perpendicular: forward when the leg points down
    if px < 0: px, py = -px, -py
    return (hip[0] + ux * a + side * px * h, hip[1] + uy * a + side * py * h, z)

# ---- stand block: both forearms up in front of the face, the body tucked back a touch
BLOCK = lean(upper(G, (-1, 0)), 4)
BLOCK = setj(BLOCK, elb_f=(18, 59, -8), wr_f=(23, 74, -6), fist_f=(24, 79, -5),
             elb_n=(10, 51, 12), wr_n=(17, 68, 11), fist_n=(19, 73, 10))
# ---- crouch (build 3): the feet stay planted exactly where they are in the guard stance, the hips drop 14 px straight down,
# the knees bend and spread (front knee forward, back knee back and out), the torso stays upright, the guard stays up
def crouched(base, d=14, spread=0.75):
    J = upper(base, (0, -d))
    hf, hb = J['hip_f'], J['hip_b']
    af, ab = G['ank_f'], G['ank_b']
    kf = ik(hf, af, 22.8, 20.6, 8, 1)
    kb = ik(hb, ab, 22.0, 20.6, -8, -1)
    kb = (kb[0] * spread + ab[0] * (1 - spread) * 0.0 + (hb[0] * (1 - spread)), kb[1], kb[2])
    return setj(J, knee_f=kf, knee_b=kb)
CROUCH = crouched(G)
# crouch block: the same legs, the forearms come down in front of the body (head and chest covered from the front)
CBLOCK = crouched(BLOCK)
CBLOCK = setj(CBLOCK, elb_f=(15, 36, -8), wr_f=(23, 47, -6), fist_f=(25, 52, -5),
              elb_n=(7, 31, 12), wr_n=(16, 42, 11), fist_n=(19, 47, 10))
# ---- idle bob: the guard breathing (two more drawings)
BOB1 = pose_guard(math.pi / 2)[0]
BOB2 = pose_guard(-math.pi / 2)[0]
# ---- knocked down: the hit reaction goes on into a backwards fall and a heap on the ground
FALL1 = setj(lean(upper(G, (-5, 2)), 36), elb_f=(11, 70, -8), wr_f=(10, 84, -6), fist_f=(10, 89, -5),
             elb_n=(0, 62, 12), wr_n=(-6, 76, 11), fist_n=(-8, 81, 10),
             ank_f=(26, 10, 5), toe_f=(35, 8, 5), knee_f=(19, 28, 7))
FALL1['head'] = tuple(a + b for a, b in zip(FALL1['head'], (-2, 1, 0)))
_f2 = lean(upper(G, (-17, -7)), 68)
FALL2 = setj(_f2, ank_f=(16, 42, 5), toe_f=(23, 46, 5), knee_f=(7, 30, 7),
             ank_b=(-4, 38, -5), toe_b=(5, 42, -5), knee_b=(-14, 26, -6),
             elb_f=(-14, 56, -8), wr_f=(-18, 70, -6), fist_f=(-19, 75, -5),
             elb_n=(-24, 52, 12), wr_n=(-30, 60, 11), fist_n=(-33, 64, 10))
# lying on the back, head to the left, knees a little up, one arm out
def lying():
    y = 12
    return dict(
      pelvis=(-4, y, 0), hip_f=(-1, y, 6), hip_b=(-7, y, -6), chest=(-25, y + 1, 0), neck=(-36, y, 0), head=(-43, y + 1, 0),
      sh_n=(-31, y, 11), sh_f=(-28, y + 3, -11),
      elb_n=(-22, 7, 13), wr_n=(-11, 7, 13), fist_n=(-5, 7, 13),
      elb_f=(-40, y + 10, -10), wr_f=(-44, y + 19, -8), fist_f=(-45, y + 24, -7),
      knee_f=(13, 26, 7), ank_f=(30, 12, 6), toe_f=(36, 10, 6),
      knee_b=(9, 20, -6), ank_b=(25, 7, -5), toe_b=(32, 5, -5))
LIE = lying()
SHIFT = {'LIE': 26, 'FALL2': 8}          # whole-drawing shift (pixels, to the right) so the drawing fits its window; the engine undoes it
