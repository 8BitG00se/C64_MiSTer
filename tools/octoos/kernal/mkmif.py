# octo64.bin (BASIC + KERNAL, 16 KB) -> rtl/roms/octo_C64.mif, in the layout the file already has
import sys
d=open('octo64.bin','rb').read(); assert len(d)==16384
hdr='''-- Octophonic 64 V1.1: Commodore's own BASIC V2 and KERNAL (901226-01, 901227-03) - every C64 program
-- as on a real machine - with the start screen made over: eight colours a stock C64 cannot make
-- (OctoVIC), OCTOPHONIC 64 V1.1, OCTOVIC 256, READY. Its code sits where the tape routines were
-- ($F92C-$FB8D: the core has no tape). RUN, SYS and LOAD switch OctoVIC off first. SHIFT+RUN/STOP:
-- LOAD"*",8 and RUN. By Neal (8BitG00se).
-- Octophonic OS 1 (Mong00se): at READY, @ lists the SD folder, @NAME / @/NAME change folder, /NAME
-- loads and runs, F1 opens the browser (SHELL.PRG) - code in the rest of the tape room ($F72C-$F92B
-- and $FB97-$FCD0), talking to Main through the mailbox at $D6F0 (docs/OCTOOS.md), every request
-- giving up after 3 seconds. Device 1 (tape) gives ?ILLEGAL DEVICE NUMBER.
--
DEPTH = 16384;
WIDTH = 8;
ADDRESS_RADIX = HEX;
DATA_RADIX = HEX;
CONTENT BEGIN
'''
out=[hdr]
for a in range(0,16384,24):
    out.append('%04X: %s;\n'%(a,' '.join('%02X'%b for b in d[a:a+24])))
out.append('END;\n')
open(sys.argv[1],'w').write(''.join(out))
