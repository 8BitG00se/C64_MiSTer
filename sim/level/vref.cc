// vref - "stock VICE x64sc" sound for a recorded SID write log (.sidw from the Octophonic emulator).
// Each SID is VICE's own engine library with VICE 3.10's default settings (reSID: resampling,
// passband 90%, gain 97%, bias 500 mV; reSID-fp: SINC resampling, curve/range 0.5, CAPS470,
// combined AVERAGE), PAL clock, 48 kHz. Stereo as VICE does with N SIDs: odd SIDs left, even
// right, summed with sound_audio_mix(); one SID = both sides.
//   vref ENGINE(resid|residfp) MODEL(6581|8580) NSIDS in.sidw out.pcm SECONDS
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>
#include "resid/sid.h"
#include "SID.h"

static inline int16_t mix(int ch1, int ch2)
{
    if (ch1 == 0) return (int16_t)ch2;
    if (ch2 == 0) return (int16_t)ch1;
    if ((ch1 > 0 && ch2 < 0) || (ch1 < 0 && ch2 > 0)) return (int16_t)(ch1 + ch2);
    if (ch1 > 0) return (int16_t)((ch1 + ch2) - (ch1 * ch2 / 32768));
    return (int16_t)-((-(ch1) + -(ch2)) - (-(ch1) * -(ch2) / 32768));
}

int main(int argc, char **argv)
{
    if (argc < 7) { fprintf(stderr, "usage\n"); return 1; }
    const bool fp = !strcmp(argv[1], "residfp");
    const bool m8580 = !strcmp(argv[2], "8580");
    const int ns = atoi(argv[3]);
    const double secs = atof(argv[6]);
    const double clk = 985248.0; const int rate = 48000;
    std::vector<reSID::SID *> r(8); std::vector<reSIDfp::SID *> f(8);
    for (int i = 0; i < 8; i++) {
        if (!fp) {
            r[i] = new reSID::SID();
            r[i]->set_chip_model(m8580 ? reSID::MOS8580 : reSID::MOS6581);
            r[i]->set_voice_mask(0x07); r[i]->input(0);
            r[i]->enable_filter(true);
            r[i]->adjust_filter_bias(m8580 ? 0.0 : 0.5);
            r[i]->enable_external_filter(true);
            r[i]->set_sampling_parameters(clk, reSID::SAMPLE_RESAMPLE, rate, rate * 90 / 200.0, 0.97);
        } else {
            f[i] = new reSIDfp::SID();
            f[i]->setChipModel(m8580 ? reSIDfp::CSG8580 : reSIDfp::MOS6581);
            f[i]->input(0);
            if (m8580) f[i]->setFilter6581Curve(0.5); else { f[i]->setFilter6581Curve(0.5); f[i]->setFilter6581Range(0.5); }
            f[i]->enableFilter(true);
            f[i]->set6581caps(reSIDfp::CAPS470);
            f[i]->setCombinedWaveforms(reSIDfp::AVERAGE);
            f[i]->setSamplingParameters(clk, reSIDfp::RESAMPLE, rate);
        }
    }
    FILE *in = fopen(argv[4], "rb"); FILE *out = fopen(argv[5], "wb");
    if (!in || !out) return 2;
    struct W { uint64_t cyc; int chip, reg; uint8_t v; };
    std::vector<W> w; uint8_t rec[9];
    while (fread(rec, 1, 9, in) == 9) {
        uint32_t fr = rec[0] | rec[1] << 8 | rec[2] << 16 | (uint32_t)rec[3] << 24;
        uint16_t ln = rec[4] | rec[5] << 8, a = rec[6] | rec[7] << 8;
        const int tgt = (a >> 7 & 1) << 2 | (a >> 8 & 1) << 1 | (a >> 5 & 1);
        w.push_back({ (uint64_t)fr * 19656 + (uint64_t)ln * 63, tgt, a & 0x1F, rec[8] });
    }
    const uint64_t total = (uint64_t)(secs * clk);
    size_t wi = 0; uint64_t now = 0;
    std::vector<int16_t> buf[8];
    const int CH = 1000;   // cycles per step
    while (now < total) {
        uint64_t end = now + CH;
        // writes up to end: clock to each write, then write
        while (true) {
            uint64_t t = (wi < w.size() && w[wi].cyc < end) ? w[wi].cyc : end;
            int dt0 = (int)(t - now);
            if (dt0 > 0) {
                for (int i = 0; i < ns; i++) {
                    int16_t tmp[4096];
                    int n;
                    if (!fp) { reSID::cycle_count dt = dt0; n = r[i]->clock(dt, tmp, 4096); }
                    else n = f[i]->clock((unsigned)dt0, tmp);
                    buf[i].insert(buf[i].end(), tmp, tmp + n);
                }
                now = t;
            }
            if (t == end) break;
            if (w[wi].chip < ns) { if (!fp) r[w[wi].chip]->write(w[wi].reg, w[wi].v); else f[w[wi].chip]->write(w[wi].reg, w[wi].v); }
            wi++;
        }
        size_t n = buf[0].size();
        for (int i = 1; i < ns; i++) if (buf[i].size() < n) n = buf[i].size();
        for (size_t k = 0; k < n; k++) {
            int16_t L, R;
            if (ns == 1) L = R = buf[0][k];
            else {
                L = buf[0][k]; R = buf[1][k];
                for (int i = 2; i + 1 < ns + 1; i += 2) { L = mix(L, buf[i][k]); if (i + 1 < ns) R = mix(R, buf[i + 1][k]); }
            }
            int16_t lr[2] = { L, R }; fwrite(lr, 2, 2, out);
        }
        for (int i = 0; i < ns; i++) buf[i].erase(buf[i].begin(), buf[i].begin() + n);
    }
    fclose(out);
    return 0;
}
