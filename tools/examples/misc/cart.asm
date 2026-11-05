; HELLO CART - an 8K cartridge for the Octophonic 64 (or any C64): it starts the moment the
; machine does, prints its message and runs colour bars in the border. Original: Octophonic 64 / Mong00se.
* = $8000
        !word cold, cold
        !byte $c3, $c2, $cd, $38, $30          ; CBM80
cold    sei
        ldx #$ff
        txs
        cld
        jsr $ff84               ; IOINIT
        lda #0                  ; (no RAM test: the screen at $0400, as RAMTAS would set)
        tay
-       sta $0002,y
        sta $0200,y
        sta $0300,y
        iny
        bne -
        lda #4
        sta $0288
        jsr $ff8a               ; RESTOR
        jsr $ff81               ; CINT
        cli
        lda #0
        sta $d021
        ldx #0
-       lda msg,x
        beq +
        jsr $ffd2
        inx
        bne -
+       sei
bars    ldx #0                  ; a colour every 4 lines, moving down a line each frame
-       lda $d012
        bne -
        inc phase
        ldy #0
line    lda $d012
-       cmp $d012
        beq -
        tya
        clc
        adc phase
        lsr
        lsr
        and #15
        tax
        lda cols,x
        sta $d020
        iny
        bne line
        jmp bars
cols    !byte 0,6,14,3,1,3,14,6,0,2,10,7,1,7,10,2
phase   !byte 0
msg     !pet 147, 5, 13, 13, "        hello from the cartridge!", 13, 13
        !pet 159, "   an 8k .crt, picked in the browser:", 13
        !pet "   it starts as the machine starts.", 0
!fill $a000 - *, $ff
