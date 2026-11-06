; stub.inc - the BASIC line  10 SYS2061  and the entry jump.  NAME PLAY patches the entry word to play_start.
        * = $0801
        !byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00      ; 10 SYS2061
        jmp (entry)             ; $080D
entry   !word ENTRY_POINT      ; $0810 (NAME PLAY has play_start here)
