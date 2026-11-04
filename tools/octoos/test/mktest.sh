#!/bin/sh
# the suite's folders, in DIR (default: here): folder/ (the SD card: hello.prg, zdisk.d64, sub/ with two
# demos, a 16 MB .reu, a folder INNER and a folder named with letters the C64 can't show), netshare/ (a
# network share) and test.d64 (the 1541's disk)
#   mktest.sh [DIR]
set -e
H="$(cd "$(dirname "$0")" && pwd)"
D="${1:-$H}"
mkdir -p "$D/folder/sub/inner" "$D/netshare/Octophonic"
cd "$D"
python3 "$H/mkdemos.py" folder
python3 "$H/mkd64.py" test.d64
cp test.d64 folder/zdisk.d64
python3 -c "open('folder/hello.prg','wb').write(bytes([1,8,12,8,10,0,0x99,0x20,0x22,0x48,0x49,0x22,0,0,0]))"   # 10 PRINT "HI"
[ -e folder/sub/big.reu ] || head -c 16777216 /dev/zero > folder/sub/big.reu
mkdir -p "folder/sub/éé"
cp folder/hello.prg netshare/net.prg
mkdir -p "netshare/Octophonic Horizon build 10" "netshare/Octophonic Showcase Lanterns Edition build 12"
