#!/bin/sh
set -e
cd "$(dirname "$0")"
acme -f plain -o octo.bin -l octo.lbl octo.asm
acme -f plain -o wedge.bin -l wedge.lbl wedge.asm
acme -f plain -o wedge2.bin -l wedge2.lbl wedge2.asm
python3 patch.py
acme -f cbm -o shell.prg shell.asm
ls -la octo64.bin shell.prg
