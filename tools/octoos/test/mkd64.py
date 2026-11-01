# a small, valid 35-track D64 with one BASIC program HELLO (10 PRINT "HI") - for the ROM tests
import sys
spt=[21]*17+[19]*7+[18]*6+[17]*5
off=[0]
for n in spt: off.append(off[-1]+n)
img=bytearray(off[-1]*256)
def sec(t,s): o=(off[t-1]+s)*256; return o
# the program: load $0801, line 10 PRINT "HI"
prog=bytes([0x01,0x08, 0x0C,0x08, 0x0A,0x00, 0x99,0x20,0x22,0x48,0x49,0x22,0x00, 0x00,0x00])
# file on track 17 sector 0
o=sec(17,0); img[o]=0; img[o+1]=len(prog)+1; img[o+2:o+2+len(prog)]=prog
# BAM 18/0
b=sec(18,0); img[b:b+4]=bytes([18,1,0x41,0])
for t in range(1,36):
    n=spt[t-1]; free=list(range(n))
    if t==18: free=[s for s in free if s not in (0,1)]
    if t==17: free=[s for s in free if s!=0]
    bits=0
    for s in free: bits|=1<<s
    e=b+4*t; img[e]=len(free); img[e+1]=bits&255; img[e+2]=(bits>>8)&255; img[e+3]=(bits>>16)&255
name=b'OCTO TEST'.ljust(16,b'\xa0'); img[b+0x90:b+0xA0]=name
img[b+0xA0:b+0xA2]=b'\xa0\xa0'; img[b+0xA2:b+0xA4]=b'OS'; img[b+0xA4]=0xA0; img[b+0xA5:b+0xA7]=b'2A'; img[b+0xA7:b+0xAB]=b'\xa0'*4
# directory 18/1
d=sec(18,1); img[d]=0; img[d+1]=0xFF
img[d+2]=0x82; img[d+3]=17; img[d+4]=0; img[d+5:d+21]=b'HELLO'.ljust(16,b'\xa0'); img[d+30]=1; img[d+31]=0
open(sys.argv[1],'wb').write(img)
