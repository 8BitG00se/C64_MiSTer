; (C) 2026 Mong00se
; IRIS.ASM - the stock show's setting up, and its line about the machine
; (with SHOW.ASM). (Its name is from build 1, when the pictures opened
; with an iris.)
; A part of ODYSSEY.ASM (2026: An Octophonic Odyssey), by Mong00se:
; F2 on it builds the whole demo.
!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }
!if odyp = 0 {
        !src "odyssey.asm"
} else {
!zone setup
setup   sei
        lda #$33        ; the letters from the ROM to $5800
        sta $01
        ldx #0
-       lda $d000,x
        sta $5800,x
        lda $d100,x
        sta $5900,x
        lda $d200,x
        sta $5a00,x
        lda $d300,x
        sta $5b00,x
        lda $d400,x
        sta $5c00,x
        lda $d500,x
        sta $5d00,x
        lda $d600,x
        sta $5e00,x
        lda $d700,x
        sta $5f00,x
        inx
        bne -
        lda #$36
        sta $01
        cli
        ldx #0          ; both screens black, the text screen clear, the sprites empty
-       lda #0
        sta $4000,x
        sta $4100,x
        sta $4200,x
        sta $42e8,x
        sta $8000,x
        sta $8100,x
        sta $8200,x
        sta $82e8,x
        sta $4800,x
        sta $4900,x
        sta $4a00,x
        sta $8800,x
        sta $8900,x
        sta $8a00,x
        lda #$20
        sta $4400,x
        sta $4500,x
        sta $4600,x
        sta $46e8,x
        inx
        bne -
        ldx #7
-       lda #0
        sta sprx,x
        sta sprxh,x
        sta spry,x
        dex
        bpl -
        ldx #63
-       sta SPST,x
        dex
        bpl -
        ldx #31
-       sta TWT,x
        dex
        bpl -
        rts

; a text row's offset (40 x row) for PRINT2
rowlo   !for r, 0, 24 { !byte <(r*40) }
rowhi   !for r, 0, 24 { !byte >(r*40) }

; the scroll text's line about the machine
!zone mkmsg
mkmsg   ldx #0
        ldy #0
        lda mode
        beq .one
-       lda t_m2,x
        beq .hex
        sta MSGBUF,y
        inx
        iny
        bne -
.hex    lda sid2hi      ; the second SID's address in hex
        jsr .h2
        lda sid2lo
        jsr .h2
        ldx #0
-       lda t_m2b,x
        sta MSGBUF,y
        beq +
        inx
        iny
        bne -
+       rts
.one    lda t_m1,x
        sta MSGBUF,x
        beq +
        inx
        bne .one
+       rts
.h2     pha
        lsr
        lsr
        lsr
        lsr
        jsr .h1
        pla
        and #$0f
.h1     tax
        lda hexd,x
        sta MSGBUF,y
        iny
        rts
!zone hexd
hexd    !scr "0123456789abcdef"

}
