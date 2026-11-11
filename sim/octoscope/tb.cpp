// sim/octoscope: OCTOSCOPE (Fix 55) - the core's scope against the emulator's, sample for sample and pixel for pixel.
// (c) 2026 Mong00se.
//
// The RTL: OctoVIC and the four SID pairs (tb_top.sv), the VIC's timing, a DDR3 that is busy and late at random
// (as sim/finescroll), and can be held for a whole line once a frame. The captures live in that DDR3 (byte $33000000):
// what is compared is what the core wrote there. Eight SIDs play synthetic voices through their registers: a triangle, a saw, a pulse whose
// width keeps changing, noise, a FREQ sweeping from high to under 839 and back, the test bit, hard sync, ring
// modulation, note changes in the middle of a capture, gates going off and on, FREQ 839 and 838 (either side of the
// line), a test bit toggled every few microseconds, volume writes on the right chips.
//
// The reference: the emulator's own code (octovic.c, the Fix 55 patch: sc_store, octovic_scope_tick, sc_latch,
// scope_line, put/layer_pix), copied here word for word, fed each microsecond with the voices' own registers
// (sid_voice's dac_out, env_dac, oscillator, freq - not the scope's record path) and the chips' outputs.
//
// Checks, each one FAILs the run:
//   CAPTURE  every capture the emulator completes, the RTL completes in the same microsecond, the same 304 samples
//   LATCH    at each frame's latch, all 32 shown captures equal the emulator's sc_disp; the latch happens once a
//            frame, when the renderer starts line 0; the slot being shown (and the complete one) are never written
//   PIXELS   every pixel of every line 16-299 equals the emulator's (24 copper bands, each with its own voice,
//            centre, height, gain, glow, colour and a palette change; then a tall scope over a sprite, mixed)
//   TRACE    the trace never breaks: where y(i) is inside +-SCH, columns i and i+1 are both lit on line SCY + y(i)
//   BANDS    each band's first line already shows that band's colour (the copper's writes land on their line)
//   LATE     no late lines (the scope pass waits for the line's earlier pixels; it must not make lines late)
//
//   tb frames [seed busy% latmin latmax]
#include "Vtb_top.h"
#include "Vtb_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>
#include <deque>
#include <random>
#include <algorithm>

// =====================================================================================================
//  THE EMULATOR (octovic.c, OCTOSCOPE, Fix 55) - copied as it is; only "sc_new[v] = 1" added where sc_done
//  changes, so the check knows a capture completed
// =====================================================================================================
#define SCN 304
static int8_t sc_cap[32][SCN], sc_done[32][SCN], sc_disp[32][SCN];
static int sc_n[32], sc_cyc[32], sc_on[32]; static uint32_t sc_prev[32], sc_age[32], sc_tick[32];
static int sc_new[32];
static long n_lowwrap;
static void sc_store(int v, int s, uint32_t acc, int locked)
{
    if (s > 127) s = 127; else if (s < -127) s = -127;
    if (sc_age[v] < 0x7FFFFFFF) sc_age[v]++;
    if (locked) {                       /* in step with the oscillator: from a wrap, 2 cycles */
        int wrap = acc < sc_prev[v];
        sc_prev[v] = acc;
        if (wrap) {
            if (sc_on[v] && ++sc_cyc[v] == 2) {
                while (sc_n[v] < SCN) sc_cap[v][sc_n[v]++] = (int8_t)s;
                memcpy(sc_done[v], sc_cap[v], SCN); sc_on[v] = 0; sc_new[v] = 1;
            }
            if (!sc_on[v]) { sc_on[v] = 1; sc_cyc[v] = 0; sc_n[v] = 0; sc_age[v] = 0; }
        }
        if (sc_on[v] && sc_age[v] < 40000) {
            int t = sc_cyc[v] * 152 + (int)(((acc >> 8) * 152u) >> 16);
            while (sc_n[v] <= t && sc_n[v] < SCN) sc_cap[v][sc_n[v]++] = (int8_t)s;
            return;
        }
    } else sc_prev[v] = acc;
    /* by time (a note under about 50 Hz, or an oscillator that stopped): a sample every 66 us */
    if (sc_on[v]) { sc_on[v] = 0; sc_n[v] = 0; }
    if (++sc_tick[v] >= 66) {
        sc_tick[v] = 0;
        sc_cap[v][sc_n[v]++] = (int8_t)s;
        if (sc_n[v] >= SCN) { memcpy(sc_done[v], sc_cap[v], SCN); sc_n[v] = 0; sc_new[v] = 1; }
    }
}
// octovic_scope_tick: the same, from the voices' registers (coresid_voice_t's dac_out, env_dac, osc, freq = the
// core's sid_voice dac_out, env_dac, oscillator, freq; c->mode; c->audio = the chip's 18-bit output)
struct VoiceIn { int32_t dac_out, env_dac; uint32_t osc; int freq; };
static void octovic_scope_tick(int sid, const VoiceIn* v3, int mode, int32_t audio)
{
    for (int i = 0; i < 3; i++) {
        const VoiceIn *vo = &v3[i];
        int32_t w = vo->dac_out + (mode ? 0x800 : 0x380) - 2048;
        {   // (the check's own count: a wrap the core sees only through osc[7:0] != 0 - set to 0 from below 256)
            const uint32_t a = vo->osc & 0xFFFFFF, pv = sc_prev[sid * 3 + i];
            if (vo->freq >= 839 && a < pv && (a >> 8) == (pv >> 8)) ++n_lowwrap;
        }
        sc_store(sid * 3 + i, (w * (int32_t)vo->env_dac) >> 12, vo->osc & 0xFFFFFF, vo->freq >= 839);
    }
    sc_store(24 + sid, audio >> 10, 0, 0);      /* the SID's whole output (18 bits) */
}
static void sc_latch(void) { memcpy(sc_disp, sc_done, sizeof sc_disp); }

// the drawing side
static const int RW = 396;
static uint8_t r[256];
static uint32_t pal[256];
static int32_t linebuf[RW], *buf = linebuf;
static int xw = RW;
static inline void put(int R, uint32_t c, int m)
{
    int32_t u = buf[R];
    if (m && u >= 0) {
        uint32_t o = 0;
        for (int sh = 0; sh <= 16; sh += 8) {
            int a = (u >> sh) & 255, b = (c >> sh) & 255, x;
            x = m == 1 ? (a + b) >> 1 : m == 2 ? (a + b > 255 ? 255 : a + b) : (a - b < 0 ? 0 : a - b);
            o |= (uint32_t)x << sh;
        }
        c = o;
    }
    buf[R] = (int32_t)c;
}
static inline void layer_pix(int R, uint32_t idx, int lm) { put(R, pal[idx & 255], lm); }
static void scope_line(int L, int lm)
{
    int v = r[0xC4] & 0x20 ? 24 + (r[0xC4] & 7) : (r[0xC4] & 31) % 24;
    int cy = r[0xC5] | (r[0xC6] & 1) << 8, hh = r[0xC7], g = r[0xC8], col = r[0xC9], x0 = r[0xCA], glow = r[0xCB] & 1;
    int dy = L - cy;
    if (dy < -hh || dy > hh) return;
    const int8_t *s = sc_disp[v];
    int prev = -(s[0] * g) / 128;
    for (int i = 0; i < SCN; i++) {
        int yv = -(s[i] * g) / 128, lo = prev < yv ? prev : yv, hi = prev < yv ? yv : prev;
        prev = yv;
        if (lo < -hh) lo = -hh; if (hi > hh) hi = hh;
        int R = x0 + 32 + i;
        if (R < 0 || R >= xw) continue;
        if (dy >= lo && dy <= hi) layer_pix(R, (uint8_t)col, lm);
        else if (glow && dy >= lo - 1 && dy <= hi + 1) layer_pix(R, (uint8_t)(col + 1), lm);
    }
}
// =====================================================================================================

static int fails = 0;
#define FAIL(...) do { if (fails++ < 40) { std::printf ("FAIL "); std::printf (__VA_ARGS__); std::printf ("\n"); } } while (0)

static const uint32_t VBASE = 0x06400000;
static const uint32_t VICRGB = 0x2E2C9B;        // the VIC's picture: colour 6 everywhere (behind the layers)

// VRAM layout of the test
static const uint32_t COPB = 0x010000, SATB = 0x020000, GFXB = 0x030000;

int main (int argc, char** argv)
{
    const int frames = argc > 1 ? std::atoi (argv[1]) : 13;
    const unsigned seed = argc > 2 ? std::atoi (argv[2]) : 1;
    const int busyp = argc > 3 ? std::atoi (argv[3]) : 20, latmin = argc > 4 ? std::atoi (argv[4]) : 6, latmax = argc > 5 ? std::atoi (argv[5]) : 30;
    const int holdc = argc > 6 ? std::atoi (argv[6]) : 0;      // the port held this many clocks once a frame (0: never)
    std::mt19937 rng (seed);
    std::vector<uint8_t> vram (32 << 20, 0);       // the VRAM, and above it (byte $33000000) the scope's captures

    // ---- the copper list: 24 bands of 11 lines from line 22, each: SCV, SCY, SCH, SCG, SCF, SCC, LMODE0 and a
    // palette entry (its colour) - 12 writes a band, like OctoPlay build 4
    struct CopE { int line, reg, val; };
    std::vector<CopE> cop;
    for (int b = 0; b < 24; ++b) {
        const int l0 = 22 + 11 * b, cy = l0 + 5;
        const int col = 0x40 + 2 * b;
        cop.push_back ({l0, 0xC4, b % 3 == 2 ? (0x20 | (b / 3)) : b});      // voices, and every third band a SID's output
        cop.push_back ({l0, 0xC5, cy & 255});
        cop.push_back ({l0, 0xC6, cy >> 8});
        cop.push_back ({l0, 0xC7, 3 + b % 4});                                // half height 3-6 (some traces clipped)
        cop.push_back ({l0, 0xC8, 16 + 20 * b % 240});                        // gains from small to large
        cop.push_back ({l0, 0xCB, b & 1});                                    // glow every other band
        cop.push_back ({l0, 0xC9, col});
        cop.push_back ({l0, 0xCA, (7 * b) & 63});                             // where it starts
        cop.push_back ({l0, 0x2F, 0x10 | (b % 4 == 3 ? 2 : 0)});              // a scope layer; some bands added
        cop.push_back ({l0, 0x1A, col});                                      // the band's colour, by the copper
        cop.push_back ({l0, 0x1B, 40 + 8 * b});
        cop.push_back ({l0, 0x1C, 255 - 9 * b});
        cop.push_back ({l0, 0x1D, (31 * b) & 255});
    }
    for (size_t i = 0; i < cop.size(); ++i) {
        uint8_t* p = &vram[COPB + 4 * i]; p[0] = cop[i].line & 255; p[1] = cop[i].line >> 8; p[2] = cop[i].reg; p[3] = cop[i].val;
    }
    { uint8_t* p = &vram[COPB + 4 * cop.size()]; p[0] = 0xFF; p[1] = 0xFF; }
    // ---- a sprite (64 x 64, 256 colours, colour 5, behind both layers) under the tall scope of the last frames
    for (int i = 0; i < 64 * 64; ++i) vram[GFXB + i] = 5;
    {
        uint8_t* p = &vram[SATB];
        const int X = 120, Y = 96;                      // screen x 120.., sprite y 96.. (raster lines 147..210)
        p[0] = X & 255; p[1] = X >> 8; p[2] = Y & 255; p[3] = Y >> 8; p[4] = 0; p[5] = 0;
        p[6] = 3 | (3 << 2) | 0x40 | 0x80;               // 64 wide, 64 tall, 256 colours, on
        p[7] = 2 << 4;                                   // priority 2 (behind both layers), drawn as it is
    }

    // ---- the CPU's writes to OctoVIC, each at a frame's line 305 (the vertical blank)
    struct RegW { int frame, reg, val; };
    std::vector<RegW> rw;
    auto at = [&] (int f, std::initializer_list<std::pair<int,int>> l) { for (auto& p : l) rw.push_back ({f, p.first, p.second}); };
    const int FB = 5, FT = FB + 3;                      // the bands from frame FB, the tall scope from frame FT
    at (FB - 1, {{0x05, 0x05}, {0x19, 0}, {0x1A, 0}, {0x1B, 1}, {0x1C, 2}, {0x1D, 3},       // CTRL: ENABLE, VIC behind
                 {0x1A, 5}, {0x1B, 0}, {0x1C, 0}, {0x1D, 200},                             // the sprite's colour
                 {0x20, 0x01}, {0x2F, 0x10},                                               // layer 0: the scope
                 {0x10, COPB & 255}, {0x11, (COPB >> 8) & 255}, {0x12, COPB >> 16}, {0x0E, 1}});
    // the tall scope: no copper, one voice, a big gain and height, glow, half-and-half over a sprite; then colour 255
    // (its glow is colour 0, drawn - pixel 0 is not see-through on the scope), then the pulse at x 255 (clipped right)
    at (FT - 1, {{0x0E, 0}, {0x13, SATB & 255}, {0x14, (SATB >> 8) & 255}, {0x15, SATB >> 16},
                 {0x16, GFXB & 255}, {0x17, (GFXB >> 8) & 255}, {0x18, GFXB >> 16}, {0x0F, 1},
                 {0xC4, 0}, {0xC5, 170}, {0xC6, 0}, {0xC7, 110}, {0xC8, 255}, {0xCB, 1}, {0xC9, 0x80}, {0xCA, 10},
                 {0x2F, 0x11}, {0x1A, 0x80}, {0x1B, 255}, {0x1C, 128}, {0x1D, 0}, {0x1B, 0}, {0x1C, 90}, {0x1D, 60}});
    at (FT, {{0xC4, 9}, {0xC9, 0xFF}, {0xC8, 200}, {0xC5, 0x2C}, {0xC6, 1}, {0xC7, 30}, {0x2F, 0x10},
             {0x1A, 0xFF}, {0x1B, 250}, {0x1C, 250}, {0x1D, 10}, {0x1B, 9}, {0x1C, 8}, {0x1D, 7}});
    at (FT + 1, {{0xC4, 2}, {0xCA, 255}, {0xC9, 0x80}, {0xC5, 160}, {0xC6, 0}, {0xC7, 120}, {0xC8, 128}, {0xCB, 0}});
    at (FT + 2, {{0xC4, 1}, {0xCA, 40}, {0xC8, 100}, {0xC7, 127}, {0xC5, 150}, {0xCB, 1}});                     // the saw, all inside
    at (FT + 3, {{0xC4, 0x24}, {0xCA, 0}, {0xC8, 255}, {0xCB, 1}, {0x30, 0x01}, {0x3F, 0x13}});   // a SID's output; layer 1 too (taken away)

    // ---- the SIDs' writes, each at microsecond-clock 28 of its microsecond
    struct SidW { long us; int sid, reg, val; };
    std::vector<SidW> sw;
    auto sidw = [&] (long us, int sid, int reg, int val) { sw.push_back ({us, sid, reg, val}); };
    auto voice = [&] (long us, int sid, int v, int freq, int pw, int ctrl, int ad, int sr) {
        const int b = 7 * v;
        sidw (us, sid, b + 0, freq & 255); sidw (us, sid, b + 1, freq >> 8);
        sidw (us, sid, b + 2, pw & 255);   sidw (us, sid, b + 3, pw >> 8);
        sidw (us, sid, b + 5, ad); sidw (us, sid, b + 6, sr); sidw (us, sid, b + 4, ctrl);
    };
    const long T = (long) frames * 312 * 63 + 1000;    // microseconds the run lasts (about)
    for (int sid = 0; sid < 8; ++sid) {
        const double k = sid >= 4 ? 1.5 : 1.0;
        sidw (20, sid, 0x18, 0x0F);
        switch (sid & 3) {
        case 0:
            voice (30, sid, 0, (int) (7382 * k), 0, 0x11, 0x00, 0xF0);          // triangle
            voice (30, sid, 1, (int) (3000 * k), 0, 0x21, 0x22, 0xA8);          // saw
            voice (30, sid, 2, (int) (1500 * k), 0x200, 0x41, 0x11, 0xC4);      // pulse, its width changing
            for (long t = 800; t < T; t += 777) { const int pw = (0x200 + 0x123 * (int) (t / 777)) & 0xFFF; sidw (t, sid, 16, pw & 255); sidw (t, sid, 17, pw >> 8); }
            if (sid == 4) voice (30, sid, 0, 839, 0, 0x21, 0x00, 0xF0);         // FREQ 839: 2 cycles just inside 40,000 us
            break;
        case 1:
            voice (30, sid, 0, 20000, 0, 0x81, 0x00, 0xF0);                     // noise
            voice (30, sid, 1, 30000, 0, 0x21, 0x00, 0xF0);                     // a saw sweeping down past 839 and back
            { long t = 600; double f = 30000; while (t < T) { f *= 0.8; if (f < 300) f = 30000; const int fi = (int) f; sidw (t, sid, 7, fi & 255); sidw (t, sid, 8, fi >> 8); t += 400; } }
            voice (30, sid, 2, (int) (9000 * k), 0, 0x11, 0x00, 0xF0);          // triangle; the test bit now and then
            for (long t = 1500; t < T; t += 2000) { sidw (t, sid, 18, 0x19); sidw (t + 100 + sid * 7, sid, 18, 0x11); }
            if (sid == 5) voice (30, sid, 2, 838, 0, 0x41, 0x00, 0xF0);         // FREQ 838: by time
            break;
        case 2:
            voice (30, sid, 0, (int) (2000 * k), 0x800, 0x43, 0x00, 0xF0);      // pulse, hard sync from voice 3
            if (sid == 2) {                                                     // FREQ 65281: 257 steps from 0 the oscillator
                sidw (70000, sid, 14, 65281 & 255); sidw (70000, sid, 15, 65281 >> 8);   // has gone round to 1; the test
                for (long t = 70010, j = 0; t < 110000; t += 280, ++j) {        // bit set about then - set to 0 from below 256
                    sidw (t, sid, 18, 0x21); sidw (t + 255 + j % 8, sid, 18, 0x29);
                }
            }
            voice (30, sid, 1, (int) (4000 * k), 0, 0x15, 0x00, 0xF0);          // triangle, ring modulated by voice 1
            voice (30, sid, 2, (int) (5100 * k), 0x600, 0x41, 0x00, 0xF0);      // pulse
            if (sid == 6) {                                                     // the test bit held 50 ms at FREQ >= 839:
                sidw (90000, sid, 18, 0x49); sidw (140000, sid, 18, 0x41);      // the capture runs out at 40,000 us exactly
                for (long t = 160000; t < 200000; t += 9000) { sidw (t, sid, 14, 0x60); sidw (t, sid, 15, 0x03); sidw (t + 4000, sid, 14, 0x20); sidw (t + 4000, sid, 15, 0x14); }
            }                                                                   // (and FREQ 864 mid-capture: a cycle of 19,400 us)
            break;
        case 3:
            voice (30, sid, 0, 5000, 0, 0x21, 0x00, 0xF0);                      // saw: the note changes mid-capture
            for (long t = 333; t < T; t += 333) { const int f = (t / 333) & 1 ? 9000 : 5000; sidw (t, sid, 0, f & 255); sidw (t, sid, 1, f >> 8); }
            voice (30, sid, 1, (int) (12000 * k), 0, 0x11, 0x09, 0x84);         // triangle: gate off and on (release, attack)
            for (long t = 3000; t < T; t += 3000) sidw (t, sid, 11, (t / 3000) & 1 ? 0x10 : 0x11);
            voice (30, sid, 2, (int) (6000 * k), 0, 0x21, 0x00, 0xF0);          // saw: the test bit every 5 us for a while
            for (long t = 20000; t < 23000; t += 5) sidw (t, sid, 18, ((t / 5) & 1) ? 0x29 : 0x21);
            for (long t = 61000; t < 61400; t += 3) sidw (t + sid, sid, 18, ((t / 3) & 1) ? 0x29 : 0x21);
            break;
        }
        if (sid & 1) for (long t = 1000; t < T; t += 1000) sidw (t + sid, sid, 0x18, (t / 1000) & 1 ? 0x08 : 0x0F);   // volume (right chips)
    }
    std::stable_sort (sw.begin(), sw.end(), [] (const SidW& a, const SidW& b) { return a.us < b.us; });

    // ---- run
    Verilated::commandArgs (argc, argv);
    auto* t = new Vtb_top;
    auto* rp = t->rootp;
    t->clk = 0; t->reset = 1; t->cs = 0; t->wr = 0; t->rd = 0; t->pix_en = 0; t->ddr_busy = 0; t->ddr_dout_ready = 0;
    t->quarter = 0; t->sid_ce = 0; t->sid_cs = 0; t->sid_we = 0; t->sid_mode = 2;      // right chips 8580
    for (int i = 0; i < 64; ++i) { t->clk ^= 1; t->eval(); }
    t->reset = 0;

    int phase = 0, R = 404, y = 300, frame = -1;
    struct Pend { uint64_t due; uint32_t word; };
    std::deque<Pend> reads;
    uint64_t now = 0, last_due = 0;
    size_t rwi = 0, swi = 0;
    int es = 99; long us = -1;                                   // clocks since the SIDs' edge, microseconds
    struct TickIn { VoiceIn v[24]; int32_t aud[8]; };
    std::deque<TickIn> pend;                                     // microseconds taken, waiting for the RTL's tick
    std::vector<uint32_t> pic ((size_t) 504 * 312, 0);
    std::vector<std::pair<int,int>> act;                         // pixel strobes: (R, y), 1 clock later out
    long n_cap = 0, n_capcmp = 0, n_latch = 0, n_px = 0, n_lines = 0, n_trace = 0, n_bands = 0, n_ticks = 0;
    long n_scope_lines = 0, st_timed = 0, st_locked = 0, st_hole = 0, st_bighole = 0, st_bigfill = 0;
    int latch_check = 0;
    int last_latch_frame = -9;
    bool cop_on = false;
    uint8_t rc[256]; std::memset (rc, 0, sizeof rc);             // the registers (CPU + copper) as the C side has them
    uint32_t pal_c[256]; for (int i = 0; i < 256; ++i) pal_c[i] = (uint32_t) i * 0x010101;
    int palidx_c = 0, palr_c = 0, palg_c = 0;
    auto creg = [&] (int a, int v) {                             // a register write as the emulator's reg_write keeps it
        rc[a] = (uint8_t) v;
        if (a == 0x1A) palidx_c = v;
        if (a == 0x1B) palr_c = v;
        if (a == 0x1C) palg_c = v;
        if (a == 0x1D) { if (rc[0x19] == 0) pal_c[palidx_c] = (uint32_t) palr_c << 16 | palg_c << 8 | v; palidx_c = (palidx_c + 1) & 255; }
    };
    // an RTL slot as the renderer reads it: its 304 bytes from the DDR3 (byte $33000000 + slot x 304), its rules
    auto slot_samples = [&] (int sidx, uint64_t d, int zero, int8_t* out) {
        const int fv = (int8_t) (d & 255), fn = (d >> 8) & 511, hv = (int8_t) ((d >> 17) & 255), hs = (d >> 25) & 255, hok = (d >> 33) & 1;
        for (int i = 0; i < SCN; ++i) {
            int s = (int8_t) vram[0x1000000 + (size_t) sidx * 304 + i];
            if (zero) s = 0; else if (i >= fn) s = fv; else if (hok && i >= hs && i <= 152) s = hv;
            out[i] = (int8_t) s;
        }
    };
    auto dmem = [&] (int sidx) { return (uint64_t) rp->tb_top__DOT__octo__DOT__scope__DOT__dmem[sidx]; };
    // a comparison waits until every word queued before it is in the DDR3 (the queue has passed its mark and the
    // port holds no scope write)
    struct Cmp { int ch, sidx, zero, disp, mark; long when; int8_t want[SCN]; uint64_t d; int dready; };
    std::deque<Cmp> cmpq;
    std::vector<int> comps;                                      // the RTL's completions this microsecond: (channel, slot)
    std::vector<int> comps_slot;
    int prev_y = y;

    while (frame < frames)
    {
        // ---- the SIDs' microsecond
        t->sid_ce = (phase == 0);
        t->sid_we = 0; t->sid_cs = 0;
        // one SID write a clock at microsecond-clocks 26-29 (as the 6510's land, a few clocks before the next edge;
        // more wait for the next microsecond)
        if (es >= 26 && es <= 29 && swi < sw.size() && sw[swi].us <= us) {
            t->sid_we = 1; t->sid_cs = 1 << sw[swi].sid; t->sid_addr = sw[swi].reg; t->sid_data = sw[swi].val; ++swi;
        }
        // ---- the VIC's timing and the CPU's OctoVIC writes
        const bool pe = (phase & 3) == 2;
        t->pix_en = pe; t->vic_x = R; t->vic_y = y; t->vic_index = 6; t->vic_rgb = VICRGB;
        t->wr = 0; t->cs = 0; t->rd = 0;
        if ((phase & 31) == 28 && y == 305 && rwi < rw.size() && rw[rwi].frame <= frame) {
            t->cs = 1; t->wr = 1; t->addr = rw[rwi].reg; t->din = rw[rwi].val;
            creg (rw[rwi].reg, rw[rwi].val);
            if (rw[rwi].reg == 0x0E || (rw[rwi].reg >= 0x10 && rw[rwi].reg <= 0x12)) cop_on = false;   // waits for line 0
            ++rwi;
        }
        // ---- the DDR3
        const bool held = holdc > 0 && y == 100 + frame % 7 * 20 && R < 300 + holdc / 4 && frame >= 0;   // the port held (other users)
        const bool busy = held || (int) (rng() % 100) < busyp;
        t->ddr_busy = busy; t->ddr_dout_ready = 0;
        if (! reads.empty() && reads.front().due <= now) {
            const uint32_t w = reads.front().word; reads.pop_front();
            uint64_t d = 0; const size_t a = (size_t) (w - VBASE) * 8;
            for (int k = 0; k < 8; ++k) d |= (uint64_t) vram[(a + k) & (vram.size() - 1)] << (8 * k);
            t->ddr_dout = d; t->ddr_dout_ready = 1;
        }
        const bool rd = t->ddr_rd, we = t->ddr_we; const uint32_t ad = t->ddr_addr; const uint64_t din = t->ddr_din; const int be = t->ddr_be;
        t->clk = 1; t->eval();
        if (rd && ! busy) { uint64_t due = now + latmin + rng() % (latmax - latmin + 1); if (due <= last_due) due = last_due + 1; last_due = due; reads.push_back ({due, ad}); }
        if (we && ! busy && std::getenv ("DBG") && ad >= 0x06600000u) { const int wa = ad - 0x06600000u, sl = wa / 38; if (sl / 3 == std::atoi (std::getenv ("DBG")) && us > 700 && us < 2600) std::printf ("us %ld write slot %d word %d be %02x data %016llx\n", us, sl % 3, wa % 38, be, (unsigned long long) din); }
        if (we && ! busy) { const size_t a = (size_t) (ad - VBASE) * 8; for (int k = 0; k < 8; ++k) if (be & (1 << k)) vram[(a + k) & (vram.size() - 1)] = (din >> (8 * k)) & 255; }
        if (phase == 0) { es = 0; ++us; } else ++es;
        // the microsecond's values, once they stand (the edge was at the clock with sid_ce; no write before clock 28)
        if (es == 20) {
            TickIn ti;
            for (int c = 0; c < 24; ++c) {
                ti.v[c].dac_out = (int32_t) ((int16_t) (t->dbg_dac[c] << 3) >> 3);
                ti.v[c].env_dac = t->dbg_env[c]; ti.v[c].osc = t->dbg_osc[c]; ti.v[c].freq = t->dbg_freq[c];
            }
            for (int s = 0; s < 8; ++s) ti.aud[s] = (int32_t) (t->dbg_aud[s] << 14) >> 14;
            pend.push_back (ti);
        }
        if (std::getenv ("DBG") && rp->tb_top__DOT__octo__DOT__scope__DOT__wm_we) {
            const auto& w = rp->tb_top__DOT__octo__DOT__scope__DOT__wm_wd; const int a12 = (w[2] >> 8) & 0xFFF, sl = a12 / 38;
            if (sl / 3 == std::atoi (std::getenv ("DBG")) && us > 700 && us < 1100) std::printf ("us %ld es %d ENQ at %d slot %d word %d be %02x data %08x%08x\n", us, es, rp->tb_top__DOT__octo__DOT__scope__DOT__wm_wa, sl % 3, a12 % 38, w[0] & 255, (w[2] << 24) | (w[1] >> 8), (w[1] << 24) | (w[0] >> 8));
        }
        if (std::getenv ("DBGL") && frame == FB && y >= 20 && y <= 27 && (phase & 31) == 0 && R < 410) std::printf ("y %d R %d st %d L %d rok %d w %d r %d mark %d busy %d\n", y, R, rp->tb_top__DOT__octo__DOT__st, rp->tb_top__DOT__octo__DOT__L, t->dbg_rok, t->dbg_wptr, t->dbg_rptr, rp->tb_top__DOT__octo__DOT__scope__DOT__wq_mark, rp->tb_top__DOT__octo__DOT__scope__DOT__lat_busy);
        // the checks the RTL raises itself
        if (t->dbg_dbl) FAIL ("us %ld: two words to queue for one channel in one microsecond", us);
        if (t->dbg_bad) FAIL ("us %ld: a word queued for the slot being shown", us);
        // the queued comparisons whose words are all in the DDR3
        {
            const bool port_scope = t->ddr_we && t->ddr_addr >= 0x06600000u;
            for (auto& q : cmpq) if (! q.dready) { q.d = dmem (q.sidx); q.dready = 1; }      // (the rules: a clock after)
            while (! cmpq.empty() && ! port_scope && ((t->dbg_rptr - cmpq.front().mark) & 0x1FF) < 256 && cmpq.front().when < (long) now) {
                Cmp& q = cmpq.front();
                int8_t got[SCN]; slot_samples (q.sidx, q.d, q.zero, got);
                if (! q.disp) {
                    const int fn = (q.d >> 8) & 511, hs = (q.d >> 25) & 255, hok = (q.d >> 33) & 1;
                    if (hok) { ++st_hole; if (152 - hs + 1 > 2) ++st_bighole; }
                    if (fn < SCN && SCN - fn > 2) ++st_bigfill;
                }
                for (int i = 0; i < SCN; ++i) if (got[i] != q.want[i]) {
                    if (q.disp) FAIL ("frame %d channel %d: shown sample %d is %d, the emulator's %d", frame, q.ch, i, got[i], q.want[i]);
                    else FAIL ("us %ld channel %d: capture sample %d is %d, the emulator's %d", us, q.ch, i, got[i], q.want[i]);
                    break;
                }
                cmpq.pop_front();
            }
            if (cmpq.size() > 4000) FAIL ("comparisons waiting for the DDR3: %zu", cmpq.size());
        }
        if (t->dbg_comp) { comps.push_back (t->dbg_ch); comps_slot.push_back (t->dbg_ch * 3 + t->dbg_slot); }
        // the RTL has stored a whole microsecond: the emulator does the same one, then compare
        if (t->dbg_tick) {
            if (pend.empty()) FAIL ("the RTL stored a microsecond that hasn't happened");
            else {
                TickIn ti = pend.front(); pend.pop_front(); ++n_ticks;
                std::memset (sc_new, 0, sizeof sc_new);
                for (int s = 0; s < 8; ++s) octovic_scope_tick (s, &ti.v[s * 3], s & 1 ? 1 : 0, ti.aud[s]);
                if (std::getenv ("DBG") && us > 850 && us < 1010) { const int c = std::atoi (std::getenv ("DBG")); const auto& m = rp->tb_top__DOT__octo__DOT__scope__DOT__cmem[c]; auto bits = [&] (int lo, int n) { uint64_t v = 0; for (int b = 0; b < n; ++b) v |= (uint64_t) ((m[(lo + b) / 32] >> ((lo + b) % 32)) & 1) << b; return v; };
                    std::printf ("us %ld C: n %d cyc %d on %d age %u tick %u | RTL n %d on %d tick %d sv %d ss %d sw %d sbe %02x\n", us, sc_n[c], sc_cyc[c], sc_on[c], sc_age[c], sc_tick[c], (int) bits (42, 9), (int) bits (40, 1), (int) bits (17, 7), (int) bits (139, 1), (int) bits (137, 2), (int) bits (131, 6), (int) bits (59, 8)); }
                int rtl_new[32] = {0}, rtl_slot[32];
                for (size_t k = 0; k < comps.size(); ++k) { rtl_new[comps[k]]++; rtl_slot[comps[k]] = comps_slot[k]; }
                comps.clear(); comps_slot.clear();
                for (int c = 0; c < 32; ++c) {
                    if (sc_new[c]) ++n_cap;
                    if ((rtl_new[c] != 0) != (bool) sc_new[c] || rtl_new[c] > 1) { FAIL ("us %ld channel %d: the emulator %s a capture, the RTL %s", us, c, sc_new[c] ? "completed" : "did not complete", rtl_new[c] ? "did" : "did not"); continue; }
                    if (! sc_new[c]) continue;
                    Cmp q; q.ch = c; q.sidx = rtl_slot[c]; q.zero = 0; q.disp = 0; q.mark = t->dbg_wptr; q.when = (long) now; q.dready = 0;
                    std::memcpy (q.want, sc_done[c], SCN);
                    cmpq.push_back (q); ++n_capcmp;
                    if (sc_on[c]) ++st_locked; else ++st_timed;          // (a phase-locked capture restarts at once)
                }
                if (t->dbg_latch) {
                    sc_latch(); ++n_latch;
                    if (frame == last_latch_frame) FAIL ("two latches in frame %d", frame);
                    if (rp->tb_top__DOT__octo__DOT__L != 0) FAIL ("the latch came with the renderer on line %d, not line 0", rp->tb_top__DOT__octo__DOT__L);
                    last_latch_frame = frame;
                    latch_check = 1;                                     // the shown slots: once the latch is applied (r_ok)
                }
            }
        }
        if (t->dbg_latch && ! t->dbg_tick) FAIL ("a latch not at the end of a microsecond");
        if (latch_check && t->dbg_rok && ! t->dbg_tick) {
            latch_check = 0;
            for (int c = 0; c < 32; ++c) {
                Cmp q; q.ch = c; q.sidx = c * 3 + rp->tb_top__DOT__octo__DOT__scope__DOT__disp[c];
                q.zero = (rp->tb_top__DOT__octo__DOT__scope__DOT__disp_z >> c) & 1; q.disp = 1; q.mark = t->dbg_rptr; q.when = (long) now; q.dready = 0;
                std::memcpy (q.want, sc_disp[c], SCN);
                cmpq.push_back (q);
            }
        }
        if (pend.size() > 2) FAIL ("the RTL is behind: %zu microseconds waiting", pend.size());
        // the picture: a pixel is out 1 clock after its strobe
        for (auto& p : act) { const uint32_t c = t->rgb; pic[(size_t) p.second * 504 + p.first] = c; }
        act.clear();
        if (pe) act.push_back ({R, y});
        if (pe) {
            R = (R + 1) % 504;
            if (R == 408) {
                y = (y + 1) % 312;
                if (y == 0) ++frame;
                if (y == 300 && frame >= 0) {
                    // ---- the frame is done: the emulator draws it (copper and all) and every pixel is compared
                    if (rp->tb_top__DOT__octo__DOT__h_late != 0 && frame >= FB) FAIL ("frame %d: %d late lines", frame - 1, rp->tb_top__DOT__octo__DOT__h_late);
                    std::memcpy (r, rc, sizeof r); std::memcpy (pal, pal_c, sizeof pal);
                    size_t ci = 0;
                    // (the C side's own register file runs through the copper's writes line by line)
                    for (int L = 0; L < 300; ++L) {
                        if (cop_on) while (ci < cop.size() && cop[ci].line <= L) { creg (cop[ci].reg, cop[ci].val); ++ci; }
                        std::memcpy (r, rc, sizeof r); std::memcpy (pal, pal_c, sizeof pal);
                        if (L < 16) continue;
                        for (int i = 0; i < RW; ++i) linebuf[i] = -1;
                        if (r[0x05] & 1) {
                            // the sprite (priority 2, behind layer 0): raster lines 51 + 96 .. +63, x 120.. (raster 152..)
                            const int sy = L - 51;
                            if (r[0x0F] && sy >= 96 && sy < 160) for (int R2 = 152; R2 < 216; ++R2) put (R2, pal[5], 0);
                            if ((r[0x20] & 1) && (r[0x2F] & 0x10)) scope_line (L, r[0x2F] & 3);
                            if ((r[0x30] & 1) && (r[0x3F] & 0x10)) scope_line (L, r[0x3F] & 3);
                        }
                        bool any = false;
                        for (int R2 = 0; R2 < RW; ++R2) {
                            const uint32_t want = linebuf[R2] >= 0 ? (uint32_t) linebuf[R2] : VICRGB;
                            const uint32_t got = pic[(size_t) L * 504 + R2];
                            ++n_px;
                            if (linebuf[R2] >= 0) any = true;
                            if (got != want) FAIL ("frame %d line %d x %d: pixel %06X, the emulator's %06X", frame, L, R2 - 32, got, want);
                        }
                        ++n_lines; if (any) ++n_scope_lines;
                        // BANDS: on a band's first line (the copper's writes for it), the band's colour where its trace is
                        if (cop_on && (r[0x05] & 1)) for (int b = 0; b < 24; ++b) if (L == 22 + 11 * b) {
                            // its centre line is 5 below: check that line instead (the trace is surely there? not if
                            // clipped) - the first line drawn with the band's registers must use the band's colour only
                            for (int R2 = 0; R2 < RW; ++R2) if (linebuf[R2] >= 0) {
                                const uint32_t c = pic[(size_t) L * 504 + R2];
                                if (c != pal[r[0xC9]] && c != pal[(r[0xC9] + 1) & 255] && (r[0x2F] & 3) == 0) FAIL ("band %d line %d: a colour not the band's", b, L);
                            }
                            ++n_bands;
                        }
                        // TRACE: columns i and i+1 both lit on line SCY + y(i), where y(i) is inside +-SCH (one voice,
                        // no copper, mode 0: frames from FT)
                        if (! cop_on && (r[0x05] & 1) && (r[0x2F] & 0x13) == 0x10 && !(r[0x30] & 1)) {
                            const int v = r[0xC4] & 0x20 ? 24 + (r[0xC4] & 7) : (r[0xC4] & 31) % 24;
                            const int cy = r[0xC5] | (r[0xC6] & 1) << 8, hh = r[0xC7], g = r[0xC8], x0 = r[0xCA];
                            for (int i = 0; i + 1 < SCN; ++i) {
                                const int yv = -(sc_disp[v][i] * g) / 128;
                                if (yv < -hh || yv > hh || L != cy + yv) continue;
                                const int Ra = x0 + 32 + i, Rb = Ra + 1;
                                if (Rb >= RW) continue;
                                const uint32_t lit = pal[r[0xC9]];
                                if (pic[(size_t) L * 504 + Ra] != lit || pic[(size_t) L * 504 + Rb] != lit) FAIL ("frame %d: the trace breaks between columns %d and %d (line %d)", frame, i, i + 1, L);
                                ++n_trace;
                            }
                        }
                    }
                    std::memcpy (r, rc, sizeof r);
                }
                if (y == 0 && rp->tb_top__DOT__octo__DOT__copen) cop_on = true;    // armed at line 0, as the RTL
            }
        }
        (void) prev_y;
        t->clk = 0; t->eval();
        phase = (phase + 1) & 31; ++now;
    }
    // the latch: once each frame
    if (n_latch < frames - 1) FAIL ("only %ld latches in %d frames", n_latch, frames);
    std::printf ("ticks %ld (us), captures completed %ld (compared %ld, all 304 samples), latches %ld (32 channels each)\n", n_ticks, n_cap, n_capcmp, n_latch);
    std::printf ("pixels compared %ld on %ld lines (%ld with a trace), band first lines %ld, trace joins %ld\n", n_px, n_lines, n_scope_lines, n_bands, n_trace);
    std::printf ("captures: %ld phase-locked, %ld by time; %ld with the jump into cycle 2 kept as a rule (%ld over 2 samples: sync/test), %ld ended early by a wrap (fill over 2 samples)\n",
                 st_locked, st_timed, st_hole, st_bighole, st_bigfill);
    if (! st_timed || ! st_locked || ! st_bighole || ! st_bigfill) FAIL ("a kind of capture never happened");
    std::printf ("wraps from below 256 to 0 (seen only through osc[7:0] != 0): %ld\n", n_lowwrap);
    if (! n_lowwrap) FAIL ("no wrap from below 256 happened");
    std::printf ("DDR3 write queue: %u words lost (must be 0), %zu comparisons still waiting at the end\n", (unsigned) t->dbg_lost, cmpq.size());
    if (t->dbg_lost) FAIL ("capture words lost");
    std::printf ("SID writes %zu/%zu, OctoVIC writes %zu/%zu\n", swi, sw.size(), rwi, rw.size());
    if (n_capcmp < 1000 || n_scope_lines < 300 || n_trace < 200) FAIL ("too little was checked");
    std::printf (fails ? "OCTOSCOPE: FAIL (%d)\n" : "OCTOSCOPE: PASS\n", fails);
    delete t;
    return fails ? 1 : 0;
}
