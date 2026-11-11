#!/bin/sh
# SPEC.PRG (Fix 59) - the machine's spec page, for the Tools folder. (c) 2026 Mong00se
cd "$(dirname "$0")" && acme -f cbm -o "${1:-SPEC.PRG}" spec.asm && echo "SPEC.PRG: $(wc -c < "${1:-SPEC.PRG}") bytes"
