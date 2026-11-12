// Octo Remaster (Build 12): Main's automatic pack maker, on a PC - the same code as in Octophonic Main
// (taken out of tools/octoos/main/octophonic-rgb256.patch between OCTO-PACK-BEGIN and OCTO-PACK-END by
// autopack.sh), so the proof stills show exactly what the MiSTer makes.          (c) 2026 Mong00se
//   autopack GAME OUT.rgb [grade 0-4] [strength 0-3]
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>
#include <math.h>
#include <vector>
#include <string>
#include "autopack_block.inc"
int main(int argc, char **argv)
{
	if (argc < 3) { fprintf(stderr, "autopack GAME OUT.rgb [grade] [strength]\n"); return 1; }
	std::vector<uint8_t> d(4 * 1024 * 1024);
	FILE *f = fopen(argv[1], "rb");
	if (!f) { perror(argv[1]); return 1; }
	size_t n = fread(d.data(), 1, d.size(), f);
	fclose(f);
	int bd, bg;
	pk_scan(d.data(), n, &bd, &bg);
	printf("found: border %d, background %d\n", bd, bg);
	if (bg < 0) bg = 0;
	if (bd < 0) bd = (bg == 0) ? 0 : 14;
	static uint8_t pk[PK_SIZE];
	pk_build(pk, "TEST", bg, bd, argc > 3 ? atoi(argv[3]) : 0, argc > 4 ? atoi(argv[4]) : 2);
	f = fopen(argv[2], "wb");
	fwrite(pk, 1, PK_SIZE, f);
	fclose(f);
	return 0;
}
