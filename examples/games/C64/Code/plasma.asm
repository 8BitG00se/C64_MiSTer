; PLASMA.ASM - a plasma and colour
; cycling. A 256-colour bitmap layer
; is filled once with sums of sines;
; then only the palette moves: 255
; colours turned round every frame,
; and the picture drifts sideways
; (the layer is "turned and sized",
; shown twice as big). RUN/STOP+RESTORE
; goes back to the editor.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

xs      = 2     ; ripples across (1-4)
ys      = 3     ; ripples down (1-4)
spin    = 2     ; colour speed (1-8)
drift   = $40   ; sideways speed
; the colour wheel's three phases:
; red, green and blue (0-255)
rph     = 0
gph     = 85
bph     = 170

; ======== the program ================

sine    = $3000         ; 256 bytes
sinx    = $3100         ; sine(x*xs)
wheel   = $3200         ; 0-255 sine
pic     = $10           ; VRAM $100000

start   sei
        jsr screen
        jsr octoon
        jsr mksine
        jsr fill
        jsr layer
main    lda #250        ; wait for the
-       cmp $d012       ; bottom
        bne -
        jsr colours
        lda u0+1        ; drift: U0 grows
        clc
        adc #drift
        sta u0+1
        sta $d689
        bcc +
        inc u0+2
        lda u0+2
        sta $d68a
+       lda frame
        clc
        adc #spin
        sta frame
        jmp main

; ---- black screen, no text
screen  lda #0
        sta $d020
        sta $d021
        ldx #0
-       lda #32
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        inx
        bne -
        rts

; ---- OctoVIC on, everything off
octoon  lda #$4f
        sta $d03f
        lda #$38
        sta $d03f
        ldx #$4b
        lda #0
-       sta $d605,x
        dex
        bpl -
        ldx #$17        ; $d688-$d69f: 0
-       sta $d688,x
        dex
        bpl -
        lda #9          ; on, VIC's black
        sta $d605       ; see-through
        lda #1
        sta $d603
        rts

; ---- a sine (parabolas, made with the
; maths unit): 128 +- i*(128-i)/64,
; then 0-255 wide
mksine  ldx #0
        stx $d651
        stx $d653
-       txa
        and #127
        sta $d650       ; i
        eor #127
        clc
        adc #1          ; 128-i
        sta $d652
        lda $d654       ; /64: shift the
        asl             ; 16 bits left 2
        lda $d655
        rol
        sta t
        lda $d654
        asl
        asl
        lda t
        rol             ; 0-64
        cpx #128
        bcs +
        clc
        adc #128
        jmp ++
+       sta t
        lda #128
        sec
        sbc t
++      sta sine,x
        inx
        bne -
        ldx #0          ; sinx: sine(x*xs)
-       txa
        ldy #xs
        jsr times
        tay
        lda sine,y
        sta sinx,x
        inx
        bne -
        ldx #0          ; the colour wheel:
-       lda sine,x      ; the sine made
        sec             ; 0-255 high
        sbc #64
        asl
        bcc +
        lda #255
+       sta wheel,x
        inx
        bne -
        rts

; A = A * Y
times   sta t
        lda #0
-       clc
        adc t
        dey
        bne -
        rts

; ---- the picture: 256 x 160 pixels,
; each sine(x*xs) + sine(y*ys) +
; sine(x+2y) - 0 is see-through, so 1
fill    lda #0
        sta $d600
        sta $d601
        lda #pic
        sta $d602       ; VRAM $100000
        lda #0
        sta y
nexty   lda y
        ldy #ys
        jsr times
        tay
        lda sine,y
        sta a           ; sine(y*ys)
        lda y
        asl
        tay             ; Y = x+2y
        ldx #0
-       lda sinx,x
        clc
        adc sine,y
        clc
        adc a
        bne +
        lda #1
+       sta $d604
        iny
        inx
        bne -
        inc y
        lda y
        cmp #160
        bne nexty
        rts

; ---- layer 0: a bitmap, 256 x 256,
; turned and sized: half a picture
; pixel a screen pixel = twice as big
layer   lda #0
        sta $d624       ; the bitmap
        sta $d625
        lda #pic
        sta $d626
        lda #$80        ; DUX = 0.5
        sta $d691
        lda #$80        ; DVY = 0.5
        sta $d69d
        lda #4          ; turned and sized
        sta $d62f
        lda #$0b        ; on, 256 colours,
        sta $d620       ; a bitmap
        rts

; ---- the palette, turned round:
; colour k gets the wheel at k+frame
colours lda #0
        sta $d619
        lda #1
        sta $d61a
        ldx #1
-       txa
        clc
        adc frame
        tay
        lda wheel,y
        sta $d61b
        tya
        clc
        adc #gph-rph
        tay
        lda wheel,y
        sta $d61c
        tya
        clc
        adc #bph-gph
        tay
        lda wheel,y
        sta $d61d
        inx
        bne -
        rts



frame   !byte 0
u0      !byte 0,0,0
y       !byte 0
a       !byte 0
t       !byte 0
