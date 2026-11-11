// Fix 48 checks (Verilator): the PLL mode writes, the 1541 / RTC enables, a fast-loader-style timed
// handshake, and C1530 tape pulse timing. Prints plain lines; check.py turns them into time and verdicts.
// (c) 2026 Mong00se
#include "Vtop.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>
#include <string>
#include <algorithm>

static Vtop* t;
static uint64_t ticks = 0;
static inline void tick() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); ticks++; }

struct Phase { const char* name; int ntsc, exact, osd; int expect; };

// The loader: drive polls the C64's sync line in a 7-cycle loop, then puts 4 bit-pairs out 6, 16, 26, 36
// drive cycles after it saw it; the C64 reads them 14, 24, 34, 44 of its cycles after it released the line.
static void loader(const char* name, const std::vector<uint64_t>& D)
{
	const int POLL = 7, W0 = 6, SP = 10, R0 = 14, PAIRS = 4;
	int64_t minb = 1 << 30, mina = 1 << 30, maxb = 0, maxa = 0; int n = 0, bad = 0;
	size_t j = 1000;
	for (int i = 0; i < 20000; i++) {
		uint64_t s = 32ull * (40000ull + (uint64_t)i * 401ull);    // the C64 releases the line (C64 cycle boundary)
		while (j < D.size() && D[j] < s) j++;
		while (j < D.size() && (j % POLL) != 0) j++;                // the next poll of the drive's loop
		if (j + W0 + SP * PAIRS + 2 >= D.size()) break;
		for (int k = 0; k < PAIRS; k++) {
			int64_t w  = (int64_t)D[j + W0 + SP * k];               // drive writes pair k
			int64_t w2 = (int64_t)D[j + W0 + SP * (k + 1)];         // ...and the next one
			int64_t r  = (int64_t)(s + 32ull * (R0 + SP * k));      // C64 reads pair k
			int64_t b = r - w, a = w2 - r;
			if (b <= 0 || a <= 0) bad++;
			minb = std::min(minb, b); mina = std::min(mina, a); maxb = std::max(maxb, b); maxa = std::max(maxa, a);
		}
		n++;
	}
	// margins in clk_sys ticks; check.py converts to C64 cycles and microseconds
	printf("LOADER %s transfers=%d bad=%d min_before=%lld min_after=%lld max_before=%lld max_after=%lld\n",
	       name, n, bad, (long long)minb, (long long)mina, (long long)maxb, (long long)maxa);
}

int main(int argc, char** argv)
{
	Verilated::commandArgs(argc, argv);
	t = new Vtop;
	t->ntsc_req = 0; t->exact_req = 0; t->osd_status = 0; t->restart_tape = 0; t->tap_wr = 0; t->cass_motor = 1;
	for (int i = 0; i < 10; i++) tick();

	// ---- A: the PLL mode block -----------------------------------------------------------------------
	Phase ph[] = {
		{"boot_exact",      0, 1, 0, 3},   // a fresh core: Exact is the default -> written once at start
		{"to_original",     0, 0, 0, 3},
		{"to_exact_osd",    0, 1, 1, 3},   // changed from the OSD: OSD closed first, then written
		{"to_ntsc",         1, 1, 0, 3},
		{"ntsc_exact_off",  1, 0, 0, 0},   // Exact means nothing on NTSC: no write, no reset
		{"to_original_pal", 0, 0, 0, 3},
	};
	for (auto& p : ph) {
		t->ntsc_req = p.ntsc; t->exact_req = p.exact; t->osd_status = p.osd;
		uint64_t start = ticks, first = 0, osdt = 0; int nw = 0; uint32_t k = 0; int a0 = 0, a2 = 0;
		for (uint64_t i = 0; i < 9000000; i++) {
			tick();
			if (t->close_osd) osdt++;
			if (t->cfg_write) {
				if (!nw) first = ticks - start;
				nw++;
				if (t->cfg_address == 7) k = t->cfg_data;
				if (t->cfg_address == 0) a0++;
				if (t->cfg_address == 2) a2++;
			}
		}
		t->osd_status = 0;
		printf("PLL %s writes=%d expect=%d addr0=%d addr2=%d K=%u first_write_ticks=%llu close_osd_ticks=%llu ntsc_r=%d exact_r=%d\n",
		       p.name, nw, p.expect, a0, a2, k, (unsigned long long)first, (unsigned long long)osdt, t->ntsc_r, t->exact_r);
	}

	// ---- B: the drive / RTC enables -------------------------------------------------------------------
	const uint64_t T = 62899200ull;                  // 2.000 s of Exact-mode clk_sys
	uint64_t dc[3] = {0, 0, 0}, rc[3] = {0, 0, 0}, mism = 0;
	std::vector<uint64_t> Dorig, Dexact, Dunslowed;  // drive 6502 cycles (every 16th 16 MHz enable), in ticks
	uint64_t b0 = ticks;
	for (uint64_t i = 0; i < T; i++) {
		tick();
		uint64_t at = ticks - b0;
		for (int m = 0; m < 3; m++) {
			if ((t->drive_ce >> m) & 1) dc[m]++;
			if ((t->rtc_ce >> m) & 1) rc[m]++;
		}
		if (((t->drive_ce >> 0) & 1) != ((t->drive_ce >> 1) & 1)) mism++;
		if ((t->drive_ce & 1) && (dc[0] % 16) == 0) Dorig.push_back(at);
		if ((t->drive_ce & 2) && (dc[1] % 16) == 0) Dexact.push_back(at);
		if ((t->rtc_ce & 2) && (rc[1] % 16) == 0) Dunslowed.push_back(at);   // a drive NOT slowed (real 1 MHz)
	}
	printf("ENABLES ticks=%llu drive_orig=%llu drive_exact=%llu drive_ntsc=%llu rtc_orig=%llu rtc_exact=%llu rtc_ntsc=%llu drive_pattern_mismatch=%llu\n",
	       (unsigned long long)T, (unsigned long long)dc[0], (unsigned long long)dc[1], (unsigned long long)dc[2],
	       (unsigned long long)rc[0], (unsigned long long)rc[1], (unsigned long long)rc[2], (unsigned long long)mism);
	loader("original", Dorig);
	loader("exact", Dexact);
	loader("exact_drive_not_slowed", Dunslowed);

	// ---- C: tape (TAP v1) --------------------------------------------------------------------------
	const uint8_t seq[3] = {0x30, 0x42, 0x56};    // short / medium / long pulses, as the KERNAL writes them
	std::vector<uint8_t> tap;
	const char* hdr = "C64-TAPE-RAW";
	for (int i = 0; i < 12; i++) tap.push_back(hdr[i]);
	tap.push_back(1); tap.push_back(0); tap.push_back(0); tap.push_back(0);
	tap.push_back(0); tap.push_back(0x10); tap.push_back(0); tap.push_back(0);
	for (int i = 0; i < 300; i++) tap.push_back(seq[i % 3]);
	t->restart_tape = 1; tick(); tick(); t->restart_tape = 0;
	t->cass_motor = 0;
	size_t wp = 0; int old = t->cass_read; uint64_t lastf = 0; std::vector<uint64_t> iv; long errat = -1;
	for (uint64_t i = 0; i < 60000000ull && iv.size() < 240; i++) {
		t->tap_wr = 0;
		if (wp < tap.size() && !t->tap_full) { t->tap_in = tap[wp++]; t->tap_wr = 1; }
		tick();
		t->tap_wr = 0;
		int cr = t->cass_read;
		if (t->tap_err && errat < 0) errat = (long)iv.size();
		if (old && !cr) { if (lastf) iv.push_back(ticks - lastf); lastf = ticks; }
		old = cr;
	}
	// find the phase of the byte sequence, then check every pulse
	int best = -1;
	for (int o = 0; o < 3; o++) {
		bool ok = iv.size() > 30;
		for (size_t i = 10; i < iv.size() - 5 && ok; i++) if (iv[i] != 256ull * seq[(i + o) % 3]) ok = false;
		if (ok) best = o;
	}
	int mis = -1;
	if (best < 0 && iv.size() > 12) {   // the phase from pulse 10, then the first pulse that is off
		for (int o = 0; o < 3; o++) if (iv[10] == 256ull * seq[(10 + o) % 3]) { for (size_t i = 10; i < iv.size(); i++) if (iv[i] != 256ull * seq[(i + o) % 3]) { mis = (int)i; break; } }
	}
	printf("TAPE pulses=%zu err=%d err_at_pulse=%ld first_mismatch=%d match=%s", iv.size(), t->tap_err, errat, mis, best >= 0 ? "yes" : "no");
	for (int i = 0; i < 3 && best >= 0; i++) {
		for (size_t x = 10; x < iv.size(); x++) if (seq[(x + best) % 3] == seq[i]) { printf(" 0x%02X=%llu", seq[i], (unsigned long long)iv[x]); break; }
	}
	if (best < 0) { printf(" first:"); for (size_t i = 0; i < iv.size() && i < 12; i++) printf(" %llu", (unsigned long long)iv[i]);
		if (mis > 0) { printf(" around_mismatch:"); for (int i = std::max(0, mis - 3); i < (int)iv.size() && i < mis + 3; i++) printf(" %llu", (unsigned long long)iv[i]); } }
	printf("\n");

	delete t;
	return 0;
}
