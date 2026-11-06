; weaver.asm - Octo Weaver Lite build 1: the editor program.  ACME (-f cbm).  By Mong00se (Octophonic 64).
; Memory map: defs.inc.  Layout in the PRG: the stub at $0801, the player at PLAYER, the (default) song at SONG, then the platform
; library + the PLAY program (front.asm) and the editor (editor.asm, roll.asm, disk.asm).
!source "defs.inc"
ENTRY_POINT = editor_start
!source "stub.inc"
        * = PLAYER
!source "player.asm"
        * = SONG
        !binary "out/default.song", SONGSIZE
        * = FRONT
!source "front.asm"
!source "editor.asm"
