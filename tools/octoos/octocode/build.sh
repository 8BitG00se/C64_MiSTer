#!/bin/sh
# OCTOCODE and its test disk: OCTOCODE.PRG first (LOAD"*",8 then RUN), HELLO.ASM as a PETSCII SEQ file
# Original project by Mong00se - Octophonic 64 and OctoVIC by Mong00se (github.com/8BitG00se). GPL v3 or later.
set -e
cd "$(dirname "$0")"
acme -f cbm -o octocode.prg octocode.asm
python3 a2p.py hello.asm hello.seq
python3 a2p.py stock.asm stock.seq
D="Compile Test build 2.d64"
rm -f "$D"
c1541 -format "compile test 2,ct" d64 "$D" -write octocode.prg octocode -write hello.seq "hello.asm,s" -write stock.seq "stock.asm,s" > /dev/null
rm -f hello.seq stock.seq
ls -la octocode.prg "$D"
