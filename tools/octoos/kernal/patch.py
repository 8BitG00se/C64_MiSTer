d=bytearray(open('std.bin','rb').read())
o=open('octo.bin','rb').read()
lab={l.split('=')[0].strip():int(l.split('=')[1].split(';')[0].strip().lstrip('$'),16) for l in open('octo.lbl') if '=' in l}
def K(a): return 8192 + a - 0xE000
def B(a): return a - 0xA000
assert d[K(0xE39A):K(0xE39A)+3]==bytes([0x20,0x22,0xE4])
d[K(0xE39A):K(0xE39A)+3]=bytes([0x20,lab['newboot']&255,lab['newboot']>>8])
for addr,orig,new in ((0xA020,0xA871,'w_run'),(0xA032,0xE168,'w_load'),(0xA048,0xE12A,'w_sys')):
    v=d[B(addr)]|d[B(addr)+1]<<8; assert v==orig-1,(hex(addr),hex(v))
    t=lab[new]-1; d[B(addr)]=t&255; d[B(addr)+1]=t>>8
assert d[K(0xE5EE):K(0xE5EE)+5]==bytes([0xA2,0x09,0x78,0x86,0xC6])
d[K(0xE5EE):K(0xE5EE)+5]=bytes([0xA2,0x08,0x20,lab['shiftrun']&255,lab['shiftrun']>>8])
assert d[K(0xECE7):K(0xECE7)+9]==b'LOAD\rRUN\r'
d[K(0xECE7):K(0xECE7)+9]=bytes([0x4C,0xCF,0x22,0x2A,0x22,0x2C,0x38,0x0D,0x0D])
d[K(0xF92C):K(0xF92C)+len(o)]=o
# OCTOPHONIC OS: the wedge in the tape room below, and device 1 (tape) turned away
w=open('wedge.bin','rb').read(); assert len(w)<=0xF92C-0xF72C
d[K(0xF72C):K(0xF72C)+len(w)]=w
for a in (0xF533,0xF659):                    # LOAD, SAVE: LSR / BCS tape / JMP illegal
    assert d[K(a):K(a)+6]==bytes([0x4A,0xB0,0x03,0x4C,0x13,0xF7]),hex(a)
    d[K(a)+1:K(a)+3]=bytes([0xEA,0xEA])
assert d[K(0xF384):K(0xF38E)]==bytes([0xC9,0x02,0xD0,0x03,0x4C,0x09,0xF4,0x20,0xD0,0xF7])   # OPEN: device 1
d[K(0xF38B):K(0xF38E)]=bytes([0x4C,0x13,0xF7])
open('octo64.bin','wb').write(d)
import os
os.makedirs('/tmp/kr11',exist_ok=True)
open('/tmp/kr11/basic-901226-01.bin','wb').write(d[:8192]); open('/tmp/kr11/kernal-901227-03.bin','wb').write(d[8192:])
print('ok')
