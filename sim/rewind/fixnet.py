#!/usr/bin/env python3
# REWIND simulation: GHDL's Verilog names a signal and an instance's output the same when the VHDL has
# both (T65: the signal ALU_Q and the port Q of the instance alu) - the second declaration and the
# "assign x = x;" between them are taken out.   fixnet.py file.v              (c) 2026 Mong00se
import re, sys
p = sys.argv[1]
out, seen, n = [], set(), 0
for line in open(p):
    if line.startswith("module "): seen = set()
    m = re.match(r"\s*(?:wire|reg)\s*(?:\[[^\]]+\]\s*)?(\w+)\s*;", line)
    if m:
        if m.group(1) in seen: n += 1; continue
        seen.add(m.group(1))
    m = re.match(r"\s*assign\s+(\w+)\s*=\s*(\w+)\s*;", line)
    if m and m.group(1) == m.group(2): n += 1; continue
    out.append(line)
open(p, "w").write("".join(out))
print("fixnet: %d lines taken out" % n)
