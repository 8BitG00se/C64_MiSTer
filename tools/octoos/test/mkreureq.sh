#!/bin/sh
# the REU REQUEST test folder: REU Request.prg and two .reu files (Part A, Part B), neither named as
# the program, so the browser attaches neither when it runs it - the program asks for each itself.
#   sh mkreureq.sh DIR
set -e
D=${1:?folder}; mkdir -p "$D"; H=$(cd "$(dirname "$0")" && pwd)
acme -f cbm -o "$D/REU Request.prg" "$H/reureq.asm"
python3 - "$D" <<'PY'
import sys
def scr(t):   # screen codes, upper case
    return bytes((ord(c) - 64) if 'A' <= c <= 'Z' else ord(c) for c in t.upper())
for n, t in (("Part A", "PART A IS IN THE REU - SCENE 1 MUSIC  "), ("Part B", "PART B IS IN THE REU - SCENE 2 PICTURE")):
    b = scr(t.ljust(40))[:40]
    open(sys.argv[1] + "/" + n + ".reu", "wb").write(b + bytes(65536 - len(b)))
PY
