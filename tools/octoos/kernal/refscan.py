# run by build.sh: every branch, JSR and JMP in Commodore's ROMs (std.bin) that lands in a piece the
# Octophonic ROM overwrites (patch.py's pieces, the wedges' tape room), from stock code that is not
# itself overwritten. Each hit must be one checked by hand: listed below with why it is harmless.
# A new hit stops the build - the piece has grown over code something still calls.
import re, sys
d = open('std.bin', 'rb').read()
def adr(i): return 0xA000 + i if i < 8192 else 0xE000 + i - 8192
src = open('patch.py').read()
pieces = [(int(a, 16), int(b, 16)) for a, b in re.findall(r"'[a-z]': \(0x([0-9A-F]{4}), 0x([0-9A-F]{4})", src)]
pieces += [(0xF72C, 0xF92B), (0xFB97, 0xFCD0)]          # the wedges
patched = {0xE39A, 0xF179, 0xF17A, 0xF17B, 0xF1E5, 0xF1E6, 0xF1E7, 0xF38B, 0xF38C, 0xF38D,
           0xF534, 0xF535, 0xF65A, 0xF65B}                # patch.py rewrites these (the calls into us, the tape paths cut)
known = {                                                 # (from, to): why it is not a call
    (0xAFB0, 0xFA20): 'an operand byte', (0xB8F4, 0xE4D0): 'an operand byte', (0xBFE7, 0xBF6A): "EXP's constants",
    (0xF152, 0xF0F8): 'an operand byte', (0xF1AE, 0xF1A0): 'an operand byte', (0xF506, 0xF552): 'an operand byte',
    (0xF517, 0xF539): 'an operand byte', (0xF525, 0xF577): 'an operand byte', (0xF725, 0xF747): 'an operand byte',
    (0xFD14, 0xFCB8): 'RESTOR\'s table', (0xFD16, 0xFCB8): 'RESTOR\'s table'}
dead = lambda a: any(lo <= a <= hi for lo, hi in pieces)
bad = []
for i in range(len(d) - 2):
    a = adr(i); op = d[i]
    if dead(a) or a in patched: continue
    if op in (0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0): o = d[i + 1]; t = a + 2 + (o - 256 if o > 127 else o)
    elif op in (0x20, 0x4C): t = d[i + 1] | d[i + 2] << 8
    else: continue
    if dead(t) and (a, t) not in known: bad.append('%02X at $%04X -> $%04X' % (op, a, t))
if bad: print('refscan: stock code calls into an overwritten piece:\n  ' + '\n  '.join(bad)); sys.exit(1)
print('refscan: ok (%d pieces, %d hits checked by hand)' % (len(pieces), len(known)))
