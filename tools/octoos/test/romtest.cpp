// romtest: the Octophonic V1.1 ROM against the stock Commodore ROMs, side by side.
// Every case runs on a fresh machine with each ROM set (a real 1541 with a test disk on the bus,
// and for the V1.1 ROM a model of Octophonic Main's mailbox serving a test folder). After each
// step the screen and BASIC's memory are compared; cases marked OCTO check what the V1.1 ROM
// must do differently (start screen, tape gone, @ / and F1). Keys go through the keyboard matrix
// exactly as a person types them. The SAME cases start with a RUN in both (the start screen's
// 24-row editor then gives way to the stock one, as for every program): from there every BASIC,
// editor and disk case must match stock; the start screen's own editor is checked by OCTO cases.
//   romtest stockroms octoroms drive.rom test.d64 folder shell.prg [case-filter]
#include "C64Machine.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <strings.h>
#include <fstream>
#include <vector>
#include <string>
#include <algorithm>
#include <functional>
#include <dirent.h>
#include <sys/stat.h>
#include <memory>
#include <map>

static std::vector<uint8_t> rd (const std::string& p) { std::ifstream f (p, std::ios::binary); return std::vector<uint8_t> ((std::istreambuf_iterator<char> (f)), {}); }

// ------------------------------------------------------------------ the mailbox (Main's model)
struct Entry { std::string name; int dir; long long size; };
struct Mailbox
{
    // Main, as it behaves: it takes one request at a time (the registers as they were when it
    // picked it up), answers 40 ms later (slowCmd: much later, once), and the core drops an answer
    // whose number isn't the 6502's current one
    int busy = 0; bool pending = false; uint8_t cap[16] = {}; std::string capName; int slowCmd = -1, slowTicks = 0, drops = 0;
    struct Line { std::string label; std::vector<std::string> ch; int v; };
    std::vector<Line> lines = { { "CHIP PRESET", { "PLAIN", "WARM", "CLASSIC" }, 0 }, { "MY CHIP LEFT", { "MOS_6581_3184", "MOS_6581_5084" }, 0 }, { "MY CHIP RIGHT", { "CSG_8580R5_3591", "MOS_8580R5_4687" }, 0 }, { "START IN", { "SD CARD", "LAST USED", "NETWORK" }, 0 },
        { "LEFT SIDS 1357", { "6581", "8580" }, 0 }, { "RIGHT SIDS 2468", { "6581", "8580" }, 0 }, { "MY CHIPS", { "ON", "OFF" }, 0 }, { "OCTOPHONIC", { "8 SIDS", "4 SIDS", "OFF" }, 0 },
        { "OCTOSID FX", { "OFF", "CHORUS", "ECHO", "CHORUS+ECHO" }, 0 }, { "SPLIT SCREENS", { "OFF", "VGA C64+HDMI" }, 0 }, { "TURBO MODE", { "C128", "OFF", "SMART" }, 1 }, { "TURBO SPEED", { "2X", "3X", "4X" }, 0 } };
    bool mute = false, mister = false; int menus = 0; int presetSel = 0; std::string boot = "PLAIN"; int saves = 0;
    std::string top, cwd, shell; uint8_t palSel = 0, palIdx = 0; int palPart = 0; uint8_t vicPal[16][3] = {}; uint8_t mb[16] = {}; std::string name; bool unlocked = false, stage = false; int ran = 0; std::string lastRun;
    uint8_t* ram = nullptr; C64Machine* m = nullptr; std::string loadedReu;
    // the network share, as Main: 0 none set up, 1 waiting, 2 there, 3 set up but not there; netAt:
    // ticks until it appears; netTop: the share's C64 folder. "*" is the drives level
    int net = 0, netAt = -1; bool netWait = false; std::string netTop; int shots = 0, reuLoads = 0; std::string lastShot; std::map<int, std::string> appendFile; std::map<std::string, std::string> appended;
    void list (std::vector<Entry>& v)
    {
        v.clear(); if (cwd == "*") return; DIR* d = opendir (cwd.c_str()); if (! d) return;
        while (auto* de = readdir (d)) { if (de->d_name[0] == '.') continue; struct stat st; std::string p = cwd + "/" + de->d_name; if (stat (p.c_str(), &st)) continue; v.push_back ({ de->d_name, S_ISDIR (st.st_mode) ? 1 : 0, (long long) st.st_size }); }
        closedir (d);
        auto prg = [] (const Entry& e) { auto x = ext_of (e.name); return ! e.dir && ! strcasecmp (x.c_str(), "prg"); };
        std::sort (v.begin(), v.end(), [&] (const Entry& a, const Entry& b) { if (a.dir != b.dir) return a.dir > b.dir; if (prg (a) != prg (b)) return prg (a); return strcasecmp (a.name.c_str(), b.name.c_str()) < 0; });
    }
    static std::string base_of (const std::string& n) { auto d = n.rfind ('.'); if (d == std::string::npos || d == 0 || n.size() - d > 4) return n; return n.substr (0, d); }
    static std::string ext_of (const std::string& n) { auto d = n.rfind ('.'); if (d == std::string::npos || d == 0 || n.size() - d > 4) return ""; return n.substr (d + 1); }
    static int find (const std::vector<Entry>& v, std::string w, int dirs)
    {
        if (! w.empty() && w.back() == '*') w.pop_back(); if (w.empty()) return -1;
        for (int p = 0; p < 3; ++p) for (size_t i = 0; i < v.size(); ++i) { if (v[i].dir != dirs) continue; const auto& n = v[i].name;
            if (p == 0 && ! strcasecmp (n.c_str(), w.c_str())) return (int) i; if (p == 1 && ! strcasecmp (base_of (n).c_str(), w.c_str())) return (int) i; if (p == 2 && ! strncasecmp (n.c_str(), w.c_str(), w.size())) return (int) i; }
        return -1;
    }
    static uint8_t pet (char c) { unsigned char u = c; if (u >= 'a' && u <= 'z') return u - 32; if (u >= 0x20 && u <= 0x5D) return u; if (u == '_') return 0xA4; return '?'; }
    static void put (std::vector<uint8_t>& o, const char* s) { for (; *s; ++s) o.push_back (*s == '\n' ? 0x0D : pet (*s)); }
    void ramw (uint16_t a, const std::vector<uint8_t>& d) { for (size_t i = 0; i < d.size(); ++i) ram[(uint16_t) (a + i)] = d[i]; }
    void reply (int st, int res, int len = -1, int val = -1) { mb[0xA] = res & 255; mb[0xB] = res >> 8; if (len >= 0) { mb[4] = len & 255; mb[5] = len >> 8; } if (val >= 0) mb[7] = val; mb[1] = st; }
    int up() const { return cwd != "*" ? 1 : 0; }
    void goUp() { if (cwd == "*") return; if (cwd == top || cwd == netTop) cwd = "*"; else cwd = cwd.substr (0, cwd.rfind ('/')); }
    std::vector<Entry> drives() { std::vector<Entry> d = { { "SD CARD", 1, 0 } }; if (net) d.push_back ({ "NETWORK", net == 2 ? 1 : 2, 0 }); return d; }
    int type_of (const Entry& e) { if (e.dir) return 0; auto x = ext_of (e.name); for (auto& c : x) c = (char) tolower (c);
        if (x == "prg" || x.empty()) return 1; if (x == "d64" || x == "g64" || x == "d81") return 2; if (x == "crt") return 3; return 4; }
    // a program, as Octophonic Main does it: the demo's .reu in first (same name, or the only one in
    // the folder), then the menu's PRG load - the core resets (the mailbox with it) and runs it
    void run_entry (const Entry& e)
    {
        int t = type_of (e);
        if (t == 2) { reply (2, 0, -1, 8); return; }
        if (t == 4 && ! strcasecmp (ext_of (e.name).c_str(), "reu") && m) {   // a .reu on its own: attached, the C64 carries on
            auto d = rd (cwd + "/" + e.name); m->loadReuImage (d.data(), d.size()); loadedReu = cwd + "/" + e.name; ++reuLoads;
            std::vector<Entry> v; list (v); int at = 0xFFFF;
            for (size_t i = 0; i < v.size(); ++i) if (! v[i].dir && ! strcasecmp (ext_of (v[i].name).c_str(), "prg") && ! strcasecmp (base_of (v[i].name).c_str(), base_of (e.name).c_str())) { at = (int) i + up(); break; }
            reply (2, (int) ((d.size() + 65535) >> 16), at, 2); return; }
        if (t != 1 && t != 3) { reply (0x85, 0); return; }
        reply (2, 0, -1, 1); ran++; lastRun = e.name;
        if (t != 1 || m == nullptr) return;
        std::vector<Entry> v; list (v); std::string reu, only; int reus = 0;
        for (auto& x : v) { if (x.dir) continue; auto ex = ext_of (x.name); for (auto& c : ex) c = (char) tolower (c); if (ex != "reu") continue;
            ++reus; only = x.name; if (! strcasecmp (base_of (x.name).c_str(), base_of (e.name).c_str())) reu = x.name; }
        if (reu.empty() && reus == 1) reu = only;
        if (! reu.empty() && cwd + "/" + reu != loadedReu) { auto d = rd (cwd + "/" + reu); m->loadReuImage (d.data(), d.size()); loadedReu = cwd + "/" + reu; ++reuLoads; }
        auto p = rd (cwd + "/" + e.name);
        coreReset();
        m->loadProgramWhenReady (p.data(), p.size(), true);
    }
    // the core's reset: the machine starts again, and the mailbox's registers go back to 0
    void coreReset() { if (m) m->reset(); std::memset (mb, 0, 16); name.clear(); pending = false; busy = 0; unlocked = false; stage = false; }
    void serve()
    {
        std::string nm; for (char c : name) { unsigned char u = c; if (u >= 0xC1 && u <= 0xDA) u = u - 0xC1 + 'a'; nm += (char) u; }
        while (! nm.empty() && nm.back() == ' ') nm.pop_back();
        const uint16_t addr = mb[2] | mb[3] << 8; const int len = mb[4] | mb[5] << 8;
        std::vector<Entry> v; list (v);
        if (mb[0] == 1) {
            int lines = mb[7] ? mb[7] : 20; int total = (int) v.size() + up(); std::vector<uint8_t> o; char line[96];
            if (len == 0) { auto leaf = cwd.substr (cwd.rfind ('/') + 1); char nm2[20]; std::snprintf (nm2, sizeof nm2, "%-16.16s", leaf.c_str()); o.push_back (0x12); std::snprintf (line, sizeof line, "0 \"%s\" OS 1", nm2); put (o, line); o.push_back (0x92); o.push_back (13); }
            int i = len, sh = 0;
            for (; i < total && sh < lines; ++i, ++sh) {
                if (up() && i == 0) { put (o, "0    \"..\"               DIR\n"); continue; }
                const auto& e = v[(size_t) (i - up())]; std::string s = e.dir ? e.name : base_of (e.name); std::string t = e.dir ? "DIR" : ext_of (e.name);
                if (s.size() > 26) s = s.substr (0, 26); long long bl = e.dir ? 0 : (e.size + 253) / 254; if (bl > 9999) bl = 9999;
                char q[40]; std::snprintf (q, sizeof q, "\"%s\"", s.c_str()); std::snprintf (line, sizeof line, "%-5lld%-18s %.3s\n", bl, q, t.c_str()); put (o, line); }
            const int more = i < total; if (! more) { std::snprintf (line, sizeof line, "%d %s.\n", (int) v.size(), v.size() == 1 ? "ENTRY" : "ENTRIES"); put (o, line); }
            o.push_back (0); ramw (addr ? addr : 0xA000, o); reply (2, (int) o.size(), i, more);
        }
        else if (mb[0] == 2) {
            std::string keep = cwd; size_t p = 0;
            if (nm.empty() || nm[0] == '/') { cwd = top; while (p < nm.size() && nm[p] == '/') ++p; }
            while (p < nm.size()) { size_t q = nm.find ('/', p); std::string part = nm.substr (p, q == std::string::npos ? std::string::npos : q - p); p = q == std::string::npos ? nm.size() : q + 1;
                if (part.empty()) continue; if (part == "..") { goUp(); continue; }
                list (v); int kk = find (v, part, 1); if (kk < 0) { reply (find (v, part, 0) >= 0 ? 0x82 : 0x81, 0); cwd = keep; return; } cwd += "/" + v[(size_t) kk].name; }
            reply (2, 0);
        }
        else if (mb[0] == 4) { int kk = find (v, nm, 0); if (kk < 0) { reply (0x81, 0); return; } run_entry (v[(size_t) kk]); }
        else if (mb[0] == 6) {
            int count = mb[7] ? mb[7] : 17; int total = (int) v.size() + up(); std::vector<uint8_t> o;
            if (cwd == "*") { auto d = drives(); total = (int) d.size();
                const char* pth = "DRIVES"; for (int i = 0; i < 40; ++i) o.push_back (i < 6 ? (uint8_t) pth[i] : ' ');
                int w = 0; for (int i = len; i < total && w < count; ++i, ++w) { uint8_t rec[40]; std::memset (rec, ' ', 40); rec[0] = d[(size_t) i].dir == 2 ? 6 : 0;
                    if (d[(size_t) i].dir == 2) { rec[3] = 'O'; rec[4] = 'F'; rec[5] = 'F'; } rec[6] = 'D'; rec[7] = 'R'; rec[8] = 'V';
                    for (int k = 0; k < 23 && k < (int) d[(size_t) i].name.size(); ++k) rec[9 + k] = pet (d[(size_t) i].name[(size_t) k]); o.insert (o.end(), rec, rec + 40); }
                ramw (addr ? addr : 0xCA00, o); reply (2, total, -1, w); return; }
            std::string path = cwd.substr (cwd.compare (0, top.size(), top) ? 0 : top.size()); if (cwd == netTop) path = "/NET"; else if (! netTop.empty() && ! cwd.compare (0, netTop.size(), netTop)) path = "/NET" + cwd.substr (netTop.size()); else if (path.empty()) path = "/"; if (path.compare (0, 4, "/NET")) path = "/TEST" + (path == "/" ? std::string() : path);
            if (path.size() > 40) path = "..." + path.substr (path.size() - 37);
            for (int i = 0; i < 40; ++i) o.push_back (i < (int) path.size() ? pet (path[(size_t) i]) : ' ');
            int w = 0;
            for (int i = len; i < total && w < count; ++i, ++w) {
                uint8_t rec[40]; std::memset (rec, ' ', 40);
                // as Main: type, size text (5: blocks under 1000, else K/M), ext (3), name (31; long ones cut in the middle to 28)
                if (up() && i == 0) { rec[0] = 5; rec[6] = 'D'; rec[7] = 'I'; rec[8] = 'R'; const char* u = ".. (UP A FOLDER)"; for (int k = 0; u[k]; ++k) rec[9 + k] = pet (u[k]); }
                else { const auto& e = v[(size_t) (i - up())];
                    rec[0] = (uint8_t) type_of (e);
                    char t[16] = ""; if (! e.dir) { long long z = e.size, b = (z + 253) / 254;
                        if (b < 1000) std::snprintf (t, sizeof t, "%lld", b); else if (z < 1000LL * 1024) std::snprintf (t, sizeof t, "%lldK", (z + 1023) / 1024); else std::snprintf (t, sizeof t, "%lldM", (z + 1048575) / 1048576); }
                    char sz[8]; std::snprintf (sz, sizeof sz, "%5s", t); for (int k = 0; k < 5; ++k) rec[1 + k] = pet (sz[k]);
                    std::string x = e.dir ? "DIR" : ext_of (e.name); for (int k = 0; k < 3 && k < (int) x.size(); ++k) rec[6 + k] = pet (x[(size_t) k]);
                    std::string n = e.dir ? e.name : base_of (e.name); if (n.find_first_not_of (' ') == std::string::npos) n = "?";
                    if (n.size() > 28) n = n.substr (0, 16) + ".." + n.substr (n.size() - 10);
                    for (int k = 0; k < 31 && k < (int) n.size(); ++k) rec[9 + k] = pet (n[(size_t) k]); }
                o.insert (o.end(), rec, rec + 40); }
            ramw (addr ? addr : 0xCA00, o); reply (2, total, -1, w);
        }
        else if (mb[0] == 7) {
            if (cwd == "*") { auto d = drives(); if (len >= (int) d.size()) { reply (0x81, 0); return; } if (d[(size_t) len].dir == 2) { reply (0x86, 0); return; }
                cwd = len == 0 ? top : netTop; reply (2, 0, -1, 0x10); return; }
            int total = (int) v.size() + up(); if (len < 0 || len >= total) { reply (0x81, 0); return; }
            if (up() && len == 0) { goUp(); reply (2, 0, -1, 0x10); return; }
            const auto& e = v[(size_t) (len - up())];
            if (e.dir) { cwd += "/" + e.name; reply (2, 0, -1, 0x10); return; }
            run_entry (e);
        }
        else if (mb[0] == 8) {
            std::vector<uint8_t> o; auto field = [&] (const std::string& t) { for (int i = 0; i < 20; ++i) o.push_back (i < (int) t.size() ? pet (t[(size_t) i]) : ' '); };
            for (size_t i = 0; i < lines.size(); ++i) { field (lines[i].label); std::string v = lines[i].ch[(size_t) (i == 0 ? presetSel : lines[i].v)]; if (i == 0 && lines[0].ch[(size_t) presetSel] != boot) v += " (RETURN)"; field (v); }
            ramw (addr ? addr : 0xCA00, o); reply (2, (int) lines.size());
        }
        else if (mb[0] == 9) {
            int l = mb[6], st = mb[7] == 0xFF ? -1 : 1; if (l >= (int) lines.size()) { reply (0x8F, 0); return; }
            int n = (int) lines[(size_t) l].ch.size();
            if (l == 0) presetSel = (presetSel + st + n) % n; else { lines[(size_t) l].v = (lines[(size_t) l].v + st + n) % n; ++saves; }
            reply (2, 0);
        }
        else if (mb[0] == 10) { boot = lines[0].ch[(size_t) presetSel]; reply (2, 0, -1, 1); ran++; lastRun = "preset " + boot; }
        else if (mb[0] == 0x0B) { netWait = false; cwd = top; if (net == 1) net = 3; reply (2, 0); }
        else if (mb[0] == 0x10) { ++shots; lastShot = nm; reply (2, 0); }
        else if (mb[0] == 0x11) { if (mb[7] == 0xFF) appendFile[mb[6] & 3] = nm; else if (appendFile.count (mb[6] & 3)) { auto& f = appended[appendFile[mb[6] & 3]]; f += nm; if (! (mb[7] & 1)) f += "\n"; } reply (appendFile.count (mb[6] & 3) || mb[7] == 0xFF ? 2 : 0x81, 0); }
        else if (mb[0] == 0x12) { if (mister) { ++menus; reply (2, 0); } else reply (0x8F, 0); }   // MENU: Main loads the MiSTer's menu core
        else if (mb[0] == 0x0F) {
            auto d = rd (shell); if (d.size() < 3) { reply (0x81, 0); return; }
            uint16_t at = d[0] | d[1] << 8; ramw (at, std::vector<uint8_t> (d.begin() + 2, d.end())); reply (2, at);
        }
        else reply (0x8F, 0);
    }
    void tick()
    {
        if (netAt > 0 && --netAt == 0) { if (net == 1 || net == 3) { if (netWait) { cwd = netTop; netWait = false; } net = 2; } }
        if (mute) return;
        if (busy > 0)
        {
            if (--busy > 0) return;
            uint8_t live[16]; std::memcpy (live, mb, 16); std::string liveName = name;
            std::memcpy (mb, cap, 16); name = capName;
            serve();
            if (cap[0xD] == live[0xD]) { for (int r : { 1, 4, 5, 7, 0xA, 0xB }) live[r] = mb[r]; live[0xE] = cap[0xD]; pending = false; }
            else ++drops;
            std::memcpy (mb, live, 16); name = liveName;
            return;
        }
        if (pending) { std::memcpy (cap, mb, 16); capName = name; busy = 4; if (mb[0] == slowCmd) { busy = slowTicks; slowCmd = -1; } }
    }
    void attach (C64Machine& m)
    {
        m.getBus().ioWriteHook = [this] (uint16_t a, uint8_t v) -> bool {
            if (a >= 0xD000 && a < 0xD400 && (a & 0x3F) == 0x3F) { if (v == 0x4F) stage = true; else if (v == 0x38 && stage) { unlocked = true; stage = false; } else { unlocked = false; stage = false; } return false; }
            if (! unlocked || a < 0xD600 || a >= 0xD700) return false;
            const uint8_t r = a & 0xFF;
            if (r == 0x19) palSel = v; else if (r == 0x1A) { palIdx = v; palPart = 0; }
            else if (r >= 0x1B && r <= 0x1D) { if (palSel == 1 && palIdx < 16) vicPal[palIdx][r - 0x1B] = v; if (r == 0x1D) ++palIdx; }   // PALB stores and moves PALIDX on
            if (r >= 0xF0) { const uint8_t i = r & 15;
                if (i == 0) { mb[0] = v; mb[1] = 1; pending = true; }
                else if (i == 8) { if (name.size() < 32) name += (char) v; }
                else if (i == 9) name.clear();
                else mb[i] = v; }
            return true;
        };
        m.getBus().ioReadHook = [this] (uint16_t a, uint8_t& v) -> bool {
            if (! unlocked || a < 0xD600 || a >= 0xD700) return false;
            const uint8_t r = a & 0xFF;
            if (r >= 0xF0) { const uint8_t i = r & 15; v = i == 0xC ? 2 : i == 8 ? (uint8_t) name.size() : i == 0xF ? (uint8_t) (net | (mister ? 0x20 : 0)) : mb[i]; return true; }
            static const char tag[] = "CORE7   ";     // the core's name and build date (OctoVIC version 3)
            v = r == 0x1E ? 0x8C : r == 0x1F ? 3 : (r >= 0xB8 && r <= 0xBF) ? (uint8_t) tag[r - 0xB8]
              : r == 0xB4 ? 0x01 : r == 0xB5 ? 0x11 : r == 0xB6 ? 0x26 : 0; return true;
        };
    }
};

// --------------------------------------------------------------------------------- the machine
struct Roms { std::vector<uint8_t> k, b, ch; bool octo; };
struct Snap { std::vector<uint8_t> screen, mem; std::string text; };

static std::string text_of (const uint8_t* scr)
{
    std::string t;
    for (int r = 0; r < 25; ++r) { std::string l; for (int c = 0; c < 40; ++c) { uint8_t s = scr[r * 40 + c] & 0x7F; char ch = s == 0 ? '@' : s < 27 ? (char) ('A' + s - 1) : s < 64 ? (char) s : s == 0x64 ? '_' : '#'; l += ch; }
        while (! l.empty() && l.back() == ' ') l.pop_back(); t += l + "\n"; }
    return t;
}

struct Rig
{
    std::unique_ptr<C64Machine> own; C64Machine* m; Mailbox box; D64Image disk; std::vector<float> l, r; bool octo = false;
    Rig (const Roms& roms, const std::vector<uint8_t>& driveRom, const std::vector<uint8_t>& d64, const std::string& folder, const std::string& shell, bool novic = false)
        : l (480), r (480)
    {
        own = std::make_unique<C64Machine>(); m = own.get();
        m->prepare (48000.0, false);
        m->setRoms (roms.k.data(), roms.k.size(), roms.b.data(), roms.b.size(), roms.ch.data(), roms.ch.size());
        std::string err; disk.load (d64.data(), d64.size(), err);
        m->setDriveRom (driveRom.data(), driveRom.size());
        m->insertDiskInDrive (disk);
        m->reset();
        box.ram = m->getBus().getRam(); box.m = m; box.top = box.cwd = folder; box.shell = shell; box.netTop = folder.substr (0, folder.rfind ('/')) + "/netshare";
        octo = roms.octo && ! novic; if (octo) box.attach (*m); else box.m = nullptr;
    }
    void run (double s) { const auto fa = m->getFrameCount(); while (m->getFrameCount() < fa + (uint64_t) (s * 50)) { m->renderStereo (l.data(), r.data(), 480); box.tick(); } }
    void key (int row, int col, bool shift, double hold = 0.1)
    {
        if (shift) m->setKeyDown (1, 7, true);
        m->setKeyDown (row, col, true); run (hold);
        m->setKeyDown (row, col, false); if (shift) m->setKeyDown (1, 7, false); run (0.1);
    }
    void type (const std::string& t)
    {
        m->typeText (t);
        int guard = 0; while (m->getTypeQueueSize() > 0 && guard++ < 3000) run (0.02);
        run (0.3);
    }
    // a step: text, with {KEY} tokens
    void step (const std::string& s)
    {
        size_t i = 0; std::string buf;
        auto flush = [&] { if (! buf.empty()) { type (buf); buf.clear(); } };
        while (i < s.size())
        {
            if (s[i] == '{') { size_t j = s.find ('}', i); std::string k = s.substr (i + 1, j - i - 1); i = j + 1; flush();
                if (k == "CLR") key (6, 3, true); else if (k == "HOME") key (6, 3, false);
                else if (k == "DOWN") key (0, 7, false); else if (k == "UP") key (0, 7, true);
                else if (k == "RIGHT") key (0, 2, false); else if (k == "LEFT") key (0, 2, true);
                else if (k == "DEL") key (0, 0, false); else if (k == "INST") key (0, 0, true);
                else if (k == "RET") key (0, 1, false); else if (k == "SRET") key (0, 1, true);
                else if (k == "F1") key (0, 4, false); else if (k == "F3") key (0, 5, false); else if (k == "F5") key (0, 6, false); else if (k == "F7") key (0, 3, false);
                else if (k == "F2") key (0, 4, true); else if (k == "F8") key (0, 3, true);
                else if (k == "F1LONG") key (0, 4, false, 1.5);
                else if (k == "CF1") { m->setKeyDown (7, 5, true); run (0.05); key (0, 4, false); m->setKeyDown (7, 5, false); run (0.1); }
                else if (k == "CHOLD") { m->setKeyDown (7, 5, true); run (0.3); }
                else if (k == "CUP") { m->setKeyDown (7, 5, false); run (0.2); }
                else if (k == "MISTER") box.mister = true;
                else if (k == "STOP") key (7, 7, false); else if (k == "SSTOP") key (7, 7, true);
                else if (k == "RESTORE") { m->setKeyDown (7, 7, true); run (0.05); m->getCpu().triggerNmi(); run (0.2); m->setKeyDown (7, 7, false); run (0.5); }
                else if (k.rfind ("WAIT", 0) == 0) run (atof (k.c_str() + 4));
                else if (k == "MUTE") box.mute = true;
                else if (k == "EXIT") { if (box.m && octo) box.coreReset(); run (0.1); }   // Main's CTRL+F12: Reset & Detach Cartridge, the folder kept
                else if (k == "NETUP") { box.net = 2; box.cwd = box.netTop; }
                else if (k.rfind ("NETWAIT", 0) == 0) { box.net = 1; box.netWait = true; box.netAt = atoi (k.c_str() + 7) * 100; }
                else if (k.rfind ("SLOW", 0) == 0) { int c, sec; std::sscanf (k.c_str() + 4, "%x,%d", &c, &sec); box.slowCmd = c; box.slowTicks = sec * 100; }
                else if (k == "JDOWN") { m->setJoystick (2, false, true, false, false, false); run (0.15); m->setJoystick (2, false, false, false, false, false); run (0.1); }
                else if (k == "JFIRE") { m->setJoystick (2, false, false, false, false, true); run (0.15); m->setJoystick (2, false, false, false, false, false); run (0.1); }
                else { std::printf ("unknown key %s\n", k.c_str()); std::exit (3); }
                continue; }
            buf += s[i++];
        }
        flush();
    }
    Snap snap()
    {
        Snap sn; const uint8_t* ram = m->getBus().getRam();
        sn.screen.assign (ram + 0x400, ram + 0x400 + 1000);
        sn.mem.assign (ram + 0x2B, ram + 0x39);          // BASIC's pointers
        sn.mem.insert (sn.mem.end(), ram + 0x801, ram + 0x0C00);   // the program
        sn.text = text_of (ram + 0x400);
        return sn;
    }
};

// ------------------------------------------------------------------------ the boot screen
// The V1.1 start screen as approved (Neal's mock-up 12, 4 Nov 2026): the top box (OCTOPHONIC 64, NET
// and its light; 8 SIDS, OCTOVIC 256 in the rainbow, the REU), 38911 BASIC BYTES FREE on row 3,
// READY. on row 5, the cursor on row 6, the bar on row 24 (keys yellow, labels pale), the editor at
// 24 rows, the colours (OctoVIC's VIC palette), and the whole VIC picture against boot_ref.idx (pixels
// that blink left out). REFDIR set and no reference there yet: this frame becomes it.
static std::string g_refdir;
static const char* BAR = "F1 BROWSE F3 LOAD F5 SIDS F7 DUAL F8 SET";
static std::string rowtext (Rig& r, int y) { auto* ram = r.m->getBus().getRam(); std::string t; for (int c = 0; c < 40; ++c) { uint8_t s = ram[0x400 + y * 40 + c] & 0x7F; t += s == 0x20 ? ' ' : s < 27 ? (char) ('A' + s - 1) : (char) s; } return t; }
static std::string barcheck (Rig& r)
{
    std::string why; auto* ram = r.m->getBus().getRam();
    if (rowtext (r, 24) != BAR) why += "the bar not on row 24: '" + rowtext (r, 24) + "'; ";
    for (int c = 0; c < 40; ++c) { const char ch = BAR[c]; const int want = (ch == 'F' || (ch >= '0' && ch <= '9')) ? 7 : 15;
        if ((r.m->getBus().readColour (960 + c) & 15) != want) { why += "the bar's colours; "; break; } }
    if (ram[0xB0] != 24 || ram[0xB1] != 23 || ram[0xBE] != 22) why += "the editor not at 24 rows; ";
    return why;
}
static std::string bootcheck (Rig& r)
{
    auto* ram = r.m->getBus().getRam();
    auto row = [&] (int y) { return rowtext (r, y); };
    std::string why;
    if (row (0).substr (13, 13) != "OCTOPHONIC 64") why += "title not at row 0, column 13; ";
    if (row (0).substr (32, 3) != "NET") why += "NET not at row 0, column 32; ";
    if (row (1).substr (0, 6) != "8 SIDS") why += "8 SIDS not at row 1 left; ";
    if (row (1).substr (13, 11) != "OCTOVIC 256") why += "OCTOVIC 256 not at row 1, column 13; ";
    if (row (1).substr (32).find ("REU") == std::string::npos) why += "the REU not at row 1, column 32; ";
    if (row (3) .substr (0, 22) != "38911 BASIC BYTES FREE") why += "BYTES FREE not at row 3 left: '" + row (3) + "'; ";
    if (row (5).substr (0, 6) != "READY.") why += "READY. not at row 5 left; ";
    if (ram[0xD6] != 6 || ram[0xD3] != 0) why += "cursor not at row 6 left; ";
    for (int y : { 2, 4 }) if (row (y).find_first_not_of (' ') != std::string::npos) why += "row " + std::to_string (y) + " not empty; ";
    static const int rb[7] = { 2, 8, 9, 5, 10, 14, 4 };
    for (int c = 0; c < 7; ++c) if ((r.m->getBus().readColour (53 + c) & 15) != rb[c]) { why += "OCTOVIC not in the rainbow; "; break; }
    for (int c = 0; c < 6; ++c) if ((ram[0x400 + c] & 0xFF) != 0xA0 || (r.m->getBus().readColour (c) & 15) != 3) { why += "the eq's cells; "; break; }
    if (r.octo) {
        if ((ram[0x400 + 38] & 0x7F) != 0x51) why += "no light's ball at row 0, column 38; ";
        const int lc = r.m->getBus().readColour (38) & 15, want = r.box.net == 0 ? 6 : r.box.net == 2 ? 5 : 2;
        if (lc != want) why += "the light's colour " + std::to_string (lc) + " (want " + std::to_string (want) + "); ";
        why += barcheck (r);
        if (ram[0x2A7] != 1) why += "OCTST not set; ";
    }
    const int W = r.m->getFramebufferWidth(), H = r.m->getFramebufferHeight();
    std::vector<uint8_t> a (r.m->getFramebuffer(), r.m->getFramebuffer() + W * H); r.run (0.33);
    std::vector<uint8_t> b (r.m->getFramebuffer(), r.m->getFramebuffer() + W * H);
    for (auto& v : a) v &= 15; for (auto& v : b) v &= 15;
    if (a[0] != (r.octo ? 11 : 6)) why += "border not colour " + std::string (r.octo ? "11" : "6") + " (" + std::to_string (a[0]) + "); ";
    if (r.octo && (r.box.vicPal[6][0] != 16 || r.box.vicPal[6][1] != 18 || r.box.vicPal[6][2] != 56)) why += "VIC colour 6 not the box's dark (OctoVIC palette); ";
    if (r.octo && (r.box.vicPal[11][0] != 20 || r.box.vicPal[11][1] != 22 || r.box.vicPal[11][2] != 70)) why += "VIC colour 11 not the border's navy; ";
    if (a[(size_t) (H / 2) * W + W / 2] != 6) why += "background not navy; ";
    if (! g_refdir.empty()) {
        auto ref = rd (g_refdir + "/boot_ref.idx");
        if (ref.size() != a.size()) { std::ofstream f (g_refdir + "/boot_ref.idx", std::ios::binary); f.write ((const char*) a.data(), (std::streamsize) a.size()); std::printf ("  (boot_ref.idx written)\n"); }
        else { size_t d = 0; for (size_t i = 0; i < a.size(); ++i) if (a[i] == b[i] && a[i] != ref[i]) ++d; if (d) why += std::to_string (d) + " pixels differ from boot_ref.idx; "; }
    }
    return why;
}

static std::string browsercheck (Rig& r)
{
    auto* ram = r.m->getBus().getRam();
    auto row = [&] (int y) { std::string t; for (int c = 0; c < 40; ++c) { uint8_t s = ram[0x400 + y * 40 + c] & 0x7F; t += s == 0x20 ? ' ' : s < 27 ? (char) ('A' + s - 1) : (char) s; } return t; };
    std::string why;
    if (row (0).substr (13, 13) != "OCTOPHONIC 64") why += "title; ";
    if (row (1).substr (13, 11) != "OCTOVIC 256") why += "OCTOVIC 256 not on row 1; ";
    if (row (4).find_first_not_of (' ') != std::string::npos) why += "row 4 not blank (crowded under the box); ";
    if (row (24).substr (0, 7) != "RET RUN") why += "the browser's help not on row 24; ";
    if (row (5).substr (0, 5) != "/TEST") why += "path not on row 5: '" + row (5) + "'; ";
    if (row (6).find_first_not_of (' ') != std::string::npos) why += "row 6 not blank; ";
    if (row (7).substr (1, 4) != "NAME" || row (7).substr (30, 9) != "TYPE SIZE") why += "column names not on row 7; ";
    if (row (8).find_first_not_of (' ') != std::string::npos) why += "row 8 not blank (the list touches the column names); ";
    for (int y = 9; y < 22; ++y) { std::string t = row (y); if (t.substr (30, 3) != "   " && t.substr (1, 23).find_first_not_of (' ') == std::string::npos) why += "a blank name on row " + std::to_string (y) + "; "; }
    for (int y = 9; y < 22; ++y) if (row (y).find ("65535") != std::string::npos) why += "65535 on row " + std::to_string (y) + "; ";
        const int W = r.m->getFramebufferWidth(); const auto* fb = r.m->getFramebuffer();
    if ((fb[0] & 15) != 11) why += "border not colour 11; ";
    if ((fb[(size_t) (r.m->getFramebufferHeight() / 2) * W + W / 2] & 15) != 6) why += "background not colour 6; ";
    return why;
}

// ---------------------------------------------------------------------------------- the cases
enum Mode { SAME, OCTO };
struct Case { std::string name; Mode mode; std::vector<std::string> steps;
              std::function<std::string (const Snap& stock, const Snap& octo, Rig& so, Rig& oc)> check; };

static bool has (const Snap& s, const char* t) { return s.text.find (t) != std::string::npos; }

int main (int argc, char** argv)
{
    if (argc < 7) { std::printf ("romtest stockroms octoroms drive.rom test.d64 folder shell.prg [filter]\n"); return 2; }
    auto load = [] (const std::string& d, bool o) { Roms r; r.k = rd (d + "/kernal-901227-03.bin"); r.b = rd (d + "/basic-901226-01.bin"); r.ch = rd (d + "/chargen-901225-01.bin"); r.octo = o; return r; };
    Roms stock = load (argv[1], false), octo = load (argv[2], true);
    if (stock.ch.empty()) stock.ch = octo.ch;
    auto drv = rd (argv[3]); auto d64 = rd (argv[4]); std::string folder = argv[5], shell = argv[6]; std::string filter = argc > 7 ? argv[7] : "";
    if (getenv ("REFDIR")) g_refdir = getenv ("REFDIR");

    const std::string PROG30 = [] { std::string s; for (int i = 1; i <= 30; ++i) s += std::to_string (i * 10) + " PRINT \"LINE " + std::to_string (i) + "\";" + std::to_string (i) + "*2\n"; return s; }();

    std::vector<Case> cases = {
        { "boot screen: cold start", OCTO, { "{WAIT1}" }, [] (const Snap&, const Snap&, Rig&, Rig& oc) { return bootcheck (oc); } },
        { "boot screen: after CTRL+F12", OCTO, { "10 PRINT 1\n", "/HELLO\n{WAIT5}", "{EXIT}{WAIT4}" }, [] (const Snap&, const Snap&, Rig&, Rig& oc) { return bootcheck (oc); } },
        { "browser screen: layout, names, sizes, colours", OCTO, { "{F1}{WAIT1}" }, [] (const Snap&, const Snap& o, Rig&, Rig& oc) {
            std::string w = browsercheck (oc); if (! has (o, "UP A FOLDER") && oc.box.cwd != oc.box.top) w += "no UP A FOLDER; "; return w; } },
        { "browser screen: in a folder - .. named, bar below it, 16M", OCTO, { "{F1}{WAIT1}", "{RET}{WAIT1}" }, [] (const Snap&, const Snap& o, Rig&, Rig& oc) {
            std::string w = browsercheck (oc); if (! has (o, ".. (UP A FOLDER)")) w += "no '.. (UP A FOLDER)'; "; if (! has (o, "  16M")) w += "16 MB .reu not shown as 16M; ";
            auto* ram = oc.m->getBus().getRam(); if ((ram[0x400 + 10 * 40 + 1] & 0x80) == 0) w += "the bar is not on the first entry below ..; "; return w; } },
        { "SHIFT+RUN/STOP shows LOAD and RUN in full", OCTO, { "{CLR}{SSTOP}{WAIT10}" }, [] (const Snap&, const Snap& o, Rig&, Rig&) {
            return has (o, "LOAD\"*\",8") && has (o, "\nRUN") ? std::string() : std::string ("LOAD/RUN not spelt out"); } },
        { "boot screen: after F1, F7", OCTO, { "{F1}{WAIT1}", "{F7}{WAIT1}" }, [] (const Snap&, const Snap&, Rig&, Rig& oc) {
            return rowtext (oc, 0).substr (13, 13) == "OCTOPHONIC 64" && barcheck (oc).empty() ? std::string() : std::string ("title or bar gone after the browser: ") + barcheck (oc); } },
        { "boot pointers and FRE", SAME, { "{CLR}PRINT FRE(0)\n", "PRINT PEEK(43);PEEK(44);PEEK(45);PEEK(46)\n" }, [] (const Snap& s, const Snap& o, Rig&, Rig&) { return has (s, " 1  8  3  8") && has (o, " 1  8  3  8") ? std::string() : std::string ("missing  1  8  3  8"); } },
        { "enter a numbered line (the hang)", SAME, { "{CLR}10 PRINT \"NEAL\"\n", "LIST\n", "RUN\n" }, [] (const Snap& s, const Snap& o, Rig&, Rig&) { return has (s, "\nNEAL") && has (o, "\nNEAL") ? std::string() : std::string ("missing NEAL"); } },
        { "program with strings and maths", SAME, { "{CLR}10 PRINT \"NEAL\"\n20 A=5:B$=\"X\"+\"Y\"\n30 PRINT A*2;B$\n", "LIST\n", "RUN\n" }, [] (const Snap& s, const Snap& o, Rig&, Rig&) { return has (s, " 10 XY") && has (o, " 10 XY") ? std::string() : std::string ("missing  10 XY"); } },
        { "replace and delete lines", SAME, { "{CLR}10 PRINT 1\n20 PRINT 2\n", "10 PRINT 3\n", "LIST\n", "20\n", "LIST\n", "RUN\n" }, nullptr },
        { "LIST ranges", SAME, { "{CLR}10 REM A\n20 REM B\n30 REM C\n40 REM D\n50 REM E\n", "LIST 20-40\n", "{CLR}LIST -20\n", "{CLR}LIST 30-\n" }, nullptr },
        { "RUN NEW CLR", SAME, { "{CLR}10 A=1\nRUN\n", "PRINT A\n", "CLR\nPRINT A\n", "NEW\nLIST\n", "PRINT FRE(0)\n" }, nullptr },
        { "direct mode PRINT POKE PEEK SYS", SAME, { "{CLR}PRINT 2+3*4\n", "POKE 1024,1:PRINT PEEK(1024)\n", "POKE 49152,96:SYS 49152:PRINT \"OK\"\n", "PRINT FRE(0)\n" }, nullptr },
        { "FOR NEXT GOSUB arrays strings", SAME, { "{CLR}10 FOR I=1 TO 3:PRINT I;:NEXT\n20 GOSUB 100:PRINT \"BACK\"\n30 DIM X(5):X(3)=7:PRINT X(3)\n40 S$=\"AB\":PRINT LEFT$(S$,1);LEN(S$)\n50 END\n100 PRINT \"SUB\":RETURN\n", "RUN\n" }, [] (const Snap& s, const Snap& o, Rig&, Rig&) { return has (s, "BACK") && has (o, "BACK") ? std::string() : std::string ("missing BACK"); } },
        { "screen editor: edit a listed line", SAME, { "{CLR}10 PRINT \"A\"\n", "LIST\n", "{UP}{UP}2{RET}", "LIST\n", "RUN\n" }, nullptr },
        { "screen editor: insert and delete", SAME, { "{CLR}PRINT \"ABC\"{LEFT}{LEFT}{DEL}{INST}Z{RET}" }, nullptr },
        { "screen editor: quote mode", SAME, { "{CLR}PRINT \"{DOWN}{RIGHT}X\"{RET}" }, nullptr },
        { "RUN/STOP breaks a program", SAME, { "{CLR}10 GOTO 10\n", "RUN\n", "{STOP}", "LIST\n" }, nullptr },
        { "RUN/STOP+RESTORE, then a new line", SAME, { "{CLR}10 PRINT 7\n", "{RESTORE}", "20 PRINT 8\n", "LIST\n", "RUN\n" }, nullptr },
        { "warm reset in a running program", SAME, { "{CLR}10 GOTO 10\n", "RUN\n", "{RESTORE}", "LIST\n", "15 PRINT 1\n", "LIST\n" }, nullptr },
        { "long typed program", SAME, { "{CLR}" + PROG30, "{CLR}LIST 100-200\n", "{CLR}RUN\n{WAIT3}" }, nullptr },
        { "GET sees F1 in a program", SAME, { "{CLR}10 GET A$:IF A$=\"\" GOTO 10\n20 PRINT ASC(A$)\n", "RUN\n", "{F1}", "{WAIT1}" }, [] (const Snap& s, const Snap& o, Rig&, Rig&) { return has (s, " 133") && has (o, " 133") ? std::string() : std::string ("missing  133"); } },
        { "F3 F5 F7 at READY", SAME, { "{CLR}{F3}{F5}{F7}{F2}", "PRINT 1\n" }, nullptr },
        { "disk: LOAD\"$\" and LIST", SAME, { "{CLR}LOAD\"$\",8\n{WAIT8}", "LIST\n" }, [] (const Snap& s, const Snap& o, Rig&, Rig&) { return has (s, "BLOCKS FREE") && has (o, "BLOCKS FREE") ? std::string() : std::string ("missing BLOCKS FREE"); } },
        { "disk: LOAD, LIST, RUN, VERIFY", SAME, { "{CLR}LOAD\"HELLO\",8\n{WAIT8}", "LIST\n", "RUN\n", "VERIFY\"HELLO\",8\n{WAIT8}" }, [] (const Snap& s, const Snap& o, Rig&, Rig&) { return has (s, "\nOK") && has (o, "\nOK") ? std::string() : std::string ("missing OK"); } },
        { "disk: SAVE and LOAD back", SAME, { "{CLR}10 PRINT 9\n", "SAVE\"T\",8\n{WAIT40}", "NEW\n", "LOAD\"T\",8\n{WAIT8}", "LIST\n" }, nullptr },
        { "disk: OPEN PRINT# CLOSE, error channel", SAME, { "{CLR}10 OPEN 2,8,2,\"S,S,W\":PRINT#2,\"X\":CLOSE 2\n20 OPEN 1,8,15:INPUT#1,A,B$:CLOSE 1:PRINT A;B$\n", "RUN\n{WAIT12}" }, nullptr },
        { "disk: CMD", SAME, { "{CLR}10 REM CMD\n", "OPEN 4,8,4,\"C,S,W\":CMD 4:LIST\n{WAIT6}", "PRINT#4:CLOSE 4\n{WAIT6}", "PRINT \"DONE\"\n" }, nullptr },
        { "device 1 is turned away (no tape)", OCTO, { "{CLR}LOAD\"X\",1\n", "SAVE\"X\",1\n", "OPEN 1,1\n" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { size_t n = 0, p = 0; while ((p = o.text.find ("ILLEGAL DEVICE", p)) != std::string::npos) { ++n; ++p; } return n >= 3 ? std::string() : "expected 3 x ?ILLEGAL DEVICE NUMBER"; } },
        { "SHIFT+RUN/STOP loads and runs from drive 8", OCTO, { "{CLR}{SSTOP}{WAIT10}" },
          [] (const Snap& s, const Snap& o, Rig&, Rig&) { if (! has (o, "\nHI")) return std::string ("V1.1: no HI from HELLO"); if (! has (s, "SEARCHING")) return std::string ("stock: not the tape LOAD"); return std::string(); } },
        { "@ lists the folder", OCTO, { "{CLR}@\n" },
          [] (const Snap& s, const Snap& o, Rig&, Rig&) { if (! has (o, "ENTRIES")) return std::string ("V1.1: no listing"); if (! has (s, "SYNTAX")) return std::string ("stock: no SYNTAX ERROR"); return std::string(); } },
        { "@NAME, @.., /NAME", OCTO, { "{CLR}@SUB\n", "{CLR}@..\n", "{CLR}/HELLO\n{WAIT5}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { if (oc.box.ran != 1) return std::string ("V1.1: /HELLO did not run"); if (! has (o, "\nHI")) return std::string ("HELLO did not print HI"); return std::string(); } },
        { "a BASIC line still works after @", OCTO, { "{CLR}@\n", "10 PRINT \"AFTER\"\n", "RUN\n" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "\nAFTER") ? std::string() : std::string ("no AFTER"); } },
        { "F1 opens the browser", OCTO, { "{CLR}{F1}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "TYPE SIZE") && has (o, "HELLO") ? std::string() : std::string ("no browser"); } },
        { "browser: down, RETURN runs", OCTO, { "{CLR}{F1}{WAIT1}", "{DOWN}", "{RET}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { return oc.box.ran == 1 && oc.box.lastRun == "hello.prg" ? std::string() : "browser ran '" + oc.box.lastRun + "'"; } },
        { "browser: into a folder and back up", OCTO, { "{CLR}{F1}{WAIT1}", "{RET}{WAIT1}", "{F3}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { return oc.box.cwd == oc.box.top && has (o, "HELLO") ? std::string() : std::string ("not back at the top"); } },
        { "browser: F7 back to READY, BASIC intact", OCTO, { "{CLR}10 PRINT \"KEPT\"\n", "{F1}{WAIT1}", "{F7}{WAIT1}", "RUN\n" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "\nKEPT") ? std::string() : std::string ("program lost"); } },
        { "browser: joystick down and fire", OCTO, { "{CLR}{F1}{WAIT1}", "{JDOWN}", "{JFIRE}{WAIT1}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { return oc.box.ran == 1 ? std::string() : std::string ("fire did not run"); } },
        { "settings: F8, change left SIDs", OCTO, { "{CLR}{F1}{WAIT1}", "{F8}{WAIT1}", "{DOWN}{DOWN}{DOWN}{DOWN}{RIGHT}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { return oc.box.lines[4].v == 1 && has (o, "LEFT SIDS 1357") && has (o, "8580") ? std::string() : std::string ("left SIDs not changed"); } },
        { "settings: chip preset picked and started", OCTO, { "{CLR}{F1}{WAIT1}", "{F8}{WAIT1}", "{RIGHT}{WAIT1}", "{RET}{WAIT1}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { return oc.box.boot == "WARM" ? std::string() : "boot preset " + oc.box.boot; } },
        { "settings: F7 back to the files, then RUN a file", OCTO, { "{CLR}{F1}{WAIT1}", "{F8}{WAIT1}", "{F7}{WAIT1}", "{DOWN}{RET}{WAIT1}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { return oc.box.lastRun == "hello.prg" ? std::string() : "ran '" + oc.box.lastRun + "'"; } },
        { "browser: a disk goes in and loads", OCTO, { "{CLR}{F1}{WAIT1}", "{DOWN}{DOWN}{RET}{WAIT12}" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "DISK IN DRIVE 8") && has (o, "\nHI") ? std::string() : std::string ("disk not loaded"); } },
        { "browser: F2 start folder, HOME, page keys", OCTO, { "{CLR}{F1}{WAIT1}", "{RET}{WAIT1}", "{F2}{WAIT1}", "{F5}{F1}{HOME}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { return oc.box.cwd == oc.box.top && has (o, "ZDISK") ? std::string() : std::string ("not at the start folder"); } },
        { "no reply at all: the 20 s message", OCTO, { "{CLR}{MUTE}@\n{WAIT22}" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "NO REPLY FROM OCTOPHONIC MAIN (CMD 01)") ? std::string() : std::string ("no timeout message"); } },
        { "slow network: a 7 s @ is still answered", OCTO, { "{CLR}{SLOW1,7}@\n{WAIT9}" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "ENTRIES") && ! has (o, "NO REPLY") ? std::string() : std::string ("slow DIR not answered"); } },
        { "slow network: the browser says SCANNING", OCTO, { "{CLR}{SLOW6,7}{F1}{WAIT3}" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "SCANNING...") ? std::string() : std::string ("no SCANNING"); } },
        { "slow network: the browser list after 7 s", OCTO, { "{CLR}{SLOW6,7}{F1}{WAIT9}" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "HELLO") && ! has (o, "SCANNING") ? std::string() : std::string ("no list"); } },
        { "@ times out, @SUB after it gets its own answer", OCTO, { "{CLR}{SLOW1,25}@\n{WAIT21}", "@SUB\n{WAIT8}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { if (! has (o, "(CMD 01)")) return std::string ("no timeout"); if (oc.box.drops != 1) return "drops " + std::to_string (oc.box.drops);
              return has (o, "INNER") ? std::string() : std::string ("SUB not listed"); } },
        { "browser times out, F2 after it gets its own answer", OCTO, { "{CLR}{SLOW6,25}{F1}{WAIT21}", "{F2}{WAIT8}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { if (oc.box.drops != 1) return "drops " + std::to_string (oc.box.drops);
              return has (o, "HELLO") && ! has (o, "NO REPLY") ? std::string() : std::string ("no list after F2"); } },
        { "demo A with its REU, CTRL+F12 out, F1, demo B with its REU", OCTO,
          { "{CLR}@SUB/DEMOA\n", "/DEMOA\n{WAIT5}", "{EXIT}{WAIT4}", "{F1}{WAIT1}", "{F3}{WAIT1}", "{DOWN}{RET}{WAIT1}", "{RET}{WAIT6}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { if (oc.box.lastRun != "demob.prg") return "last run " + oc.box.lastRun;
              return has (o, "DEMO B REU B") ? std::string() : std::string ("demo B didn't see its own REU"); } },
        { "demo A runs with its own REU", OCTO, { "{CLR}@SUB/DEMOA\n", "/DEMOA\n{WAIT5}" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "DEMO A REU A") ? std::string() : std::string ("demo A didn't see its REU"); } },
        { "CTRL+F12 gets out to the start screen, folder kept", OCTO, { "{CLR}@SUB/DEMOA\n", "/DEMOA\n{WAIT5}", "{EXIT}{WAIT4}", "{F1}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "OCTOPHONIC 64") && has (o, "/TEST/SUB/DEMOA") ? std::string() : std::string ("not back in the demo's folder"); } },
        { "network: none set up - no light, browser on the SD card", OCTO, { "{WAIT1}", "{F1}{WAIT1}" }, [] (const Snap&, const Snap& o, Rig&, Rig& oc) {
            return has (o, "/TEST") && ! has (o, "PLEASE WAIT") && oc.box.net == 0 ? std::string() : std::string ("not straight to the SD card"); } },
        { "network: waiting - red light on the start screen", OCTO, { "{NETWAIT30}{WAIT1}" }, [] (const Snap&, const Snap&, Rig&, Rig& oc) {
            auto* ram = oc.m->getBus().getRam(); return (ram[0x400 + 38] & 0x7F) == 0x51 && (oc.m->getBus().readColour (38) & 15) == 2 ? std::string() : std::string ("no red light at row 0, column 38"); } },
        { "network: there - green light", OCTO, { "{NETUP}{WAIT1}" }, [] (const Snap&, const Snap&, Rig&, Rig& oc) {
            auto* ram = oc.m->getBus().getRam(); return (ram[0x400 + 38] & 0x7F) == 0x51 && (oc.m->getBus().readColour (38) & 15) == 5 ? std::string() : std::string ("no green light"); } },
        { "network: F1 while connecting says PLEASE WAIT", OCTO, { "{NETWAIT8}{F1}{WAIT2}" }, [] (const Snap&, const Snap& o, Rig&, Rig&) {
            return has (o, "PLEASE WAIT - CONNECTING TO NETWORK...") ? std::string() : std::string ("no PLEASE WAIT"); } },
        { "network: the share opens by itself when it connects", OCTO, { "{NETWAIT8}{F1}{WAIT2}", "{WAIT9}" }, [] (const Snap&, const Snap& o, Rig&, Rig&) {
            return has (o, "/NET") && has (o, "NET") && ! has (o, "PLEASE WAIT") ? std::string() : std::string ("the share's folder didn't open"); } },
        { "network: any key while waiting - the SD card", OCTO, { "{NETWAIT40}{F1}{WAIT2}", "{RET}{WAIT2}" }, [] (const Snap&, const Snap& o, Rig&, Rig& oc) {
            return has (o, "/TEST") && has (o, "HELLO") && oc.box.cwd == oc.box.top ? std::string() : std::string ("not on the SD card after a key"); } },
        { "network: already up - the browser opens the share", OCTO, { "{NETUP}{F1}{WAIT1}" }, [] (const Snap&, const Snap& o, Rig&, Rig&) {
            return has (o, "/NET") && ! has (o, "PLEASE WAIT") ? std::string() : std::string ("not on the share"); } },
        { "drives: up from the top - SD CARD and NETWORK", OCTO, { "{NETUP}{F1}{WAIT1}", "{F3}{WAIT1}" }, [] (const Snap&, const Snap& o, Rig&, Rig& oc) {
            return has (o, "SD CARD") && has (o, "NETWORK") && oc.box.cwd == "*" ? std::string() : std::string ("no drives level"); } },
        { "drives: SD CARD opens the card", OCTO, { "{NETUP}{F1}{WAIT1}", "{F3}{WAIT1}", "{HOME}{RET}{WAIT1}" }, [] (const Snap&, const Snap& o, Rig&, Rig& oc) {
            return oc.box.cwd == oc.box.top && has (o, "HELLO") ? std::string() : "drive SD went to " + oc.box.cwd; } },
        { "drives: NETWORK off while not connected", OCTO, { "{NETWAIT90}{F1}{WAIT2}", "{RET}{WAIT2}", "{F3}{WAIT1}", "{DOWN}{RET}{WAIT1}" }, [] (const Snap&, const Snap& o, Rig&, Rig&) {
            return has (o, "NETWORK") && has (o, "OFF") && has (o, "NOT CONNECTED") ? std::string() : std::string ("NETWORK not shown as off / no message"); } },
        { "REU: RETURN on a .reu attaches it, back to the list, bar on its .prg", OCTO, { "{F1}{WAIT1}", "{RET}{WAIT1}", "{RET}{WAIT1}", "{DOWN}{RET}{WAIT2}" }, [] (const Snap&, const Snap& o, Rig&, Rig& oc) {
            if (! has (o, "REU ATTACHED")) return std::string ("no REU ATTACHED"); if (oc.box.reuLoads != 1) return "reu loads " + std::to_string (oc.box.reuLoads);
            auto* ram = oc.m->getBus().getRam();
            if ((ram[0x400 + 10 * 40 + 1] & 0x80) == 0) return std::string ("the bar isn't on the .prg"); return std::string(); } },
        { "REU: then RETURN runs the demo without a second load", OCTO, { "{F1}{WAIT1}", "{RET}{WAIT1}", "{RET}{WAIT1}", "{DOWN}{RET}{WAIT2}", "{RET}{WAIT6}" }, [] (const Snap&, const Snap& o, Rig&, Rig& oc) {
            if (oc.box.lastRun != "demoa.prg") return "ran " + oc.box.lastRun; if (oc.box.reuLoads != 1) return "reu loaded " + std::to_string (oc.box.reuLoads) + " times";
            return has (o, "DEMO A REU A") ? std::string() : std::string ("demo A didn't see its REU"); } },
        { "REU: a 16 MB .reu on its own doesn't hang", OCTO, { "{F1}{WAIT1}", "{RET}{WAIT1}", "{DOWN}{DOWN}{DOWN}{DOWN}{RET}{WAIT3}" }, [] (const Snap&, const Snap& o, Rig&, Rig&) {
            return has (o, "REU ATTACHED (16M)") && ! has (o, "LOADING") ? std::string() : std::string ("no REU ATTACHED (16M)"); } },
        { "browser: a long name keeps its build number", OCTO, { "{NETUP}{F1}{WAIT1}" }, [] (const Snap&, const Snap& o, Rig&, Rig&) {
            return has (o, " OCTOPHONIC HORIZON BUILD 10 ") && has (o, " OCTOPHONIC SHOWC..N BUILD 12 ") ? std::string() : std::string ("long names cut wrong"); } },

        // the start screen's own editor: rows 0-23, the bar on 24 never touched; the top box scrolls away
        { "start screen: 30 typed lines scroll rows 0-23, the bar stays, the program as stock's", OCTO, { PROG30, "LIST 280-300\n" },
          [] (const Snap& st, const Snap& o, Rig&, Rig& oc) { std::string w = barcheck (oc); auto* ram = oc.m->getBus().getRam();
            if (! has (o, "300 PRINT \"LINE 30\";30*2")) w += "LIST 280-300 not shown; "; if (ram[0x2B0] != 0xE8) w += "the top box not scrolled away; ";
            if (st.mem != o.mem) w += "the program differs from stock's; "; return w; } },
        { "start screen: one scroll - the top box up a line with the text", OCTO, { "FOR I=1 TO 15:PRINT I:NEXT\n{WAIT1}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { std::string w = barcheck (oc); auto* ram = oc.m->getBus().getRam();
            if (rowtext (oc, 0).substr (0, 6) != "8 SIDS") w += "row 0 not the box's second line: '" + rowtext (oc, 0) + "'; ";
            if (ram[0x2B0] != 0xF8) w += "TOPY " + std::to_string (ram[0x2B0]) + " (want $F8); "; return w; } },
        { "start screen: CLR clears rows 0-23, the bar stays, the box goes", OCTO, { "{CLR}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { std::string w = barcheck (oc); auto* ram = oc.m->getBus().getRam();
            for (int y = 0; y < 24; ++y) if (rowtext (oc, y).find_first_not_of (' ') != std::string::npos) { w += "row " + std::to_string (y) + " not cleared; "; break; }
            if (ram[0x2B0] != 0xE8) w += "the top box still there; "; if (ram[0xD6] != 0) w += "the cursor not home; "; return w; } },
        { "start screen: cursor down past row 23 scrolls, never onto the bar", OCTO, { "{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN}X" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { std::string w = barcheck (oc); auto* ram = oc.m->getBus().getRam();
            if (ram[0xD6] != 23) w += "the cursor on row " + std::to_string (ram[0xD6]) + " (want 23); "; if (rowtext (oc, 23)[0] != 'X') w += "the X not on row 23; "; return w; } },
        { "start screen: RUN - the stock 25-row editor, the bar's row an ordinary one", OCTO, { "10 PRINT 1\n", "RUN\n" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { std::string w; auto* ram = oc.m->getBus().getRam();
            if (ram[0x2A7] != 0) w += "OCTST still set; "; if (ram[0xB0] != 25 || ram[0xB1] != 24 || ram[0xBE] != 23) w += "the editor not at 25 rows; ";
            if (rowtext (oc, 24).find_first_not_of (' ') != std::string::npos) w += "row 24 not cleared; "; return w; } },
        { "start screen: RUN/STOP+RESTORE - the stock 25-row editor", OCTO, { "{RESTORE}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { auto* ram = oc.m->getBus().getRam();
            return ram[0x2A7] == 0 && ram[0xB0] == 25 ? std::string() : std::string ("not back to the stock editor"); } },
        { "stock VIC (no OctoVIC): the words plain, no bar, the 25-row editor", OCTO, { "{WAIT1}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { std::string w; auto* ram = oc.m->getBus().getRam();
            if (rowtext (oc, 0).substr (13, 13) != "OCTOPHONIC 64") w += "no title; "; if (rowtext (oc, 3).substr (0, 22) != "38911 BASIC BYTES FREE") w += "no BYTES FREE; ";
            if (rowtext (oc, 24).find_first_not_of (' ') != std::string::npos) w += "a bar on row 24; ";
            if (ram[0xB0] != 25 || ram[0x2A7] != 0) w += "not the stock editor; "; return w; } },
        // the MiSTer's own menu: C=+F1 (NET b5 says Main is on a MiSTer)
        { "C=+F1 without a MiSTer: nothing", OCTO, { "{CF1}{WAIT1}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { return oc.box.menus == 0 && rowtext (oc, 0).substr (13, 13) == "OCTOPHONIC 64" ? std::string() : std::string ("something happened"); } },
        { "C=+F1 on a MiSTer: MENU to Main", OCTO, { "{MISTER}{WAIT1}", "{CF1}{WAIT1}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { return oc.box.menus == 1 ? std::string() : std::string ("MENU not sent"); } },
        { "browser on a MiSTer: C= held shows the MiSTer's page", OCTO, { "{MISTER}{F1}{WAIT1}", "{CHOLD}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { return rowtext (oc, 24).substr (0, 17) == "C=+F1 MISTER MENU" ? std::string() : std::string ("row 24: '" + rowtext (oc, 24) + "'"); } },
        { "browser on a MiSTer: C=+F1 sends MENU; without one F1 pages", OCTO, { "{MISTER}{F1}{WAIT1}", "{CF1}{WAIT1}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { return oc.box.menus == 1 ? std::string() : std::string ("MENU not sent from the browser"); } },
        { "browser without a MiSTer: C= held, the help as it is", OCTO, { "{F1}{WAIT1}", "{CHOLD}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { return rowtext (oc, 24).substr (0, 7) == "RET RUN" ? std::string() : std::string ("row 24: '" + rowtext (oc, 24) + "'"); } },

        { "settings: START IN", OCTO, { "{CLR}{F1}{WAIT1}", "{F8}{WAIT1}", "{DOWN}{DOWN}{DOWN}{RIGHT}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { return oc.box.lines[3].v == 1 && has (o, "START IN") && has (o, "LAST USED") ? std::string() : std::string ("START IN not changed"); } },
    };


    int pass = 0, fail = 0;
    for (auto& c : cases)
    {
        if (! filter.empty() && c.name.find (filter) == std::string::npos) continue;
        Rig so (stock, drv, d64, folder, shell), oc (octo, drv, d64, folder, shell, c.name.rfind ("stock VIC", 0) == 0);
        so.run (3.5); oc.run (3.5);
        if (c.mode == SAME) { so.step ("RUN\n"); oc.step ("RUN\n"); }   // past the start screen, as every program is
        std::string why; Snap ls, lo;
        for (size_t i = 0; i < c.steps.size(); ++i)
        {
            so.step (c.steps[i]); oc.step (c.steps[i]);
            ls = so.snap(); lo = oc.snap();
            if (c.mode == SAME && why.empty())
            {
                if (ls.screen != lo.screen) why = "screen differs after step " + std::to_string (i + 1);
                else if (ls.mem != lo.mem) { size_t k = 0; while (ls.mem[k] == lo.mem[k]) ++k; char b[80]; std::snprintf (b, sizeof b, "memory differs after step %zu at %s+%zu", i + 1, k < 14 ? "$2B" : "$0801", k < 14 ? k : k - 14); why = b; }
            }
        }
        if (c.check && why.empty()) why = c.check (ls, lo, so, oc);
        if (getenv ("SHOT")) { static int n = 0; std::ofstream f (std::string (getenv ("SHOT")) + std::to_string (n++) + ".idx", std::ios::binary);
            const auto* fb = oc.m->getFramebuffer(); const int W = oc.m->getFramebufferWidth(), H = oc.m->getFramebufferHeight(); for (int i = 0; i < W * H; ++i) { uint8_t c = fb[i] & 15; f.write ((const char*) &c, 1); } }
        if (why.empty()) { ++pass; std::printf ("PASS  %s\n", c.name.c_str()); if (getenv ("VERBOSE")) std::printf ("--- stock\n%s--- V1.1\n%s", ls.text.c_str(), lo.text.c_str()); }
        else { ++fail; std::printf ("FAIL  %s: %s\n--- stock\n%s--- V1.1\n%s", c.name.c_str(), why.c_str(), ls.text.c_str(), lo.text.c_str()); }
    }
    std::printf ("\n%d passed, %d failed\n", pass, fail);
    return fail ? 1 : 0;
}
