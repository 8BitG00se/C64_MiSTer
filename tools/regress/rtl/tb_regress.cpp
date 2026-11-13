// OCTOPHONIC 64 - OLD-SOFTWARE REGRESSION TEST (Fix 69): the whole-C64 Verilator part.     (c) 2026 Mong00se
//
// The real core's C64 (GHDL's Verilog of rtl/fpga64_sid_iec.vhd, built as sim/rewind builds it: the 6510, the
// VIC-II, the bus logic, the real CIAs, the SDRAM model; NO OctoVIC and no SID sound in this sim) boots the
// Octophonic KERNAL from rom.hex, and optionally runs one stock-C64 program: at frame INJECT its bytes go into
// RAM where it loads, and RUN (or SYS) is typed into the keyboard buffer, as a LOAD and RUN would leave it.
//
//   tb_regress FRAMES OUT [PRG] [INJECT]
//     OUT.txt : one line a frame: "F frame crc32-of-the-picture crc32-of-the-SID-registers SID-write-clocks"
//               (the picture: the VIC's colour index of every pixel of the raster, 512 x 320, as sim/rewind)
//     OUT.bin : every frame's picture (512 x 320 bytes), for the side-by-side of the first changed frame
// The same binary runs the last core's RTL and the new core's (each built from its own tree): compare_rtl.py
// compares the two OUT folders.
#include "Vtb_top.h"
#include "Vtb_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <string>

static Vtb_top *top;
static const int FW = 512, FH = 320;
static uint8_t fb[FH][FW];
static int fx = 0, fy = 0, vframe = 0;
static bool phb = false, pvb = false;
static FILE *fbin = nullptr, *ftxt = nullptr;
static uint64_t sid_clocks = 0;

#define ROOT    (top->rootp)
#define SDRAM   (ROOT->tb_top__DOT__sdram)
#define SIDREGS (ROOT->tb_top__DOT__c64__DOT__sid__DOT__regs)

static uint32_t crc_tab[256];
static void crc_init() { for (uint32_t i = 0; i < 256; i++) { uint32_t c = i; for (int k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320u ^ (c >> 1) : c >> 1; crc_tab[i] = c; } }
static uint32_t crc32(const uint8_t *p, size_t n) { uint32_t c = 0xFFFFFFFFu; while (n--) c = crc_tab[(c ^ *p++) & 255] ^ (c >> 8); return c ^ 0xFFFFFFFFu; }

static void frame_done() {
	uint8_t s[64]; for (int i = 0; i < 64; i++) s[i] = SIDREGS[i];
	fprintf(ftxt, "F %d %08x %08x %llu\n", vframe, crc32(&fb[0][0], sizeof fb), crc32(s, 64), (unsigned long long)sid_clocks);
	if (fbin) fwrite(fb, 1, sizeof fb, fbin);
	sid_clocks = 0;
}

static void tick() {
	top->ddr_stall = 0;
	top->clk = 0; top->eval();
	top->clk = 1; top->eval();
	if (top->sid_wr) sid_clocks++;
	if (top->pix_en) {
		bool hb = top->hblank, vb = top->vblank;
		if (vb && !pvb) { frame_done(); memset(fb, 0x80, sizeof fb); fy = 0; vframe++; }
		if (hb && !phb) { fx = 0; if (fy < FH - 1) fy++; }
		else if (fx < FW) fb[fy][fx++] = (top->index & 15) | (hb || vb ? 0x80 : 0);
		phb = hb; pvb = vb;
	}
}
static void run_frames(int n) { int e = vframe + n; while (vframe < e) tick(); }

static void poke(int a, int v) { SDRAM[a & 0xFFFF] = v & 0xFF; }
static void type(const char *s) { int n = 0; for (; s[n]; n++) poke(0x0277 + n, s[n]); poke(0xC6, n); }

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	setvbuf(stdout, nullptr, _IOLBF, 0);
	if (argc < 3) { printf("usage: tb_regress FRAMES OUT [PRG] [INJECT]\n"); return 2; }
	crc_init();
	int frames = atoi(argv[1]);
	std::string out = argv[2];
	const char *prg = argc > 3 && argv[3][0] ? argv[3] : nullptr;
	int inject = argc > 4 ? atoi(argv[4]) : 180;
	ftxt = fopen((out + ".txt").c_str(), "w");
	fbin = fopen((out + ".bin").c_str(), "wb");
	fprintf(ftxt, "# Octophonic 64 RTL regression run (c) 2026 Mong00se: frames %d, program %s, injected at frame %d\n", frames, prg ? prg : "(none: the KERNAL alone)", inject);
	std::vector<uint8_t> p;
	if (prg) { FILE *f = fopen(prg, "rb"); if (!f) { printf("FAIL no program %s\n", prg); return 2; } int c; while ((c = fgetc(f)) != EOF) p.push_back(c); fclose(f); }
	top = new Vtb_top;
	top->enable = 1; top->hold = 0; top->block = 0; top->joyA = 0; top->joyB = 0; top->bios = 0; top->ddr_lat = 60;
	top->cart_on = 0; top->cart_loading = 0; top->cart_bank_wr = 0;
	top->reset_n = 0;
	for (int i = 0; i < 2000; i++) tick();
	top->reset_n = 1;
	if (prg && p.size() > 2) {
		run_frames(inject);
		int at = p[0] | (p[1] << 8), end = at + (int)p.size() - 2;
		for (size_t i = 2; i < p.size(); i++) poke(at + (int)i - 2, p[i]);
		if (at == 0x0801) {
			for (int z : {0x2D, 0x2F, 0x31, 0xAE}) { poke(z, end & 255); poke(z + 1, end >> 8); }
			type("RUN\r");
		} else {
			char s[16]; snprintf(s, sizeof s, "SYS%d\r", at); type(s);
		}
		printf("INFO frame %d: %zu bytes put at $%04X-$%04X, %s typed\n", vframe, p.size() - 2, at, end - 1, at == 0x0801 ? "RUN" : "SYS");
	}
	run_frames(frames - vframe);
	// READY. on the screen? (only a note: a program may have cleared it)
	static const uint8_t rdy[6] = {18, 5, 1, 4, 25, 46};
	int found = -1;
	for (int i = 0; i < 1000 - 6 && found < 0; i++) { bool m = true; for (int k = 0; k < 6; k++) if (SDRAM[0x0400 + i + k] != rdy[k]) m = false; if (m) found = i; }
	printf("INFO %d frames; READY. on the screen: %s; the 6510 at $%04X\n", vframe, found >= 0 ? "yes" : "no", (unsigned)(top->cpu_o[0] & 0xFFFF));
	fclose(ftxt); fclose(fbin);
	top->final();
	printf("RTL_REGRESS_RUN_DONE\n");
	return 0;
}
