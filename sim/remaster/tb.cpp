// LEVEL 2 REMASTER (Build 14) - the unit's testbench                              (c) 2026 Mong00se
// tb PACK FRAMES.l2f OUT.rgb [palette] [on 1/0] [learn 1/0] [DDR3 latency] [busy %] [LEARNOUT]
// The pack goes into the DDR3 model whole (as Main copies it) and its first $3800 bytes through the loader;
// each frame of the .l2f is played as the VIC would give it (504 x 312 pixels, 4 clocks each: colour, tag,
// the graphics layer, the cells, the sprites' starts and state); the picture comes out 16 lines later and is
// written to OUT (RGB24, the frame's W x H). Each pixel is read on its 7th and 8th clock: both must agree.
#include "Vtb_rm.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <vector>
#include <deque>

static Vtb_rm *m;
static const uint32_t PACK = 0x06800000, LEARN = 0x06C00000;
static std::vector<uint64_t> ddr_pack(4 << 20), ddr_learn(1 << 20);   // 32 MB and 8 MB of words
static uint8_t ram[65536];
static int lat = 12, busy_pct = 0;
static unsigned long clocks = 0, ddr_reads = 0, ddr_words = 0, ddr_writes = 0;
static uint32_t rnd_s = 12345;
static uint32_t rnd() { rnd_s = rnd_s * 1664525u + 1013904223u; return rnd_s >> 8; }

static uint64_t *word(uint32_t a)
{
	static uint64_t dummy;
	if (a >= PACK && a < PACK + ddr_pack.size()) return &ddr_pack[a - PACK];
	if (a >= LEARN && a < LEARN + ddr_learn.size()) return &ddr_learn[a - LEARN];
	fprintf(stderr, "DDR3: address %08x outside the pack and the log\n", a); dummy = 0; return &dummy;
}

struct Beat { unsigned long at; uint64_t d; };
static std::deque<Beat> beats;
static bool xq_pend = false; static uint8_t xq_val = 0;

static void tick()
{
	// the DDR3: a request is taken when not busy; its words come back lat clocks later, one a clock
	m->ddr_busy = (busy_pct && (int)(rnd() % 100) < busy_pct) ? 1 : 0;
	m->ddr_ready = 0;
	if (!beats.empty() && beats.front().at <= clocks) { m->ddr_ready = 1; m->ddr_dout = beats.front().d; beats.pop_front(); }
	m->x_ack = m->x_req && (rnd() % 4 != 0);
	m->clk = 0; m->eval();
	bool rd = m->ddr_rd && !m->ddr_busy, we = m->ddr_we && !m->ddr_busy;
	uint32_t a = m->ddr_addr; int n = m->ddr_burstcnt; uint64_t din = m->ddr_din;
	bool xr = m->x_req && m->x_ack; uint16_t xa = m->x_addr;
	m->clk = 1; m->eval();
	if (xr) m->x_q = ram[xa];
	if (rd) {
		unsigned long t = clocks + lat + (busy_pct ? rnd() % 40 : 0);
		if (!beats.empty() && beats.back().at >= t) t = beats.back().at + 1;
		for (int i = 0; i < n; i++) beats.push_back({ t + i, *word(a + i) });
		ddr_reads++; ddr_words += n;
	}
	if (we) { *word(a) = din; ddr_writes++; }
	clocks++;
}

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);
	if (argc < 4) { fprintf(stderr, "tb PACK FRAMES OUT [palette] [on] [learn] [latency] [busy%%] [LEARNOUT]\n"); return 2; }
	int pal = argc > 4 ? atoi(argv[4]) : 0, on = argc > 5 ? atoi(argv[5]) : 1, learn = argc > 6 ? atoi(argv[6]) : 0;
	if (argc > 7) lat = atoi(argv[7]);
	if (argc > 8) busy_pct = atoi(argv[8]);
	m = new Vtb_rm;
	FILE *pf = fopen(argv[1], "rb"); if (!pf) return 2;
	std::vector<uint8_t> pack(ddr_pack.size() * 8);
	size_t pn = fread(pack.data(), 1, pack.size(), pf); fclose(pf);
	memcpy(ddr_pack.data(), pack.data(), (pn + 7) & ~7);
	ddr_learn[0] = 0;

	m->reset = 1; m->on = on; m->learn = learn; m->palette = pal;
	for (int i = 0; i < 8; i++) tick();
	m->reset = 0;
	// Level 1 through the loader, then "a pack has gone in"
	m->ld_download = 1; tick();
	for (int a = 0; a < 0x3800; a++) { m->ld_addr = a; m->ld_data = pack[a]; m->ld_wr = 1; tick(); m->ld_wr = 0; tick(); }
	m->ld_download = 0; tick(); tick();
	m->reload = 1; tick(); m->reload = 0;
	for (int i = 0; i < 3000 && !m->l2_ok; i++) tick();
	fprintf(stderr, "pack: %zu bytes, Level 1 %s, Level 2 %s\n", pn, m->loaded ? "in" : "NOT in", m->l2_ok ? "found" : "not found");
	if (!m->loaded) return 1;

	FILE *tf = fopen(argv[2], "rb"); if (!tf) return 2;
	FILE *of = fopen(argv[3], "wb");
	const int LW = 504, LH = 312, DELAY = 16;
	struct Frame { int w, h, line0; std::vector<uint8_t> idx, gfx, cell, code, spr, ram; std::vector<uint16_t> tag; };
	std::vector<Frame> fr;
	uint32_t hdr[8];
	while (fread(hdr, 4, 8, tf) == 8) {
		Frame f; f.w = hdr[2]; f.h = hdr[3]; f.line0 = hdr[4]; int n = f.w * f.h;
		f.idx.resize(n); f.tag.resize(n); f.gfx.resize(n); f.cell.resize(n); f.code.resize(n); f.spr.resize(96 * f.h); f.ram.resize(65536);
		if (fread(f.idx.data(), 1, n, tf) != (size_t)n || fread(f.tag.data(), 2, n, tf) != (size_t)n || fread(f.gfx.data(), 1, n, tf) != (size_t)n ||
		    fread(f.cell.data(), 1, n, tf) != (size_t)n || fread(f.code.data(), 1, n, tf) != (size_t)n ||
		    fread(f.spr.data(), 1, 96 * f.h, tf) != (size_t)(96 * f.h) || fread(f.ram.data(), 1, 65536, tf) != 65536) break;
		fr.push_back(f);
	}
	fclose(tf);
	int nf = fr.size();
	std::vector<std::vector<uint8_t>> out(nf);
	for (int i = 0; i < nf; i++) out[i].assign(fr[i].w * fr[i].h * 3, 0);
	long steady_bad = 0, vs_bad = 0;
	// one more (blank) frame at the end pushes the last one out of the ring
	for (int fi = 0; fi <= nf; fi++) {
		const Frame *f = fi < nf ? &fr[fi] : nullptr;
		if (f) memcpy(ram, f->ram.data(), 65536);
		for (int line = 0; line < LH; line++) {
			int y = f ? line - f->line0 : -1;
			bool inl = f && y >= 0 && y < f->h;
			// the sprites' state for this line
			VlWide<6> &sp = m->l2_spr;
			for (int i = 0; i < 6; i++) sp[i] = 0;
			int sx[8]; uint32_t bank = 0;
			for (int n = 0; n < 8; n++) {
				sx[n] = -1;
				if (!inl) continue;
				const uint8_t *r = &f->spr[(y * 8 + n) * 12];
				if (!(r[0] & 1)) continue;
				int X = r[2] | (r[3] << 8), addr = r[8] | (r[9] << 8);
				sx[n] = X + 8;
				uint64_t rec = (uint64_t)(3 * r[1] + 3) | ((uint64_t)((r[0] >> 1) & 1) << 6) | ((uint64_t)((r[0] >> 2) & 1) << 7) |
				               ((uint64_t)((r[0] >> 3) & 1) << 8) | ((uint64_t)(r[4] & 15) << 9) | ((uint64_t)((addr >> 6) & 255) << 13);
				int b = n * 22;
				for (int k = 0; k < 22; k++) if ((rec >> k) & 1) sp[(b + k) / 32] |= 1u << ((b + k) % 32);
				for (int k = 0; k < 4; k++) { if ((r[5] >> k) & 1) sp[(176 + k) / 32] |= 1u << ((176 + k) % 32); if ((r[6] >> k) & 1) sp[(180 + k) / 32] |= 1u << ((180 + k) % 32); }
				bank = addr >> 14;          // (one bank for the line: the frames' sprites share it in practice; the last one's counts)
			}
			for (int x = 0; x < LW; x++) {
				bool in = inl && x < f->w;
				int i = in ? y * f->w + x : 0;
				int kind = in ? f->tag[i] >> 8 : 3, code = in ? f->tag[i] & 255 : 0;
				m->index = in ? f->idx[i] & 15 : 0;
				m->tag = ((uint32_t)kind << 27) | ((uint32_t)code << 19) | ((uint32_t)x << 9) | (uint32_t)line;
				uint32_t p = 0;
				if (in) {
					p = (f->gfx[i] & 15) | (((f->gfx[i] >> 4) & 1) << 4);
					if (f->cell[i] != 0xFF) {
						if ((f->cell[i] & 7) == 0) p |= 1 << 5;
						p |= 1 << 6;
						p |= (uint32_t)((f->cell[i] >> 3) & 7) << 7;
						p |= (uint32_t)f->code[i] << 18;
					}
				}
				for (int n = 0; n < 8; n++) if (sx[n] == x) {
					p |= 1u << (10 + n);
					// (a sprite's bank is the VIC's at its start)
					bank = (f->spr[(y * 8 + n) * 12 + 8] | (f->spr[(y * 8 + n) * 12 + 9] << 8)) >> 14;
				}
				m->l2_pix = p;
				m->bank = bank;
				m->vsync_in = line < 3;
				tick();
				if (getenv("RM_DBG") && fi == atoi(getenv("RM_DBG")) && line == 51 + DELAY && x >= 30 && x < 60) fprintf(stderr, "x %d: index %d tag kind %d code %02x x %d y %d\n", x, m->dbg_index, m->dbg_tag >> 27, (m->dbg_tag >> 19) & 255, (m->dbg_tag >> 9) & 1023, m->dbg_tag & 511);
				tick();
				if (getenv("RM_DBG") && fi == atoi(getenv("RM_DBG")) && line == 51 + DELAY && x >= 30 && x < 60) fprintf(stderr, "      ovr %d slot %02x\n", m->dbg_ovr, m->dbg_slot);
				tick();
				// the pixel that left the ring one pixel ago: (frame, line - 16, x - 1)
				uint32_t a = m->rgb; int vs = m->d_vsync;
				tick();
				if (m->rgb != a) steady_bad++;
				int ox = x - 1, oline = line - DELAY, ofi = fi;
				if (ox < 0) { ox += LW; oline--; }
				if (oline < 0) { oline += LH; ofi--; }
				if (ofi >= 0 && ofi < nf) {
					if (vs != (oline < 3) && (ofi || oline || ox)) {   // (not the very first pixel: nothing was before it)
						 if (!vs_bad) fprintf(stderr, "sync: frame %d line %d x %d: %d\n", ofi, oline, ox, vs); vs_bad++; }
					int oy = oline - fr[ofi].line0;
					if (oy >= 0 && oy < fr[ofi].h && ox < fr[ofi].w) {
						uint8_t *o = &out[ofi][(oy * fr[ofi].w + ox) * 3];
						o[0] = a >> 16; o[1] = a >> 8; o[2] = a;
					}
				}
			}
		}
	}
	for (int i = 0; i < nf; i++) fwrite(out[i].data(), 1, out[i].size(), of);
	fclose(of);
	fprintf(stderr, "%d frames, %lu clocks; DDR3: %lu reads (%lu words), %lu writes; learned %d; %ld pixels not steady, %ld sync errors\n",
	        nf, clocks, ddr_reads, ddr_words, ddr_writes, (int)m->lcount, steady_bad, vs_bad);
	if (argc > 9) {
		FILE *lf = fopen(argv[9], "wb");
		uint32_t cnt = ddr_learn[0] >> 32;
		fwrite(ddr_learn.data(), 8, 1 + (size_t)cnt * 10, lf); fclose(lf);
	}
	delete m;
	return (steady_bad || vs_bad) ? 1 : 0;
}
