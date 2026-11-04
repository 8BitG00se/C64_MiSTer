#!/usr/bin/env python3
# ASCII source -> PETSCII (the OCTOCODE editor's upper/lower case set), as Octophonic Main converts it
import sys
def a2p(c):
    o=ord(c)
    if 'a'<=c<='z': return o-0x20
    if 'A'<=c<='Z': return o+0x80
    if 0x20<=o<=0x40: return o
    return {'[':0x5B,']':0x5D,'\\':0x5C,'^':0x5E,'_':0x5F,'{':0xDB,'}':0xDD,'|':0xDC,'~':0xDE,'`':0x27,'\t':0x20}.get(c,0x3F)
src=open(sys.argv[1]).read().replace('\r\n','\n')
out=bytearray()
for line in src.split('\n')[:-1] if src.endswith('\n') else src.split('\n'):
    out+=bytes(a2p(c) for c in line)+b'\r'
open(sys.argv[2],'wb').write(out)
