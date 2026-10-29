// OctoVIC on its own, cycle by cycle: the VIC's timing (8 pixel strobes a microsecond, 504
// pixels a line, 312 lines), a pattern for the VIC's own picture, the 6510's register writes
// out of a script (one a microsecond), and a DDR3 that is busy at random and answers late.
// Writes every frame's picture (504 x 312, rgb) for the reference to check.
//   tb vram.bin script.txt frames out.rgb [seed busy% latmin latmax]
#include "Voctovic.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <deque>
#include <random>
#include <fstream>
#include <sstream>
#include <string>

static const uint32_t VBASE = 0x06400000;
static const uint8_t PAL[16][3] = {   // the "core's palette" for the VIC (deliberately not OctoVIC's)
 {0,0,0},{255,255,255},{129,51,56},{117,206,200},{142,60,151},{86,172,77},{46,44,155},{237,241,113},
 {142,80,41},{85,56,0},{196,108,113},{74,74,74},{123,123,123},{169,255,159},{112,109,235},{178,178,178}};

static int vic_colour (int R, int y)
{
    if (R < 32 || R >= 352 || y < 51 || y >= 251) return 14;                 // the border
    int cx = (R - 32) / 8, cy = (y - 51) / 8;
    if ((cx * 3 + cy * 5) % 11 == 0 && ((R + y) & 2)) return 1;               // some "text"
    if (cx == 5 && cy == 3) return 2;
    return 6;                                                                 // the background
}

int main (int argc, char** argv)
{
    if (argc < 5) { std::printf ("tb vram.bin script.txt frames out.rgb [seed busy%% latmin latmax]\n"); return 2; }
    std::vector<uint8_t> vram (16 << 20, 0);
    { std::ifstream f (argv[1], std::ios::binary); f.read ((char*) vram.data(), vram.size()); }
    struct Op { int kind; int a, b; };            // 0 write a=b; 1 wait for frame a line b
    std::vector<Op> ops;
    { std::ifstream f (argv[2]); std::string w; while (f >> w) { Op o; if (w == "w") { o.kind = 0; f >> std::hex >> o.a >> o.b >> std::dec; } else { o.kind = 1; f >> o.a >> o.b; } ops.push_back (o); } }
    const int frames = std::atoi (argv[3]);
    std::ofstream out (argv[4], std::ios::binary);
    const unsigned seed = argc > 5 ? std::atoi (argv[5]) : 1;
    const int busyp = argc > 6 ? std::atoi (argv[6]) : 20, latmin = argc > 7 ? std::atoi (argv[7]) : 6, latmax = argc > 8 ? std::atoi (argv[8]) : 30;
    std::mt19937 rng (seed);

    Verilated::commandArgs (argc, argv);
    auto* t = new Voctovic;
    t->clk = 0; t->reset = 1; t->cs = 0; t->wr = 0; t->rd = 0; t->pix_en = 0; t->ddr_busy = 0; t->ddr_dout_ready = 0;
    int phase = 0, R = 404, y = 300, frame = -1, vi = 14;
    struct Pend { uint64_t due; uint32_t word; };
    std::deque<Pend> reads;
    uint64_t now = 0, last_due = 0;
    size_t op = 0;
    std::vector<uint8_t> pic (504 * 312 * 3, 0);
    int capR[4] = {-1,-1,-1,-1}, capY[4] = {0,0,0,0};   // pixels waiting for their colour (2 clocks on)
    long maxlate = 0;
    for (int i = 0; i < 64; ++i) { t->clk ^= 1; t->eval(); }
    t->reset = 0;
    while (frame < frames)
    {
        // --- the inputs for this clock
        const bool pe = (phase & 3) == 2;
        t->pix_en = pe;
        t->vic_x = R; t->vic_y = y; t->vic_index = vi;
        t->vic_rgb = (PAL[vi][0] << 16) | (PAL[vi][1] << 8) | PAL[vi][2];
        t->wr = 0; t->cs = 0;
        if (phase == 28 && op < ops.size() && frame >= 0)
        {
            if (ops[op].kind == 0) { t->cs = 1; t->wr = 1; t->addr = ops[op].a; t->din = ops[op].b; ++op; }
            else if (frame > ops[op].a || (frame == ops[op].a && y >= ops[op].b)) ++op;
        }
        const bool busy = (int) (rng() % 100) < busyp;
        t->ddr_busy = busy;
        t->ddr_dout_ready = 0;
        if (! reads.empty() && reads.front().due <= now)
        {
            const uint32_t w = reads.front().word; reads.pop_front();
            uint64_t d = 0; const size_t a = (size_t) (w - VBASE) * 8;
            for (int k = 0; k < 8; ++k) d |= (uint64_t) vram[(a + k) & (vram.size() - 1)] << (8 * k);
            t->ddr_dout = d; t->ddr_dout_ready = 1;
        }
        const bool rd = t->ddr_rd, we = t->ddr_we; const uint32_t ad = t->ddr_addr; const uint64_t din = t->ddr_din; const int be = t->ddr_be;
        // --- the clock edge
        t->clk = 1; t->eval();
        if (rd && ! busy) { uint64_t due = now + latmin + rng() % (latmax - latmin + 1); if (due <= last_due) due = last_due + 1; last_due = due; reads.push_back ({due, ad}); }
        if (we && ! busy) { const size_t a = (size_t) (ad - VBASE) * 8; for (int k = 0; k < 8; ++k) if (be & (1 << k)) vram[(a + k) & (vram.size() - 1)] = (din >> (8 * k)) & 255; }
        // the picture: a pixel's colour is out two clocks after its strobe
        if (capR[2] >= 0 && frame >= 0) { const uint32_t c = t->rgb; uint8_t* p = &pic[((size_t) capY[2] * 504 + capR[2]) * 3]; p[0] = c >> 16; p[1] = c >> 8; p[2] = c; }
        capR[2] = capR[1]; capY[2] = capY[1]; capR[1] = -1;
        if (pe) { capR[1] = R; capY[1] = y; }
        // the VIC's pixel and counters move on at the strobe
        if (pe)
        {
            vi = vic_colour (R, y);
            R = (R + 1) % 504;
            if (R == 408) { y = (y + 1) % 312; if (y == 0) { if (frame >= 0) out.write ((const char*) pic.data(), pic.size()); ++frame; } }
        }
        t->clk = 0; t->eval();
        phase = (phase + 1) & 31; ++now;
    }
    std::printf ("ok: %d frames, %llu clocks, script %zu/%zu\n", frames, (unsigned long long) now, op, ops.size());
    delete t;
    return 0;
}
