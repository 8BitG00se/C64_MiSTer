#!/usr/bin/env python3
# OCTOPHONIC 64 - OLD-SOFTWARE REGRESSION TEST (Fix 69): the emulator part.        (c) 2026 Mong00se
#
# Runs every program in manifest.txt in the Octophonic 64 emulator (headless, the CURRENT Octophonic KERNAL -
# it refuses to make a baseline with any other), keeps a fingerprint of every frame's picture, the SID writes
# and the sound, and compares a new core's emulator with the last one's. Nothing here is PC-rendered: every
# picture is the emulated 6502 + VIC/OctoVIC running the real program.
#
#   regress.py list                                   what is in the list and whether each can be found here
#   regress.py baseline NAME   [--emu X64SC] [--only id,id] [--force]
#                              run the list on the last core's emulator, store the fingerprints in baselines/NAME
#   regress.py compare  NAME   [--emu X64SC] [--only id,id] [--out DIR] [--mif FILE]
#                              run the same list on a candidate emulator and compare with baselines/NAME:
#                              identical / changed (side-by-side picture of the first changed frame, where the
#                              sound differs) / crashed / timed out / did not start; ends PASS or FAIL
#   regress.py determinism     [--emu X64SC] [--only id,id]
#                              run each entry twice on the same emulator: both runs must be identical
#
# Settings (environment):
#   OCTO_EMU          the emulator (default /home/claude/emu/x64sc; its ROMs folder sits beside it)
#   OCTO_EMU_RT       the emulator's run folder with vicerc and Games/C64 (default: octophonic-backgrounds/emulator/rt)
#   OCTO_OB_REPO      the octophonic-backgrounds checkout (default /home/claude/octophonic-backgrounds)
#   OCTO_BUILDS       folders holding Neal's finished builds, split by ":" (LOCAL entries)
#   NEAL_GAMES        the folder with Neal's own stock C64 classics (NEAL entries; none are in the repo)
#   OCTO_REGRESS_WORK where runs, pictures and reports go (default /tmp/octo-regress)
import argparse, gzip, hashlib, json, os, re, shutil, subprocess, sys, time, zlib
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
SEED = 12345                 # VICE's random seed, fixed: without it two runs of the same program differ
CYCLES_PER_FRAME = 19656     # 63 x 312, one PAL frame
DROP_AT = 150                # Octophonic OS has booted by then; the program is dropped on it as a user would
SHOTS = (100, 300, 600, 900, 1200)   # frames kept as pictures in every run (100 = the KERNAL start screen)
AUDIO_BLOCK = 960            # 20 ms of the 48 kHz stereo mix
F3_LOAD = 'KEYS=170:0:5'     # F3 on the start screen (keyboard row 0, column 5): LOAD"*",8,1 and RUN
FORMAT = 1

def env(k, d=''):
    return os.environ.get(k, d)

EMU = env('OCTO_EMU', '/home/claude/emu/x64sc')
RT = env('OCTO_EMU_RT', '/home/claude/octophonic-backgrounds/emulator/rt')
OB = env('OCTO_OB_REPO', '/home/claude/octophonic-backgrounds')
WORK = env('OCTO_REGRESS_WORK', '/tmp/octo-regress')

# ------------------------------------------------------------------------------------------ the list
class Entry:
    def __init__(self, f):
        self.id, self.where, self.find, self.run, fr, self.input, self.needs, self.what = f
        self.frames = int(fr)
        self.path = None; self.why = ''

def load_manifest():
    out = []
    for ln in open(os.path.join(HERE, 'manifest.txt'), encoding='utf-8'):
        ln = ln.strip()
        if not ln or ln.startswith('#'): continue
        f = [x.strip() for x in ln.split('|')]
        if len(f) != 8: sys.exit('manifest.txt: this line does not have 8 fields: ' + ln)
        out.append(Entry(f))
    ids = [e.id for e in out]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup: sys.exit('manifest.txt: ids used twice: ' + ', '.join(sorted(dup)))
    return out

_index = None
def build_index():
    """every folder and file under the OCTO_BUILDS folders (LOCAL entries are found by name)"""
    global _index
    if _index is not None: return _index
    dirs, files = {}, {}
    for root in [r for r in env('OCTO_BUILDS').split(':') if r]:
        for dp, dn, fn in os.walk(root):
            if dp[len(root):].count(os.sep) > 6: dn[:] = []; continue
            dirs.setdefault(os.path.basename(dp), []).append(dp)
            for f in fn: files.setdefault(f, []).append(os.path.join(dp, f))
    _index = (dirs, files)
    return _index

def assemble(e):
    src = os.path.join(REPO, e.find)
    out = os.path.join(WORK, 'built', e.id, e.run)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    r = subprocess.run(['acme', '-f', 'cbm', '-o', out, os.path.basename(src)], cwd=os.path.dirname(src),
                       capture_output=True, text=True)
    if r.returncode or not os.path.exists(out):
        return None, 'acme could not assemble %s: %s' % (e.find, (r.stdout + r.stderr).strip()[:200])
    return out, ''

def resolve(e):
    """sets e.path (the file dropped on Octophonic OS) or e.why (why it is skipped)"""
    if e.where == 'REPO':
        p = os.path.join(REPO, e.find)
    elif e.where == 'BUILT':
        if not shutil.which('acme'): e.why = 'acme is not installed'; return
        p, e.why = assemble(e)
        if not p: return
    elif e.where == 'OB':
        p = os.path.join(OB, e.find)
    elif e.where == 'LOCAL':
        if not env('OCTO_BUILDS'): e.why = 'OCTO_BUILDS is not set (Neal\'s demo folders)'; return
        dirs, files = build_index()
        p = None
        for d in sorted(dirs.get(e.find, [])):
            if os.path.exists(os.path.join(d, e.run)): p = os.path.join(d, e.run); break
        if not p:   # the folder has another name here: the program's own file name, the newest copy
            c = files.get(os.path.basename(e.run), [])
            if c: p = max(c, key=lambda x: (os.path.getmtime(x), x))
        if not p: e.why = 'not found under OCTO_BUILDS (%s / %s)' % (e.find, e.run); return
    elif e.where == 'NEAL':
        g = env('NEAL_GAMES')
        if not g: e.why = 'Neal supplies this one (stock C64 classic, not in the repo): NEAL_GAMES is not set'; return
        p = os.path.join(g, e.find)
        if not os.path.exists(p): e.why = 'Neal supplies this one: %s is not in NEAL_GAMES' % e.find; return
    else:
        e.why = 'unknown "where": ' + e.where; return
    if e.where in ('REPO', 'OB') and e.run != '-': p = os.path.join(os.path.dirname(p), e.run)
    if not os.path.exists(p): e.why = 'file not found: ' + p; return
    e.path = p

def md5(p):
    h = hashlib.md5()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''): h.update(b)
    return h.hexdigest()

def program_md5(p):
    """the program and its REU (the .reu of the same name beside a .prg is attached with it)"""
    s = md5(p)
    reu = os.path.splitext(p)[0] + '.reu'
    if p.lower().endswith('.prg') and os.path.exists(reu): s += '+' + md5(reu)
    return s

# ------------------------------------------------------------------------------------------ the KERNAL rule
def mif_roms(path):
    d = open(path).read(); out = {}
    d = d[d.index('BEGIN') + 5:]
    for a, vs in re.findall(r'^\s*\[?([0-9A-Fa-f]+)(?:\.\.[0-9A-Fa-f]+\])?\s*:\s*([0-9A-Fa-f ]+);', d, re.M):
        for k, v in enumerate(vs.split()): out[int(a, 16) + k] = int(v, 16)
    o = bytes(out.get(i, 0) for i in range(16384))
    return '%08X' % zlib.crc32(o[:8192]), '%08X' % zlib.crc32(o[8192:])

def roms_used(emu_txt):
    """the KERNAL and BASIC the emulator really ran, from its own log"""
    r = {}
    for what in ('KERNAL', 'BASIC'):
        m = re.search(r'OctoROM: %s: Octophonic 64 V1\.1 made from your stock ROM \(CRC32 ([0-9A-F]{8})' % what, emu_txt)
        if m: r[what] = m.group(1); continue
        if re.search(r'OctoROM: %s: the Octophonic ROM as supplied' % what, emu_txt): r[what] = 'as supplied'; continue
        r[what] = 'NOT the Octophonic ROM'
    return r

# ------------------------------------------------------------------------------------------ one run
def vicerc(work):
    src = open(os.path.join(RT, 'vicerc')).read()
    src = re.sub(r'"[^"]*?/rt/', '"' + RT + '/', src)
    p = os.path.join(work, 'vicerc.local'); open(p, 'w').write(src)
    return p

def run_one(e, emu, out, shots=SHOTS, png_only=None, timeout=None):
    """runs e in the emulator; out = a folder for this entry. Returns a dict (status, fingerprints...)."""
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.startswith('e.') or f.startswith('e_'): os.remove(os.path.join(out, f))
    pre = os.path.join(out, 'e')
    os.symlink('/dev/null', pre + '.log')       # every OctoVIC write: hundreds of MB, not needed here
    cfg = vicerc(out)
    ev = dict(os.environ, OCTO_RUN=e.path, OCTO_DUMP=pre)
    if png_only is not None:
        ev.update(OCTO_DUMP_FROM=str(png_only), OCTO_DUMP_TO=str(png_only), OCTO_DUMP_STEP='1')
    else:
        ev.update(OCTO_DUMP_FROM=str(shots[0]), OCTO_DUMP_TO=str(e.frames + 400), OCTO_DUMP_STEP=str(shots[1] - shots[0]))
    inp = e.input
    if inp == '-' and e.path.lower().endswith(('.d64', '.g64', '.d81')): inp = F3_LOAD   # a disk is only mounted by the drop
    if inp.startswith('JOY='): ev['OCTO_JOY'] = inp[4:]
    elif inp.startswith('KEYS='): ev['OCTO_KEYS'] = inp[5:]
    cmd = [emu, '-config', cfg, '-sounddev', 'wav', '-soundarg', '/dev/null', '-soundrate', '48000',
           '-seed', str(SEED), '-warp', '-limitcycles', str(e.frames * CYCLES_PER_FRAME)]
    t0 = time.time(); status = 'ran'
    timeout = timeout or max(120, e.frames // 5)
    with open(pre + '.emu.txt', 'w') as so:
        try:
            p = subprocess.run(cmd, cwd=out, env=ev, stdout=so, stderr=subprocess.STDOUT, timeout=timeout)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            rc = None; status = 'timed out'
    secs = time.time() - t0
    os.remove(pre + '.log')
    txt = open(pre + '.emu.txt', errors='replace').read()
    res = {'id': e.id, 'seconds': round(secs, 1), 'rc': rc, 'roms': roms_used(txt)}
    # pictures: keep the HDMI ones (what the player sees); the VIC-only CRT ones are in the hash
    for f in os.listdir(out):
        if f.startswith('e_crt_'): os.remove(os.path.join(out, f))
    if png_only is not None:
        for f in ('e.pcm', 'e.sidw', 'e.hash'):
            if os.path.exists(os.path.join(out, f)): os.remove(os.path.join(out, f))
        return res
    # what went wrong, if anything
    if 'nothing to run' in txt: status = 'did not start'
    jam = re.search(r'JAM at \$([0-9A-F]{4})', txt)
    if jam: status = 'crashed'; res['jam'] = '$' + jam.group(1)
    if rc not in (0, 1, None) and status == 'ran': status = 'crashed'; res['note'] = 'the emulator exited with code %s' % rc
    res['status'] = status
    # fingerprints: every frame's picture (HDMI and the VIC's own CRT picture), the SID writes, the sound
    F = []
    if os.path.exists(pre + '.hash'):
        for ln in open(pre + '.hash'):
            p = ln.split()
            if len(p) >= 4: F.append((int(p[0]), p[1], p[2], p[3]))
    res['frames'] = F
    S = {}
    if os.path.exists(pre + '.sidw'):
        W = np.fromfile(pre + '.sidw', np.dtype([('f', '<u4'), ('l', '<u2'), ('a', '<u2'), ('v', 'u1')]))
        if len(W):
            fr = W['f'].astype(np.int64); cut = np.nonzero(np.diff(fr))[0] + 1
            for seg in np.split(np.arange(len(W)), cut):
                if len(seg): S[int(fr[seg[0]])] = ('%08x' % zlib.crc32(W[seg].tobytes()), len(seg))
        os.remove(pre + '.sidw')
    res['sid'] = S
    A = []
    if os.path.exists(pre + '.pcm'):
        pcm = np.fromfile(pre + '.pcm', '<i2')
        n = len(pcm) // (2 * AUDIO_BLOCK)
        blk = pcm[:n * 2 * AUDIO_BLOCK].reshape(n, AUDIO_BLOCK, 2)
        rms = np.sqrt((blk.astype(np.float64) ** 2).mean(axis=1))
        db = np.where(rms > 0, 20 * np.log10(np.maximum(rms, 1e-9) / 32768.0), -99.0)
        for i in range(n):
            A.append(('%08x' % zlib.crc32(blk[i].tobytes()), round(max(db[i, 0], -99.0), 1), round(max(db[i, 1], -99.0), 1)))
        os.remove(pre + '.pcm')
    res['audio'] = A
    if os.path.exists(pre + '.hash'): os.remove(pre + '.hash')
    return res

def save_fp(res, path):
    with gzip.GzipFile(path, 'wb', mtime=0) as g:
        w = lambda s: g.write((s + '\n').encode())
        w('# Octophonic 64 regression fingerprint (c) 2026 Mong00se - format %d' % FORMAT)
        w('# F frame hdmi_crc32 crt_crc32 octovic_on | S frame sid_writes_crc32 count | A block(20ms) crc32 rmsL_dB rmsR_dB')
        for f in res['frames']: w('F %d %s %s %s' % f)
        for k in sorted(res['sid']): w('S %d %s %d' % (k, res['sid'][k][0], res['sid'][k][1]))
        for i, a in enumerate(res['audio']): w('A %d %s %.1f %.1f' % (i, a[0], a[1], a[2]))

def load_fp(path):
    res = {'frames': [], 'sid': {}, 'audio': []}
    with gzip.open(path, 'rt') as g:
        for ln in g:
            p = ln.split()
            if not p or p[0] == '#': continue
            if p[0] == 'F': res['frames'].append((int(p[1]), p[2], p[3], p[4]))
            elif p[0] == 'S': res['sid'][int(p[1])] = (p[2], int(p[3]))
            elif p[0] == 'A': res['audio'].append((p[2], float(p[3]), float(p[4])))
    return res

# ------------------------------------------------------------------------------------------ comparing
def compare_fp(b, c):
    """what differs between two fingerprints (baseline b, candidate c)"""
    d = {}
    bf = {f[0]: f for f in b['frames']}; cf = {f[0]: f for f in c['frames']}
    d['frames_base'] = len(bf); d['frames_cand'] = len(cf)
    common = sorted(set(bf) & set(cf))
    bad = [k for k in common if bf[k][1:3] != cf[k][1:3]]
    d['frames_differ'] = len(bad)
    d['first_frame'] = bad[0] if bad else None
    if bad:
        d['first_frame_part'] = 'boot / start screen (before the program is dropped at frame %d)' % DROP_AT if bad[0] < DROP_AT else 'the program'
        d['hdmi_differ'] = sum(1 for k in bad if bf[k][1] != cf[k][1]); d['crt_differ'] = sum(1 for k in bad if bf[k][2] != cf[k][2])
        d['last_frame'] = bad[-1]
        # the same pictures, only later or earlier? (a timing shift, e.g. a slower boot)
        tail = [k for k in common if k >= max(DROP_AT, bad[0])]
        best = (0, 0)
        if len(tail) > 50:
            for off in range(-75, 76):
                if off == 0: continue
                n = sum(1 for k in tail if k + off in cf and cf[k + off][1] == bf[k][1])
                if n > best[0]: best = (n, off)
            if best[0] >= 0.9 * len(tail): d['shift'] = best[1]
    sb, sc = b['sid'], c['sid']
    sbad = [k for k in sorted(set(sb) | set(sc)) if sb.get(k) != sc.get(k)]
    d['sid_frames_differ'] = len(sbad); d['sid_first'] = sbad[0] if sbad else None
    ab, ac = b['audio'], c['audio']
    n = min(len(ab), len(ac))
    abad = [i for i in range(n) if ab[i][0] != ac[i][0]]
    d['audio_blocks'] = (len(ab), len(ac)); d['audio_differ'] = len(abad) + abs(len(ab) - len(ac))
    if abad:
        d['audio_first_s'] = round(abad[0] * AUDIO_BLOCK / 48000.0, 2); d['audio_last_s'] = round(abad[-1] * AUDIO_BLOCK / 48000.0, 2)
        dl = [abs(ab[i][1] - ac[i][1]) for i in abad] + [abs(ab[i][2] - ac[i][2]) for i in abad]
        d['audio_level_change_db'] = round(max(dl), 1)
    return d

def side_by_side(png_b, png_c, out):
    from PIL import Image, ImageChops, ImageDraw
    a = Image.open(png_b).convert('RGB'); b = Image.open(png_c).convert('RGB')
    w, h = a.size
    diff = ImageChops.difference(a, b).convert('L').point(lambda v: 255 if v else 0)
    m = Image.new('RGB', (w, h)); m.paste((255, 0, 255), mask=diff)
    S = 2; im = Image.new('RGB', (3 * w * S + 2 * 8, h * S + 18), (20, 20, 40))
    for i, x in enumerate((a, b, m)): im.paste(x.resize((w * S, h * S), Image.NEAREST), (i * (w * S + 8), 18))
    dr = ImageDraw.Draw(im)
    for i, t in enumerate(('LAST CORE', 'NEW CORE', 'WHAT CHANGED (magenta)')): dr.text((i * (w * S + 8) + 4, 4), t, fill=(255, 255, 255))
    im.save(out)
    return int((np.array(diff) > 0).sum())

# ------------------------------------------------------------------------------------------ commands
def pick(args):
    M = load_manifest()
    if args.only:
        want = set(args.only.split(','))
        miss = want - {e.id for e in M}
        if miss: sys.exit('not in manifest.txt: ' + ', '.join(sorted(miss)))
        M = [e for e in M if e.id in want]
    for e in M: resolve(e)
    return M

def emulator_guard(emu, strict):
    if not os.path.exists(emu): sys.exit('no emulator at ' + emu)
    want = os.path.join(os.path.dirname(emu), 'x64sc.md5')
    if strict and os.path.exists(want):
        if md5(emu) != open(want).read().split()[0]:
            sys.exit('REFUSED: %s is not the current-KERNAL emulator (its md5 is not the one in %s)' % (emu, want))

def kernal_line(roms, mif):
    b, k = mif_roms(mif)
    ok = roms.get('KERNAL') == k and roms.get('BASIC') == b
    return ok, 'KERNAL %s, BASIC %s (this repo\'s %s: KERNAL %s, BASIC %s)' % (
        roms.get('KERNAL'), roms.get('BASIC'), os.path.relpath(mif, REPO), k, b)

def cmd_list(args):
    M = pick(args)
    for e in M:
        print('%-18s %-5s %-6s %s' % (e.id, e.where, 'ok' if e.path else 'SKIP', e.path or e.why))
    print('%d entries: %d can run here, %d skipped' % (len(M), sum(1 for e in M if e.path), sum(1 for e in M if not e.path)))

def cmd_baseline(args):
    emu = args.emu or EMU
    emulator_guard(emu, True)
    mif = args.mif or os.path.join(REPO, 'rtl/roms/octo_C64.mif')
    B = os.path.join(HERE, 'baselines', args.name)
    if os.path.exists(B) and not args.force and not args.only: sys.exit(B + ' exists (--force to replace it)')
    os.makedirs(B, exist_ok=True)
    M = pick(args)
    idx_path = os.path.join(B, 'index.json')
    idx = json.load(open(idx_path)) if os.path.exists(idx_path) else {'entries': {}}
    run_dir = os.path.join(WORK, 'baseline-' + args.name)
    rev = subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], cwd=REPO, capture_output=True, text=True).stdout.strip()
    idx.update({'name': args.name, 'emulator': os.path.abspath(emu), 'emulator_md5': md5(emu), 'seed': SEED,
                'made': time.strftime('%Y-%m-%d %H:%M UTC', time.gmtime()), 'repo_commit': rev, 'format': FORMAT,
                'note': 'fingerprints of the last core (emulator), made by tools/regress/regress.py baseline'})
    for e in M:
        if not e.path:
            print('%-18s SKIPPED  %s' % (e.id, e.why)); idx['entries'][e.id] = {'status': 'skipped', 'why': e.why}; continue
        r = run_one(e, emu, os.path.join(run_dir, e.id))
        ok, kl = kernal_line(r['roms'], mif)
        if not ok:
            sys.exit('REFUSED: the emulator did not run the current Octophonic KERNAL: ' + kl)
        idx['kernal'] = kl
        save_fp(r, os.path.join(B, e.id + '.fp.gz'))
        idx['entries'][e.id] = {'status': r['status'], 'program': os.path.relpath(e.path, REPO) if e.path.startswith(REPO) else e.path,
                                'program_md5': program_md5(e.path), 'frames': len(r['frames']), 'audio_s': round(len(r['audio']) * AUDIO_BLOCK / 48000, 1),
                                'sid_frames': len(r['sid']), 'jam': r.get('jam'), 'what': e.what, 'budget': e.frames}
        print('%-18s %-8s %4d frames, %5.1f s of sound, %4d frames with SID writes, %.0f s  %s' % (
            e.id, r['status'], len(r['frames']), len(r['audio']) * AUDIO_BLOCK / 48000, len(r['sid']), r['seconds'], e.what), flush=True)
        json.dump(idx, open(idx_path, 'w'), indent=1, sort_keys=True)
    print('baseline %s: %s' % (args.name, B))

def cmd_compare(args):
    emu = args.emu or EMU
    emulator_guard(emu, False)
    B = os.path.join(HERE, 'baselines', args.name)
    idx = json.load(open(os.path.join(B, 'index.json')))
    mif = args.mif or os.path.join(REPO, 'rtl/roms/octo_C64.mif')
    out = args.out or os.path.join(WORK, 'compare-%s-%s' % (args.name, time.strftime('%Y%m%d-%H%M%S')))
    os.makedirs(out, exist_ok=True)
    M = pick(args)
    base_emu = idx['emulator']
    can_redraw = os.path.exists(base_emu) and md5(base_emu) == idx['emulator_md5']
    L = []; P = lambda s='': (L.append(s), print(s, flush=True))
    P('OCTOPHONIC 64 - OLD-SOFTWARE REGRESSION TEST (Fix 69)                       (c) 2026 Mong00se')
    P('last core : baseline "%s" (%s, emulator md5 %s)' % (args.name, idx['made'], idx['emulator_md5']))
    P('            %s' % idx.get('kernal', ''))
    P('new core  : %s (md5 %s)' % (os.path.abspath(emu), md5(emu)))
    P('runs      : seed %d, program dropped on Octophonic OS at frame %d; work folder %s' % (SEED, DROP_AT, out))
    P()
    counts = {}; fails = []; kl_shown = False
    for e in M:
        be = idx['entries'].get(e.id)
        if be is None or be.get('status') == 'skipped':
            st = 'SKIPPED'; why = (be or {}).get('why') or 'not in the baseline'
            if not e.path: why = e.why
            P('%-18s %-10s %s' % (e.id, st, why)); counts[st] = counts.get(st, 0) + 1; continue
        if not e.path:
            P('%-18s %-10s %s (it IS in the baseline: nothing to run it from here)' % (e.id, 'MISSING', e.why))
            counts['MISSING'] = counts.get('MISSING', 0) + 1; fails.append(e.id); continue
        if program_md5(e.path) != be['program_md5']:
            P('%-18s %-10s the program file is not the one in the baseline (%s) - compare cores with the SAME programs' % (e.id, 'WRONG FILE', e.path))
            counts['WRONG FILE'] = counts.get('WRONG FILE', 0) + 1; fails.append(e.id); continue
        r = run_one(e, emu, os.path.join(out, e.id))
        if not kl_shown:
            ok, kl = kernal_line(r['roms'], mif)
            P('new core ran: %s%s' % (kl, '' if ok else '   <- NOT this repo\'s KERNAL')); P(); kl_shown = True
        b = load_fp(os.path.join(B, e.id + '.fp.gz'))
        if r['status'] == 'timed out': st = 'TIMED OUT'
        elif r['status'] in ('crashed', 'did not start') and be['status'] == 'ran':
            st = r['status'].upper()
        else:
            st = None
        d = compare_fp(b, r)
        if st is None and d['frames_cand'] < d['frames_base'] - 2:
            st = 'CRASHED'; r['note'] = 'stopped after %d of %d frames' % (d['frames_cand'], d['frames_base'])
        if st is None:
            st = 'IDENTICAL' if not d['frames_differ'] and not d['audio_differ'] and not d['sid_frames_differ'] and d['frames_cand'] == d['frames_base'] else 'CHANGED'
        counts[st] = counts.get(st, 0) + 1
        if st != 'IDENTICAL': fails.append(e.id)
        line = '%-18s %-10s %s' % (e.id, st, e.what)
        P(line)
        if st == 'IDENTICAL':
            P('%18s   %d frames, %d SID-write frames, %.1f s of sound: all the same' % ('', d['frames_cand'], len(r['sid']), len(r['audio']) * AUDIO_BLOCK / 48000))
            continue
        if r.get('jam'): P('%18s   the 6510 jammed (JAM at %s)' % ('', r['jam']))
        if r.get('note'): P('%18s   %s' % ('', r['note']))
        if d['frames_differ']:
            P('%18s   picture: %d of %d frames differ (HDMI %d, VIC/CRT %d), first frame %d (%s), last %d' % (
                '', d['frames_differ'], min(d['frames_base'], d['frames_cand']), d['hdmi_differ'], d['crt_differ'], d['first_frame'], d['first_frame_part'], d['last_frame']))
            if 'shift' in d: P('%18s   the program\'s pictures are the same, %d frame(s) %s' % ('', abs(d['shift']), 'later' if d['shift'] > 0 else 'earlier'))
            f = d['first_frame']
            if can_redraw:
                pb = os.path.join(out, e.id, 'last'); pc = os.path.join(out, e.id, 'new')
                ee = Entry([e.id, e.where, e.find, e.run, str(max(e.frames, f + 10)), e.input, e.needs, e.what]); ee.path = e.path
                run_one(ee, base_emu, pb, png_only=f); run_one(ee, emu, pc, png_only=f)
                fb = os.path.join(pb, 'e_hdmi_%05d.png' % f); fc = os.path.join(pc, 'e_hdmi_%05d.png' % f)
                if os.path.exists(fb) and os.path.exists(fc):
                    sbs = os.path.join(out, '%s - first changed frame %d.png' % (e.id, f))
                    n = side_by_side(fb, fc, sbs)
                    P('%18s   side by side: %s (%d pixels differ on the HDMI picture%s)' % ('', sbs, n, '' if n else ' - only the VIC/CRT picture differs'))
            else:
                P('%18s   (no side-by-side: the last core\'s emulator %s is gone or changed)' % ('', base_emu))
        if d['sid_frames_differ']:
            P('%18s   SID writes differ in %d frames, first in frame %d' % ('', d['sid_frames_differ'], d['sid_first']))
        if d['audio_differ']:
            P('%18s   sound: %d of %d 20 ms blocks differ, from %.2f s to %.2f s; biggest level change %.1f dB%s' % (
                '', d['audio_differ'], max(d['audio_blocks']), d.get('audio_first_s', 0), d.get('audio_last_s', 0), d.get('audio_level_change_db', 0),
                '' if d['sid_frames_differ'] else ' (same SID writes: the SIDs or the mix sound different)'))
        if not d['frames_differ'] and not d['audio_differ'] and not d['sid_frames_differ'] and d['frames_cand'] != d['frames_base']:
            P('%18s   ran %d frames, the baseline %d' % ('', d['frames_cand'], d['frames_base']))
    P()
    P('totals: ' + ', '.join('%s %d' % kv for kv in sorted(counts.items())))
    verdict = 'FAIL' if fails else 'PASS'
    P('%s%s' % (verdict, (' - not the same: ' + ', '.join(fails)) if fails else ' - every program that ran is identical to the last core' +
                ('' if not counts.get('SKIPPED') else ' (%d skipped, listed above)' % counts['SKIPPED'])))
    open(os.path.join(out, 'REPORT.txt'), 'w').write('\n'.join(L) + '\n')
    print('report: ' + os.path.join(out, 'REPORT.txt'))
    sys.exit(1 if fails else 0)

def cmd_determinism(args):
    emu = args.emu or EMU
    emulator_guard(emu, False)
    M = pick(args); bad = 0
    for e in M:
        if not e.path: print('%-18s SKIPPED  %s' % (e.id, e.why)); continue
        a = run_one(e, emu, os.path.join(WORK, 'determinism', e.id, 'run1'), shots=(999999, 1000000))
        b = run_one(e, emu, os.path.join(WORK, 'determinism', e.id, 'run2'), shots=(999999, 1000000))
        d = compare_fp(a, b)
        same = not d['frames_differ'] and not d['audio_differ'] and not d['sid_frames_differ'] and d['frames_cand'] == d['frames_base']
        bad += not same
        print('%-18s %s  (%d frames, %.1f s of sound)%s' % (e.id, 'SAME TWICE' if same else 'DIFFERENT', d['frames_base'], len(a['audio']) * AUDIO_BLOCK / 48000,
              '' if same else ' first frame %s, sound from %s s' % (d['first_frame'], d.get('audio_first_s'))), flush=True)
    print('determinism: %s' % ('OK - every run gave the same pictures, SID writes and sound twice' if not bad else '%d NOT deterministic' % bad))
    sys.exit(1 if bad else 0)

def main():
    ap = argparse.ArgumentParser(description='Octophonic 64 old-software regression test (Fix 69) - (c) 2026 Mong00se')
    sp = ap.add_subparsers(dest='cmd', required=True)
    for n in ('list', 'baseline', 'compare', 'determinism'):
        s = sp.add_parser(n)
        if n in ('baseline', 'compare'): s.add_argument('name')
        s.add_argument('--only'); s.add_argument('--emu'); s.add_argument('--mif'); s.add_argument('--out'); s.add_argument('--force', action='store_true')
    args = ap.parse_args()
    os.makedirs(WORK, exist_ok=True)
    {'list': cmd_list, 'baseline': cmd_baseline, 'compare': cmd_compare, 'determinism': cmd_determinism}[args.cmd](args)

if __name__ == '__main__':
    main()
