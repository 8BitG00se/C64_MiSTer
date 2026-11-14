// (c) 2026 Mong00se
// FAST LOAD (Fix 49) simulation (Verilator): the Octophonic KERNAL comes up, LOAD"*",8,1 is put into the
// keyboard buffer, and the file comes off the disk in the 1541 - through the real ROM bank, CIAs, VIAs
// and drive logic. The memory loaded is compared with the file, and the time taken is printed.
//   tb fast|slow|noport file.prg [more seconds]
//     fast    the menu's Fast loader On (the default)       slow    Fast loader Off
//     noport  Fast loader On, Parallel port Disabled (must load the slow way)
#include "Vtb_top.h"
#include "Vtb_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>

static Vtb_top *top;
static uint64_t clocks = 0;
static const double HZ = 31449600.0;          // clk_sys with Exact 50 Hz
#define RAM (top->rootp->tb_top__DOT__sdram)

static uint64_t bank_clocks = 0, bank_ons = 0, stb_c64 = 0, stb_drv = 0, clk_edges = 0, access_clocks = 0;
static bool p_bank = false, p_sc = true, p_sd = true, p_clk = true;
static int max_track = 0, min_track = 127;

static void tick() {
	top->clk = 0; top->eval();
	top->clk = 1; top->eval();
	clocks++;
	if (top->fl_bank) bank_clocks++;
	if (top->fl_bank && !p_bank) bank_ons++;
	p_bank = top->fl_bank;
	if (!top->stb_c64 && p_sc) stb_c64++;
	if (!top->stb_drv && p_sd) stb_drv++;
	p_sc = top->stb_c64; p_sd = top->stb_drv;
	if (top->clk_line != p_clk) clk_edges++;
	p_clk = top->clk_line;
	if (top->disk_access) access_clocks++;
}
static void run(double s) { uint64_t e = clocks + (uint64_t)(s * HZ); while (clocks < e) tick(); }

static void screen(int rows) {
	for (int r = 0; r < rows; r++) {
		printf("     |");
		for (int c = 0; c < 40; c++) { int ch = RAM[0x400 + r * 40 + c] & 0x7F; putchar(ch == 32 ? ' ' : ch < 27 ? '@' + ch : ch < 64 ? ch : '.'); }
		printf("|\n");
	}
}
static bool onscreen(const char *t) {
	int n = 0; while (t[n]) n++;
	for (int i = 0; i + n <= 1000; i++) {
		bool m = true;
		for (int k = 0; k < n && m; k++) { int ch = RAM[0x400 + i + k] & 0x7F, w = t[k]; if (w >= 'A' && w <= 'Z') w -= 64; if (ch != w) m = false; }
		if (m) return true;
	}
	return false;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	setvbuf(stdout, nullptr, _IOLBF, 0);
	std::string mode = argc > 1 ? argv[1] : "fast";
	std::vector<uint8_t> prg;
	{ FILE *f = argc > 2 ? fopen(argv[2], "rb") : nullptr; if (!f) { printf("FAIL no file to compare with\n"); return 2; }
	  int c; while ((c = fgetc(f)) != EOF) prg.push_back((uint8_t)c); fclose(f); }
	double limit = argc > 3 ? atof(argv[3]) : 40.0;
	int fails = 0;
	top = new Vtb_top;
	top->fl_en = (mode != "slow"); top->parport = (mode != "noport"); top->img_mount = 0;
	top->reset_n = 0;
	for (int i = 0; i < 4000; i++) tick();
	top->reset_n = 1;
	run(0.05);
	top->img_mount = 1; for (int i = 0; i < 64; i++) tick(); top->img_mount = 0;      // the disk goes in
	run(3.2);                                                                        // the KERNAL's start
	bool ready = onscreen("READY.");
	printf("%s %s: the Octophonic KERNAL reaches READY. (%.2f s); drive 8 %s the fast loader\n", ready ? "OK  " : "FAIL", mode.c_str(), clocks / HZ, top->fast_ok ? "can take" : "cannot take");
	if (!ready) { screen(8); return 1; }
	if (!top->fast_ok) { printf("FAIL the drive is not up on the standard ROM with its parallel port\n"); fails++; }
	// LOAD"*",8,1 and RETURN into the keyboard buffer: L, shifted O (LOAD's short form), "*",8,1
	static const uint8_t keys[10] = {0x4C, 0xCF, 0x22, 0x2A, 0x22, 0x2C, 0x38, 0x2C, 0x31, 0x0D};
	for (int i = 0; i < 10; i++) RAM[0x277 + i] = keys[i];
	RAM[0xC6] = 10;
	bank_clocks = bank_ons = stb_c64 = stb_drv = clk_edges = access_clocks = 0;
	uint64_t t0 = clocks, t_search = 0, t_loading = 0, t_done = 0;
	bool second = false;
	while ((clocks - t0) / HZ < limit) {
		for (int i = 0; i < 20000; i++) tick();
		if (top->track > max_track) max_track = top->track;
		if (top->track < min_track) min_track = top->track;
		if (!t_search && onscreen("SEARCHING")) t_search = clocks;
		if (!t_loading && onscreen("LOADING")) t_loading = clocks;
		if (t_search && onscreen("ERROR")) break;
		// back at READY.: the second one on the screen, the cursor flashing again ($CC 0), nothing left to type
		if (t_search && RAM[0xCC] == 0 && RAM[0xC6] == 0) {
			int n = 0; for (int i = 0; i + 6 <= 1000; i++) { static const uint8_t r[6] = {18, 5, 1, 4, 25, 46}; bool m = true; for (int k = 0; k < 6; k++) if ((RAM[0x400 + i + k] & 0x7F) != r[k]) m = false; n += m; }
			if (n >= 2) { t_done = clocks; break; }
		}
	}
	double secs = (t_done ? t_done - t0 : clocks - t0) / HZ;
	screen(9);
	if (!t_done) { printf("FAIL %s: the load did not come back to READY. in %.1f s\n", mode.c_str(), secs); fails++; }
	// the memory against the file, the end address the KERNAL reports, its status
	int at = prg[0] | prg[1] << 8, n = (int)prg.size() - 2, wrong = 0, first = -1;
	for (int i = 0; i < n; i++) if (RAM[(at + i) & 0xFFFF] != prg[2 + i]) { if (first < 0) first = i; wrong++; }
	int end = RAM[0xAE] | RAM[0xAF] << 8;
	bool okm = wrong == 0, oke = end == ((at + n) & 0xFFFF), oks = RAM[0x90] == 0x40;
	printf("%s %s: %d bytes at $%04X: %d wrong%s\n", okm ? "OK  " : "FAIL", mode.c_str(), n, at, wrong, wrong ? "" : " - the file is in memory as it is on the disk");
	if (first >= 0) printf("     first wrong byte at $%04X: is %02X, should be %02X\n", at + first, RAM[at + first], prg[2 + first]);
	printf("%s %s: end address $%04X (should be $%04X), ST $%02X (should be $40)\n", (oke && oks) ? "OK  " : "FAIL", mode.c_str(), end, (at + n) & 0xFFFF, RAM[0x90]);
	fails += !okm + !(oke && oks);
	bool want_fast = (mode == "fast");
	bool went_fast = bank_ons > 0 && stb_c64 > (uint64_t)n / 2;
	printf("%s %s: the loader's bank came in %llu time(s) for %.3f s and is %s now; %llu strobes to the drive, %llu changes of CLK; heads on half-tracks %d-%d\n",
	       (went_fast == want_fast && !top->fl_bank) ? "OK  " : "FAIL", mode.c_str(), (unsigned long long)bank_ons, bank_clocks / HZ, top->fl_bank ? "IN" : "out",
	       (unsigned long long)stb_c64, (unsigned long long)clk_edges, min_track, max_track);
	fails += !(went_fast == want_fast && !top->fl_bank);
	int blocks = (n + 2 + 253) / 254;
	printf("TIME %s %d blocks: %.2f s from RETURN to READY. (SEARCHING at %.2f s, LOADING at %.2f s): %.1f blocks a second over the whole load\n",
	       mode.c_str(), blocks, secs, t_search ? (t_search - t0) / HZ : -1.0, t_loading ? (t_loading - t0) / HZ : -1.0, blocks / secs);
	printf("%s\n", fails ? "FASTLOAD_RUN_FAILED" : "FASTLOAD_RUN_OK");
	top->final();
	return fails ? 1 : 0;
}
