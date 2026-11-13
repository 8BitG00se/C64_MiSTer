#!/bin/sh
# TESTCARD.PRG - the monitor test card, for the Tools folder. (c) 2026 Mong00se
cd "$(dirname "$0")" && python3 make_card.py card.bin && acme -f cbm -o "${1:-TESTCARD.PRG}" testcard.asm && echo "TESTCARD.PRG: $(wc -c < "${1:-TESTCARD.PRG}") bytes"
