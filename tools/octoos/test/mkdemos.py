# two tiny "demos" for the suite: each reads byte 0 of the REU (a REU DMA, as the demos do) and
# prints it - so demo B run after demo A shows whose REU is in
import os, sys
top = sys.argv[1]
def prg(letter):
    T = {'POKE': 0x97, 'PRINT': 0x99, 'CHR$': 0xC7, 'PEEK': 0xC2}
    parts = [('POKE', '57090,0'), ('POKE', '57091,192'), ('POKE', '57092,0'), ('POKE', '57093,0'), ('POKE', '57094,0'),
             ('POKE', '57095,1'), ('POKE', '57096,0'), ('POKE', '57089,145')]
    body = b''
    for i, (t, a) in enumerate(parts):
        if i: body += b':'
        body += bytes([T[t]]) + a.encode()
    body += b':' + bytes([T['PRINT']]) + b'"DEMO ' + letter.encode() + b' REU ";' + bytes([T['CHR$']]) + b'(' + bytes([T['PEEK']]) + b'(49152))'
    line = (10).to_bytes(2, 'little') + body + b'\x00'
    nxt = 0x0801 + 2 + len(line)
    return b'\x01\x08' + nxt.to_bytes(2, 'little') + line + b'\x00\x00'
for L in 'AB':
    d = os.path.join(top, 'sub', 'demo' + L.lower()); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, 'demo' + L.lower() + '.prg'), 'wb').write(prg(L))
    open(os.path.join(d, 'demo' + L.lower() + '.reu'), 'wb').write(bytes([ord(L)]) + bytes(255))
print('ok')
