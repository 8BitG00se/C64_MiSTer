; RASTER.ASM - raster bars, done the
; OctoVIC way. The 6510 makes 64
; copper lists once (one a frame),
; then OctoVIC plays them by itself:
; the 6510 has nothing left to do.
; RUN/STOP+RESTORE: back to the editor.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

bars    = 4     ; how many bars (1-4)
size    = 32    ; lines a bar (8-32)
gap     = 12    ; how far apart (0-63)
speed   = 1     ; 1 slow, 2, 3 fast

; each bar's colour: red, green, blue
cols    !byte 255,40,90     ; bar 1
        !byte 40,200,255    ; bar 2
        !byte 255,210,40    ; bar 3
        !byte 120,255,80    ; bar 4

msg     !scr "raster bars by octovic's copper"
        !byte 0

; ======== the program ================

top     = 30            ; first line
red     = $3000         ; a line's red
green   = $3100         ; green
blue    = $3200         ; blue
shades  = $3300         ; bars, shaded

start   sei
        jsr screen
        jsr octoon
        jsr shade
        lda #0          ; 64 lists, at
        sta frame       ; VRAM $020000,
        sta vmid        ; $1100 apart
        lda #2
        sta vhi
-       jsr paint       ; this frame's
        jsr emit        ; bars, a list
        lda vmid
        clc
        adc #$11
        sta vmid
        bcc +
        inc vhi
+       inc frame
        lda frame
        cmp #64
        bne -
        jsr play        ; OctoVIC: go
        cli
loop    jmp loop        ; nothing to do

; ---- OctoVIC on, everything off
octoon  lda #$4f
        sta $d03f
        lda #$38
        sta $d03f
        ldx #$4b
        lda #0
-       sta $d605,x     ; $d605-$d650: 0
        dex
        bpl -
        lda #2          ; the VIC's 16
        sta $d605       ; colours: ours
        lda #1
        sta $d619       ; the VIC palette
        sta $d603       ; VRAM step 1
        rts

; ---- black screen, white text
screen  lda #0
        sta $d020
        sta $d021
        ldx #0
-       lda #32
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        lda #1
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne -
        ldx #0
-       lda msg,x
        beq +
        sta $0400+12*40+4,x
        inx
        bne -
+       rts

; ---- each bar's lines, dark at the
; edges: colour x shape / 256, done
; by OctoVIC's maths unit ($d650)
shade   ldx #0          ; bar*32+line
-       txa
        and #31
        tay
        lda shape,y
        sta $d652       ; MULB
        lda #0
        sta $d651
        sta $d653
        txa
        lsr
        lsr
        lsr
        lsr
        lsr             ; the bar
        sta n
        asl
        adc n           ; bar * 3
        tay
        lda cols,y
        jsr mul
        sta shades,x
        lda cols+1,y
        jsr mul
        sta shades+128,x
        lda cols+2,y
        jsr mul
        sta shades+256,x
        inx
        cpx #128
        bne -
        rts
mul     sta $d650       ; MULA
        lda $d655       ; (A*B)/256
        rts

; ---- the bars into red/green/blue
paint   ldx #0
        txa
-       sta red,x
        sta green,x
        sta blue,x
        inx
        bne -
        lda #0
        sta bar
nextbar lda bar
        tay             ; its position:
        lda #0          ; frame*speed +
-       dey             ; bar*gap
        bmi +
        clc
        adc #gap
        jmp -
+       ldy #speed
-       clc
        adc frame
        dey
        bne -
        and #63
        tay
        lda sine,y
        tay             ; first line
        lda bar
        asl
        asl
        asl
        asl
        asl
        tax             ; bar*32
        lda #size
        sta n
-       lda shades,x
        sta red,y
        lda shades+128,x
        sta green,y
        lda shades+256,x
        sta blue,y
        inx
        iny
        dec n
        bne -
        inc bar
        lda bar
        cmp #bars
        bne nextbar
        rts

; ---- one list: each line sets the
; VIC's colour 0 (border and screen)
; = 4 copper steps: line, register,
; value (PALIDX 0, then R, G, B)
emit    lda #0
        sta $d600
        lda vmid
        sta $d601
        lda vhi
        sta $d602
        ldy #0
-       tya
        clc
        adc #top
        sta lo
        lda #0
        adc #0          ; A = the line's
        ldx lo          ; PALIDX = 0
        stx $d604
        sta $d604
        ldx #$1a
        stx $d604
        ldx #0
        stx $d604
        ldx lo          ; red
        stx $d604
        sta $d604
        ldx #$1b
        stx $d604
        ldx red,y
        stx $d604
        ldx lo          ; green
        stx $d604
        sta $d604
        ldx #$1c
        stx $d604
        ldx green,y
        stx $d604
        ldx lo          ; blue
        stx $d604
        sta $d604
        ldx #$1d
        stx $d604
        ldx blue,y
        stx $d604
        iny
        bne -
        lda #$ff        ; the end
        sta $d604
        sta $d604
        sta $d604
        sta $d604
        rts
; ---- OctoVIC steps through the 64
; lists by itself, one a frame
play    lda #0
        sta $d640       ; COPSTEP
        lda #$11        ; = $001100
        sta $d641
        lda #0
        sta $d642
        lda #64         ; COPSTEPS
        sta $d643
        lda #0
        sta $d644
        lda #1
        sta $d645       ; a frame a step
        lda #0
        sta $d610       ; COPBASE
        sta $d611       ; = $020000
        lda #2
        sta $d612
        lda #1
        sta $d60e       ; the copper on
        rts

shape   !byte 3,14,31,50,71,94,117,140
        !byte 163,184,203,219,233,244,251,255
        !byte 255,251,244,233,219,203,184,163
        !byte 140,117,94,71,50,31,14,3
sine    !byte 100,110,119,129,138,147,155
        !byte 163,170,177,183,188,192,196
        !byte 198,200,200,200,198,196,192
        !byte 188,183,177,170,163,155,147
        !byte 138,129,119,110,100,90,81
        !byte 71,62,53,45,37,30,23,17,12
        !byte 8,4,2,0,0,0,2,4,8,12,17,23
        !byte 30,37,45,53,62,71,81,90

frame   !byte 0
vmid    !byte 0
vhi     !byte 0
bar     !byte 0
n       !byte 0
lo      !byte 0
