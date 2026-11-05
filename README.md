# sdcard-examples - the payload of SD recipe step 015

Binaries only (the source is on the octophonic-v1.1 branch: tools/examples, docs/EXAMPLES.md).
`examples/games/C64/...` is copied onto the card by `tools/sdcard/steps/015-examples.sh`;
`examples/MANIFEST.txt` lists every file with its md5. `tools/sdcard/build-image.sh` fetches
this branch for the release image.

Demos/: every Octophonic demo build, a folder each with its .prg and the .reu it needs, and
Demos/Stock64/ the stock one-SID versions. The rest: the example set (docs/EXAMPLES.md).
All of it Octophonic 64 / Mong00se's own work.
