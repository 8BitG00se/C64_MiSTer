; SPRITES.ASM - 64 sprites at once,
; each a 16x16 ball in 256 colours,
; flying in a sine wave. OctoVIC has
; 128 sprites, so no multiplexer is
; needed: the 6510 just writes where
; they are, into a sprite table.
; RUN/STOP+RESTORE: back to the editor.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

count   = 64    ; how many (1-64)
xstep   = 1     ; spacing across
ystep   = 2     ; spacing down
xspeed  = 1     ; speed across
yspeed  = 2     ; speed down

; four ball colours: red, green, blue
cols    !byte 255,80,60     ; red
        !byte 80,220,255    ; cyan
        !byte 255,220,60    ; gold
        !byte 160,255,90    ; green

; ======== the program ================

gfx     = $05       ; VRAM $050000
table   = $06       ; VRAM $060000/$0200

start   sei
        jsr screen
        jsr octoon
        jsr palette
        jsr balls
        lda #<count
        sta $d60f       ; sprites in use
main    lda #250        ; wait for the
-       cmp $d012       ; bottom
        bne -
        jsr place       ; the next table
        lda #0          ; and show it:
        sta $d613       ; SATBASE
        lda buf
        sta $d614
        lda #table
        sta $d615
        lda buf         ; swap the two
        eor #2
        sta buf
        inc frame
        jmp main

; ---- black screen, a line of text
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
        sta $0400+24*40+5,x
        inx
        bne -
+       rts
msg     !scr "64 sprites - no multiplexer", 0

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
        lda #9          ; on; the VIC in
        sta $d605       ; front, colour 0
        lda #0          ; see-through
        sta $d606
        lda #2          ; the backdrop:
        sta $d619       ; near black
        lda #0
        sta $d61a
        sta $d61b
        sta $d61c
        lda #24
        sta $d61d
        lda #0          ; sprite graphics
        sta $d616       ; at $050000
        sta $d617
        lda #gfx
        sta $d618
        lda #1
        sta $d603
        rts

; ---- palette: colour c, shade s at
; entry c*16+s, = colour*s*17/256
palette lda #0
        sta $d619
        sta $d651
        sta $d653
        ldx #0          ; c*16+s
-       txa
        and #15
        sta t
        asl             ; s*17
        asl
        asl
        asl
        ora t
        sta $d652       ; MULB
        txa
        lsr
        lsr
        lsr
        lsr
        sta t
        asl
        adc t           ; c*3
        tay
        stx $d61a
        lda cols,y
        sta $d650
        lda $d655
        sta $d61b
        lda cols+1,y
        sta $d650
        lda $d655
        sta $d61c
        lda cols+2,y
        sta $d650
        lda $d655
        sta $d61d
        inx
        cpx #64
        bne -
        rts

; ---- four ball pictures (256 bytes
; each): shade + colour*16
balls   lda #0
        sta $d600
        sta $d601
        lda #gfx
        sta $d602
        ldx #0          ; colour
--      ldy #0
-       lda ball,y
        beq +
        sta t
        txa
        asl
        asl
        asl
        asl
        ora t
+       sta $d604
        iny
        bne -
        inx
        cpx #4
        bne --
        rts

; ---- the table: 8 bytes a sprite
; X, Y, picture, size, colour
place   lda #0              ; VRAM address
        sta $d600
        lda buf
        sta $d601
        lda #table
        sta $d602
        ldx #0
-       txa             ; across
        ldy #xstep
        jsr times
        sta t
        lda frame
        ldy #xspeed
        jsr times
        clc
        adc t
        and #63
        tay
        lda sinx,y
        clc
        adc #34
        sta $d604       ; X
        lda #0
        adc #0
        sta $d604
        txa             ; down
        ldy #ystep
        jsr times
        sta t
        lda frame
        ldy #yspeed
        jsr times
        clc
        adc t
        and #63
        tay
        lda siny,y
        clc
        adc #20
        sta $d604       ; Y
        lda #0
        sta $d604
        txa             ; the picture:
        and #3          ; colour*8
        asl
        asl
        asl
        sta $d604
        lda #0
        sta $d604
        lda #$c5        ; on, 256 colours,
        sta $d604       ; 16x16
        lda #0          ; in front
        sta $d604
        inx
        cpx #count
        bne -
        rts

; A = A * Y (small numbers)
times   sta t2
        lda #0
        cpy #0
        beq +
-       clc
        adc t2
        dey
        bne -
+       rts

; the ball: shades 1-15, 0 see-through
ball    !byte 0,0,0,0,0,0,0,9,8,0,0,0,0,0,0,0
        !byte 0,0,0,0,10,11,10,10,9,9,8,7,0,0,0,0
        !byte 0,0,0,11,12,12,12,11,10,9,8,7,6,0,0,0
        !byte 0,0,11,12,13,13,13,12,11,10,9,8,7,5,0,0
        !byte 0,10,12,13,14,15,14,13,12,10,9,8,7,6,5,0
        !byte 0,11,12,13,15,15,15,13,12,11,9,8,7,6,5,0
        !byte 0,10,12,13,14,15,14,13,12,10,9,8,7,6,5,0
        !byte 9,10,11,12,13,13,13,12,11,10,9,8,7,5,4,3
        !byte 8,9,10,11,12,12,12,11,10,9,8,7,6,5,4,3
        !byte 0,9,9,10,10,11,10,10,9,9,8,7,6,5,4,0
        !byte 0,8,8,9,9,9,9,9,8,8,7,6,5,4,3,0
        !byte 0,7,7,8,8,8,8,8,7,7,6,5,4,4,3,0
        !byte 0,0,6,7,7,7,7,7,6,6,5,4,4,3,0,0
        !byte 0,0,0,5,6,6,6,5,5,5,4,4,3,0,0,0
        !byte 0,0,0,0,5,5,5,4,4,4,3,3,0,0,0,0
        !byte 0,0,0,0,0,0,0,3,3,0,0,0,0,0,0,0
sinx    !byte 125,137,149,161,173,184,194,204
        !byte 213,222,229,235,240,245,248,249
        !byte 250,249,248,245,240,235,229,222
        !byte 213,204,194,184,173,161,149,137
        !byte 125,113,101,89,77,66,56,46
        !byte 37,28,21,15,10,5,2,1
        !byte 0,1,2,5,10,15,21,28
        !byte 37,46,56,66,77,89,101,113
siny    !byte 85,93,102,110,118,125,132,139
        !byte 145,151,156,160,164,166,168,170
        !byte 170,170,168,166,164,160,156,151
        !byte 145,139,132,125,118,110,102,93
        !byte 85,77,68,60,52,45,38,31
        !byte 25,19,14,10,6,4,2,0
        !byte 0,0,2,4,6,10,14,19
        !byte 25,31,38,45,52,60,68,77
frame   !byte 0
buf     !byte 0
t       !byte 0
t2      !byte 0
