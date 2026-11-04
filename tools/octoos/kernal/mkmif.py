# octo64.bin (BASIC + KERNAL, 16 KB) -> rtl/roms/octo_C64.mif, in the layout the file already has
import sys
d=open('octo64.bin','rb').read(); assert len(d)==16384
hdr='''-- Octophonic 64 V1.1: Commodore's own BASIC V2 and KERNAL (901226-01, 901227-03) - every C64 program
-- as on a real machine - with the start screen made over (Neal's mock-up 12): a dark top box drawn by
-- OctoVIC (the 8-SID eq, OCTOPHONIC 64 and the words in a cyan-to-violet gradient, OCTOVIC in the
-- rainbow, the network light, the REU attached), 38911 BASIC BYTES FREE, and the bar on row 24 that
-- the screen editor never reaches (rows 0-23 only while the start screen is up). Its code sits where
-- the core never runs (no tape): the tape room and the tape's other paths, the old banner, the
-- unused bytes (tools/octoos/kernal/octo.asm). RUN, SYS and LOAD switch it off first - the stock
-- 25-row editor again. SHIFT+RUN/STOP: LOAD"*",8 and RUN. By Neal (8BitG00se).
-- Octophonic OS 1 (Mong00se): at READY, @ lists the SD folder, @NAME / @/NAME change folder, /NAME
-- loads and runs, F1 opens the browser (SHELL.PRG), C=+F1 on a MiSTer its own menu - code in the
-- tape room ($F72C-$F928 and $FB97-$FCD0), talking to Main through the mailbox at $D6F0
-- (docs/OCTOOS.md). Device 1 (tape) gives ?ILLEGAL DEVICE NUMBER.
-- Built by tools/octoos/kernal/build.sh, which makes the Octophonic 64 Emulator's ROM from this file.
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
