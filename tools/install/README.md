# Installing a core on the MiSTer

Every package that carries a core (a core build, an OS build) installs it the same way:

- `install_core.sh` is copied to the MiSTer's /tmp with the .rbf and run there:
  `sh /tmp/install_core.sh C64_Octophonic_<date>_<tag>.rbf <core number>`.
- `core-number.txt` holds the core number: one line of cores, the number grows with every core
  build (6 = V1.1 core build 6 `_v11b6`, 7 = memory build 1 `_mem1`, 8 = memory build 2 `_mem2`,
  9 = core build 7 `_core7` (the one line: V1.1 and the memory work together)).
- A NEWER core on the MiSTer is never replaced without asking (exit 3; the .bat asks Y/N).
- Nothing is deleted: the core that was there goes to `_Octophonic/old cores`.
- `/media/fat/_Octophonic/core.txt` records the core in place (NAME, ORDER).
- The script prints `Now active: <rbf>`; the .bat then restarts the MiSTer.
- An OS build ships the SAME core as the newest core build (never a core of its own line) and its
  .bat calls `install_core.sh` for it instead of moving cores itself.

On the machine, the running core shows its own name: right of OCTOVIC 256 on the start screen,
and its name and build date at the top of the F8 settings page (OctoVIC $D6B8-$D6BF, $D6B4-$D6B6).
