; STARFIELD.ASM - a starfield on a
; STOCK C64: 48 stars in four depths
; flying left, in the hires bitmap.
; The near ones are fast, the far
; ones slow (that is all parallax is).
; Each star is drawn with EOR, so
; drawing it a second time rubs it out.
; target stock
; RUN/STOP+RESTORE: back to READY.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

nstars  = 48    ; how many (1-64)

; ======== the program ================

xlo     = $0c00         ; the stars: x low and
xhi     = $0c40         ; high (0-319), y, and
sy      = $0c80         ; how many pixels a
spd     = $0cc0         ; frame (1-4)
ylo     = $0d00         ; a bitmap row's address,
yhi     = $0e00         ; for each of 200 lines
p       = $fb
seed    = $fd

start   lda #0
        sta $d020
        sta $d021
        lda #$10        ; every cell: white on black
        ldx #0
-       sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        inx
        bne -
        lda #<$2000     ; clear the bitmap
        sta p
        lda #>$2000
        sta p+1
        ldx #32
        ldy #0
        tya
-       sta (p),y
        iny
        bne -
        inc p+1
        dex
        bne -
        jsr rows
        jsr mkstars
        lda #$18        ; bitmap at $2000,
        sta $d018       ; screen at $0400
        lda #$3b        ; bitmap mode on
        sta $d011
        lda #$08
        sta $d016

main    lda #251        ; wait for the bottom
-       cmp $d012
        bne -
        ldx #nstars-1
-       jsr toggle      ; rub it out
        sec             ; move left
        lda xlo,x
        sbc spd,x
        sta xlo,x
        lda xhi,x
        sbc #0
        sta xhi,x
        bpl +
        clc             ; off the left side:
        lda xlo,x       ; back in at the right
        adc #<320
        sta xlo,x
        lda xhi,x
        adc #>320
        sta xhi,x
+       jsr toggle      ; draw it again
        dex
        bpl -
        jmp main

; flip the pixel of star X
toggle  ldy sy,x
        lda xlo,x
        and #$f8
        clc
        adc ylo,y
        sta p
        lda xhi,x
        adc yhi,y
        sta p+1
        lda xlo,x
        and #7
        tay
        lda bits,y
        ldy #0
        eor (p),y
        sta (p),y
        rts
bits    !byte $80,$40,$20,$10,$08,$04,$02,$01

; the address of every bitmap line:
; $2000 + (y/8)*320 + y mod 8
rows    lda #<$2000
        sta p
        lda #>$2000
        sta p+1
        ldx #0          ; y
-       txa
        and #7
        clc
        adc p
        sta ylo,x
        lda p+1
        adc #0
        sta yhi,x
        txa
        and #7
        cmp #7
        bne +
        clc             ; the next row of cells
        lda p
        adc #<320
        sta p
        lda p+1
        adc #>320
        sta p+1
+       inx
        cpx #200
        bne -
        rts

; random stars: a little shuffle of a
; number gives each its place and speed
mkstars lda #77
        sta seed
        ldx #0
star    jsr rnd         ; x: even stars 0-255,
        sta xlo,x       ; odd ones 64-319
        lda #0
        sta xhi,x
        txa
        and #1
        beq +
        lda xlo,x
        clc
        adc #64
        sta xlo,x
        lda #0
        adc #0
        sta xhi,x
+       jsr rnd         ; y: 0-199
-       cmp #200
        bcc +
        sbc #200
        jmp -
+       sta sy,x
        txa             ; speed 1-4 from the
        and #3          ; star number
        clc
        adc #1
        sta spd,x
        inx
        cpx #nstars
        bne star
        rts
rnd     lda seed        ; 8 bit random
        asl
        bcc +
        eor #$1d
+       sta seed
        rts
