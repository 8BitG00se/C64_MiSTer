#!/bin/sh
# the suite's folders: folder/ (the SD card: hello.prg, zdisk.d64, sub/ with two demos, a 16 MB .reu
# and a folder named with letters the C64 can't show) and netshare/ (a network share)
set -e
cd "$(dirname "$0")"
mkdir -p folder/sub netshare/Octophonic
python3 mkdemos.py folder
[ -e folder/sub/big.reu ] || head -c 16777216 /dev/zero > folder/sub/big.reu
mkdir -p "folder/sub/éé"
cp folder/hello.prg netshare/net.prg 2>/dev/null || true
