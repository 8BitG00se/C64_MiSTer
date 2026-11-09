; (C) 2026 Mong00se. All rights reserved.
; IRIS.ASM - the stock show's changes: the iris, the fades, the raster bars;
; its setting up (with SHOW.ASM)
; A part of ODYSSEY.ASM (2026: An Octophonic Odyssey), by Mong00se:
; F2 on it builds the whole demo.
!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }
!if odyp = 0 {
        !src "odyssey.asm"
} else {
; ================================================== the iris
; A = frames a step. Opens: the cells inside a circle (radius
; irisr, in half cells) get their colours from the buffer, row by
; row, as it grows (HW: how far each row has come out each side).
!zone iris_open
iris_open
        sta cnt
        lda #0
        sta irisr
.st     ldx cnt
-       jsr waitfr
        dex
        bne -
        inc irisr
        jsr setr2
        ldx #23
.row    stx tmp+2
        jsr setdy
.more   ldx tmp+2
        lda HW,x
        cmp #20
        bcs .nr
        asl             ; the next cell out: 2h + 1
        adc #1
        jsr inside
        bcs .nr
        ldx tmp+2       ; in: cells 20+h and 19-h
        lda HW,x
        clc
        adc #20
        jsr cellin
        ldx tmp+2
        lda #19
        sec
        sbc HW,x
        jsr cellin
        ldx tmp+2
        inc HW,x
        jmp .more
.nr     ldx tmp+2
        dex
        bpl .row
        lda irisr
        cmp #48
        bcc .st
        rts
; Closes: from the edge in, the cells outside go black
!zone iris_close
iris_close
        sta cnt
        lda #48
        sta irisr
        ldx #23
        lda #20
-       sta HW,x
        dex
        bpl -
.st     ldx cnt
-       jsr waitfr
        dex
        bne -
        dec irisr
        jsr setr2
        ldx #23
.row    stx tmp+2
        jsr setdy
.more   ldx tmp+2
        lda HW,x
        beq .nr
        asl             ; the cell at the edge: 2h - 1
        sec
        sbc #1
        jsr inside
        bcc .nr
        ldx tmp+2
        dec HW,x
        lda HW,x
        clc
        adc #20
        jsr cellout
        ldx tmp+2
        lda #19
        sec
        sbc HW,x
        jsr cellout
        jmp .more
.nr     ldx tmp+2
        dex
        bpl .row
        lda irisr
        bne .st
        rts
; r2 = irisr squared
!zone setr2
setr2   ldx irisr
        lda SQ,x
        sta r2
        lda SQ+50,x
        sta r2+1
        rts
; dy2 = (2y - 23) squared, y = tmp+2
!zone setdy
setdy   lda tmp+2
        asl
        sec
        sbc #23
        bcs +
        eor #$ff
        adc #1
+       tax
        lda SQ,x
        sta dy2
        lda SQ+50,x
        sta dy2+1
        rts
; carry clear: A^2 + dy2 < r2 (inside the circle)
!zone inside
inside  tax
        clc
        lda SQ,x
        adc dy2
        sta tmp
        lda SQ+50,x
        adc dy2+1
        cmp r2+1
        bne +
        lda tmp
        cmp r2
+       rts
; the cell at row tmp+2, column A: in (from the buffer) / out (black)
!zone cellin
cellin  jsr cellp
        ldy #0
        lda (ptr2),y
        sta (ptr),y
        lda ptr2+1      ; its colour RAM: buffer + $3E8
        clc
        adc #3
        sta ptr2+1
        lda ptr2
        clc
        adc #$e8
        sta ptr2
        bcc +
        inc ptr2+1
+       lda (ptr2),y
        sta (ptr3),y
        rts
!zone cellout
cellout jsr cellp
        lda #0
        tay
        sta (ptr),y
        sta (ptr3),y
        rts
; ptr: the screen, ptr2: the buffer, ptr3: colour RAM, for the cell
!zone cellp
cellp   ldx tmp+2
        clc
        adc rowlo,x
        sta ptr
        sta ptr2
        sta ptr3
        lda rowhi,x
        adc #0
        sta tmp+3
        ldx bank
        adc b_scr,x
        sta ptr+1
        lda tmp+3
        adc b_buf,x
        sta ptr2+1
        lda tmp+3
        adc #$d8
        sta ptr3+1
        rts
!zone rowlo
rowlo   !for r, 0, 23 { !byte <(r*40) }
!zone rowhi
rowhi   !for r, 0, 23 { !byte >(r*40) }

; wait for the next frame
!zone waitfr
waitfr  lda frame
-       cmp frame
        beq -
        rts

; ================================================== the fades
; out: 5 steps darker (2 frames each) to black; in: back
!zone fade_out
fade_out
        lda #1
-       pha
        jsr fadestep
        pla
        clc
        adc #1
        cmp #6
        bne -
        rts
!zone fade_in
fade_in lda #4
-       pha
        jsr fadestep
        pla
        sec
        sbc #1
        bpl -
        rts
; the view's colours A steps darker, onto the screen
!zone fadestep
fadestep
        sta tmp+2
        ldx #15         ; each colour A steps down its ramp
-       stx tmp
        txa
        ldy tmp+2
        beq +
--      tax
        lda darker,x
        dey
        bne --
+       ldx tmp
        sta fl,x
        dex
        bpl -
        ldx #0          ; and a table for a screen byte (2 colours)
-       txa
        lsr
        lsr
        lsr
        lsr
        tay
        lda fl,y
        asl
        asl
        asl
        asl
        sta tmp
        txa
        and #$0f
        tay
        lda fl,y
        ora tmp
        sta FADET,x
        inx
        bne -
        jsr waitfr
        ldx bank        ; screen: 960 bytes, colour RAM: 960
        lda b_buf,x
        sta ptr2+1
        lda b_scr,x
        sta ptr+1
        lda #0
        sta ptr
        sta ptr2
        lda #$d8
        sta ptr3+1
        lda #0
        sta ptr3
        ldx #4          ; 3 pages and 192 bytes
.pg     ldy #0
-       lda (ptr2),y
        sty tmp
        tay
        lda FADET,y
        ldy tmp
        sta (ptr),y
        iny
        cpx #1
        bne +
        cpy #192
        beq ++
+       cpy #0
        bne -
++      inc ptr+1
        inc ptr2+1
        dex
        bne .pg
        ldx bank        ; the colour RAM from buffer + $3E8
        lda b_buf,x
        clc
        adc #3
        sta ptr2+1
        lda #$e8
        sta ptr2
        ldx #4
.pc     ldy #0
-       lda (ptr2),y
        sty tmp
        tay
        lda FADET,y
        ldy tmp
        sta (ptr3),y
        iny
        cpx #1
        bne +
        cpy #192
        beq ++
+       cpy #0
        bne -
++      inc ptr3+1
        inc ptr2+1
        dex
        bne .pc
        jmp waitfr
!zone fl
fl      !fill 16, 0
; a step darker: each C64 colour to the next one down its ramp
!zone darker
darker  !byte 0,15,9,14,2,11,0,10,2,0,8,0,11,5,6,12

; ============================================ the raster bars
; the telescope opens: three bars (blue, gold, blue) sweep down
; the blank screen, about 2 seconds
!zone bars
bars    lda #$0b        ; the screen blank: no bad lines
        sta $d011
        lda #0
        sta tmp+2       ; where the bars are
.fr     ldx #199        ; this frame's colours, line by line
        lda #0
-       sta LINEC,x
        dex
        cpx #$ff
        bne -
        ldx #0          ; three bars, one after another
.b      lda tmp+2
        sec
        sbc barofs,x
        sta tmp         ; the bar's top line
        stx tmp+1
        lda barlo,x     ; its colours
        sta ptr
        lda barhi,x
        sta ptr+1
        ldy #0
-       ldx tmp
        cpx #200
        bcs +
        lda (ptr),y
        sta LINEC,x
+       inc tmp
        iny
        cpy #15
        bne -
        ldx tmp+1
        inx
        cpx #3
        bne .b
-       lda $d012       ; then line by line from $30
        cmp #$30
        bne -
        ldx #0
.ln     txa
        clc
        adc #$30
-       cmp $d012
        bne -
        ldy #7          ; to the line's right border
-       dey
        bne -
        lda LINEC,x
        sta $d020
        inx
        cpx #200
        bne .ln
        lda #0
        sta $d020
        lda tmp+2
        clc
        adc #3
        sta tmp+2
        cmp #255
        bcc .fr
        rts
!zone barofs
barofs  !byte 0, 22, 44
!zone barlo
barlo   !byte <barcol, <barcol2, <barcol
!zone barhi
barhi   !byte >barcol, >barcol2, >barcol
!zone barcol
barcol  !byte 6,6,14,6,14,14,3,14,3,3,1,3,14,6,0
!zone barcol2
barcol2 !byte 9,2,9,8,2,8,10,8,10,7,10,8,2,9,0
; ================================================== setting up
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
        ldx #0          ; the sprites, in both banks
-       lda sprdata,x
        sta $4880,x
        sta $8880,x
        lda sprdata+$100,x
        sta $4980,x
        sta $8980,x
        inx
        bne -
        ldx #127        ; the equaliser's two: empty
        lda #0
-       sta $4800,x
        sta $8800,x
        dex
        bpl -
        ldx #0          ; both screens black, the text rows clear
-       lda #0
        sta $4000,x
        sta $4100,x
        sta $4200,x
        sta $42e8,x
        sta $8000,x
        sta $8100,x
        sta $8200,x
        sta $82e8,x
        lda #$20
        sta $4400,x
        sta $4500,x
        sta $4600,x
        sta $46e8,x
        sta $8400,x
        sta $8500,x
        sta $8600,x
        sta $86e8,x
        inx
        bne -
        ldx #7          ; sprite pointers: 0-1 the equaliser,
-       lda sprptr,x    ; 2-6 sparkles, 7 the comet
        sta $43f8,x
        sta $47f8,x
        sta $83f8,x
        sta $87f8,x
        lda #0
        sta sprx,x
        sta sprxh,x
        sta spry,x
        dex
        bpl -
        ldx #63
        lda #0
-       sta SPST,x
        dex
        bpl -
        ldx #23
-       sta TWT,x
        sta HW,x
        dex
        bpl -
        ldx #0          ; the squares 0-49 (for the iris)
        stx SQ
        stx SQ+50
        lda #0
        sta it
        sta it+1
-       clc             ; (n+1)^2 = n^2 + 2n + 1
        txa
        asl
        adc #1
        adc it
        sta it
        lda it+1
        adc #0
        sta it+1
        inx
        lda it
        sta SQ,x
        lda it+1
        sta SQ+50,x
        cpx #49
        bne -
        ; the sprites: the equaliser at the bottom right, x twice as wide
        lda #<290
        sta sprx
        lda #>290
        sta sprxh
        lda #<238
        sta sprx+1
        lda #>238
        sta sprxh+1
        lda #221
        sta spry
        sta spry+1
        lda #3
        sta $d01d
        lda #0
        sta $d017
        sta $d01b
        sta $d01c
        lda #14
        sta $d027
        lda #3
        sta $d028
        ldx #5
        lda #1
-       sta $d029,x
        dex
        bpl -
        lda #<600
        sta cometw
        lda #>600
        sta cometw+1
        lda #0
        sta comety
        rts
!zone sprptr
sprptr  !byte $20,$21,$22,$22,$22,$22,$22,$26

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
