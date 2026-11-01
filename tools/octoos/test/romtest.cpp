// romtest: the Octophonic V1.1 ROM against the stock Commodore ROMs, side by side.
// Every case runs on a fresh machine with each ROM set (a real 1541 with a test disk on the bus,
// and for the V1.1 ROM a model of Octophonic Main's mailbox serving a test folder). After each
// step the screen and BASIC's memory are compared; cases marked OCTO check what the V1.1 ROM
// must do differently (start screen, tape gone, @ / and F1). Keys go through the keyboard matrix
// exactly as a person types them.
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

static std::vector<uint8_t> rd (const std::string& p) { std::ifstream f (p, std::ios::binary); return std::vector<uint8_t> ((std::istreambuf_iterator<char> (f)), {}); }

// ------------------------------------------------------------------ the mailbox (Main's model)
struct Entry { std::string name; int dir; long long size; };
struct Mailbox
{
    int ticks = 0;                       // Main answers 40 ms after the bell (its poll, the SPI, the work)
    struct Line { std::string label; std::vector<std::string> ch; int v; };
    std::vector<Line> lines = { { "CHIP PRESET", { "PLAIN", "WARM", "CLASSIC" }, 0 }, { "MY CHIP LEFT", { "MOS_6581_3184", "MOS_6581_5084" }, 0 }, { "MY CHIP RIGHT", { "CSG_8580R5_3591", "MOS_8580R5_4687" }, 0 },
        { "LEFT SIDS 1357", { "6581", "8580" }, 0 }, { "RIGHT SIDS 2468", { "6581", "8580" }, 0 }, { "MY CHIPS", { "ON", "OFF" }, 0 }, { "OCTOPHONIC", { "8 SIDS", "4 SIDS", "OFF" }, 0 },
        { "OCTOSID FX", { "OFF", "CHORUS", "ECHO", "CHORUS+ECHO" }, 0 }, { "SPLIT SCREENS", { "OFF", "VGA C64+HDMI" }, 0 }, { "TURBO MODE", { "C128", "OFF", "SMART" }, 1 }, { "TURBO SPEED", { "2X", "3X", "4X" }, 0 } };
    bool mute = false; int presetSel = 0; std::string boot = "PLAIN"; int saves = 0;
    std::string top, cwd, shell; uint8_t mb[16] = {}; std::string name; bool unlocked = false, stage = false; int ran = 0; std::string lastRun;
    uint8_t* ram = nullptr;
    void list (std::vector<Entry>& v)
    {
        v.clear(); DIR* d = opendir (cwd.c_str()); if (! d) return;
        while (auto* de = readdir (d)) { if (de->d_name[0] == '.') continue; struct stat st; std::string p = cwd + "/" + de->d_name; if (stat (p.c_str(), &st)) continue; v.push_back ({ de->d_name, S_ISDIR (st.st_mode) ? 1 : 0, (long long) st.st_size }); }
        closedir (d);
        std::sort (v.begin(), v.end(), [] (const Entry& a, const Entry& b) { if (a.dir != b.dir) return a.dir > b.dir; return strcasecmp (a.name.c_str(), b.name.c_str()) < 0; });
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
    int up() const { return cwd != top ? 1 : 0; }
    int type_of (const Entry& e) { if (e.dir) return 0; auto x = ext_of (e.name); for (auto& c : x) c = (char) tolower (c);
        if (x == "prg" || x.empty()) return 1; if (x == "d64" || x == "g64" || x == "d81") return 2; if (x == "crt") return 3; return 4; }
    void run_entry (const Entry& e)
    {
        int t = type_of (e);
        if (t == 2) reply (2, 0, -1, 8); else if (t == 1 || t == 3) { reply (2, 0, -1, 1); ran++; lastRun = e.name; } else reply (0x85, 0);
    }
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
                if (part.empty()) continue; if (part == "..") { if (cwd != top) cwd = cwd.substr (0, cwd.rfind ('/')); continue; }
                list (v); int kk = find (v, part, 1); if (kk < 0) { reply (find (v, part, 0) >= 0 ? 0x82 : 0x81, 0); cwd = keep; return; } cwd += "/" + v[(size_t) kk].name; }
            reply (2, 0);
        }
        else if (mb[0] == 4) { int kk = find (v, nm, 0); if (kk < 0) { reply (0x81, 0); return; } run_entry (v[(size_t) kk]); }
        else if (mb[0] == 6) {
            int count = mb[7] ? mb[7] : 17; int total = (int) v.size() + up(); std::vector<uint8_t> o;
            std::string path = cwd.substr (top.size()); if (path.empty()) path = "/"; path = "/TEST" + (path == "/" ? std::string() : path);
            if (path.size() > 40) path = "..." + path.substr (path.size() - 37);
            for (int i = 0; i < 40; ++i) o.push_back (i < (int) path.size() ? pet (path[(size_t) i]) : ' ');
            int w = 0;
            for (int i = len; i < total && w < count; ++i, ++w) {
                uint8_t rec[32]; std::memset (rec, ' ', 32);
                if (up() && i == 0) { rec[0] = 5; rec[1] = rec[2] = 0; rec[3] = 'D'; rec[4] = 'I'; rec[5] = 'R'; rec[6] = '.'; rec[7] = '.'; }
                else { const auto& e = v[(size_t) (i - up())]; long long bl = e.dir ? 0 : (e.size + 253) / 254; if (bl > 65535) bl = 65535;
                    rec[0] = (uint8_t) type_of (e); rec[1] = bl & 255; rec[2] = (bl >> 8) & 255;
                    std::string x = e.dir ? "DIR" : ext_of (e.name); for (int k = 0; k < 3 && k < (int) x.size(); ++k) rec[3 + k] = pet (x[(size_t) k]);
                    std::string n = e.dir ? e.name : base_of (e.name); for (int k = 0; k < 26 && k < (int) n.size(); ++k) rec[6 + k] = pet (n[(size_t) k]); }
                o.insert (o.end(), rec, rec + 32); }
            ramw (addr ? addr : 0xCA00, o); reply (2, total, -1, w);
        }
        else if (mb[0] == 7) {
            int total = (int) v.size() + up(); if (len < 0 || len >= total) { reply (0x81, 0); return; }
            if (up() && len == 0) { cwd = cwd.substr (0, cwd.rfind ('/')); reply (2, 0, -1, 0x10); return; }
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
        else if (mb[0] == 0x0F) {
            auto d = rd (shell); if (d.size() < 3) { reply (0x81, 0); return; }
            uint16_t at = d[0] | d[1] << 8; ramw (at, std::vector<uint8_t> (d.begin() + 2, d.end())); reply (2, at);
        }
        else reply (0x8F, 0);
    }
    void attach (C64Machine& m)
    {
        m.getBus().ioWriteHook = [this] (uint16_t a, uint8_t v) -> bool {
            if (a >= 0xD000 && a < 0xD400 && (a & 0x3F) == 0x3F) { if (v == 0x4F) stage = true; else if (v == 0x38 && stage) { unlocked = true; stage = false; } else { unlocked = false; stage = false; } return false; }
            if (! unlocked || a < 0xD600 || a >= 0xD700) return false;
            const uint8_t r = a & 0xFF;
            if (r >= 0xF0) { const uint8_t i = r & 15;
                if (i == 0) { mb[0] = v; mb[1] = 1; ticks = 4; }
                else if (i == 8) { if (name.size() < 32) name += (char) v; }
                else if (i == 9) name.clear();
                else mb[i] = v; }
            return true;
        };
        m.getBus().ioReadHook = [this] (uint16_t a, uint8_t& v) -> bool {
            if (! unlocked || a < 0xD600 || a >= 0xD700) return false;
            const uint8_t r = a & 0xFF;
            if (r >= 0xF0) { const uint8_t i = r & 15; v = i == 0xC ? 1 : i == 8 ? (uint8_t) name.size() : mb[i]; return true; }
            v = r == 0x1E ? 0x8C : r == 0x1F ? 2 : 0; return true;
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
    std::unique_ptr<C64Machine> own; C64Machine* m; Mailbox box; D64Image disk; std::vector<float> l, r;
    Rig (const Roms& roms, const std::vector<uint8_t>& driveRom, const std::vector<uint8_t>& d64, const std::string& folder, const std::string& shell)
        : l (480), r (480)
    {
        own = std::make_unique<C64Machine>(); m = own.get();
        m->prepare (48000.0, false);
        m->setRoms (roms.k.data(), roms.k.size(), roms.b.data(), roms.b.size(), roms.ch.data(), roms.ch.size());
        std::string err; disk.load (d64.data(), d64.size(), err);
        m->setDriveRom (driveRom.data(), driveRom.size());
        m->insertDiskInDrive (disk);
        m->reset();
        box.ram = m->getBus().getRam(); box.top = box.cwd = folder; box.shell = shell;
        if (roms.octo) box.attach (*m);
    }
    void run (double s) { const auto fa = m->getFrameCount(); while (m->getFrameCount() < fa + (uint64_t) (s * 50)) { m->renderStereo (l.data(), r.data(), 480); if (box.ticks > 0 && --box.ticks == 0 && ! box.mute) box.serve(); } }
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
                else if (k == "STOP") key (7, 7, false); else if (k == "SSTOP") key (7, 7, true);
                else if (k == "RESTORE") { m->setKeyDown (7, 7, true); run (0.05); m->getCpu().triggerNmi(); run (0.2); m->setKeyDown (7, 7, false); run (0.5); }
                else if (k.rfind ("WAIT", 0) == 0) run (atof (k.c_str() + 4));
                else if (k == "MUTE") box.mute = true;
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

    const std::string PROG30 = [] { std::string s; for (int i = 1; i <= 30; ++i) s += std::to_string (i * 10) + " PRINT \"LINE " + std::to_string (i) + "\";" + std::to_string (i) + "*2\n"; return s; }();

    std::vector<Case> cases = {
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
        { "@NAME, @.., /NAME", OCTO, { "{CLR}@SUB\n", "{CLR}@..\n", "{CLR}/HELLO\n" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { if (oc.box.ran != 1) return std::string ("V1.1: /HELLO did not run"); if (! has (o, "LOADING")) return std::string ("no LOADING"); return std::string(); } },
        { "a BASIC line still works after @", OCTO, { "{CLR}@\n", "10 PRINT \"AFTER\"\n", "RUN\n" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "\nAFTER") ? std::string() : std::string ("no AFTER"); } },
        { "F1 opens the browser", OCTO, { "{CLR}{F1}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "TYPE BLKS") && has (o, "HELLO") ? std::string() : std::string ("no browser"); } },
        { "browser: down, RETURN runs", OCTO, { "{CLR}{F1}{WAIT1}", "{DOWN}", "{RET}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { return oc.box.ran == 1 && oc.box.lastRun == "hello.prg" ? std::string() : "browser ran '" + oc.box.lastRun + "'"; } },
        { "browser: into a folder and back up", OCTO, { "{CLR}{F1}{WAIT1}", "{RET}{WAIT1}", "{F3}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { return oc.box.cwd == oc.box.top && has (o, "HELLO") ? std::string() : std::string ("not back at the top"); } },
        { "browser: F7 back to READY, BASIC intact", OCTO, { "{CLR}10 PRINT \"KEPT\"\n", "{F1}{WAIT1}", "{F7}{WAIT1}", "RUN\n" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "\nKEPT") ? std::string() : std::string ("program lost"); } },
        { "browser: joystick down and fire", OCTO, { "{CLR}{F1}{WAIT1}", "{JDOWN}", "{JFIRE}{WAIT1}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { return oc.box.ran == 1 ? std::string() : std::string ("fire did not run"); } },
        { "settings: F8, change left SIDs", OCTO, { "{CLR}{F1}{WAIT1}", "{F8}{WAIT1}", "{DOWN}{DOWN}{DOWN}{RIGHT}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { return oc.box.lines[3].v == 1 && has (o, "LEFT SIDS 1357") && has (o, "8580") ? std::string() : std::string ("left SIDs not changed"); } },
        { "settings: chip preset picked and started", OCTO, { "{CLR}{F1}{WAIT1}", "{F8}{WAIT1}", "{RIGHT}{WAIT1}", "{RET}{WAIT1}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { return oc.box.boot == "WARM" ? std::string() : "boot preset " + oc.box.boot; } },
        { "settings: F7 back to the files, then RUN a file", OCTO, { "{CLR}{F1}{WAIT1}", "{F8}{WAIT1}", "{F7}{WAIT1}", "{DOWN}{RET}{WAIT1}" },
          [] (const Snap&, const Snap&, Rig&, Rig& oc) { return oc.box.lastRun == "hello.prg" ? std::string() : "ran '" + oc.box.lastRun + "'"; } },
        { "browser: a disk goes in and loads", OCTO, { "{CLR}{F1}{WAIT1}", "{DOWN}{DOWN}{RET}{WAIT12}" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "DISK IN DRIVE 8") && has (o, "\nHI") ? std::string() : std::string ("disk not loaded"); } },
        { "browser: F2 start folder, HOME, page keys", OCTO, { "{CLR}{F1}{WAIT1}", "{RET}{WAIT1}", "{F2}{WAIT1}", "{F5}{F1}{HOME}{WAIT1}" },
          [] (const Snap&, const Snap& o, Rig&, Rig& oc) { return oc.box.cwd == oc.box.top && has (o, "ZDISK") ? std::string() : std::string ("not at the start folder"); } },
        { "no reply: 3 s timeout message", OCTO, { "{CLR}{MUTE}@\n{WAIT4}" },
          [] (const Snap&, const Snap& o, Rig&, Rig&) { return has (o, "NO REPLY FROM OCTOPHONIC MAIN (CMD 01)") ? std::string() : std::string ("no timeout message"); } },
    };

    int pass = 0, fail = 0;
    for (auto& c : cases)
    {
        if (! filter.empty() && c.name.find (filter) == std::string::npos) continue;
        Rig so (stock, drv, d64, folder, shell), oc (octo, drv, d64, folder, shell);
        so.run (3.5); oc.run (3.5);
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
