# Front-screen cards

Each demo's own picture for the MiSTer's tty2oled front screen: 256 x 64 in 16 greys, saved as `.gsc` (8192 bytes, two pixels
a byte, the left one high). tty2oled shows the card named after the running core (`/tmp/CORENAME`) from `tty2oled/pics_pri`.
The recipe step `tools/sdcard/steps/085-oled-pics.sh` puts them there (payload `tools/sdcard/files/tty2oled/pics_pri/`).
The animated octopus logo is the screen's own firmware: 8BitG00se/octophonic-tty2oled.

| card | demo |
|---|---|
| `GeometrySings.gsc` | Geometry Sings - the finale's nine-fold spiral beside the title (`make_card.py geometry`) |

A card only shows when the core's name matches it: the demo needs its own launcher with `<setname>` (e.g. GeometrySings),
or the now-playing feature in Octophonic Main (to do) that names the screen after the demo being run.
