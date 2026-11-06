#!/usr/bin/env python3
# md2txt.py IN.md OUT.txt - a plain text copy of docs/OCTOPAINT.md ("How to use.txt"): no markdown marks, tables as aligned
# columns, lines wrapped at 78, Windows line ends. Original work by Mong00se.
import re, sys, textwrap

def clean(t):
    t = re.sub(r'\*\*(.+?)\*\*', r'\1', t)
    t = re.sub(r'`([^`]*)`', r'\1', t)
    return t

def table(rows):
    cells = [[clean(c.strip()) for c in r.strip().strip('|').split('|')] for r in rows]
    cells = [c for c in cells if not all(re.fullmatch(r'-+', x) for x in c)]
    n = len(cells[0])
    w = [max(len(r[i]) for r in cells[1:]) if len(cells) > 1 else 0 for i in range(n - 1)]
    out = []
    for r in cells[1:]:
        head = '  '.join(r[i].ljust(w[i]) for i in range(n - 1))
        last = r[-1]
        ind = len(head) + 2
        wrapped = textwrap.wrap(last, max(30, 78 - ind)) or ['']
        out.append('  ' + head + '  ' + wrapped[0])
        for x in wrapped[1:]:
            out.append(' ' * (ind + 2) + x)
    return out

src = open(sys.argv[1]).read().split('\n')
out = []
para = []          # the paragraph / list item being gathered: (marker, [lines])

def flush():
    global para
    if para:
        mk, lines = para
        body = clean(' '.join(x.strip() for x in lines))
        w = textwrap.wrap(body, 78 - len(mk)) or ['']
        out.append(mk + w[0])
        out.extend(' ' * len(mk) + x for x in w[1:])
        para = []

i = 0
while i < len(src):
    line = src[i]
    if line.startswith('|'):
        flush()
        j = i
        while j < len(src) and src[j].startswith('|'):
            j += 1
        out += table(src[i:j]); i = j; continue
    m = re.match(r'(#+) (.*)', line)
    if m:
        flush()
        t = clean(m.group(2)).upper()
        out += ['', t, ('=' if len(m.group(1)) == 1 else '-') * len(t), '']
    elif line.startswith('    '):
        flush(); out.append(line)
    elif re.match(r'(- |\d+\. )', line):
        flush()
        mk = re.match(r'(- |\d+\. )', line).group(1)
        para = (mk, [line[len(mk):]])
    elif line.strip() == '':
        flush(); out.append('')
    elif para and line.startswith('  '):
        para[1].append(line)
    else:
        if para and para[0] == '':
            para[1].append(line)
        else:
            flush(); para = ('', [line])
    i += 1
flush()
txt = re.sub(r'\n{3,}', '\n\n', '\n'.join(out).strip('\n') + '\n')
open(sys.argv[2], 'w', newline='').write(txt.replace('\n', '\r\n'))
