#!/usr/bin/env python3
# OCTOPHONIC 64 - REGRESSION TEST (Fix 69): make a TEST "new core" to prove the comparator works. (c) 2026 Mong00se
#
# These are NOT real cores: each is a copy of the current emulator (with its ROMs folder and OS files beside it)
# with ONE deliberate, tiny change, so we can show the test catches a one-register difference - and that an
# unchanged copy passes.
#
#   make_test_candidate.py same          OUTDIR   an exact copy (the comparator must say PASS)
#   make_test_candidate.py kernal-border OUTDIR   the KERNAL's start-screen border colour, LDA #$06 at $FBC9 ->
#                                                 LDA #$0E (one VIC register value; the emulator's built-in KERNAL
#                                                 patch and its CRC are changed as a rebuild with that mif would)
#   make_test_candidate.py jingle-note   OUTDIR   the start jingle's first note C4: SID frequency 4455 -> 4456
#                                                 (one SID register value, one step; in SHELL.PRG, the OS side)
#   [--emu X64SC]   the emulator to copy (default /home/claude/emu/x64sc)
import os, re, shutil, sys, zlib

def mif_kernal(path):
    d = open(path).read(); out = {}
    d = d[d.index('BEGIN') + 5:]
    for a, vs in re.findall(r'^\s*\[?([0-9A-Fa-f]+)(?:\.\.[0-9A-Fa-f]+\])?\s*:\s*([0-9A-Fa-f ]+);', d, re.M):
        for k, v in enumerate(vs.split()): out[int(a, 16) + k] = int(v, 16)
    return bytes(out.get(i, 0) for i in range(8192, 16384))

def main():
    a = sys.argv[1:]
    emu = '/home/claude/emu/x64sc'
    if '--emu' in a: i = a.index('--emu'); emu = a[i + 1]; del a[i:i + 2]
    if len(a) != 2 or a[0] not in ('same', 'kernal-border', 'jingle-note'): sys.exit('usage: make_test_candidate.py same|kernal-border|jingle-note OUTDIR [--emu X64SC]')
    kind, out = a
    src = os.path.dirname(os.path.abspath(emu))
    os.makedirs(out, exist_ok=True)
    for d in ('ROMs', 'octophonic'):
        if os.path.isdir(os.path.join(src, d)): shutil.copytree(os.path.join(src, d), os.path.join(out, d), dirs_exist_ok=True)
    b = bytearray(open(emu, 'rb').read())
    if kind == 'kernal-border':
        repo = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
        k = bytearray(mif_kernal(os.path.join(repo, 'rtl/roms/octo_C64.mif')))
        at = 0x1BC9                                    # $FBC9: LDA #$06 / STA $D020
        assert k[at:at + 5] == bytes.fromhex('a9068d20d0'), 'the KERNAL is not the one this test knows'
        win = bytes(k[at - 5:at + 7])                  # the bytes around it, inside the emulator's KERNAL patch
        hits = [m.start() for m in re.finditer(re.escape(win), b)]
        assert len(hits) == 1, 'the KERNAL patch bytes are not found once in the emulator (%d)' % len(hits)
        old = zlib.crc32(bytes(k)); k[at + 1] = 0x0E; new = zlib.crc32(bytes(k))
        b[hits[0] + 6] = 0x0E
        o, n = old.to_bytes(4, 'little'), new.to_bytes(4, 'little')
        c = b.count(o); b = bytearray(bytes(b).replace(o, n))
        print('kernal-border: $FBCA 06 -> 0E; the KERNAL CRC %08X -> %08X (%d places in the emulator)' % (old, new, c))
    elif kind == 'jingle-note':
        p = os.path.join(out, 'octophonic', 'SHELL.PRG')
        s = bytearray(open(p, 'rb').read())
        w = (4455).to_bytes(2, 'little') + (5001).to_bytes(2, 'little') + (5613).to_bytes(2, 'little')
        i = s.find(w); assert i > 0 and s.find(w, i + 1) < 0, 'the jingle table is not found once in SHELL.PRG'
        s[i:i + 2] = (4456).to_bytes(2, 'little')
        open(p, 'wb').write(s)
        print('jingle-note: SHELL.PRG offset %d: the first note 4455 -> 4456' % i)
    open(os.path.join(out, 'x64sc'), 'wb').write(b)
    os.chmod(os.path.join(out, 'x64sc'), 0o755)
    print('test candidate (%s): %s/x64sc' % (kind, out))

if __name__ == '__main__':
    main()
