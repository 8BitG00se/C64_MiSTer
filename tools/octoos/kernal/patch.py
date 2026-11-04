# OCTOPHONIC 64 V1.1: Commodore's own BASIC and KERNAL (std.bin: 901226-01 then 901227-03, 16 KB) with
# the start screen (octo.asm), Octophonic OS's commands (wedge.asm, wedge2.asm) and the hooks into
# them -> octo64.bin. Every byte it changes is checked against what the stock ROM has there first.
import os, sys
d = bytearray(open('std.bin', 'rb').read()); assert len(d) == 16384, 'std.bin: BASIC + KERNAL, 16 KB'
o = open('octo.bin', 'rb').read()
lab = {l.split('=')[0].strip(): int(l.split('=')[1].split(';')[0].strip().lstrip('$'), 16) for l in open('octo.lbl') if '=' in l}
OBASE = 0xBF53                                   # octo.bin starts at its lowest piece
def at(a): return a - 0xA000 if a < 0xC000 else 8192 + a - 0xE000
def want(a, b, why):
    assert d[at(a):at(a) + len(b)] == bytes(b), '%s at $%04X: %s' % (why, a, d[at(a):at(a) + len(b)].hex())
def put(a, b): d[at(a):at(a) + len(b)] = bytes(b)
def jsr(lbl): return [0x20, lab[lbl] & 255, lab[lbl] >> 8]
def jmp(a): return [0x4C, a & 255, a >> 8]

# BASIC's cold start: the start screen instead of the banner (COMMODORE 64 BASIC V2 / BYTES FREE)
want(0xE39A, [0x20, 0x22, 0xE4], 'the banner call'); put(0xE39A, jsr('newboot'))
# RUN, LOAD, SYS: OctoVIC off first (BASIC's statement table, address - 1)
for addr, orig, new in ((0xA020, 0xA871, 'w_run'), (0xA032, 0xE168, 'w_load'), (0xA048, 0xE12A, 'w_sys')):
    v = d[at(addr)] | d[at(addr) + 1] << 8; assert v == orig - 1, (hex(addr), hex(v))
    t = lab[new] - 1; put(addr, [t & 255, t >> 8])
# SHIFT+RUN/STOP: LOAD"*",8 and RUN, spelt out (wedge.asm's SHIFTR2)
want(0xE5EE, [0xA2, 0x09, 0x78, 0x86, 0xC6], 'SHIFT+RUN/STOP'); put(0xE5EE, [0xA2, 0x08] + jsr('shiftrun'))
want(0xECE7, b'LOAD\rRUN\r', 'the SHIFT+RUN/STOP text'); put(0xECE7, [0x4C, 0xCF, 0x22, 0x2A, 0x22, 0x2C, 0x38, 0x0D, 0x0D])

# the start screen's pieces, each where the stock ROM has nothing the core runs (see octo.asm)
free = {'h': (0xBF53, 0xBF70, [0xAA] * 30),      # BASIC: unused
        'e': (0xE422, 0xE446, [0xA5, 0x2B, 0xA4, 0x2C, 0x20, 0x08, 0xA4]),   # the banner routine
        'f': (0xE473, 0xE4AB, [0x93, 0x0D, 0x20, 0x20, 0x20, 0x20, 0x2A]),   # its text
        'g': (0xE4B7, 0xE4D2, [0xAA] * 28),      # KERNAL: unused
        'n': (0xE4E0, 0xE4E9, [0x69, 0x02, 0xA4, 0x91, 0xC8]),               # the tape's wait after FOUND (E4EA-B: RS232's table)
        'd': (0xF0D8, 0xF105, b'\rPRESS PLAY ON TAP'),                       # the tape's messages
        'l': (0xF17C, 0xF1AC, [0x99, 0xF1, 0xB0, 0x16]),               # CHRIN from tape
        'm': (0xF1E8, 0xF1FB, [0xD0, 0x0E, 0x20, 0x64, 0xF8]),               # CHROUT to tape
        'k': (0xF2CB, 0xF2ED, [0x0F, 0xF0, 0x23, 0x20, 0xD0, 0xF7]),         # CLOSE of a tape file
        'i': (0xF38E, 0xF3D2, [0xB0, 0x03, 0x4C, 0x13, 0xF7, 0xA5, 0xB9]),   # OPEN of a tape file
        'b': (0xF539, 0xF5A8, [0x20, 0xD0, 0xF7, 0xB0, 0x03]),               # the tape LOAD
        'c': (0xF65F, 0xF68D, [0x20, 0xD0, 0xF7, 0x90, 0x8D]),               # the tape SAVE
        'a': (0xF92C, 0xFB8D, [0xAE, 0x07, 0xDC, 0xA0, 0xFF])}                           # the tape room
for k, (lo, hi, sig) in free.items():
    want(lo, sig, 'free room %s' % k)
    a, e = lab['seg_' + k], lab['seg_' + k + 'e']
    assert a == lo and e <= hi + 1, ('seg', k, hex(a), hex(e))
    put(a, o[a - OBASE:e - OBASE])
assert o[0xF92C - OBASE] == 0x4C and o[0xF92F - OBASE] == 0x4C and (o[0xF930 - OBASE] | o[0xF931 - OBASE] << 8) == lab['frame'], 'the vectors at $F92C/$F92F'
# device 1 (tape): never opened, so these paths can't run - each now goes where an error or a
# non-tape device would, in case anything ever gets there
want(0xF179, [0x86, 0x97, 0x20], 'CHRIN tape'); put(0xF179, jmp(0xF70A))      # ?NOT INPUT FILE
want(0xF1E5, [0x20, 0x0D, 0xF8], 'CHROUT tape'); put(0xF1E5, jmp(0xF1FC))     # as RS232's end
want(0xF2C8, [0xA5, 0xB9, 0x29], 'CLOSE tape'); put(0xF2C8, jmp(0xF2F1))      # as the screen's
for a in (0xF533, 0xF659):                       # LOAD, SAVE: LSR / BCS tape / JMP illegal
    want(a, [0x4A, 0xB0, 0x03, 0x4C, 0x13, 0xF7], 'LOAD/SAVE device 1'); put(a + 1, [0xEA, 0xEA])
want(0xF384, [0xC9, 0x02, 0xD0, 0x03, 0x4C, 0x09, 0xF4, 0x20, 0xD0, 0xF7], 'OPEN device 1')
put(0xF38B, jmp(0xF713))                         # ?ILLEGAL DEVICE NUMBER

# OCTOPHONIC OS: the wedge in the tape room below, wedge2 above (the start screen's pieces between)
w = open('wedge.bin', 'rb').read(); assert len(w) <= 0xF92C - 0xF72C
put(0xF72C, w)
w2 = open('wedge2.bin', 'rb').read(); assert len(w2) <= 0xFCD1 - 0xFB97
put(0xFB97, w2)

# the hooks: CINT (reset, RUN/STOP+RESTORE) the 25-row editor and OctoVIC off; the IRQ the eq and
# the light; CLR and the scroll the top box
wl = {l.split('=')[0].strip(): int(l.split('=')[1].split(';')[0].strip().lstrip('$'), 16) for l in open('wedge.lbl') if '=' in l}
want(0xE518, [0x20, 0xA0, 0xE5], 'CINT'); put(0xE518, [0x20, wl['cinthk'] & 255, wl['cinthk'] >> 8])   # (wedge.asm)
want(0xEA31, [0x20, 0xEA, 0xFF], 'the IRQ'); put(0xEA31, jsr('irqhk'))
want(0xE86E, [0x20, 0x44, 0xE5], 'CLR'); put(0xE86E, jsr('clrhk'))
want(0xE8F6, [0xA2, 0xFF, 0xC6, 0xD6, 0xC6, 0xC9, 0xCE, 0xA5, 0x02], 'the scroll')
put(0xE8F6, jsr('scrhk') + [0xEA] * 6)
# the screen editor's rows: R25 / R24 / R23 (zero page, 25 24 23 or 24 23 22) for its constants
R25, R24, R23 = lab['R25'], lab['R24'], lab['R23']
for a, op, n, new in ((0xE55E, 0xA2, 0x18, [0xA6, R24]),       # CLR: LDX #24 - the rows it clears
                      (0xE6CF, 0xE0, 0x19, [0xE4, R25]),       # CPX #25: a long line, scroll
                      (0xE881, 0xE0, 0x19, [0xE4, R25]),       # CPX #25: cursor down, scroll
                      (0xE8C4, 0xE0, 0x19, [0xE4, R25]),       # CPX #25: the line's end
                      (0xE903, 0xE0, 0x18, [0xE4, R24]),       # the scroll: the rows it moves up
                      (0xE925, 0xE0, 0x18, [0xE4, R24]),       #   and their line links
                      (0xE96F, 0xE0, 0x18, [0xE4, R24]),       # INST: a line in, scroll?
                      (0xE98D, 0xA2, 0x19, [0xA6, R25]),       #   the rows it moves down
                      (0xE9A9, 0xA2, 0x17, [0xA6, R23])):      #   and their line links
    want(a, [op, n], 'the editor at $%04X' % a); put(a, new)
want(0xE929, [0xA5, 0xF1, 0x09, 0x80, 0x85, 0xF1], 'the scroll: the last line link')
put(0xE929, [0xB5, 0xD9, 0x09, 0x80, 0x95, 0xD9])               # LDA/STA $D9,X (X: the last row)

# stock code inside the tape areas that the disk uses - never overwritten: the disk LOAD's end
# (F52E BCC $F5A9: CLC, LDX $AE, LDY $AF, RTS) and the disk SAVE's start address (F617 JSR $FB8E).
# (V1.1 builds up to start screen build 1 wrote over $FB8E: SAVE to disk then took its start address
# from whatever $AD held.)
stock = open('std.bin', 'rb').read()
for lo, hi, why in ((0xF5A9, 0xF5AE, 'the disk LOAD\'s end'), (0xFB8E, 0xFB96, 'the disk SAVE\'s start address')):
    assert d[at(lo):at(hi) + 1] == stock[at(lo):at(hi) + 1], 'overwritten: ' + why
open('octo64.bin', 'wb').write(d)
# the ROMs as files, for romtest and the emulator's own check
out = sys.argv[1] if len(sys.argv) > 1 else '/tmp/kr11'
os.makedirs(out, exist_ok=True)
open(out + '/basic-901226-01.bin', 'wb').write(d[:8192]); open(out + '/kernal-901227-03.bin', 'wb').write(d[8192:])
print('ok: tape room left %d, start screen %d bytes' % (0xFB8E - lab['seg_ae'], sum(lab['seg_' + k + 'e'] - lab['seg_' + k] for k in free)))
