#!/usr/bin/env python3
# REWIND simulation: the data tables of the test "game" (rwgame.asm) - a hex font, a ball sprite and a
# triangle wave - and the tiny ROM the simulated C64 starts from.          (c) 2026 Mong00se
import sys
F = {  # 5x7 digits and A-F
 '0':"01110 10001 10011 10101 11001 10001 01110", '1':"00100 01100 00100 00100 00100 00100 01110",
 '2':"01110 10001 00001 00010 00100 01000 11111", '3':"11110 00001 00001 01110 00001 00001 11110",
 '4':"00010 00110 01010 10010 11111 00010 00010", '5':"11111 10000 11110 00001 00001 10001 01110",
 '6':"00110 01000 10000 11110 10001 10001 01110", '7':"11111 00001 00010 00100 01000 01000 01000",
 '8':"01110 10001 10001 01110 10001 10001 01110", '9':"01110 10001 10001 01111 00001 00010 01100",
 'A':"01110 10001 10001 11111 10001 10001 10001", 'B':"11110 10001 10001 11110 10001 10001 11110",
 'C':"01110 10001 10000 10000 10000 10001 01110", 'D':"11110 10001 10001 10001 10001 10001 11110",
 'E':"11111 10000 10000 11110 10000 10000 11111", 'F':"11111 10000 10000 11110 10000 10000 10000"}
out = ["; made by mkgame.py", "font"]
out.append("        !byte 0,0,0,0,0,0,0,0")
for c in "0123456789ABCDEF":
    rows = [int(r, 2) << 2 for r in F[c].split()] + [0]
    out.append("        !byte " + ",".join("$%02x" % r for r in rows))
out.append("        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff")        # 17: solid
out.append("        !byte $aa,$55,$aa,$55,$aa,$55,$aa,$55")        # 18: checker
out.append("ball")
import math
for y in range(21):
    b = 0
    for x in range(24):
        if (x - 11.5) ** 2 + ((y - 10) * 1.15) ** 2 < 100: b |= 1 << (23 - x)
    out.append("        !byte $%02x,$%02x,$%02x" % (b >> 16, (b >> 8) & 255, b & 255))
out.append("        !byte 0")
out.append("tri")
for i in range(256):
    v = i if i < 128 else 255 - i
    out.append("        !byte %d" % (60 + v))
open(sys.argv[1], "w").write("\n".join(out) + "\n")
