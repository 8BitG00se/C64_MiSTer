# (c) 2026 Mong00se
# OCTOPHONIC FAST LOAD (Fix 49): the fast loader's ROM bank -> rtl/roms/octo_fastload.mif.
# The bank is Commodore's stock BASIC and KERNAL (the core's std_C64.mif) with our loader where the
# tape routines were; the core only keeps the 4K that differs, $F000-$FFFF (rtl/fpga64_buslogic.vhd),
# and reads the rest from the stock ROM it already has. Every byte changed is checked against the
# stock ROM first. Run by build.sh after fastdrive.asm and fastload.asm are assembled.
#   fastload.py <octo_fastload.mif> [<octo_fastload.h for the emulator: the changed bytes only; octo_fastdrive.h goes beside it>]
# (the drive's ROM goes beside the core's other drive ROMs: rtl/iec_drive/c1541_fastload.mif)
import sys, subprocess, zlib
d = bytearray(open('std.bin', 'rb').read()); assert len(d) == 16384, 'std.bin: BASIC + KERNAL, 16 KB'
stock = bytes(d)
main = open('octo64.bin', 'rb').read(); assert len(main) == 16384, 'octo64.bin: the Octophonic BASIC + KERNAL (patch.py)'
def labels(fn): return {l.split('=')[0].strip(): int(l.split('=')[1].split(';')[0].strip().lstrip('$'), 16) for l in open(fn) if '=' in l}
def at(a): return 8192 + a - 0xE000
def want(a, b, why): assert d[at(a):at(a) + len(b)] == bytes(b), '%s at $%04X: %s' % (why, a, d[at(a):at(a) + len(b)].hex())
def put(a, b): d[at(a):at(a) + len(b)] = bytes(b)
LO, HI = 0xF000, 0xFFFF                          # the 4K the core keeps
ROOM, ROOMEND = 0xF72C, 0xFB8D                   # the tape room (stock code at $FB8E: the disk SAVE's start address)
TRAP = 0xEE13                                    # ACPTR: the core swaps the bank in there and reads JMP ROOM (fpga64_buslogic.vhd)
# the serial bus routines the loader calls and goes back into must be the stock ones in the main KERNAL too
assert main[at(0xED00):at(0xEEB3)] == stock[at(0xED00):at(0xEEB3)], 'the main KERNAL\'s serial bus routines are not the stock ones'
# the way out: STA $D03D in the bank, three bytes before an RTS of the main KERNAL's (the first one from $F900 on)
OUT = next(a for a in range(0xF900, ROOMEND - 2) if main[at(a + 3)] == 0x60)
subprocess.check_call(['acme', '-f', 'plain', '-Dout=%d' % OUT, '-o', 'fastload.bin', '-l', 'fastload.lbl', 'fastload.asm'])
f = open('fastload.bin', 'rb').read(); lab = labels('fastload.lbl')
assert lab['ctrap'] == ROOM and lab['fl_end'] <= OUT, 'the loader has grown into its way out'
want(ROOM, [0xA5, 0x93, 0x48], 'the tape room'); put(ROOM, f)
put(OUT, [0x8D, 0x3D, 0xD0])
# the tape's ways in, cut as in the main KERNAL (they would run into our code)
want(0xF4B6, [0x90, 0x7B], 'LOAD: device 1/2'); put(0xF4B6, [0x90, 0xF7])
want(0xF659, [0x4A, 0xB0, 0x03, 0x4C, 0x13, 0xF7], 'SAVE device 1'); put(0xF65A, [0xEA, 0xEA])
want(0xF179, [0x86, 0x97, 0x20], 'CHRIN tape'); put(0xF179, [0x4C, 0x0A, 0xF7])
want(0xF1E5, [0x20, 0x0D, 0xF8], 'CHROUT tape'); put(0xF1E5, [0x4C, 0xFC, 0xF1])
want(0xF2C8, [0xA5, 0xB9, 0x29], 'CLOSE tape'); put(0xF2C8, [0x4C, 0xF1, 0xF2])
want(0xF384, [0xC9, 0x02, 0xD0, 0x03, 0x4C, 0x09, 0xF4, 0x20, 0xD0, 0xF7], 'OPEN device 1'); put(0xF38B, [0x4C, 0x13, 0xF7])
# the keyboard: the Octophonic KERNAL points the decode vector ($028F) at its keyhk (wedge2.asm), and the
# stock IRQ in this bank jumps through it whenever a key is down - so the same address here goes straight
# on to the stock decoder ($EB48). (The F keys' start-screen shortcuts rest while a byte is on its way.)
KH = labels('wedge2.lbl')['keyhk']
assert 0xFB97 <= KH <= 0xFCD1 - 3 and not (ROOM <= KH + 2 and KH < OUT + 3), 'keyhk ($%04X) is not in the tape code above the loader' % KH
put(KH, [0x4C, 0x48, 0xEB])
# RUN/STOP+RESTORE and BRK: back to the main KERNAL for the warm start (fastload.asm's nmix)
N = lab['nmix']
want(0xFE66, [0x20, 0x15, 0xFD, 0x20, 0xA3, 0xFD], 'the warm start'); put(0xFE66, [0x4C, N & 255, N >> 8])
for lo, hi, why in ((0xF5A9, 0xF5AE, 'the disk LOAD\'s end'), (0xFB8E, 0xFB96, 'the disk SAVE\'s start address')):
    assert d[at(lo):at(hi) + 1] == stock[at(lo):at(hi) + 1], 'overwritten: ' + why
diff = [i for i in range(16384) if d[i] != stock[i]]
assert all(at(LO) <= i <= at(HI) for i in diff), 'a change outside $F000-$FFFF'
w = d[at(LO):at(HI) + 1]
hdr = '''-- Octophonic Fast Load (Fix 49, (c) 2026 Mong00se): $F000-$FFFF of the fast loader's ROM bank - Commodore's
-- stock KERNAL (901227-03) with the Octophonic fast loader where the tape routines were ($F72C on), the
-- tape's ways in cut and RUN/STOP+RESTORE handed back. The rest of the bank is the stock ROM (std_C64.mif).
-- The core swaps the bank in as the 6510 fetches ACPTR's first instruction ($EE13), a write to $D03D swaps
-- it out (rtl/fpga64_buslogic.vhd, rtl/fpga64_sid_iec.vhd, docs/FASTLOAD.md).
-- Built by tools/octoos/kernal/build.sh (fastload.py) from fastload.asm.
--
DEPTH = 4096;
WIDTH = 8;
ADDRESS_RADIX = HEX;
DATA_RADIX = HEX;
CONTENT BEGIN
'''
out = [hdr]
for a in range(0, 4096, 24): out.append('%04X: %s;\n' % (a, ' '.join('%02X' % b for b in w[a:a + 24])))
out.append('END;\n')
open(sys.argv[1], 'w').write(''.join(out))
# the drive's side: a 512-byte ROM at $1000 in the core's 1541 (rtl/iec_drive/c1541_logic.sv)
dr = open('fastdrive.bin', 'rb').read(); assert len(dr) == 512
import os
open(os.path.join(os.path.dirname(sys.argv[1]), '..', 'iec_drive', 'c1541_fastload.mif'), 'w').write(
    '''-- Octophonic Fast Load (Fix 49, (c) 2026 Mong00se): the 1541's side - a ROM at $1000-$11FF in the core's drive
-- (rtl/iec_drive/c1541_logic.sv). Built by tools/octoos/kernal/build.sh from fastdrive.asm.
--
DEPTH = 512;
WIDTH = 8;
ADDRESS_RADIX = HEX;
DATA_RADIX = HEX;
CONTENT BEGIN
''' + ''.join('%03X: %s;\n' % (a, ' '.join('%02X' % b for b in dr[a:a + 16])) for a in range(0, 512, 16)) + 'END;\n')
open('fastbank.bin', 'wb').write(d)              # (the whole bank, for tests; never committed)
if len(sys.argv) > 2:                            # the emulator's copy: only the bytes we changed, as runs
    runs = []; i = 0
    while i < len(diff):
        j = i
        while j + 1 < len(diff) and diff[j + 1] - diff[j] <= 1: j += 1
        runs.append((diff[i] - 8192, bytes(d[diff[i]:diff[j] + 1]))); i = j + 1
    h = ['/* made by tools/octoos/kernal/fastload.py (Fix 49): the fast loader\'s bank = the stock KERNAL + these bytes */\n',
         '#define OCTO_FASTBANK_CRC 0x%08XU\n' % zlib.crc32(bytes(d[8192:at(TRAP)]) + bytes([0x4C, ROOM & 255, ROOM >> 8]) + bytes(d[at(TRAP) + 3:])),
         'static const struct { unsigned short at, len; const unsigned char *bytes; } octo_fast_runs[] = {\n']
    for a, b in runs: h.append('    { 0x%04X, %d, (const unsigned char *)"%s" },\n' % (a, len(b), ''.join('\\x%02X' % x for x in b)))
    h.append('    { 0x%04X, 3, (const unsigned char *)"\\x4C\\x%02X\\x%02X" },   /* the trap: the core reads this at ACPTR while the bank is in */\n' % (TRAP - 0xE000, ROOM & 255, ROOM >> 8))
    h.append('};\n#define OCTO_FAST_NRUNS %d\n#define OCTO_FAST_TRAP 0x%04X\n' % (len(runs) + 1, TRAP))
    open(sys.argv[2], 'w').write(''.join(h))
    open(os.path.join(os.path.dirname(sys.argv[2]), 'octo_fastdrive.h'), 'w').write(
        '/* made by tools/octoos/kernal/fastload.py (Fix 49): the fast loader\'s ROM in the 1541, $1000-$11FF */\n'
        'static const unsigned char octo_fast_drive[512] = {%s};\n' % ','.join(str(x) for x in dr))
print('fastload: ok (%d bytes of loader, %d left in the tape room; %d bytes differ from stock)' % (len(f), ROOMEND + 1 - lab['fl_end'], len(diff)))
