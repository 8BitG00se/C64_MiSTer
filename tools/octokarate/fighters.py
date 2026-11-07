#!/usr/bin/env python3
# fighters.py - Octo Karate: the fighters' drawings, their moves as frame data and the boxes taken from the pixels.
# Original work by Mong00se. The drawings come from art/ (the approved renderer and move poses); this module
#   * defines every drawing the game shows (poses + the extra ones in art/newposes.py), for both fighters,
#   * the moves as lists of (drawing, frames) with startup / active / recovery frames,
#   * renders them (cached on disk), and measures a HURT box set and a HIT box from the actual pixels.
import os, sys, math, pickle, hashlib
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, 'art')
CACHE = os.environ.get('OCTOKARATE_CACHE', '/tmp/octokarate_cache')
os.makedirs(CACHE, exist_ok=True)


def _env():
    """exec the art scripts in one namespace (they open their neighbours by relative name, so work from art/)"""
    old = os.getcwd(); os.chdir(ART); oldargv = list(sys.argv)
    ns = {'__name__': 'art'}
    try:
        src = open('fight.py').read()
        exec(src[:src.index('class F:')], ns)
        exec(open('newposes.py').read(), ns)
    finally:
        os.chdir(old); sys.argv = oldargv
    return ns


NS = _env()
VIC, SID, G = NS['VIC'], NS['SID'], NS['G']
SW, SH = NS['SW'], NS['SH']
WALK, PUNCH_, KICK_, BODYK_, HEADK_, SHIN_, HIT_ = (NS[n] for n in ('WALK', 'PUNCH', 'KICK', 'BODYK', 'HEADK', 'SHIN', 'HIT'))
lerpJ, tween, setj = NS['lerpJ'], NS['tween'], NS['setj']
STRIDE = NS['STRIDE']
OCOL = SW // 2 - 2                       # the column of joint x = 0 in an unmirrored drawing (62)

# ------------------------------------------------------------------------------------------------ the drawing set
POSES = {}          # name -> (joints, shift)
_SEEN = {}          # identical drawings share one name
def pose(name, J, shift=0):
    k = (repr(tuple(sorted((n, tuple(round(c, 2) for c in v)) for n, v in J.items()))), shift)
    if k in _SEEN: return _SEEN[k]
    POSES[name] = (J, shift); _SEEN[k] = name; return name

pose('guard', G)
pose('bob1', NS['BOB1']); pose('bob2', NS['BOB2'])
WALK_NAMES = ['guard'] + [pose('walk%d' % i, J) for i, (J, h) in enumerate(WALK[1:], 1)]
pose('block', NS['BLOCK']); pose('crouch', NS['CROUCH']); pose('cblock', NS['CBLOCK'])
HIT_SEQ = [pose('hit1', HIT_[0][0]), pose('hit2', HIT_[1][0]), pose('hit3', HIT_[2][0])]
pose('fall1', NS['FALL1'], 8); pose('fall2', NS['FALL2'], 37); pose('lie', NS['LIE'], 30)

# ---- the moves. Each is a list of (drawing, frames) built from moves.py's poses; frames are game frames (50 per second).
def mk_punch():
    P_ = PUNCH_
    # PUNCH = [(G,3),(Pw,2),(mid,1),(mid,1),(P,5)] + 4 tweens of 2
    pw, m1, m2, pp = P_[1][0], P_[2][0], P_[3][0], P_[4][0]
    a, b, c, d = pose('p_wind', pw), pose('p_m1', m1), pose('p_m2', m2), pose('p_hit', pp)
    rec = P_[5:]
    rn = [pose('p_r%d' % i, J) for i, (J, h) in enumerate(rec)]
    seq = [('guard', 1), (a, 2), (b, 1), (c, 1)]
    startup = sum(f for _, f in seq)
    seq += [(d, 4)]
    active = 4
    seq += [(n, 2) for n in rn]
    return seq, startup, active, d


def mk_kick(tag, K, hold_pre, act, hold_rec):
    """K: the kick list from moves.py: [(G,2),(R0,3),tw,(R1,2),tw,(C1,2),(lerp,1),(S,6),(Sr,3),(C1,3),tw,(R1,2),tw,tw]"""
    # indexes: 0 G, 1 R0, 2 tw(R0,R1), 3 R1, 4 tw(R1,C1), 5 C1, 6 lerp(C1,S), 7 S, 8 Sr, 9 C1, 10 tw(C1,R1), 11 R1, 12.. tw(R1,G)
    nm = [pose('%s%d' % (tag, i), J) for i, (J, h) in enumerate(K)]
    pre = [0, 1, 2, 3, 4, 5, 6]
    seq = [(nm[i], hold_pre[j]) for j, i in enumerate(pre)]
    startup = sum(hold_pre)
    seq += [(nm[7], act)]
    rec_i = [8, 9, 10, 11] + list(range(12, len(K)))
    seq += [(nm[i], hold_rec[j]) for j, i in enumerate(rec_i)]
    return seq, startup, act, nm[7]


# per move: name, level (0 high, 1 mid, 2 low), builder, damage, hitstop, hitstun, blockstun, pushback hit, pushback block, sfx
#   holds for the 7 pre-strike drawings and the recovery drawings are chosen to give the startup / recovery feel below
def moves():
    out = []
    s, su, ac, st_ = mk_punch()
    out.append(dict(name='PUNCH', level=0, seq=s, startup=su, active=ac, dmg=6, hitstop=6, hitstun=14, blockstun=10, pushhit=6, pushblock=8, strike=st_))
    # HEAD KICK (high): slow, big
    K = NS['HEADK']
    s, su, ac, st_ = mk_kick('hk', K, [2, 3, 2, 2, 2, 2, 1], 5, [3, 3, 2, 2, 2, 2, 2])
    out.append(dict(name='HEAD KICK', level=0, seq=s, startup=su, active=ac, dmg=14, hitstop=8, hitstun=22, blockstun=15, pushhit=12, pushblock=10, strike=st_))
    # BODY KICK (mid)
    K = NS['BODYK']
    s, su, ac, st_ = mk_kick('bk', K, [1, 2, 2, 2, 2, 1, 1], 5, [3, 3, 2, 2, 2, 2, 2])
    out.append(dict(name='BODY KICK', level=1, seq=s, startup=su, active=ac, dmg=10, hitstop=7, hitstun=18, blockstun=13, pushhit=10, pushblock=9, strike=st_))
    # FRONT KICK (mid, the long one)
    K = NS['KICK']
    s, su, ac, st_ = mk_kick('fk', K, [1, 2, 2, 2, 2, 1, 1], 5, [3, 3, 2, 2, 2, 2, 2])
    out.append(dict(name='FRONT KICK', level=1, seq=s, startup=su, active=ac, dmg=9, hitstop=7, hitstun=17, blockstun=13, pushhit=14, pushblock=12, strike=st_))
    # SHIN STRIKE (low, quick)
    K = NS['SHIN']
    s, su, ac, st_ = mk_kick('sh', K, [1, 1, 1, 2, 1, 1, 1], 4, [2, 2, 1, 2, 1, 2, 2])
    out.append(dict(name='SHIN STRIKE', level=2, seq=s, startup=su, active=ac, dmg=5, hitstop=6, hitstun=14, blockstun=11, pushhit=5, pushblock=7, strike=st_))
    return out


MOVES = moves()
# the strike drawings carry a HIT box
STRIKES = {m['strike'] for m in MOVES}
# fixed sequences
FALL_SEQ = [('hit1', 6), ('fall1', 6), ('fall2', 7)]          # then 'lie' forever
STANCE = {'guard', 'bob1', 'bob2', 'crouch', 'cblock', 'block'}

# the order the game numbers the drawings in (same for both fighters)
ORDER = list(POSES)
DID = {n: i for i, n in enumerate(ORDER)}

# ------------------------------------------------------------------------------------------------ rendering
def _key(J):
    return tuple(sorted((n, tuple(round(c, 2) for c in v)) for n, v in J.items()))


def _shifted(J, sh):
    if not sh: return J
    return {n: ((v[0] + sh,) + tuple(v[1:])) if n != '_foot' else v for n, v in J.items()}


def render_pose(C, name):
    """-> (RGBA ndarray 112 x 128 as the game shows it (Sid mirrored), part map or None, origin column)"""
    J, sh = POSES[name]
    flip = C is SID
    h = hashlib.md5(repr((C['name'], flip, _key(J), sh, 'v1')).encode()).hexdigest()
    fn = os.path.join(CACHE, h + '.pkl')
    if os.path.exists(fn):
        return pickle.load(open(fn, 'rb'))
    Js = _shifted(J, sh)
    im = np.asarray(NS['draw'](C, Js, flip)).copy()
    rj = {n: v for n, v in Js.items() if n != '_foot'}
    _, P1, _ = NS['render'](C, rj, 0.0, flip=False, layers=True)
    P1 = np.asarray(P1)
    if flip: P1 = P1[:, ::-1]
    oc = OCOL + sh
    if flip: oc = SW - 1 - oc
    res = (im, P1, oc)
    pickle.dump(res, open(fn, 'wb'))
    return res


# ------------------------------------------------------------------------------------------------ boxes from the pixels
HEADP = {'head', 'neck', 'hair', 'nose', 'jaw'}
TORSOP = {'torso', 'delt_n', 'delt_f', 'uarm_n', 'uarm_f', 'knot', 'tail', 'belly'}
LEGP_FIXED = {'thigh_f', 'shin_f', 'foot_f', 'thigh_b'}
LEGP_BACK = {'shin_b', 'foot_b'}


def bbox(mask):
    ys, xs = np.where(mask)
    if len(xs) == 0: return None
    return int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())


def boxes(im, P1, oc, flip, strike):
    """returns (hurt [3 x (x0,x1,y0,y1)], hit or None) with x relative to the origin column (screen directions), y in drawing rows"""
    al = im[..., 3] > 0
    pm = np.isin(P1, list(HEADP)) & al
    pt = np.isin(P1, list(TORSOP)) & al
    pl = np.isin(P1, list(LEGP_FIXED)) & al
    head = bbox(pm); torso = bbox(pt)
    if torso is None: torso = bbox(al)
    if head is None: head = (torso[0], torso[1], torso[2] - 10, torso[2] - 1)
    # the legs: the planted leg and thigh always; the other shin and foot only while they are near the body (not a kick in flight)
    lx0, lx1 = torso[0] - 16, torso[1] + 16
    pb = np.isin(P1, list(LEGP_BACK)) & al
    cols = np.zeros_like(pb); cols[:, max(0, lx0):lx1 + 1] = True
    legs = bbox(pl | (pb & cols))
    if legs is None: legs = (torso[0], torso[1], torso[3] + 1, 109)
    # the leg box starts under the torso box (no gap, no overlap)
    y0 = max(legs[2], torso[3] + 1) if legs[2] < torso[3] + 1 and legs[3] > torso[3] else legs[2]
    legs = (legs[0], legs[1], y0, legs[3])
    # the torso box: from under the head to the hips; widen to the whole silhouette of the body core
    if torso[2] <= head[3]: torso = (torso[0], torso[1], head[3] + 1, torso[3])
    hurt = [head, torso, legs]
    hit = None
    if strike:
        ys, xs = np.where(al)
        if not flip:
            tip = xs.max(); sel = xs >= tip - 13
        else:
            tip = xs.min(); sel = xs <= tip + 13
        hy = ys[sel]; hx = xs[sel]
        hit = (int(hx.min()), int(hx.max()), int(hy.min()), int(hy.max()))
    rel = lambda b: (b[0] - oc, b[1] - oc, b[2], b[3])
    return [rel(b) for b in hurt], (rel(hit) if hit else None)
