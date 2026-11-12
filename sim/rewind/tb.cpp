// REWIND simulation (sim/rewind): the whole C64 with the rewind unit.            (c) 2026 Mong00se
//
//   tb game  <frames.bin>   the test game (rwgame.asm): record, rewind, play on, rewind to the oldest
//                           frame, drop the history. After every rewind step the machine is compared
//                           with a copy taken when that frame's save state was made: all 64K of RAM,
//                           the colour RAM, every flip-flop of the 6510 and both CIAs, the SID registers.
//   tb boot  <frames.bin>   the Octophonic KERNAL to READY. without OctoVIC, then a rewind on the BASIC screen
//   tb cart  <frames.bin> <stall %> <game.crt> [frames to play] [frames to rewind]
//                           a real game from its cartridge file (your own - none is kept in the repo):
//                           played with a scripted joystick, rewound, played on; every step compared
//
// The picture (the VIC's colour index and the on-screen REWIND, every pixel of the raster) goes to
// frames.bin, 512 x 320 bytes a frame, for mkclip.py.
#include "Vtb_top.h"
#include "Vtb_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <deque>
#include <vector>
#include <string>

static Vtb_top *top;
static uint64_t clocks = 0;
static const int FW = 512, FH = 320;
static uint8_t fb[FH][FW];   // (bit 7: blanking, or never drawn)
static int fx = 0, fy = 0, vframe = 0;
static bool phb = false, pvb = false;
static FILE *fvid = nullptr;
static bool vid_on = false;
static int fails = 0, checks = 0;

struct Snap {
	std::vector<uint8_t> ram;
	uint8_t  col[1024];
	uint8_t  sid[64];
	uint32_t cpu[6], c1[10], c2[10];
	int      vf;
};
static std::deque<Snap> gold;

#define ROOT (top->rootp)
#define RAMCOPY (ROOT->tb_top__DOT__rw__DOT__ram__DOT__m)
#define COLRAM  (ROOT->tb_top__DOT__c64__DOT__colorram__DOT__ram)
#define SIDREGS (ROOT->tb_top__DOT__c64__DOT__sid__DOT__regs)
#define SDRAM   (ROOT->tb_top__DOT__sdram)

static void snap(Snap &s) {
	s.ram.resize(65536);
	for (int i = 0; i < 65536; i++) s.ram[i] = RAMCOPY[i];
	for (int i = 0; i < 1024; i++) s.col[i] = COLRAM[i] & 15;
	for (int i = 0; i < 64; i++) s.sid[i] = SIDREGS[i];
	for (int i = 0; i < 6; i++) s.cpu[i] = top->cpu_o[i];
	for (int i = 0; i < 10; i++) { s.c1[i] = top->cia1_o[i]; s.c2[i] = top->cia2_o[i]; }
	s.vf = vframe;
}

// the CIA bits that run on by themselves while the 6510 is held: the TOD's divider and digits (192-221)
static uint32_t ciamask(int w) { return w == 6 ? 0xC0000000u : 0xFFFFFFFFu; }

static int diffbits(const uint32_t *a, const uint32_t *b, int n, bool cia) {
	int d = 0;
	for (int i = 0; i < n; i++) d += __builtin_popcount((a[i] ^ b[i]) & (cia ? ciamask(i) : 0xFFFFFFFFu));
	return d;
}

static bool compare(const Snap &g, const char *what, bool quiet = false) {
	Snap n; snap(n);
	int dr = 0, first = -1;
	for (int i = 0; i < 65536; i++) if (n.ram[i] != g.ram[i]) { if (first < 0) first = i; dr++; }
	int dc = 0; for (int i = 0; i < 1024; i++) if (n.col[i] != g.col[i]) dc++;
	int ds = 0; for (int i = 0; i < 64; i++) if ((i & 31) < 25 && n.sid[i] != g.sid[i]) ds++;
	int dp = diffbits(n.cpu, g.cpu, 6, false), d1 = diffbits(n.c1, g.c1, 10, true), d2 = diffbits(n.c2, g.c2, 10, true);
	bool ok = !dr && !dc && !ds && !dp && !d1 && !d2;
	checks++;
	if (!ok) fails++;
	if (!ok || !quiet)
		printf("%s %s: frame of %d: RAM %d differ%s, colour RAM %d, SID regs %d, 6510 bits %d, CIA1 bits %d, CIA2 bits %d  PC=%04X FRAME=%02X%02X\n",
		       ok ? "OK  " : "FAIL", what, g.vf, dr, "", dc, ds, dp, d1, d2, n.cpu[0] & 0xFFFF, n.ram[3], n.ram[2]);
	if (dr && first >= 0) printf("     first RAM difference at $%04X: is %02X, was %02X\n", first, n.ram[first], g.ram[first]);
	if (dp) { printf("     6510 now "); for (int i = 5; i >= 0; i--) printf("%08X ", n.cpu[i]); printf("\n     6510 was "); for (int i = 5; i >= 0; i--) printf("%08X ", g.cpu[i]); printf("\n"); }
	if (d1) { printf("     CIA1 now "); for (int i = 9; i >= 0; i--) printf("%08X ", n.c1[i]); printf("\n     CIA1 was "); for (int i = 9; i >= 0; i--) printf("%08X ", g.c1[i]); printf("\n"); }
	if (d2) { printf("     CIA2 now "); for (int i = 9; i >= 0; i--) printf("%08X ", n.c2[i]); printf("\n     CIA2 was "); for (int i = 9; i >= 0; i--) printf("%08X ", g.c2[i]); printf("\n"); }
	return ok;
}

// statistics
static uint64_t t_freeze = 0;
static int frames_before = 0, steps = 0;
static uint64_t fr_min = ~0ull, fr_max = 0, fr_sum = 0;
static int max_fifo = 0;
static bool p_freeze = false, p_seq = false, p_err = false;
static int ry_unfreeze_max = 0;
static uint32_t lfsr = 0x1234567;
static int stall_pct = 0;
static bool quiet_steps = false;
static int sid_wr_in_step = 0;

namespace rm { extern bool on; void sample(); }   // Build 14 (below): the remaster run's recorder
static void tick() {
	// the DDR3 held off at random
	lfsr = (lfsr >> 1) ^ (-(lfsr & 1u) & 0xD0000001u);
	top->ddr_stall = ((int)(lfsr % 100) < stall_pct);
	top->clk = 0; top->eval();
	top->clk = 1; top->eval();
	clocks++;
	if (rm::on) rm::sample();

	if (top->fifo_cnt > max_fifo) max_fifo = top->fifo_cnt;
	if (top->err && !p_err) { printf("FAIL the rewind unit's error flag came on (clock %llu)\n", (unsigned long long)clocks); fails++; }
	p_err = top->err;

	// a save state is being made: the copy to compare with, later
	if (top->seq_on && !p_seq) {
		gold.emplace_back(); snap(gold.back());
		if (gold.size() > 4000) gold.pop_front();
	}
	p_seq = top->seq_on;

	if (top->freeze && !p_freeze) { t_freeze = clocks; frames_before = top->frames; sid_wr_in_step = 0; }
	if (top->freeze && top->sid_wr) sid_wr_in_step++;
	if (!top->freeze && p_freeze) {
		uint64_t d = clocks - t_freeze;
		if (d < fr_min) fr_min = d;
		if (d > fr_max) fr_max = d;
		fr_sum += d; steps++;
		if (top->ry > ry_unfreeze_max && top->ry >= 256) ry_unfreeze_max = top->ry;
		if (frames_before >= 2 && gold.size() >= 2) gold.pop_back();
		if (gold.empty()) { printf("FAIL a rewind step with no save state known\n"); fails++; }
		else {
			char w[96];
			snprintf(w, sizeof w, "step %d (held %.0f us, to line %d, %d left, %d SID writes)", steps, d / 31.4496, (int)top->ry, (int)top->frames, sid_wr_in_step);
			compare(gold.back(), w, quiet_steps);
		}
	}
	p_freeze = top->freeze;

	// the picture
	if (top->pix_en) {
		bool hb = top->hblank, vb = top->vblank;
		if (vb && !pvb) {
			if (fvid && vid_on) fwrite(fb, 1, sizeof fb, fvid);
			memset(fb, 0x80, sizeof fb);
			fy = 0; vframe++;
		}
		if (hb && !phb) { fx = 0; if (fy < FH - 1) fy++; }
		else if (fx < FW) fb[fy][fx++] = (top->index & 15) | (top->osd << 4) | (hb || vb ? 0x80 : 0);
		phb = hb; pvb = vb;
	}
}

// ---------------------------------------------------------------- Build 14: the remaster unit behind the real VIC
// tb remaster OUT stall [PACK] [first frame] [frames]: the test game runs; from the first frame on, what the VIC gives
// the remaster unit is written as OUT.l2f (the format of docs/RGB256.md, made from the VIC's own signals) and the
// picture after the remaster and recolour units as OUT.rgb (the same W x H). sim/remaster/full.sh checks them.
#define DDRP (ROOT->tb_top__DOT__ddrp)
#define DDRL (ROOT->tb_top__DOT__ddrl)
namespace rm {
	const int W = 396, H = 284, L0 = 16;
	struct Fr { std::vector<uint8_t> idx, gfx, cell, code, spr, ram, out; std::vector<uint16_t> tag; int fno; bool in_done = false, out_done = false; };
	std::deque<Fr> frs;
	bool on = false; int first = 0, count = 0, fno = -1;
	int px = -1, line_abs = 0, ccol = -1, cbit = 8;
	struct Ln { int fno, ry; } hist[64];
	bool sfirst[8];
	struct Due { uint64_t at; int fno, ry, x; };
	std::deque<Due> due;
	FILE *fl = nullptr, *fo = nullptr;
	Fr *find(int f) { for (auto &r : frs) if (r.fno == f) return &r; return nullptr; }
	void flush() {
		while (!frs.empty() && frs.front().in_done && frs.front().out_done) {
			Fr &r = frs.front();
			uint32_t h[8] = { 0x3146324C, (uint32_t)r.fno, W, H, L0, 32, 0, 0 };
			fwrite(h, 4, 8, fl); fwrite(r.idx.data(), 1, W * H, fl); fwrite(r.tag.data(), 2, W * H, fl);
			fwrite(r.gfx.data(), 1, W * H, fl); fwrite(r.cell.data(), 1, W * H, fl); fwrite(r.code.data(), 1, W * H, fl);
			fwrite(r.spr.data(), 1, 96 * H, fl); fwrite(r.ram.data(), 1, 65536, fl);
			fwrite(r.out.data(), 1, W * H * 3, fo);
			frs.pop_front();
		}
	}
	void sample() {
		while (!due.empty() && due.front().at <= clocks) {
			Due &q = due.front();
			Fr *r = find(q.fno);
			int y = q.ry - L0;
			if (r && y >= 0 && y < H && q.x < W) { uint32_t c = top->o_rgb; uint8_t *o = &r->out[(y * W + q.x) * 3]; o[0] = c >> 16; o[1] = c >> 8; o[2] = c; }
			if (r && q.ry == L0 + H && q.x == 0) { r->out_done = true; flush(); }
			due.pop_front();
		}
		uint32_t tag = top->v_tag; int x = (tag >> 9) & 1023, ry = tag & 511;
		if (x == px) return;
		px = x;
		uint32_t p = top->v_l2pix;
		if (x == 0) {
			line_abs++;
			if (ry == 0) {
				fno++;
				for (int n = 0; n < 8; n++) sfirst[n] = true;
				if (on && fno >= first && fno < first + count) {
					frs.emplace_back(); Fr &r = frs.back(); r.fno = fno;
					r.idx.assign(W * H, 0); r.tag.assign(W * H, 3 << 8); r.gfx.assign(W * H, 0); r.cell.assign(W * H, 0xFF); r.code.assign(W * H, 0);
					r.spr.assign(96 * H, 0); r.ram.resize(65536); r.out.assign(W * H * 3, 0);
				}
			}
			hist[line_abs & 63] = { fno, ry };
			ccol = -1; cbit = 8;
		}
		// the pixel that left the ring: 16 lines back, one pixel back; its colour is out 3 clocks from now
		{
			int la = line_abs - 16, ox = x - 1;
			if (ox < 0) { ox = 503; la--; }
			if (la > 0) due.push_back({ clocks + 3, hist[la & 63].fno, hist[la & 63].ry, ox });
		}
		Fr *r = find(fno);
		if (!r || r->in_done) return;
		int y = ry - L0;
		bool cs = (p >> 5) & 1, cv = (p >> 6) & 1;
		if (cs && cv) { ccol++; cbit = 0; } else if (cbit < 8) cbit++;
		if (ry == L0 + H && x == 0) { for (int i = 0; i < 65536; i++) r->ram[i] = RAMCOPY[i]; r->in_done = true; flush(); return; }
		if (y < 0 || y >= H) return;
		for (int n = 0; n < 8; n++) if ((p >> (10 + n)) & 1) {
			const VlWide<6> &sp = top->v_l2spr;
			auto bits = [&](int lo, int w) { uint32_t v = 0; for (int k = 0; k < w; k++) if (sp[(lo + k) / 32] & (1u << ((lo + k) % 32))) v |= 1u << k; return v; };
			int mc = bits(n * 22, 6), row = mc / 3 - 1, X = x - 8, addr = (top->v_bank << 14) | (bits(n * 22 + 13, 8) << 6);
			bool first = (mc == 3) && sfirst[n];
			if (mc == 3) { if (first) sfirst[n] = false; } else sfirst[n] = true;
			uint8_t *s = &r->spr[(y * 8 + n) * 12];
			s[0] = 1 | (bits(n * 22 + 6, 1) << 1) | (bits(n * 22 + 7, 1) << 2) | (bits(n * 22 + 8, 1) << 3) | (first ? 16 : 0);
			s[1] = row; s[2] = X & 255; s[3] = (X >> 8) & 255; s[4] = bits(n * 22 + 9, 4); s[5] = bits(176, 4); s[6] = bits(180, 4);
			s[8] = addr & 255; s[9] = addr >> 8;
		}
		if (x >= W) return;
		int i = y * W + x, kind = tag >> 27;
		r->idx[i] = top->index & 15;
		r->tag[i] = (kind << 8) | ((tag >> 19) & 255);
		r->gfx[i] = p & 31;
		if (ccol >= 0 && ccol < 40 && cbit < 8) { r->cell[i] = (((p >> 7) & 7) << 3) | cbit; r->code[i] = (p >> 18) & 255; }
	}
}

static void run_clocks(uint64_t n);
static bool load_pack(const char *path) {     // the pack: the whole file into the DDR3, its first $3800 bytes through the loader
	FILE *f = fopen(path, "rb");
	if (!f) { printf("FAIL no pack %s\n", path); return false; }
	std::vector<uint8_t> d(4 << 20); size_t n = fread(d.data(), 1, d.size(), f); fclose(f);
	for (size_t i = 0; i < (n + 7) / 8; i++) { uint64_t w = 0; for (int k = 7; k >= 0; k--) w = (w << 8) | d[i * 8 + k]; DDRP[i] = w; }
	top->ld_download = 1; run_clocks(2);
	for (int a = 0; a < 0x3800; a++) { top->ld_addr = a; top->ld_data = d[a]; top->ld_wr = 1; run_clocks(1); top->ld_wr = 0; run_clocks(1); }
	top->ld_download = 0; run_clocks(2);
	top->rm_reload = 1; run_clocks(1); top->rm_reload = 0;
	run_clocks(4000);
	printf("INFO pack %s: %zu bytes, Level 2 %s\n", path, n, top->rm_ok ? "found" : "NOT found");
	return true;
}

static bool joy_script = false;
static void joy() {     // fire now and then, a direction that changes: enough to get a game going and moving
	if (!joy_script) return;
	int f = vframe;
	int v = 0;
	if ((f % 50) < 6) v |= 0x10;                       // fire
	static const int dirs[8] = {0, 8, 8, 1, 4, 4, 2, 0};   // (bits: 0 up, 1 down, 2 left, 3 right, 4 fire)
	if (f > 300) v |= dirs[(f / 25) & 7];
	top->joyA = v; top->joyB = v;
}
static void run_frames(int n) { int e = vframe + n; while (vframe < e) { joy(); tick(); } }
static void run_clocks(uint64_t n) { while (n--) tick(); }

static int peek16(int a) { return RAMCOPY[a] | (RAMCOPY[a + 1] << 8); }

static void stats(const char *what) {
	if (steps) printf("INFO %s: %d steps, the 6510 held %.0f / %.0f / %.0f us (least / mean / most), back on by raster line %d, FIFO at most %d of 256\n",
	                  what, steps, fr_min / 31.4496, fr_sum / 31.4496 / steps, fr_max / 31.4496, ry_unfreeze_max, max_fifo);
	steps = 0; fr_min = ~0ull; fr_max = 0; fr_sum = 0; ry_unfreeze_max = 0;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	setvbuf(stdout, nullptr, _IOLBF, 0);
	std::string mode = argc > 1 ? argv[1] : "game";
	if (argc > 2) fvid = fopen(argv[2], "wb");
	if (argc > 3) stall_pct = atoi(argv[3]);
	top = new Vtb_top;
	top->enable = 1; top->hold = 0; top->block = 0; top->joyA = 0; top->joyB = 0; top->bios = 0; top->ddr_lat = 60;
	top->cart_on = 0; top->cart_loading = 0; top->cart_bank_wr = 0;
	top->reset_n = 0;
	run_clocks(2000);
	if (mode == "cart" && argc > 4) {
		// the .CRT as c64.sv loads it: the header's type and lines, each CHIP packet's bank, its data into the SDRAM from $200000
		FILE *f = fopen(argv[4], "rb");
		if (!f) { printf("FAIL no cartridge file %s\n", argv[4]); return 2; }
		std::vector<uint8_t> d(1 << 21);
		size_t n = fread(d.data(), 1, d.size(), f); fclose(f);
		top->cart_id = d[0x17]; top->cart_exrom = d[0x18] & 1; top->cart_game = d[0x19] & 1;
		top->cart_loading = 1; run_clocks(8);
		size_t o = 0x40; uint32_t at = 0x200000; int chips = 0;
		while (o + 16 <= n) {
			uint32_t len = (d[o + 4] << 24) | (d[o + 5] << 16) | (d[o + 6] << 8) | d[o + 7];
			uint32_t size = (d[o + 14] << 8) | d[o + 15];
			top->cart_bank_num = d[o + 11]; top->cart_bank_hi = d[o + 12] > 0x80; top->cart_bank_16k = d[o + 14] > 0x20;
			top->cart_bank_addr = (at >> 13) & 255;
			top->cart_bank_wr = 1; run_clocks(1); top->cart_bank_wr = 0; run_clocks(2);
			for (uint32_t i = 0; i < size && o + 16 + i < n; i++) SDRAM[at + i] = d[o + 16 + i];
			at += size; o += len; chips++;
		}
		top->cart_loading = 0; top->cart_on = 1;
		printf("INFO cartridge: type %d, %d CHIP packets, %u bytes\n", (int)top->cart_id, chips, at - 0x200000);
		run_clocks(2000);
	}
	top->reset_n = 1;
	// Build 14: RM_PACK=<pack>: the remaster unit at work (tiles and sprite frames from the DDR3, sprite data from
	// the 64K copy) while the rewind tests run - the two share the DDR3 port and the copy's read port
	for (int i = 0; i < (1 << 15); i++) DDRL[i] = 0;
	for (int i = 0; i < (1 << 19); i++) DDRP[i] = 0;
	if (mode != "remaster" && getenv("RM_PACK")) { top->rm_on = 1; top->rm_learn = 1; if (!load_pack(getenv("RM_PACK"))) return 2; }

	if (mode == "remaster") {
		// (see rm above) the pack: its first $3800 bytes through the loader, the whole file into the DDR3; none: no Level 2
		std::string o = argc > 2 ? argv[2] : "rm";
		if (fvid) { fclose(fvid); fvid = nullptr; remove(argv[2]); }
		rm::fl = fopen((o + ".l2f").c_str(), "wb"); rm::fo = fopen((o + ".rgb").c_str(), "wb");
		rm::first = argc > 5 ? atoi(argv[5]) : 60; rm::count = argc > 6 ? atoi(argv[6]) : 3;
		top->rm_on = 1; top->rm_learn = argc > 7 ? atoi(argv[7]) : 0; top->palette = 0;
		if (argc > 4 && argv[4][0] && !load_pack(argv[4])) return 2;
		rm::on = true;
		while (rm::fno < rm::first + rm::count + 1) tick();
		run_clocks(40000);
		fclose(rm::fl); fclose(rm::fo);
		printf("INFO remaster: frames %d-%d written to %s.l2f / .rgb; learned %d; %llu clocks\n", rm::first, rm::first + rm::count - 1, o.c_str(), (int)top->rm_lcount, (unsigned long long)clocks);
		printf("REMASTER_FULL_RUN_DONE\n");
		top->final();
		return 0;
	}

	if (mode == "boot") {
		// the Octophonic KERNAL with no OctoVIC in the core: it must come up as on a stock VIC-II
		run_frames(150);
		vid_on = true;
		run_frames(20);
		// READY. on the screen? (screen codes 18 5 1 4 25 46)
		int scr = 0x0400, found = -1;
		static const uint8_t rdy[6] = {18, 5, 1, 4, 25, 46};
		for (int i = 0; i < 1000 - 6 && found < 0; i++) { bool m = true; for (int k = 0; k < 6; k++) if (RAMCOPY[scr + i + k] != rdy[k]) m = false; if (m) found = i; }
		printf("%s the Octophonic KERNAL reaches READY. without OctoVIC (found at row %d), %zu save states so far\n", found >= 0 ? "OK  " : "FAIL", found / 40, gold.size());
		checks++; if (found < 0) fails++;
		printf("     screen rows 0-7:\n");
		for (int r = 0; r < 8; r++) { printf("     |"); for (int c = 0; c < 40; c++) { int ch = RAMCOPY[scr + r * 40 + c] & 0x7F; putchar(ch == 32 ? ' ' : ch < 27 ? '@' + ch : ch < 64 ? ch : '.'); } printf("|\n"); }
		// a rewind on the BASIC screen (the cursor blinks, the jiffy clock runs)
		int j0 = RAMCOPY[0xA2] | (RAMCOPY[0xA1] << 8);
		top->hold = 1; run_frames(40); top->hold = 0;
		int j1 = RAMCOPY[0xA2] | (RAMCOPY[0xA1] << 8);
		printf("%s the jiffy clock went back while rewinding: %d -> %d\n", j1 < j0 ? "OK  " : "FAIL", j0, j1);
		checks++; if (!(j1 < j0)) fails++;
		run_frames(30);
		int j2 = RAMCOPY[0xA2] | (RAMCOPY[0xA1] << 8);
		printf("%s and runs on after: %d -> %d\n", j2 > j1 + 20 ? "OK  " : "FAIL", j1, j2);
		checks++; if (!(j2 > j1 + 20)) fails++;
		stats("boot");
	}
	else if (mode == "cart") {
		int play = argc > 5 ? atoi(argv[5]) : 700, back = argc > 6 ? atoi(argv[6]) : 150;
		joy_script = true; quiet_steps = true;
		// the last 150 frames of play, the rewind and the play after it go to the clip
		run_frames(play - 150);
		vid_on = true;
		run_frames(150);
		printf("INFO played %d frames: %d save states (history since frame %d)\n", vframe, (int)top->frames, vframe - (int)top->frames);
		int had = top->frames;
		top->hold = 1; run_frames(back); top->hold = 0;
		while (top->freeze) tick();
		bool okb = steps >= (had < back ? had - 2 : back - 2);
		printf("%s rewound for %d frames: %d steps, %d save states left\n", okb ? "OK  " : "FAIL", back, steps, (int)top->frames);
		checks++; if (!okb) fails++;
		stats("the game");
		uint32_t a0 = 0; for (int i = 0; i < 65536; i++) a0 = a0 * 31 + RAMCOPY[i];
		run_frames(200);
		uint32_t a1 = 0; for (int i = 0; i < 65536; i++) a1 = a1 * 31 + RAMCOPY[i];
		printf("%s played on 200 frames: %d save states again, the game's memory keeps changing: %s, 6510 at $%04X\n", (a0 != a1 && top->frames > 150) ? "OK  " : "FAIL", (int)top->frames, a0 != a1 ? "yes" : "NO", (unsigned)(top->cpu_o[0] & 0xFFFF));
		checks++; if (!(a0 != a1 && top->frames > 150)) fails++;
	}
	else {
		vid_on = true;
		// A: play
		run_frames(80);
		int na = RAMCOPY[0xFB], ca = RAMCOPY[0xFC];
		run_frames(40);
		int nmis_a = (RAMCOPY[0xFB] - na) & 255, cias_a = (RAMCOPY[0xFC] - ca) & 255;
		int f_a = peek16(2);
		printf("INFO A: played 120 frames: game frame %d, %d save states, CIA1 irqs $%02X, NMIs $%02X\n", f_a, (int)top->frames, RAMCOPY[0xFC], RAMCOPY[0xFB]);
		// B: rewind 60 frames (or as far as the save states held go, with a small stack)
		int had = top->frames, want = had > 60 ? 60 : had - 1;
		top->hold = 1; run_frames(60); top->hold = 0;
		while (top->freeze) tick();
		int f_b = peek16(2);
		bool okb = f_a - f_b >= want - 1 && f_a - f_b <= want + 1;
		printf("%s B: 60 frames of rewind with %d save states held: game frame %d -> %d\n", okb ? "OK  " : "FAIL", had, f_a, f_b);
		checks++; if (!okb) fails++;
		stats("B");
		// C: play on
		uint32_t cnt0 = RAMCOPY[0xF8] | (RAMCOPY[0xF9] << 8) | (RAMCOPY[0xFA] << 16);
		int n0 = RAMCOPY[0xFB], c0 = RAMCOPY[0xFC];
		run_frames(40);
		int f_c = peek16(2);
		uint32_t cnt1 = RAMCOPY[0xF8] | (RAMCOPY[0xF9] << 8) | (RAMCOPY[0xFA] << 16);
		int nmis = (RAMCOPY[0xFB] - n0) & 255, cias = (RAMCOPY[0xFC] - c0) & 255;
		bool okc = (f_c - f_b >= 39 && f_c - f_b <= 41) && cnt1 != cnt0;
		printf("%s C: played on 40 frames: game frame %d -> %d, the main loop ran %u times\n", okc ? "OK  " : "FAIL", f_b, f_c, (cnt1 - cnt0) & 0xFFFFFF);
		checks++; if (!okc) fails++;
		// 40 frames = 786240 cycles: the CIA 2 NMI every 777 -> 1011 or 1012 (mod 256: 243, 244); the CIA 1 interrupt
		// (every 1000, some lost while the frame's work holds interrupts off) as in the 40 frames before the rewind
		bool okt = abs(((cias - cias_a + 128) & 255) - 128) <= 3 && abs(((nmis - nmis_a + 128) & 255) - 128) <= 2 && abs(((nmis - 243 + 128) & 255) - 128) <= 2;
		printf("%s C: the timers keep their pace after the rewind: CIA1 interrupts +%d (before: +%d), CIA2 NMIs +%d (before: +%d; 243-244 expected), mod 256\n", okt ? "OK  " : "FAIL", cias, cias_a, nmis, nmis_a);
		checks++; if (!okt) fails++;
		// D: rewind to the oldest save state and stay there
		quiet_steps = true;
		top->hold = 1;
		int guard = 0;
		while (top->frames > 1 && guard++ < 400) run_frames(1);
		int f_d = peek16(2);
		printf("%s D: rewound to the oldest save state: %d left, game frame %d\n", top->frames == 1 ? "OK  " : "FAIL", (int)top->frames, f_d);
		checks++; if (top->frames != 1) fails++;
		quiet_steps = false;
		run_frames(8);
		while (top->freeze) tick();
		int f_d2 = peek16(2);
		printf("%s D: held there 8 more frames: game frame %d (stands still)\n", abs(f_d2 - f_d) <= 1 ? "OK  " : "FAIL", f_d2);
		checks++; if (abs(f_d2 - f_d) > 1) fails++;
		top->hold = 0;
		stats("D");
		// E: play on from there
		run_frames(25);
		int f_e = peek16(2);
		printf("%s E: played on 25 frames: game frame %d -> %d, %d save states\n", (f_e - f_d2 >= 24 && f_e - f_d2 <= 26) ? "OK  " : "FAIL", f_d2, f_e, (int)top->frames);
		checks++; if (!(f_e - f_d2 >= 24 && f_e - f_d2 <= 26)) fails++;
		// F: the history dropped (drive busy / a file loading), no rewind then; recording starts again after
		top->block = 1; run_clocks(2000); top->block = 0;
		bool okf = top->frames == 0;
		run_clocks(100);
		top->hold = 1; top->block = 1;
		uint64_t c0f = clocks; bool froze = false;
		while (clocks < c0f + 3 * 630000ull) { tick(); if (top->freeze) froze = true; }
		top->block = 0; top->hold = 0;
		printf("%s F: history dropped while blocked (0 save states: %s), no freeze with the key held: %s\n", (okf && !froze) ? "OK  " : "FAIL", okf ? "yes" : "NO", froze ? "FROZE" : "yes");
		checks++; if (!(okf && !froze)) fails++;
		gold.clear();
		run_frames(12);
		int f_f = peek16(2);
		top->hold = 1; run_frames(6); top->hold = 0;
		while (top->freeze) tick();
		int f_g = peek16(2);
		printf("%s F: recording again afterwards: %d save states, rewind %d -> %d\n", f_g < f_f ? "OK  " : "FAIL", (int)top->frames, f_f, f_g);
		checks++; if (!(f_g < f_f)) fails++;
		stats("F");
		run_frames(10);
	}
	if (fvid) fclose(fvid);
	if (getenv("RM_PACK")) printf("INFO the remaster unit ran beside: Level 2 %s, %d keys learned\n", top->rm_ok ? "on" : "OFF", (int)top->rm_lcount);
	printf("%s: %d checks, %d failed, %llu clocks, %d frames\n", fails ? "REWIND_SIM_FAILED" : "REWIND_SIM_OK", checks, fails, (unsigned long long)clocks, vframe);
	top->final();
	return fails ? 1 : 0;
}
