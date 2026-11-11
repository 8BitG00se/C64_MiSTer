// C64RGB 256 (Fix 60) - the recolour unit's testbench          (c) 2026 Mong00se
// tb PACK TAGS OUT [palettes]: loads PACK through the ioctl port byte by byte (as Main does), then
// plays every frame of TAGS through it at the VIC's pace (a pixel every 4 clocks) for each palette,
// and writes what comes out to OUT (RGB24, frame by frame, palette by palette). Each pixel is read
// 3 and 4 clocks after it went in: both must be the same (steady until the next pixel's E3).
#include "Vrgb256.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>

static Vrgb256 *m;
static void tick() { m->clk = 0; m->eval(); m->clk = 1; m->eval(); }

static int load(const char *path)
{
	FILE *f = fopen(path, "rb"); if (!f) return 0;
	std::vector<uint8_t> d(0x3800); size_t n = fread(d.data(), 1, d.size(), f); fclose(f);
	m->ld_download = 1; tick();
	for (size_t a = 0; a < n; a++) {
		m->ld_addr = a; m->ld_data = d[a]; m->ld_wr = 1; tick(); m->ld_wr = 0; tick();
	}
	m->ld_download = 0; tick(); tick();
	return (int)n;
}

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);
	if (argc < 4) { fprintf(stderr, "tb PACK TAGS OUT [palettes]\n"); return 2; }
	m = new Vrgb256;
	m->clk = 0; m->ld_download = 0; m->ld_wr = 0; m->index = 0; m->tag = 0; m->palette = 0; m->eval();
	for (int i = 0; i < 4; i++) tick();
	// a bad pack first (wrong magic): it must not count as loaded
	{
		m->ld_download = 1; tick();
		for (int a = 0; a < 0x3800; a++) { m->ld_addr = a; m->ld_data = a < 8 ? 'X' : 0; m->ld_wr = 1; tick(); m->ld_wr = 0; tick(); }
		m->ld_download = 0; tick(); tick();
		if (m->loaded) { fprintf(stderr, "FAIL: a pack with the wrong magic was taken\n"); return 1; }
	}
	int n = load(argv[1]);
	if (!m->loaded) { fprintf(stderr, "FAIL: the pack (%d bytes) was not taken\n", n); return 1; }
	int npal = argc > 4 ? atoi(argv[4]) : m->npal;
	fprintf(stderr, "pack loaded: %d bytes, %d palettes\n", n, m->npal);

	FILE *tf = fopen(argv[2], "rb"); if (!tf) return 2;
	FILE *of = fopen(argv[3], "wb");
	long steady_bad = 0, px = 0;
	uint32_t hdr[4];
	while (fread(hdr, 4, 4, tf) == 4) {
		int w = hdr[1], h = hdr[2];
		std::vector<uint8_t> idx(w * h); std::vector<uint16_t> tag(w * h);
		if (fread(idx.data(), 1, w * h, tf) != (size_t)(w * h)) break;
		if (fread(tag.data(), 2, w * h, tf) != (size_t)(w * h)) break;
		std::vector<uint8_t> out(w * h * 3);
		for (int p = 0; p < npal; p++) {
			m->palette = p;
			for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
				int i = y * w + x, kind = tag[i] >> 8, code = tag[i] & 255, line = y + 16;
				m->index = idx[i];
				m->tag = ((uint32_t)kind << 27) | ((uint32_t)code << 19) | ((uint32_t)x << 9) | (uint32_t)line;
				tick(); tick(); tick();
				uint32_t a = m->rgb;
				tick();
				if (m->rgb != a) steady_bad++;
				out[3 * i] = a >> 16; out[3 * i + 1] = a >> 8; out[3 * i + 2] = a; px++;
			}
			fwrite(out.data(), 1, out.size(), of);
		}
	}
	fclose(tf); fclose(of);
	fprintf(stderr, "%ld pixels, %ld not steady for the pixel's 4th clock\n", px, steady_bad);
	delete m;
	return steady_bad ? 1 : 0;
}
