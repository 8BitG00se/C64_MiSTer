// octo_b1.h - Octophonic OS batch 1 helpers (Fix 76 Disks page, Fix 46 NEW DISK, Fix 38/54 video).
// © 2026 Mong00se. Octophonic 64 and OctoVIC by Mong00se (github.com/8BitG00se). GPL v3 or later.
//
// Plain C that also builds as C++: the SAME file is compiled into Octophonic Main (support/octo, from
// octophonic-batch1.patch) and into the Octophonic 64 Emulator's model of Main (octoos.c), so what
// is tested on the PC is the code the MiSTer runs.
//
//   ob1_d64_source()  does a .d64 hold source? (a SEQ file - OCTOCODE saves its source as SEQ)
//   ob1_d64_new()     a blank, formatted 35-track .d64 (as the 1541's NEW command leaves it)
//   ob1_ini_set()     MiSTer.ini: set KEY=VALUE lines, back the old file up first, touch nothing else
#ifndef OCTO_B1_H
#define OCTO_B1_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#if defined(__GNUC__)
#define OB1_UNUSED __attribute__((unused))
#else
#define OB1_UNUSED
#endif

// track -> byte offset of its sector 0 in a .d64 (tracks 1-40)
static OB1_UNUSED long ob1_d64_off(int t, int s)
{
	static const int spt[41] = { 0, 21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21, 19,19,19,19,19,19,19,
	                             18,18,18,18,18,18, 17,17,17,17,17, 17,17,17,17,17 };
	long o = 0;
	if (t < 1 || t > 40 || s < 0 || s >= spt[t]) return -1;
	for (int i = 1; i < t; i++) o += spt[i];
	return (o + s) * 256;
}

// A .d64's source: the first closed SEQ file in its directory, a name ending .ASM preferred.
// NAME (17 bytes) gets it as on the disk (PETSCII, the $A0 padding cut off). 1: found, 0: none
// (or not a .d64 we can read: .g64/.d81/.t64 and files inside a zip are never "with source").
static OB1_UNUSED int ob1_d64_source(const char *path, char *name)
{
	name[0] = 0;
	FILE *f = fopen(path, "rb");
	if (!f) return 0;
	fseek(f, 0, SEEK_END);
	long size = ftell(f);
	if (size != 174848 && size != 175531 && size != 196608 && size != 197376) { fclose(f); return 0; }
	unsigned char sec[256];
	int t = 18, s = 1, guard = 0, found = 0;
	while (t && guard++ < 40)
	{
		long o = ob1_d64_off(t, s);
		if (o < 0 || fseek(f, o, SEEK_SET) || fread(sec, 1, 256, f) != 256) break;
		for (int e = 0; e < 8; e++)
		{
			const unsigned char *d = sec + e * 32;
			if ((d[2] & 0x87) != 0x81) continue;              // a closed SEQ file
			char n[17];
			int l = 0;
			for (; l < 16 && d[5 + l] != 0xA0; l++) n[l] = (char)d[5 + l];
			n[l] = 0;
			if (!l) continue;
			int is_asm = l > 4 && !strncasecmp(n + l - 4, ".asm", 4);
			if (!found || is_asm) { memcpy(name, n, l + 1); found = is_asm ? 2 : 1; }
			if (found == 2) { fclose(f); return 1; }
		}
		t = sec[0]; s = sec[1];
	}
	fclose(f);
	return found ? 1 : 0;
}

// A blank, formatted .d64 (35 tracks): BAM on 18/0, an empty directory on 18/1, the disk's NAME
// (PETSCII, at most 16), ID "OC", DOS type "2A". 0: written; -1: already there; -2: can't write.
static OB1_UNUSED int ob1_d64_new(const char *path, const char *dname)
{
	FILE *f = fopen(path, "rb");
	if (f) { fclose(f); return -1; }                        // never over a disk that is there
	unsigned char *img = (unsigned char *)calloc(174848, 1);
	if (!img) return -2;
	long b = ob1_d64_off(18, 0), d = ob1_d64_off(18, 1);
	img[b] = 18; img[b + 1] = 1; img[b + 2] = 0x41; img[b + 3] = 0;
	for (int t = 1; t <= 35; t++)
	{
		int n = t <= 17 ? 21 : t <= 24 ? 19 : t <= 30 ? 18 : 17;
		unsigned long bits = (1UL << n) - 1;
		if (t == 18) { bits &= ~3UL; n -= 2; }                 // 18/0 the BAM, 18/1 the directory
		unsigned char *e = img + b + 4 * t;
		e[0] = (unsigned char)n; e[1] = bits & 255; e[2] = (bits >> 8) & 255; e[3] = (bits >> 16) & 255;
	}
	memset(img + b + 0x90, 0xA0, 0x1B);
	for (int i = 0; i < 16 && dname[i]; i++) img[b + 0x90 + i] = (unsigned char)dname[i];
	img[b + 0xA2] = 'O'; img[b + 0xA3] = 'C'; img[b + 0xA5] = '2'; img[b + 0xA6] = 'A';
	img[d] = 0; img[d + 1] = 0xFF;
	f = fopen(path, "wb");
	if (!f) { free(img); return -2; }
	size_t w = fwrite(img, 1, 174848, f);
	free(img);
	if (fclose(f) || w != 174848) { remove(path); return -2; }
	return 0;
}

// MiSTer.ini: every ACTIVE line of each KEY (any section, so no core section overrides it) gets the
// new VALUE; a key with no line is added under [MiSTer] (a [MiSTer] section is made if there is
// none). Comments, other keys, the order and the line ends are kept. Nothing to change: the file is
// not written at all. Otherwise the old file is copied to BACKUP first (when BACKUP is given).
// Returns the number of keys changed, -1 if it can't be written.
static OB1_UNUSED int ob1_ini_set(const char *ini, const char *const *keys, const char *const *vals, int n, const char *backup)
{
	char *old = NULL; long ol = 0;
	FILE *f = fopen(ini, "rb");
	if (f)
	{
		fseek(f, 0, SEEK_END); ol = ftell(f); fseek(f, 0, SEEK_SET);
		old = (char *)malloc(ol + 1);
		if (!old) { fclose(f); return -1; }
		ol = (long)fread(old, 1, ol, f); old[ol] = 0;
		fclose(f);
	}
	size_t cap = (size_t)ol * 2 + 128 * (n + 2) + 1024, ol2 = 0;
	char *out = (char *)malloc(cap);
	if (!out) { free(old); return -1; }
	int seen[16] = { 0 }, changed = 0, have_mister = 0;
	if (n > 16) n = 16;
	const char *p = old ? old : "";
	while (*p)
	{
		const char *e = strchr(p, '\n');
		size_t ll = e ? (size_t)(e - p) + 1 : strlen(p);
		const char *q = p;
		while (q < p + ll && (*q == ' ' || *q == '\t')) q++;
		int done = 0;
		if (*q == '[' && !strncasecmp(q, "[MiSTer]", 8))
		{
			have_mister = 1;
			memcpy(out + ol2, p, ll); ol2 += ll; done = 1;
			// keys with no active line anywhere: added right under the header (found in a first pass)
			for (int k = 0; k < n; k++)
			{
				int any = 0;
				const char *r = old;
				size_t kl = strlen(keys[k]);
				while (r && *r)
				{
					while (*r == ' ' || *r == '\t') r++;
					if (!strncasecmp(r, keys[k], kl))
					{
						const char *x = r + kl;
						while (*x == ' ' || *x == '\t') x++;
						if (*x == '=') { any = 1; break; }
					}
					r = strchr(r, '\n');
					if (r) r++;
				}
				if (!any)
				{
					ol2 += (size_t)sprintf(out + ol2, "%s=%s\n", keys[k], vals[k]);
					seen[k] = 1; changed++;
				}
			}
		}
		for (int k = 0; !done && k < n; k++)
		{
			size_t kl = strlen(keys[k]);
			if (strncasecmp(q, keys[k], kl)) continue;
			const char *x = q + kl;
			while (*x == ' ' || *x == '\t') x++;
			if (*x != '=') continue;
			x++;
			while (*x == ' ' || *x == '\t') x++;
			const char *v = x;
			while (x < p + ll && *x != ';' && *x != '\r' && *x != '\n') x++;
			const char *ve = x;
			while (ve > v && (ve[-1] == ' ' || ve[-1] == '\t')) ve--;
			seen[k] = 1;
			if ((size_t)(ve - v) == strlen(vals[k]) && !strncasecmp(v, vals[k], ve - v)) break;   // already so
			// the line again: KEY=VALUE, then whatever followed the old value (its comment, its line end)
			ol2 += (size_t)sprintf(out + ol2, "%s=%s", keys[k], vals[k]);
			size_t rest = (size_t)(p + ll - ve);
			if (*ve == ';') { out[ol2++] = ' '; out[ol2++] = ' '; }
			memcpy(out + ol2, ve, rest); ol2 += rest;
			changed++; done = 1;
		}
		if (!done) { memcpy(out + ol2, p, ll); ol2 += ll; }
		p += ll;
	}
	if (!have_mister)
	{
		// no [MiSTer] section: one at the very top, with every key
		size_t hl = 0;
		char head[1024];
		hl += (size_t)sprintf(head + hl, "[MiSTer]\n");
		for (int k = 0; k < n; k++) { hl += (size_t)sprintf(head + hl, "%s=%s\n", keys[k], vals[k]); if (!seen[k]) changed++; }
		memmove(out + hl, out, ol2); memcpy(out, head, hl); ol2 += hl;
	}
	if (!changed) { free(old); free(out); return 0; }
	if (backup && old)
	{
		FILE *bf = fopen(backup, "wb");
		if (!bf || fwrite(old, 1, ol, bf) != (size_t)ol) { if (bf) fclose(bf); free(old); free(out); return -1; }
		fclose(bf);
	}
	char tmp[1100];
	snprintf(tmp, sizeof(tmp), "%s.new", ini);
	f = fopen(tmp, "wb");
	if (!f) { free(old); free(out); return -1; }
	size_t w = fwrite(out, 1, ol2, f);
	int bad = fclose(f) || w != ol2;
	free(old); free(out);
	if (bad || rename(tmp, ini)) { remove(tmp); return -1; }
	return changed;
}

// A file on a .d64, by NAME (ASCII; letters match either case): its bytes into BUF (at most MAX).
// Returns the length, -1 not on the disk (or not a .d64 we can read).
OB1_UNUSED static long ob1_d64_read(const char *path, const char *want, unsigned char *buf, long max)
{
	FILE *f = fopen(path, "rb");
	if (!f) return -1;
	unsigned char sec[256];
	int t = 18, s = 1, guard = 0, ft = 0, fs = 0;
	while (t && guard++ < 40 && !ft)
	{
		long o = ob1_d64_off(t, s);
		if (o < 0 || fseek(f, o, SEEK_SET) || fread(sec, 1, 256, f) != 256) break;
		for (int e = 0; e < 8 && !ft; e++)
		{
			const unsigned char *d = sec + e * 32;
			if (!(d[2] & 0x80) || (d[2] & 7) == 0) continue;     // closed, not DEL
			int l = 0;
			for (; l < 16 && d[5 + l] != 0xA0; l++) ;
			if ((int)strlen(want) != l) continue;
			int same = 1;
			for (int i = 0; i < l && same; i++)
			{
				int a = d[5 + i], b = (unsigned char)want[i];
				if (a >= 0xC1 && a <= 0xDA) a -= 0x80;              // shifted letters as plain ones
				if (b >= 'a' && b <= 'z') b -= 0x20;
				if (a >= 'a' && a <= 'z') a -= 0x20;
				same = a == b;
			}
			if (same) { ft = d[3]; fs = d[4]; }
		}
		if (!ft) { t = sec[0]; s = sec[1]; }
	}
	long n = 0;
	guard = 0;
	while (ft && guard++ < 800)
	{
		long o = ob1_d64_off(ft, fs);
		if (o < 0 || fseek(f, o, SEEK_SET) || fread(sec, 1, 256, f) != 256) break;
		int last = sec[0] ? 255 : sec[1];
		for (int i = 2; i <= last && n < max; i++) buf[n++] = sec[i];
		ft = sec[0]; fs = sec[1];
	}
	fclose(f);
	return guard ? n : -1;
}

// PETSCII text (as OCTOCODE saves it: lines end with RETURN) to ASCII, the same table as COMPILE's
OB1_UNUSED static int ob1_p2a(unsigned char c)
{
	if (c == 0x0D) return '\n';
	if (c >= 0x41 && c <= 0x5A) return c + 0x20;
	if (c >= 0xC1 && c <= 0xDA) return c - 0x80;
	if (c >= 0x61 && c <= 0x7A) return c - 0x20;
	if (c >= 0x20 && c <= 0x40) return c;
	switch (c) { case 0x5B: return '['; case 0x5D: return ']'; case 0x5C: return '\\'; case 0x5E: return '^';
	             case 0x5F: case 0xA4: return '_'; case 0xDB: return '{'; case 0xDD: return '}';
	             case 0xDC: return '|'; case 0xDE: return '~'; case 0xA0: return ' '; }
	return '?';
}

// Fix 57 (the file-only part): a big project in several files. Before ACME runs on DIR/MAIN, every
//   !source "name"   (or !src)  and   !binary "name"   (or !bin)
// line whose file is not in DIR yet is taken off the disk in drive 8 (D64): source files from PETSCII
// to ASCII (and searched for their own !source lines in turn), binary files as they are. SAY gets one
// line per file joined (and per file not found). Returns how many were joined.
OB1_UNUSED static int ob1_join_sources(const char *dir, const char *main_asm, const char *d64, void (*say)(const char *))
{
	char queue[24][64];
	int nq = 0, joined = 0;
	snprintf(queue[nq++], 64, "%s", main_asm);
	unsigned char *buf = (unsigned char *)malloc(65536);
	if (!buf) return 0;
	for (int qi = 0; qi < nq; qi++)
	{
		char path[1200];
		snprintf(path, sizeof(path), "%s/%s", dir, queue[qi]);
		FILE *f = fopen(path, "rb");
		if (!f) continue;
		char line[512];
		while (fgets(line, sizeof(line), f))
		{
			char *p = line;
			while (*p == ' ' || *p == '\t') p++;
			int bin = 0;
			if (!strncasecmp(p, "!source", 7) || !strncasecmp(p, "!src", 4)) bin = 0;
			else if (!strncasecmp(p, "!binary", 7) || !strncasecmp(p, "!bin", 4)) bin = 1;
			else continue;
			char *q1 = strchr(p, '"');
			if (!q1) continue;
			char *q2 = strchr(q1 + 1, '"');
			if (!q2 || q2 - q1 - 1 <= 0 || q2 - q1 - 1 > 16) continue;
			char nm[20];
			memcpy(nm, q1 + 1, q2 - q1 - 1);
			nm[q2 - q1 - 1] = 0;
			if (strchr(nm, '/') || strchr(nm, '\\') || strstr(nm, "..")) continue;
			char out[1200];
			snprintf(out, sizeof(out), "%s/%s", dir, nm);
			FILE *t = fopen(out, "rb");
			if (t) { fclose(t); continue; }                      // there already: ACME uses that one
			char msg[96];
			long n = d64 && d64[0] ? ob1_d64_read(d64, nm, buf, 65536) : -1;
			if (n < 0) { snprintf(msg, sizeof(msg), "%s: not on the disk", nm); if (say) say(msg); continue; }
			FILE *w = fopen(out, "wb");
			if (!w) continue;
			for (long i = 0; i < n; i++)
			{
				if (bin) fputc(buf[i], w);
				else if (buf[i] != 0x0A) fputc(ob1_p2a(buf[i]), w);
			}
			fclose(w);
			joined++;
			snprintf(msg, sizeof(msg), "Joined %s from the disk", nm);
			if (say) say(msg);
			if (!bin && nq < 24) snprintf(queue[nq++], 64, "%s", nm);
		}
		fclose(f);
	}
	free(buf);
	return joined;
}

// The four screen set-ups (Fix 38's VIDEO OUT, Fix 54's DUAL SCREEN set-up page) and what each
// writes to MiSTer.ini. vsync_adjust=2 stays in all four (Fix 43: HDMI follows the core's 50 Hz).
// Neal's own JVC CRT (VGA to 5 BNC, 15 kHz) + HDMI is "HDMI + CRT 15K" - the same two lines his
// DEV step 910 has always set.
#define OB1_NVIDEO 4
OB1_UNUSED static const char *ob1_video_name[OB1_NVIDEO] = { "HDMI ONLY", "HDMI+VGA 31K", "HDMI+CRT 15K", "CRT ONLY 15K" };
OB1_UNUSED static const char *ob1_video_key[OB1_NVIDEO]  = { "hdmi", "hdmi+vga31", "hdmi+crt15", "crt15" };
OB1_UNUSED static const char *ob1_video_ini_keys[3] = { "vga_scaler", "forced_scandoubler", "vsync_adjust" };
OB1_UNUSED static const char *ob1_video_ini_vals[OB1_NVIDEO][3] = {
	{ "0", "0", "2" },      // HDMI only: MiSTer's own VGA defaults (nothing on the VGA port)
	{ "0", "1", "2" },      // a PC VGA monitor: the VGA picture line-doubled to 31 kHz
	{ "0", "0", "2" },      // a 15 kHz CRT on VGA (BNC/SCART): native 15 kHz, no scandoubler
	{ "0", "0", "2" },      // the CRT on its own: the same native 15 kHz VGA picture
};
// SCALING (Fix 38's "sharp pixels"): FILL = MiSTer's default (fit the screen height, can be uneven
// on a 4K TV), SHARP = integer scale only (every C64 pixel the same size on the TV)
#define OB1_NSCALE 2
OB1_UNUSED static const char *ob1_scale_name[OB1_NSCALE] = { "FILL SCREEN", "SHARP PIXELS" };
OB1_UNUSED static const char *ob1_scale_key[OB1_NSCALE]  = { "fill", "sharp" };
OB1_UNUSED static const char *ob1_scale_ini_val[OB1_NSCALE] = { "0", "1" };    // vscale_mode

#endif
