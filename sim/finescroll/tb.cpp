// sim/finescroll: OctoVIC on its own (the VIC's timing, a DDR3 that is busy and late at random, the
// 6510's writes out of a script - as sim/octovic/tb.cpp), but the picture is taken EVERY clock: 4
// sub-pixels a C64 pixel, 2016 x 312 a frame, the way the 4x pixel clock (Fix 42) hands it to the scaler.
//   tb vram.bin script.txt frames out.rgb [seed busy% latmin latmax]      QUARTER=1: the 4x clock on
// Built with -DNOQUARTER for an OctoVIC from before Fix 42 (no quarter input).
#include "Voctovic.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <deque>
#include <random>
#include <fstream>
#include <string>

static const uint32_t VBASE = 0x06400000;
static const uint8_t PAL[16][3] = {
 {0,0,0},{255,255,255},{129,51,56},{117,206,200},{142,60,151},{86,172,77},{46,44,155},{237,241,113},
 {142,80,41},{85,56,0},{196,108,113},{74,74,74},{123,123,123},{169,255,159},{112,109,235},{178,178,178}};
static int vic_colour (int R, int y)
{
    if (R < 32 || R >= 352 || y < 51 || y >= 251) return 14;
    int cx = (R - 32) / 8, cy = (y - 51) / 8;
    if ((cx * 3 + cy * 5) % 11 == 0 && ((R + y) & 2)) return 1;
    return 6;
}

int main (int argc, char** argv)
{
    if (argc < 5) { std::printf ("tb vram.bin script.txt frames out.rgb [seed busy%% latmin latmax]\n"); return 2; }
    std::vector<uint8_t> vram (16 << 20, 0);
    { std::ifstream f (argv[1], std::ios::binary); f.read ((char*) vram.data(), vram.size()); }
    struct Op { int kind; int a, b; };
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
#ifndef NOQUARTER
    t->quarter = std::getenv ("QUARTER") && std::atoi (std::getenv ("QUARTER")) ? 1 : 0;
#endif
    int phase = 0, R = 404, y = 300, frame = -1, vi = 14;
    struct Pend { uint64_t due; uint32_t word; };
    std::deque<Pend> reads;
    uint64_t now = 0, last_due = 0;
    size_t op = 0;
    const int W = 504 * 4;
    std::vector<uint8_t> pic ((size_t) W * 312 * 3, 0);
    struct Px { int R, y, n; };
    std::vector<Px> act;                      // pixels whose sub-pixels are coming out
    for (int i = 0; i < 64; ++i) { t->clk ^= 1; t->eval(); }
    t->reset = 0;
    while (frame < frames)
    {
        const bool pe = (phase & 3) == 2;
        t->pix_en = pe;
        t->vic_x = R; t->vic_y = y; t->vic_index = vi;
        t->vic_rgb = (PAL[vi][0] << 16) | (PAL[vi][1] << 8) | PAL[vi][2];
        t->wr = 0; t->cs = 0; t->rd = 0;
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
        t->clk = 1; t->eval();
        if (rd && ! busy) { uint64_t due = now + latmin + rng() % (latmax - latmin + 1); if (due <= last_due) due = last_due + 1; last_due = due; reads.push_back ({due, ad}); }
        if (we && ! busy) { const size_t a = (size_t) (ad - VBASE) * 8; for (int k = 0; k < 8; ++k) if (be & (1 << k)) vram[(a + k) & (vram.size() - 1)] = (din >> (8 * k)) & 255; }
        // sub-pixel s of a pixel is out s+1 clocks after its strobe (s = 0: where sim/octovic takes the pixel)
        for (auto& p : act) { ++p.n; if (p.n >= 1 && p.n <= 4 && frame >= 0) { const uint32_t c = t->rgb; uint8_t* q = &pic[((size_t) p.y * W + p.R * 4 + p.n - 1) * 3]; q[0] = c >> 16; q[1] = c >> 8; q[2] = c; } }
        while (! act.empty() && act.front().n >= 4) act.erase (act.begin());
        if (pe) act.push_back ({R, y, 0});
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
