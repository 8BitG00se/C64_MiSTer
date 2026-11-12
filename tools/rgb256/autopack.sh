#!/bin/sh
# Builds tools/rgb256/autopack (the MiSTer's automatic pack maker, for a PC) from Main's patch.
#   tools/rgb256/autopack.sh [OUTDIR]      then: OUTDIR/autopack GAME OUT.rgb [grade 0-4] [strength 0-3]
set -e
cd "$(dirname "$0")/../.."
O=${1:-/tmp/autopack}; mkdir -p "$O"
sed -n '/OCTO-PACK-BEGIN/,/OCTO-PACK-END/p' tools/octoos/main/octophonic-rgb256.patch | sed 's/^+//' > "$O/autopack_block.inc"
g++ -O2 -std=gnu++14 -I"$O" -include stdlib.h tools/rgb256/autopack.cpp -o "$O/autopack" -lm
echo "$O/autopack"
