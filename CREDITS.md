# Credits

Octophonic 64 (the core's Octophonic changes, OctoVIC, the eight SIDs, Octophonic OS, the
examples, the emulator's Octophonic parts) is **Octophonic 64 / Mong00se**. It is built on, and
forked from, these projects - thank you to everyone who made them:

| Project | By | Licence | Where |
|---|---|---|---|
| The MiSTer C64 core (this repository's base) | based on FPGA64 by Peter Wendrich, with later work by Sorgelig and many contributors | GNU GPL v2 or later (see `c64.sv`) | https://github.com/MiSTer-devel/C64_MiSTer |
| MiSTer Main (Octophonic Main is a patched build of it) and the MiSTer framework (`sys/`) | Sorgelig and the MiSTer contributors | GNU GPL v3 | https://github.com/MiSTer-devel/Main_MiSTer |
| VICE (the Octophonic 64 Emulator is a fork of its x64sc) | the VICE team | GNU GPL v2 or later | https://vice-emu.sourceforge.io |
| ACME, the 6502 cross-assembler (OCTOCODE's compiler, the examples) | Marco Baye | GNU GPL v2 or later | https://sourceforge.net/projects/acme-crossass |
| Mr. Fusion, the MiSTer SD card installer image (Octophonic Fusion is built on it) | the MiSTer-devel Mr. Fusion contributors | GNU GPL v3 | https://github.com/MiSTer-devel/mr-fusion |
| tty2oled, the front-screen firmware (the Octophonic front screen is a fork) | venice1200 and the tty2oled contributors | GNU GPL v3 | https://github.com/venice1200/MiSTer_tty2oled |
| The front-screen board (tty2oled hardware) | Antonio Villena | - | - |

No Commodore ROMs are in this repository or in anything it builds: the emulator and the image use
the owner's own ROMs, and the KERNAL changes are a patch.
