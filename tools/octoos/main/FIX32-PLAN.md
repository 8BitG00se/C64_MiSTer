# Fix 32: no MiSTer loading bar between the white noise and the Octo KERNAL

What Neal sees at power-on: the white noise (the stock menu core, which he likes), then the grey MiSTer
loading bar, then the Octo KERNAL. The goal is white noise, then the Octo KERNAL, with nothing in between.

## Where the bar comes from (from reading the Main_MiSTer source, afb917f, and our fork)

- Loading the core itself (`fpga_load_rbf`) draws nothing; the screen just goes blank while the FPGA
  is reconfigured. So the bar is not the core load.
- The grey bar is `ProgressMessage("Loading", ...)` in menu.cpp. Main calls it for every file it sends
  into a core (`user_io_file_tx`, `user_io_file_tx_a`): boot ROMs, auto-mounted files, programs.
- `octophonic-quiet-load.patch` already silences it with `if (octo_os_active()) return;`.
- **The gap:** `octo_os_active()` only turns on in `octo_os_core_init()`, which runs near the END of
  `user_io_init()` (user_io.cpp line ~1845). Everything Main loads into the core before that point
  (the boot ROMs `boot.rom` / `boot0-3.rom` from games/C64, the core's saved mounts) still gets
  the bar. Power-on is exactly that moment.

## The fix (a Main change, so a new Octophonic Main build)

1. In `support/octo/octo.cpp` add `octo_os_core_probe()`. It reads os.ini, checks `is_c64()` and polls
   the mailbox for `OCTO_MAGIC`. The core's mailbox is live as soon as the FPGA is configured, so
   this works at the very start. It sets a `boot_quiet` flag.
2. Call it in `user_io_init()` right after the core type is known, BEFORE the config/boot-ROM loads.
3. Add `octo_os_quiet()` (= `os_active || boot_quiet`) and use it in `ProgressMessage` in place of
   `octo_os_active()`.
4. A feedback loop: every time a bar is held back, `os_log` names the file. Then update.log tells
   us exactly what was loading at power-on, instead of guessing. If something still shows a bar,
   the log names it.
5. Only our core is affected: the stock C64 core has no mailbox, so it keeps its normal bar.

## Not done yet (on purpose)

- Nothing is changed on the MiSTer or the card. This is the written plan only.
- There is no ARM compiler in this session, so the Main build has to be done in the next
  Main build round (Monday's push, together with Fix 1 and the MiSTer compile patch).
- It needs a new Main on the card, so the install **will restart the MiSTer**; Neal gets told first,
  as always, and it is logged in update.log.
- Worth checking at the same time: whether his card has a `games/C64/boot*.rom` from an older
  setup. If it does, that is most likely the file behind the bar, and with this fix it goes in silently.
