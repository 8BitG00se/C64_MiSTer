// OCTOVIC REGISTER MAP TEST: writes and reads back every register the 6502 can read, checks the ID,
// the version, the core's name and build date and the meters, so a merge can never silently lose one.
//   sim/regmap/run.sh   (Verilator; exits 1 and lists what failed)
#include "Voctovic.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
static Voctovic *t; static int fails = 0;
static void tick () { t->clk = 0; t->eval (); t->clk = 1; t->eval (); }
static void wr (int a, int v) { t->cs = 1; t->addr = a; t->din = v; t->wr = 1; tick (); t->wr = 0; t->cs = 0; tick (); tick (); }
static int rd (int a) { t->cs = 1; t->addr = a; t->eval (); int v = t->dout; t->rd = 1; tick (); t->rd = 0; t->cs = 0; tick (); return v; }
static void want (const char *what, int a, int got, int exp) {
    if (got != exp) { printf ("FAIL %-28s $D6%02X read $%02X, want $%02X\n", what, a, got, exp); fails++; }
}
static void rw (const char *what, int a, int mask, int v1 = 0xA5, int v2 = 0x5A) {
    for (int v : { v1, v2 }) { wr (a, v); want (what, a, rd (a) & mask, v & mask); }
}
int main (int argc, char **argv) {
    Verilated::commandArgs (argc, argv); t = new Voctovic;
    t->reset = 1; for (int i = 0; i < 20; i++) tick (); t->reset = 0; for (int i = 0; i < 20; i++) tick ();
    want ("ID", 0x1E, rd (0x1E), 0x8C);
    int ver = rd (0x1F); if (ver < 3) { printf ("FAIL VERSION $D61F = %d, want 3 or more (the memory core)\n", ver); fails++; }
    char tag[9] = {}; for (int i = 0; i < 8; i++) { tag[i] = rd (0xB8 + i); if (tag[i] < 32 || tag[i] > 126) { printf ("FAIL TAG $D6%02X = $%02X, not a letter\n", 0xB8 + i, tag[i] & 255); fails++; } }
    int dd = rd (0xB4), mm = rd (0xB5), yy = rd (0xB6);
    auto bcd = [] (int v, int lo, int hi) { int d = (v >> 4) * 10 + (v & 15); return (v & 15) < 10 && (v >> 4) < 10 && d >= lo && d <= hi; };
    if (!bcd (dd, 1, 31) || !bcd (mm, 1, 12) || !bcd (yy, 26, 99)) { printf ("FAIL DATE $D6B4-6 = %02X %02X %02X, not a BCD date\n", dd, mm, yy); fails++; }
    printf ("core: OctoVIC version %d, \"%s\", built %02X.%02X.20%02X\n", ver, tag, dd, mm, yy);
    // the meters: 0 after a reset (a core without them reads $FF)
    for (int a = 0xA0; a <= 0xB2; a++) { int v = rd (a); if (v == 0xFF && a != 0xA4) { printf ("FAIL METER $D6%02X reads $FF (missing?)\n", a); fails++; } }
    // LOST ($D6B2): the VDATA write queue holds 63 bytes while the DDR3 port is held; the 64th on are lost and counted
    want ("LOST after reset", 0xB2, rd (0xB2), 0);
    t->ddr_busy = 1; wr (0x00, 0); wr (0x01, 0); wr (0x02, 0x40); wr (0x03, 1);
    for (int i = 0; i < 70; i++) wr (0x04, i);
    want ("LOST, port held, 70 writes", 0xB2, rd (0xB2), 7);
    if (!(rd (0x08) & 1)) { printf ("FAIL STATUS b0 (writes queued) clear with 63 queued\n"); fails++; }
    t->ddr_busy = 0; for (int i = 0; i < 200; i++) tick ();
    if (rd (0x08) & 1) { printf ("FAIL STATUS b0 still set after the port was freed\n"); fails++; }
    wr (0xB2, 0); want ("LOST cleared by a write", 0xB2, rd (0xB2), 0);
    // registers that read back what was written
    rw ("VADDR lo", 0x00, 0xFF); rw ("VADDR mid", 0x01, 0xFF); rw ("VADDR hi", 0x02, 0xFF); rw ("VINC", 0x03, 0xFF);
    rw ("KEY", 0x06, 0x0F); rw ("XADJ", 0x0C, 0xFF); rw ("YADJ", 0x0D, 0xFF);
    rw ("SPRCOUNT", 0x0F, 0xFF, 0x25, 0x40); wr (0x0F, 0);
    rw ("PALSEL", 0x19, 0x03, 0x01, 0x02); wr (0x19, 0); rw ("PALIDX", 0x1A, 0xFF, 0x11, 0x22);
    for (int L = 0; L < 2; L++) {
        int b = 0x20 + 16 * L;
        rw (L ? "L1 MODE" : "L0 MODE", b + 0x0F, 0xFF, 0x01, 0x02);
        rw (L ? "L1 SCROLLX lo" : "L0 SCROLLX lo", b + 0x08, 0xFF); rw (L ? "L1 SCROLLX hi" : "L0 SCROLLX hi", b + 0x09, 0xFF);
        rw (L ? "L1 SCROLLY lo" : "L0 SCROLLY lo", b + 0x0A, 0xFF); rw (L ? "L1 SCROLLY hi" : "L0 SCROLLY hi", b + 0x0B, 0xFF);
        rw (L ? "L1 CTRL" : "L0 CTRL", b, 0xFF, 0x00, 0x00);
    }
    for (int a = 0x50; a <= 0x53; a++) rw ("MUL operand", a, 0xFF);
    wr (0x58, 0); wr (0x50, 0x34); wr (0x51, 0x12); wr (0x52, 0x10); wr (0x53, 0x00);
    for (int i = 0; i < 10; i++) tick ();
    uint32_t r = rd (0x54) | rd (0x55) << 8 | rd (0x56) << 16 | (uint32_t) rd (0x57) << 24;
    if (r != 0x1234u * 0x10u) { printf ("FAIL MUL $1234 x $10 = $%X\n", r); fails++; }
    rw ("IRQLINE lo", 0x80, 0xFF); rw ("IRQLINE hi", 0x81, 0x01, 0x01, 0x00);
    rw ("IRQEN", 0x82, 0x0F, 0x00, 0x00); rw ("COLLIDX", 0x84, 0x0F, 0x03, 0x05);
    rw ("COPPER on", 0x0E, 0x01, 0x00, 0x00);
    // FINE SCROLL (Fix 42): L0FINE $27, L1FINE $37, SPRFINE $07 (b1-0, the rest read 0); STATUS b4 = the 4x clock on, b5 = 0
    for (int a : { 0x07, 0x27, 0x37 }) { want ("FINE after reset", a, rd (a), 0); wr (a, 0x03); want ("FINE", a, rd (a), 0x03); wr (a, 0xFE); want ("FINE (b7-2 read 0)", a, rd (a), 0x02); wr (a, 0); }
    t->quarter = 1; if ((rd (0x08) & 0x30) != 0x10) { printf ("FAIL STATUS b4/b5 with quarter pixels on: $%02X\n", rd (0x08)); fails++; }
    t->quarter = 0; if ((rd (0x08) & 0x30) != 0x00) { printf ("FAIL STATUS b4/b5 with quarter pixels off: $%02X\n", rd (0x08)); fails++; }
    if (ver < 4) { printf ("FAIL VERSION $D61F = %d, want 4 or more (FINE SCROLL)\n", ver); fails++; }
    printf (fails ? "REGMAP: %d FAILED\n" : "REGMAP: all registers right\n", fails);
    delete t; return fails ? 1 : 0;
}
