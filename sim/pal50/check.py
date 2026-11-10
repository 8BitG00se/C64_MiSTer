#!/usr/bin/env python3
# Fix 48: turn the raw sim lines into real time and verdicts. (c) 2026 Mong00se
#   check.py tb.txt vic_pal.txt vic_ntsc.txt tod_pal.txt tod_exact.txt tod_ntsc.txt
import sys, re
from fractions import Fraction as F

tb, vp, vn, tp, te, tn = [open(f).read() for f in sys.argv[1:7]]
fails = []
def ok(cond, msg):
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond: fails.append(msg)

def kv(line):
    return dict(re.findall(r'(\w+)=([\w.]+)', line))

def fclk(K):                        # clk_sys from the PLL's fractional M: 50 MHz x (11 + K/2^32) / 18
    return F(50_000_000) * (11 + F(int(K), 2**32)) / 18

print("== 1. The PLL mode block (what the core writes to the PLL) ==")
pll = {m.group(1): kv(m.group(0)) for m in re.finditer(r'^PLL (\w+) .*$', tb, re.M)}
for name, d in pll.items():
    print(f"   {name:16s} writes={d['writes']} K={d['K']} first write after {int(d['first_write_ticks'])/50e3:.1f} ms"
          f"  OSD close pulse {int(d['close_osd_ticks'])/50e3:.1f} ms")
    ok(int(d['writes']) == int(d['expect']), f"{name}: {d['expect']} PLL writes")
KEX, KPAL, KNT = int(pll['boot_exact']['K']), int(pll['to_original']['K']), int(pll['to_ntsc']['K'])
ok(KEX == 1382360994 and KPAL == 1503512573 and KNT == 3357876127, "K values: Exact 1382360994, PAL 1503512573, NTSC 3357876127")
ok(int(pll['to_exact_osd']['close_osd_ticks']) > 0 and int(pll['boot_exact']['close_osd_ticks']) == 0, "OSD is closed first only when it was open")
ok(int(pll['to_original_pal']['K']) == KPAL, "back to Original PAL from NTSC writes the PAL K")

print("== 2. The VIC-II frame, clk32 ticks (GHDL, the real video_vicII_656x.vhd) ==")
lp = [int(x) for x in re.findall(r'LINE (\d+)', vp)]; fp = [int(x) for x in re.findall(r'FRAME (\d+)', vp)]
ln = [int(x) for x in re.findall(r'LINE (\d+)', vn)]; fn = [int(x) for x in re.findall(r'FRAME (\d+)', vn)]
print(f"   PAL  line {lp}  frame {fp}")
print(f"   NTSC line {ln}  frame {fn}")
ok(fp and all(x == 312 * 63 * 32 for x in fp) and all(x == 63 * 32 for x in lp), "PAL frame = 312 x 63 x 32 = 628,992 clk32")
ok(fn and all(x == 263 * 65 * 32 for x in fn), "NTSC frame = 263 x 65 x 32 = 547,040 clk32 (unchanged)")
FR = fp[0]

print("== 3. Frame rate (frame length x PLL clock) ==")
res = {}
for nm, K in (("Original PAL", KPAL), ("Exact 50 Hz", KEX)):
    f = fclk(K); hz = f / FR; res[nm] = (f, hz)
    print(f"   {nm:13s} clk_sys {float(f):,.3f} Hz  C64 {float(f/32):,.3f} Hz  frame {float(hz):.9f} Hz"
          f"  period {float(1/hz)*1e3:.9f} ms  line {float(f/32/63):,.2f} Hz")
fex = res["Exact 50 Hz"][0]; fpal = res["Original PAL"][0]
err_ppm = float((res["Exact 50 Hz"][1] - 50) / 50 * 10**6)
ok(abs(err_ppm) < 0.001, f"Exact 50 Hz: {float(res['Exact 50 Hz'][1]):.9f} Hz, {err_ppm:+.2e} ppm from 50.000")
ok(abs(float(res["Original PAL"][1]) - 50.1246) < 0.0001, f"Original PAL still {float(res['Original PAL'][1]):.6f} Hz")
ratio = float(fex / fpal)
import math
print(f"   speed ratio {ratio:.7f} ({(1-ratio)*100:.4f}% slower), SID/OPL pitch {12*math.log2(ratio):+.4f} semitones")
ok(15000 < float(fex/32/63) < 16000 and abs(float(fex/32/63) - 15625) / 15625 < 0.01, f"CRT line rate {float(fex/32/63):.1f} Hz (PAL TV 15,625 Hz; within 1%)")
nhdmi = 50 * 20  # frames in 20 s
print(f"   capture at 50.000 fps: Original slips a frame every {float(1/(res['Original PAL'][1]-50)):.2f} s; Exact: never (core clock and HDMI share the board's 50 MHz crystal)")

print("== 4. CIA TOD (GHDL, cia_tod_clk.vhd) ==")
for nm, txt, f in (("Original PAL", tp, fpal), ("Exact 50 Hz", te, fex), ("NTSC", tn, fclk(KNT))):
    n, c = map(int, re.search(r'TOD (\d+) ticks in (\d+) clk32', txt).groups())
    hz = f * n / c
    print(f"   {nm:13s} {n} TOD ticks in {c:,} clk32 = {float(hz):.6f} Hz real time, {c/n/32:.2f} C64 cycles a tick")
    want = 60 if nm == "NTSC" else 50
    ok(abs(float(hz) - want) < 0.001, f"TOD {nm}: {float(hz):.6f} Hz (real-time {want} Hz, like the mains)")

print("== 5. 1541 and RTC enables (2.000 s of Exact clk_sys) ==")
e = kv(re.search(r'^ENABLES .*$', tb, re.M).group(0)); T = int(e['ticks'])
ok(int(e['drive_pattern_mismatch']) == 0, f"1541 enable pattern identical tick for tick in Original and Exact ({T:,} ticks compared)")
dpc = int(e['drive_exact']) / (T / 32)
print(f"   drive 16 MHz enables per C64 cycle: {dpc:.6f} (Original) = {int(e['drive_orig'])/(T/32):.6f} (Exact)  -> 1541 runs {dpc/16:.6f} cycles per C64 cycle")
print(f"   real time: drive {float(int(e['drive_orig'])*fpal/T)/16e6:.7f} MHz (Original) / {float(int(e['drive_exact'])*fex/T)/16e6:.7f} MHz (Exact)")
for nm, cnt, f in (("Original", e['rtc_orig'], fpal), ("Exact", e['rtc_exact'], fex)):
    r = float(int(cnt) * f / T)
    ok(abs(r - 16e6) / 16e6 < 2e-6, f"RTC {nm}: {r/1e6:.6f} MHz real time (16 MHz wanted)")

print("== 6. Fast-loader style timed handshake (2-bit, 4 pairs, 7-cycle poll loop) ==")
for m in re.finditer(r'^LOADER (\w+) (.*)$', tb, re.M):
    nm, d = m.group(1), kv(m.group(2)); f = fex if nm != 'original' else fpal
    b, a = int(d['min_before']), int(d['min_after'])
    print(f"   {nm:24s} {d['transfers']} transfers, bad {d['bad']}: worst margin before {b/32:.3f} / after {a/32:.3f} C64 cycles"
          f" ({float(b/f)*1e6:.3f} / {float(a/f)*1e6:.3f} us)")
    ok(int(d['bad']) == 0, f"loader {nm}: every pair read inside its window")
lo = {m.group(1): kv(m.group(2)) for m in re.finditer(r'^LOADER (\w+) (.*)$', tb, re.M)}
ok(lo['original']['min_before'] == lo['exact']['min_before'] and lo['original']['min_after'] == lo['exact']['min_after'],
   "loader margins in C64 cycles identical in Original and Exact")

print("== 7. Tape (C1530, TAP v1) ==")
tl = re.search(r'^TAPE .*$', tb, re.M).group(0); print("   " + tl)
ok('match=yes' in tl and 'err=0' in tl, "every pulse = TAP byte x 8 C64 cycles exactly")
for b in ('0x30', '0x42', '0x56'):
    mm = re.search(b.upper().replace('0X', '0x') + r'=(\d+)', tl)
    if mm:
        tk = int(mm.group(1))
        print(f"   pulse {b}: {tk//32} C64 cycles = {float(tk/fpal)*1e6:.2f} us Original, {float(tk/fex)*1e6:.2f} us Exact (+{(float(fpal/fex)-1)*100:.3f}%)")

print()
print("RESULT:", "PASS" if not fails else f"FAIL ({len(fails)})")
sys.exit(1 if fails else 0)
