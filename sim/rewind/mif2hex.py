#!/usr/bin/env python3
# REWIND simulation: a Quartus .mif (hex address : hex data) or a raw binary as $readmemh lines.
#   mif2hex.py in.mif|in.bin out.hex [size] [load address of a binary]     (c) 2026 Mong00se
import re, sys
src, dst = sys.argv[1], sys.argv[2]
size = int(sys.argv[3], 0) if len(sys.argv) > 3 else None
at = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0
if src.endswith(".mif"):
    mem = {}
    body = open(src, errors="replace").read()
    body = body[body.index("CONTENT"):]
    for m in re.finditer(r"(?:\[([0-9A-Fa-f]+)\.\.([0-9A-Fa-f]+)\]|([0-9A-Fa-f]+))\s*:\s*([0-9A-Fa-f ]+);", body):
        vals = [int(v, 16) for v in m.group(4).split()]
        if m.group(1):
            for a in range(int(m.group(1), 16), int(m.group(2), 16) + 1): mem[a] = vals[0]
        else:
            a = int(m.group(3), 16)
            for i, v in enumerate(vals): mem[a + i] = v
    n = size or (max(mem) + 1)
    data = [mem.get(a, 0) for a in range(n)]
else:
    b = open(src, "rb").read()
    n = size or len(b)
    data = [0] * n
    data[at:at + len(b)] = b
    data = data[:n]
open(dst, "w").write("\n".join("%02x" % v for v in data) + "\n")
