// © 2026 Mong00se
// MY CHIPS, PER SID (Fix 81): three .CHP files go in through the menu's file loads (chips A, B, C), the eight
// SIDs are set to an arrangement of them, and every SID is then checked against the FILE of the chip it should be:
//   MODEL   silent, volume 15: its output is the reference 6581's or the reference 8580's (they differ: the 6581's DC)
//   FILTER  the F0 its filter takes, at 48 cutoff register values: the chip file's curve entry (>> 1) - or, with no
//           chip, the reference SID's of its model
//   WAVES   OSC3 through all 4096 positions of S+T, P+T, P+S, P+S+T: the chip file's tables (chips A and B) - or the
//           reference SID's of its model (chip C, no chip)
//   SOUND   a filtered S+T note with a cutoff sweep, 6000 samples: SIDs set alike sound alike (within 64 of 131072 at
//           every sample - see there), SIDs set differently are more than 1000 apart; a SID with no chip is the
//           reference SID
// The reference pair is a fifth sid_top with My Chips out of it (tb_top.sv). Any mismatch: FAIL.
#include "Vtb_top.h"
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <fstream>
#include <string>
#include <cstring>
static std::vector<uint8_t> rd (const char* p) { std::ifstream f (p, std::ios::binary); return std::vector<uint8_t> ((std::istreambuf_iterator<char> (f)), {}); }
static Vtb_top* t;
static long fails = 0, checks = 0;
static int worst_alike = 0, least_diff = 1 << 30;
static void tick() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); }
// one microsecond (32 clocks); a register write, if any, to every SID at clock 20
static void us (int a = -1, int v = 0)
{
	for (int i = 0; i < 32; ++i) {
		t->ce_1m = (i == 0);
		t->we = (i == 20 && a >= 0); t->addr = a < 0 ? 0 : a; t->din = v;
		tick();
	}
	t->ce_1m = 0; t->we = 0;
}
static void wr (int a, int v) { us (a, v); }
static void run (int n) { for (int i = 0; i < n; ++i) us(); }

struct Chip { std::vector<uint8_t> d; std::string name; int model; uint16_t curve (int i) const { return d[0x4000 + i * 2] | (d[0x4001 + i * 2] << 8); } };
static Chip in[3];            // what is in chips A, B, C
static bool isin[3] = { false, false, false };
static void load (int c, const Chip& ch)
{
	static const int idx[3] = { 2, 3, 6 };
	t->ioctl_index = idx[c]; t->ioctl_download = 1; tick(); tick();
	for (size_t a = 0; a < ch.d.size(); ++a) { t->ioctl_addr = a; t->ioctl_data = ch.d[a]; t->ioctl_wr = 1; tick(); t->ioctl_wr = 0; tick(); tick(); }
	t->ioctl_download = 0; tick(); tick();
	in[c] = ch; isin[c] = true;
	printf ("loaded chip %c: %s (%s)\n", 'A' + c, ch.name.c_str(), ch.model ? "8580" : "6581");
}

// what SID k (0-7) should be
struct Want { int chip; int model; };       // chip: 0 A, 1 B, 2 C, -1 the core's own
static Want want (int k, int opt, int enable, int menu_ver)
{
	int side = k & 1, o = (opt >> (k * 2)) & 3;
	int c = o >= 2 ? 2 : (o ^ side);
	bool on = enable && o != 3 && isin[c];
	Want w; w.chip = on ? c : -1; w.model = on ? in[c].model : ((menu_ver >> side) & 1);
	return w;
}
static void bad (const char* what, int k, const char* fmt, long a = 0, long b = 0, long c = 0)
{
	++fails; if (fails > 40) return;
	printf ("  FAIL %s SID %d: ", what, k + 1); printf (fmt, a, b, c); printf ("\n");
}
// every register 0, and nothing left of what was played before: the envelopes run out (release 0: 6 ms), and the
// voices' outputs - which, with no waveform chosen, hold the last value they had - are left at the triangle's 0
static void silence (bool wait = false)
{
	for (int a = 0; a < 0x19; ++a) wr (a, 0);
	wr (0x04, 0x18); wr (0x0B, 0x18); wr (0x12, 0x18); run (wait ? 9000 : 8); wr (0x04, 0); wr (0x0B, 0); wr (0x12, 0);
}

static unsigned rs = 12345;
static unsigned rnd() { rs = rs * 1664525u + 1013904223u; return rs >> 8; }
static const char* label (const Want& w) { static char b[4][8]; static int i; i = (i + 1) & 3; if (w.chip < 0) snprintf (b[i], 8, "core%s", w.model ? "85" : "65"); else snprintf (b[i], 8, "%c", 'A' + w.chip); return b[i]; }

static void check (const char* title, int opt, int enable, int menu_ver, bool full)
{
	t->slot_opt = opt; t->enable = enable; t->menu_ver = menu_ver; t->menu_cfg = 0; t->fc_off_l = 0; t->fc_off_r = 0;
	Want w[8];
	printf ("%-34s", title);
	for (int k = 0; k < 8; ++k) { w[k] = want (k, opt, enable, menu_ver); printf (" %d:%-6s", k + 1, label (w[k])); }
	printf ("\n");
	long f0 = fails;

	// MODEL
	silence (true); wr (0x18, 0x0F); run (40);
	int r65 = t->aud[8], r85 = t->aud[9];
	if (r65 == r85) { ++fails; printf ("  FAIL: the two reference models sound alike silent\n"); }
	for (int k = 0; k < 8; ++k) { ++checks; if ((int)t->aud[k] != (w[k].model ? r85 : r65)) bad ("MODEL", k, "silent output %ld, a %ld wants %ld", t->aud[k], w[k].model ? 8580 : 6581, w[k].model ? r85 : r65); }

	// FILTER
	for (int i = 0; i < 48; ++i) {
		int fc = i == 0 ? 0 : i == 1 ? 0x7FF : i == 2 ? 0x400 : i == 3 ? 0x3FF : i < 12 ? (1 << (i - 4)) * 5 & 0x7FF : rnd() & 0x7FF;
		wr (0x15, fc & 7); wr (0x16, fc >> 3); run (3);
		for (int k = 0; k < 8; ++k) {
			++checks;
			int exp = w[k].chip >= 0 ? (in[w[k].chip].curve (fc >> 1) >> 1) : (int)t->f0[8 + w[k].model];
			if ((int)t->f0[k] != exp) bad ("FILTER", k, "Fc $%03lX: F0 %ld, wants %ld", fc, t->f0[k], exp);
		}
	}

	// WAVES
	static const int wave[4] = { 0x30, 0x50, 0x60, 0x70 };
	for (int wv = 0; wv < (full ? 4 : 1); ++wv) {
		silence();
		wr (0x10, 0x00); wr (0x11, 0x08);                   // pulse width $800
		wr (0x0E, 0x00); wr (0x0F, 0x10);                   // FREQ $1000: one position a microsecond
		wr (0x12, wave[wv] | 0x08); run (3);
		wr (0x12, wave[wv]);
		static uint8_t o[10][4200];
		for (int n = 0; n < 4200; ++n) { us(); for (int k = 0; k < 10; ++k) o[k][n] = t->osc3[k]; }
		for (int k = 0; k < 8; ++k) {
			++checks;
			if (w[k].chip == 0 || w[k].chip == 1) {
				const uint8_t* tb = &in[w[k].chip].d[wv * 4096];
				int best = -1, bl = 0;
				for (int lag = 0; lag < 8; ++lag) {
					int ok = 0;
					for (int p = 0; p < 4096; ++p) {
						if (wv && p <= 0x800) { ++ok; continue; }                               // pulse low (it rises a microsecond into $800): nothing of the table comes out
						int j = (wv == 1 && p >= 0x800) ? (0x800 | (~p & 0x7FF)) : p;           // no saw: the triangle's fold
						if (o[k][p + lag] == tb[j]) ++ok;
					}
					if (ok > best) { best = ok; bl = lag; }
				}
				if (best != 4096) bad ("WAVES", k, "wave $%02lX: %ld of 4096 positions are chip %ld's", wave[wv], best, w[k].chip);
				(void) bl;
			} else {
				int ok = 0; for (int n = 0; n < 4200; ++n) if (o[k][n] == o[8 + w[k].model][n]) ++ok;
				if (ok != 4200) bad ("WAVES", k, "wave $%02lX: %ld of 4200 samples are the core's own %ld", wave[wv], ok, w[k].model ? 8580 : 6581);
			}
		}
	}

	// SOUND
	if (full) {
		silence();
		wr (0x00, 0xD6); wr (0x01, 0x1C); wr (0x02, 0x00); wr (0x03, 0x08); wr (0x05, 0x00); wr (0x06, 0xF0);
		wr (0x15, 0); wr (0x16, 0x20); wr (0x17, 0x81); wr (0x18, 0x1F);
		wr (0x04, 0x31);                                   // S+T, gate on, through the low-pass
		run (12000);                                       // (12 ms of it first: the filters forget the chips they were before)
		const int N = 6000;
		static int a[10][N];
		for (int n = 0; n < N; ++n) {
			if ((n & 255) == 255) us (0x16, 0x20 + (n >> 8) * 9); else us();
			for (int k = 0; k < 10; ++k) a[k][n] = (int)(t->aud[k] << 14) >> 14;
		}
		// the filter is never reset, so two SIDs that were different chips a moment ago can still carry a few units of
		// that in their integrators (of the 18-bit output's 131072) after the 12 ms; two different chips are
		// thousands apart (measured: alike never more than 23 apart, different never less than 2760).
		// Alike: within 64 at every sample. Different: more than 1000 apart somewhere.
		auto apart = [&] (int x, int y) { int m = 0; for (int n = 0; n < N; ++n) { int d = abs (a[x][n] - a[y][n]); if (d > m) m = d; } return m; };
		for (int k = 0; k < 8; ++k) {
			if (w[k].chip < 0) { ++checks; int d = apart (k, 8 + w[k].model); if (d > worst_alike) worst_alike = d; if (d > 64) bad ("SOUND", k, "no chip, but %ld away from the reference %ld", d, w[k].model ? 8580 : 6581); }
			for (int j = k + 1; j < 8; ++j) {
				++checks;
				bool alike = w[k].chip == w[j].chip && w[k].model == w[j].model;
				int d = apart (k, j);
				if (alike) { if (d > worst_alike) worst_alike = d; if (d > 64) bad ("SOUND", k, "set as SID %ld but %ld apart", j + 1, d); }
				else       { if (d < least_diff) least_diff = d;   if (d < 1000) bad ("SOUND", k, "set differently from SID %ld but only %ld apart", j + 1, d); }
			}
		}
		printf ("    level (rms):");
		for (int k = 0; k < 10; ++k) { double s = 0, m = 0; for (int n = 1000; n < N; ++n) m += a[k][n]; m /= (N - 1000); for (int n = 1000; n < N; ++n) s += (a[k][n] - m) * (a[k][n] - m); printf (" %s%.0f", k == 8 ? "| ref65 " : k == 9 ? "ref85 " : "", sqrt (s / (N - 1000))); }
		printf ("\n");
	}
	if (fails != f0) printf ("  ^^ %ld mismatches\n", fails - f0);
}

int main (int argc, char** argv)
{
	if (argc < 5) { printf ("tb a.chp b.chp c.chp d.chp [random arrangements]\n"); return 2; }
	t = new Vtb_top;
	Chip f[4];
	for (int i = 0; i < 4; ++i) { f[i].d = rd (argv[1 + i]); if (f[i].d.size() != 18688) { printf ("%s: not a .CHP\n", argv[1 + i]); return 2; } f[i].model = f[i].d[0x4800] & 1; f[i].name = (const char*) &f[i].d[0x4810]; }
	int nrand = argc > 5 ? atoi (argv[5]) : 24;
	t->enable = 1; t->menu_ver = 2; run (64);

	// how different the chips are (so a pass means something)
	for (int i = 0; i < 4; ++i) for (int j = i + 1; j < 4; ++j) {
		int dc = 0, dw = 0; for (int n = 0; n < 1024; ++n) if ((f[i].curve (n) >> 1) != (f[j].curve (n) >> 1)) ++dc;
		for (int n = 0; n < 0x4000; ++n) if (f[i].d[n] != f[j].d[n]) ++dw;
		printf ("%s vs %s: %d of 1024 curve entries differ, %d of 16384 waveform bytes differ\n", f[i].name.c_str(), f[j].name.c_str(), dc, dw);
	}

	check ("nothing loaded",                0x0000, 1, 2, true);
	load (0, f[0]);
	check ("only A loaded",                 0x0000, 1, 1, true);
	load (1, f[1]); load (2, f[2]);
	check ("as before Fix 81 (all 0)",      0x0000, 1, 2, true);
	check ("My Chips Off",                  0x0000, 0, 1, true);
	check ("every SID chip A",              0x4444, 1, 2, true);     // odd 0 (A), even 1 (A)
	check ("every SID chip B",              0x1111, 1, 2, true);
	check ("every SID chip C",              0xAAAA, 1, 2, true);
	check ("every SID the core's own",      0xFFFF, 1, 1, true);
	check ("A B C core, twice",             0xE0E0 | 0x0000, 1, 2, true);  // SIDs 1-4: 0(A) 0(B) 2(C) 3(core)
	check ("eight different pairings",      0x1E4B, 1, 1, true);
	for (int i = 0; i < nrand; ++i) {
		char nm[40]; int opt = rnd() & 0xFFFF, mv = rnd() & 3, en = (rnd() % 8) != 0;
		snprintf (nm, sizeof (nm), "random %d ($%04X%s)", i + 1, opt, en ? "" : ", Off");
		check (nm, opt, en, mv, i < 4);
	}
	// another chip into A while B and C stay: the 8580 4687 replaces the 6581 5084
	load (0, f[3]);
	check ("A reloaded (4687), all 0",      0x0000, 1, 0, true);
	check ("A B C core, twice",             0xE0E0, 1, 1, true);
	load (2, f[0]);
	check ("C reloaded (5084)",             0x1E4B, 1, 2, true);

	// the menu's Fc offset (Adjustable filter) on both sides: a SID with a chip's curve takes none of it
	{
		int opt = 0xE0E0; t->slot_opt = opt; t->enable = 1; t->menu_ver = 0; t->fc_off_l = 0x600 - 0x100; t->fc_off_r = 0x600 - 0x180;
		long f0 = fails; int moved = 0;
		for (int i = 0; i < 24; ++i) {
			int fc = rnd() & 0x7FF; wr (0x15, fc & 7); wr (0x16, fc >> 3); run (3);
			for (int k = 0; k < 8; ++k) {
				Want w = want (k, opt, 1, 0); ++checks;
				if (w.chip >= 0) { int exp = in[w.chip].curve (fc >> 1) >> 1; if ((int)t->f0[k] != exp) bad ("FC OFFSET", k, "Fc $%03lX: F0 %ld, wants %ld", fc, t->f0[k], exp); }
				else if (t->f0[k] != t->f0[8]) ++moved;
			}
		}
		if (!moved) { ++fails; printf ("  FAIL: the Fc offset did nothing to the SIDs with no chip\n"); }
		printf ("%-34s chips' curves untouched; the core's own 6581s moved at %d of 48 readings%s\n", "Fc offset on (Adjustable)", moved, fails == f0 ? "" : "  ^^ mismatches");
		t->fc_off_l = 0; t->fc_off_r = 0;
	}

	printf ("SOUND: SIDs set alike were never more than %d apart, SIDs set differently never less than %d (of 131072)\n", worst_alike, least_diff);
	printf ("%ld checks, %ld mismatches\n", checks, fails);
	printf (fails ? "PERSLOT: FAIL\n" : "PERSLOT: PASS\n");
	return fails ? 1 : 0;
}
