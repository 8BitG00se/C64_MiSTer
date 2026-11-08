# a small **kern reader: each spine's notes as (start, length, midi or None), in whole notes
import re
def parse(path):
    lines = [l.rstrip('\n') for l in open(path)]
    spines = None; names = []
    for l in lines:
        if l.startswith('**'):
            spines = l.split('\t'); keep = [i for i, x in enumerate(spines) if x == '**kern']
            out = [[] for _ in keep]; t = [0.0] * len(keep); sections = []; continue
        if l.startswith('!!section:') and spines is not None: sections.append((t[0], l.split(':', 1)[1].strip())); continue
        if spines is None or l.startswith('!') or not l.strip(): continue
        toks = [l.split('\t')[i] for i in keep]
        if toks[0].startswith('*'):
            for i, tk in enumerate(toks):
                if tk.startswith('*I"'): pass
            continue
        if toks[0].startswith('='): continue
        for i, tk in enumerate(toks):
            if tk == '.': continue
            tk = tk.split(' ')[0]
            m = re.match(r'([\[\(]*)(\d+)(\.*)([a-gA-Gr]+)([#\-n]*)', tk)
            if not m: continue
            dur = {0: 2.0}.get(int(m.group(2)), None) or 1.0 / int(m.group(2))
            if m.group(2) == '0': dur = 2.0
            if m.group(2) == '00': dur = 4.0
            d = dur; add = dur
            for _ in m.group(3): add /= 2; d += add
            p = m.group(4); acc = m.group(5)
            if p[0] == 'r': midi = None
            else:
                base = {'c': 0, 'd': 2, 'e': 4, 'f': 5, 'g': 7, 'a': 9, 'b': 11}[p[0].lower()]
                octv = 4 + (len(p) - 1) if p[0].islower() else 3 - (len(p) - 1)
                midi = 12 * (octv + 1) + base + acc.count('#') - acc.count('-')
            if ']' in tk or '_' in tk:
                if out[i] and out[i][-1][2] == midi: s0, l0, _ = out[i][-1]; out[i][-1] = (s0, l0 + d, midi); t[i] += d; continue
            out[i].append((t[i], d, midi)); t[i] += d
    parse.sections = sections
    return out, t
if __name__ == '__main__':
    import sys
    out, t = parse(sys.argv[1])
    for i, s in enumerate(out): print('spine', i, 'notes', len(s), 'length', t[i], 'range', min(m for _, _, m in s if m), max(m for _, _, m in s if m))
    print(parse.sections)
