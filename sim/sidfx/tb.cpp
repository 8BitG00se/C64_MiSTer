// sid_fx check: SID 1 writes in, the injected writes out, with their times
#include "Vsid_fx.h"
#include <cstdio>
#include <vector>
#include <cstdlib>
int main(int argc, char** argv) {
    Vsid_fx t; t.mode = 3; t.reset = 1;
    long clk = 0; int us = 0;
    auto tick = [&]() { t.clk = 0; t.eval(); t.clk = 1; t.eval(); clk++;
        t.ce_1m = (clk % 32) == 0; if (t.ce_1m) us++;
        if (t.inj_we) printf("%d us  -> SID%d reg %02x = %02x\n", us, t.inj_tgt + 1, t.inj_addr, t.inj_data); };
    for (int i = 0; i < 64; i++) tick();
    t.reset = 0;
    auto wr = [&](int a, int d) {  // a 6510 write: one clock of cpu_wr+sid1_wr, then the rest of the microsecond
        t.cpu_wr = 1; t.sid1_wr = 1; t.addr = a; t.data = d; t.busy1 = 1; tick();
        t.cpu_wr = 0; t.sid1_wr = 0; t.busy1 = 0; for (int i = 0; i < 31; i++) tick(); };
    printf("-- volume, a note on voice 1 (pitch $1CD6), gate on\n");
    wr(0x18, 0x0F); wr(0x00, 0xD6); wr(0x01, 0x1C); wr(0x05, 0x09); wr(0x06, 0x00); wr(0x04, 0x21);
    for (int i = 0; i < 32 * 1000 * 150; i++) tick();   // 150 ms: the left echo
    printf("-- 150 ms: gate off\n");
    wr(0x04, 0x20);
    for (int i = 0; i < 32 * 1000 * 260; i++) tick();
    printf("-- a digi: 3000 volume writes at 8 kHz (the ring overflows - none may hang)\n");
    int n = 0;
    for (int k = 0; k < 3000; k++) { wr(0x18, k & 15); for (int i = 0; i < 31 * 4; i++) tick(); }
    for (int i = 0; i < 32 * 1000 * 400; i++) tick();
    return 0;
}
