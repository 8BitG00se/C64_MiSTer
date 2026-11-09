#!/usr/bin/env python3
"""Level test programs for the Octophonic 64 (Fix 28): each a .prg in its own folder.
   chord : the three voices a sawtooth chord (C E G), held, full volume
   tune  : a loud tune pattern - pulse bass, saw lead, pulse arpeggio, notes re-gated every 6 frames
 SIDs at the Octophonic addresses: 1 $D400, 2 $D420, 3 $D500, 4 $D520, 5 $D480, 6 $D4A0, 7 $D580, 8 $D5A0."""
import os, sys, subprocess
BASE = [0xD400, 0xD420, 0xD500, 0xD520, 0xD480, 0xD4A0, 0xD580, 0xD5A0]
F = lambda hz: int(round(hz * 16777216 / 985248))
N = lambda m: 440.0 * 2 ** ((m - 69) / 12)

def prog(kind, vols):
    a = ["* = $0801", "!byte $0b,$08,$0a,$00,$9e", '!text "2061"', "!byte 0,0,0", "start sei"]
    # clear and set every SID used (volume and control written: the SID wakes)
    for s in range(len(vols)):          # wake every SID first (a volume, then a control write)
        b = BASE[s]
        a += ["lda #0", f"sta ${b+0x18:04X}", f"sta ${b+4:04X}"]
    for s, v in enumerate(vols):
        b = BASE[s]
        a += ["ldx #$18", "lda #0", f"- sta ${b:04X},x", "dex", "bpl -"]
        for vc in range(3):
            o = b + vc * 7
            a += ["lda #$00", f"sta ${o+5:04X}", "lda #$F0", f"sta ${o+6:04X}",
                  "lda #$00", f"sta ${o+2:04X}", "lda #$08", f"sta ${o+3:04X}"]
        a += [f"lda #${v:02X}", f"sta ${b+0x18:04X}"]
    if kind == "chord":
        notes = [60, 64, 67]
        for s in range(len(vols)):
            b = BASE[s]
            for vc, m in enumerate(notes):
                o = b + vc * 7; f = F(N(m))
                a += [f"lda #${f & 255:02X}", f"sta ${o:04X}", f"lda #${f >> 8:02X}", f"sta ${o+1:04X}",
                      "lda #$21", f"sta ${o+4:04X}"]
        a += ["hold jmp hold"]
    else:
        bass = [36, 36, 48, 36, 39, 39, 51, 39, 41, 41, 53, 41, 43, 43, 55, 31]
        lead = [72, 72, 75, 77, 79, 79, 77, 75, 72, 70, 72, 75, 74, 74, 70, 67]
        arp = [60, 63, 67, 72, 63, 67, 70, 75, 65, 68, 72, 77, 67, 70, 74, 79]
        tb = lambda name, ms: [f"{name}lo !byte " + ",".join(str(F(N(m)) & 255) for m in ms),
                               f"{name}hi !byte " + ",".join(str(F(N(m)) >> 8) for m in ms)]
        a += ["ldx #0", "stx step", "loop"]
        a += ["- lda $d012", "cmp #$f8", "bne -", "- lda $d012", "cmp #$f8", "beq -"]
        a += ["inc cnt", "lda cnt", "cmp #6", "bcs newstep", "jmp gate1", "newstep", "lda #0", "sta cnt",
              "ldx step", "inx", "txa", "and #15", "sta step"]
        # gate off this frame, new notes, then gate on next frame
        for s in range(len(vols)):
            b = BASE[s]
            a += ["ldx step"]
            for vc, (t, w) in enumerate((("bs", 0x40), ("ld", 0x20), ("ar", 0x40))):
                o = b + vc * 7
                a += [f"lda {t}lo,x", f"sta ${o:04X}", f"lda {t}hi,x", f"sta ${o+1:04X}", f"lda #${w:02X}", f"sta ${o+4:04X}"]
        a += ["jmp loop", "gate1"]
        for s in range(len(vols)):
            b = BASE[s]
            for vc, w in enumerate((0x41, 0x21, 0x41)):
                o = b + vc * 7
                a += [f"lda #${w:02X}", f"sta ${o+4:04X}"]
        a += ["jmp loop", "cnt !byte 0", "step !byte 0"] + tb("bs", bass) + tb("ld", lead) + tb("ar", arp)
    LBL = ("start", "hold", "loop", "gate1", "cnt", "step", "bslo", "bshi", "ldlo", "ldhi", "arlo", "arhi", "newstep")
    return "\n".join(x if x.startswith(("*", "!", "-")) or x.split()[0] in LBL else "        " + x for x in a) + "\n"

TESTS = {
    "chord1": ("chord", [15]),
    "tune1": ("tune", [15]),
    "chord2": ("chord", [15] * 2),
    "tune2": ("tune", [15] * 2),
    "tune4": ("tune", [15] * 4),
    "chord8": ("chord", [15] * 8),
    "tune8": ("tune", [15] * 8),
    "uneven8": ("tune", [15, 15, 6, 5, 6, 5, 5, 6]),
    "uneven8b": ("tune", [12, 10, 8, 6, 6, 5, 4, 3]),
}
out = sys.argv[1]
for name, (k, v) in TESTS.items():
    d = os.path.join(out, name); os.makedirs(d, exist_ok=True)
    src = os.path.join(d, name + ".asm"); open(src, "w").write(prog(k, v))
    subprocess.run(["acme", "-f", "cbm", "-o", os.path.join(d, name + ".prg"), src], check=True)
print("ok")
