// MY CHIPS test: load two .CHP files (left, right), play each combined waveform on voice 3 of
// every SID (4 pairs x 2 sides) and read OSC3 back each microsecond; compare with the measured
// table for the oscillator's position. Prints matches per chip / table / pulse width.
#include "Vtb.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <fstream>
#include <string>
static std::vector<uint8_t> rd (const char* p) { std::ifstream f (p, std::ios::binary); return std::vector<uint8_t> ((std::istreambuf_iterator<char> (f)), {}); }
Vtb* t; int phase = 0;
void tick() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); }
void clk32() { for (int i = 0; i < 32; ++i) { t->ce_1m = (i == 0); tick(); } t->ce_1m = 0; }
void wreg (int pair, int side, int a, int v) { t->pair = 1 << pair; t->side = side; t->addr = a; t->din = v; t->we = 1; tick(); t->we = 0; t->pair = 0; tick(); }
int rreg (int pair, int side, int a) { t->pair = 1 << pair; t->side = side; t->addr = a; t->we = 0; tick(); tick(); int d = pair == 0 ? t->dout0 : pair == 1 ? t->dout1 : pair == 2 ? t->dout2 : t->dout3; t->pair = 0; return d; }
int main (int argc, char** argv)
{
	// argv: chipL.chp chipR.chp expL.bin expR.bin (exp: per table raw-position expectations: 4 tables x 3 widths x 4096)
	t = new Vtb;
	auto L = rd (argv[1]), R = rd (argv[2]), EL = rd (argv[3]), ER = rd (argv[4]);
	for (int s = 0; s < 2; ++s) { auto& C = s ? R : L; for (int a = 0; a < 0x4000; ++a) { t->we_c = 1; t->wside = s; t->wtbl = a >> 12; t->widx = a & 4095; t->wdata = C[a]; tick(); } }
	t->we_c = 0; t->chip_on = 3; for (int i = 0; i < 64; ++i) clk32();
	const int wave[4] = { 0x30, 0x50, 0x60, 0x70 };      // S+T, P+T, P+S, P+S+T (voice 3 control, gate off - OSC3 needs no envelope)
	const char* wn[4] = { "S+T", "P+T", "P+S", "P+S+T" };
	const int pws[3] = { 0x400, 0x800, 0xC00 };
	for (int pair = 0; pair < 4; ++pair)
	for (int side = 0; side < 2; ++side)
	for (int w = 0; w < 4; ++w)
	for (int pi = 0; pi < (w ? 3 : 1); ++pi) {
		auto& E = side ? ER : EL;
		const uint8_t* ex = &E[(w * 3 + pi) * 4096];
		wreg (pair, side, 0x10, pws[pi] & 255); wreg (pair, side, 0x11, pws[pi] >> 8);
		wreg (pair, side, 0x0E, 0x00); wreg (pair, side, 0x0F, 0x01);   // freq $0100: one position every 16 us
		wreg (pair, side, 0x12, wave[w] | 0x08); clk32(); clk32();       // test bit: the accumulator to 0
		wreg (pair, side, 0x12, wave[w]);
		int n = 0, ok = 0, okhi = 0, nhi = 0;
		for (int us = 0; us < 4096 * 16; ++us) {
			clk32();
			if ((us & 15) != 8) continue;                                  // the middle of each position
			int pos = (us * 0x100) >> 12;                                  // (approximately: the read lags a microsecond or two)
			int v = rreg (pair, side, 0x1B);
			++n; if (v == ex[pos]) ++ok;
			if (!w || pos >= pws[pi]) { ++nhi; if (v == ex[pos]) ++okhi; }
		}
		printf ("pair %d %s %-6s pw $%03X: %5.1f%% of %d positions match (pulse high: %5.1f%% of %d)\n", pair + 1, side ? "R" : "L", wn[w], pws[pi], 100.0 * ok / n, n, 100.0 * okhi / nhi, nhi);
		fflush (stdout);
	}
	return 0;
}
