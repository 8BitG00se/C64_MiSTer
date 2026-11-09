#!/bin/bash
# Proves the screen and the converter agree: cuts oled_anishift and oled_aniframe out of the firmware
# (8BitG00se/octophonic-tty2oled), compiles them on the PC with stand-ins for the screen and the serial port, plays a
# .oled through them and compares every frame with make_anim.py's own decoding.
#   fwcheck/check.sh FIRMWARE.ino FILE.oled
set -euo pipefail
INO=$1; OLED=$2; HERE=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
awk '/^void oled_anishift\(int y0.*\{/,/^}/' "$INO" > "$T/shift.inc"
awk '/^bool oled_aniframe\(int f\) *\{/,/^}/' "$INO" > "$T/frame.inc"
[ -s "$T/shift.inc" ] && [ -s "$T/frame.inc" ] || { echo "could not find the decoder in $INO"; exit 1; }
cat > "$T/h.cpp" <<'CPP'
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
static uint8_t logoBin[8192]; static FILE *out;
struct { void clearDisplay(){} void display(){} void draw4bppBitmap(const uint8_t *b){ fwrite(b,1,8192,out); } } oled;
struct { int available(){ return 0; } } Serial;
static unsigned long now=0; unsigned long millis(){ return now+=5; } void delay(int){}
#define OANI_MAXFRAMES 1024
static uint8_t *aniData; static uint32_t aniOff[OANI_MAXFRAMES]; static uint16_t aniMs=0;
#include "shift.inc"
#include "frame.inc"
int main(int c, char **v){
  FILE *f=fopen(v[1],"rb"); static uint8_t file[1<<20]; size_t n=fread(file,1,sizeof file,f); fclose(f);
  int ms=file[8], mode=file[9], frames=file[10]|(file[11]<<8); uint32_t len; memcpy(&len,file+12,4);
  aniData=file+16; out=fopen(v[2],"wb");
  uint32_t i=0; int fr=0;
  while (i+2<=len && fr<OANI_MAXFRAMES) { aniOff[fr]=i; uint16_t fl=aniData[i]|(aniData[i+1]<<8); i+=2+(fl&0x7FFF); fr++; }
  if (fr!=frames || i!=len) { printf("frames %d/%d bytes %u/%u\n",fr,frames,i,len); return 1; }
  memset(logoBin,0,8192);
  for (int k=0;k<frames;k++) oled_aniframe(k);
  if (mode==1) for (int k=frames-1;k>=1;k--) oled_aniframe(k);
  fclose(out); printf("%d frames played by the firmware's code\n", frames); return 0; }
CPP
g++ -O1 -o "$T/h" "$T/h.cpp"
"$T/h" "$OLED" "$T/fw.bin"
python3 - "$OLED" "$T/fw.bin" "$HERE/.." <<'PY'
import sys, struct; sys.path.insert(0, sys.argv[3]); import make_anim as m
b = open(sys.argv[1], 'rb').read(); ms, mode, n, ln = struct.unpack_from('<BBHI', b, 8)
py = m.decode(b[16:16 + ln], n, mode); fw = open(sys.argv[2], 'rb').read()
fws = [fw[i:i + 8192] for i in range(0, len(fw), 8192)]
bad = [k for k in range(len(py)) if k >= len(fws) or fws[k] != py[k]]
print('firmware and converter agree on all %d frames shown' % len(py) if not bad and len(fws) == len(py) else 'MISMATCH at frames %s' % bad[:10])
sys.exit(1 if bad or len(fws) != len(py) else 0)
PY
