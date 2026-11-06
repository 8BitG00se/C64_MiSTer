; SPRITES.ASM - 64 sprites at once,
; each a 16x16 ball in 256 colours,
; a snake of balls flying round a
; figure 8 (a sine wave across, one
; at twice the speed down). OctoVIC has
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

; the path has 256 steps (the tables
; at the end); a ball moves along it
count   = 64    ; how many (1-64)
xstep   = 3     ; gap between balls, across
ystep   = 6     ; gap between balls, down
xspeed  = 2     ; steps a frame, across
yspeed  = 4     ; steps a frame, down
                ; (ystep and yspeed are
                ; twice xstep and xspeed:
                ; that makes the 8)

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
        adc t           ; (256 steps: the
        tay             ; byte just wraps)
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
        tay
        lda siny,y
        clc
        adc #14
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
; the path, 256 steps: sinx 0-250 (one
; wave), siny 0-150 (the same wave:
; the program steps through it twice
; as fast, which makes the 8)
sinx    !byte 125,128,131,134,137,140,143,146,149,152,155,158,161,164,167,170
        !byte 173,176,178,181,184,187,189,192,194,197,199,202,204,207,209,211
        !byte 213,216,218,220,222,224,225,227,229,231,232,234,235,237,238,239
        !byte 240,242,243,244,245,245,246,247,248,248,249,249,249,250,250,250
        !byte 250,250,250,250,249,249,249,248,248,247,246,245,245,244,243,242
        !byte 240,239,238,237,235,234,232,231,229,227,225,224,222,220,218,216
        !byte 213,211,209,207,204,202,199,197,194,192,189,187,184,181,178,176
        !byte 173,170,167,164,161,158,155,152,149,146,143,140,137,134,131,128
        !byte 125,122,119,116,113,110,107,104,101,98,95,92,89,86,83,80
        !byte 77,74,72,69,66,63,61,58,56,53,51,48,46,43,41,39
        !byte 37,34,32,30,28,26,25,23,21,19,18,16,15,13,12,11
        !byte 10,8,7,6,5,5,4,3,2,2,1,1,1,0,0,0
        !byte 0,0,0,0,1,1,1,2,2,3,4,5,5,6,7,8
        !byte 10,11,12,13,15,16,18,19,21,23,25,26,28,30,32,34
        !byte 37,39,41,43,46,48,51,53,56,58,61,63,66,69,72,74
        !byte 77,80,83,86,89,92,95,98,101,104,107,110,113,116,119,122
siny    !byte 75,77,79,81,82,84,86,88,90,91,93,95,97,99,100,102
        !byte 104,105,107,109,110,112,114,115,117,118,120,121,123,124,125,127
        !byte 128,129,131,132,133,134,135,136,137,138,139,140,141,142,143,144
        !byte 144,145,146,146,147,147,148,148,149,149,149,149,150,150,150,150
        !byte 150,150,150,150,150,149,149,149,149,148,148,147,147,146,146,145
        !byte 144,144,143,142,141,140,139,138,137,136,135,134,133,132,131,129
        !byte 128,127,125,124,123,121,120,118,117,115,114,112,110,109,107,105
        !byte 104,102,100,99,97,95,93,91,90,88,86,84,82,81,79,77
        !byte 75,73,71,69,68,66,64,62,60,59,57,55,53,51,50,48
        !byte 46,45,43,41,40,38,36,35,33,32,30,29,27,26,25,23
        !byte 22,21,19,18,17,16,15,14,13,12,11,10,9,8,7,6
        !byte 6,5,4,4,3,3,2,2,1,1,1,1,0,0,0,0
        !byte 0,0,0,0,0,1,1,1,1,2,2,3,3,4,4,5
        !byte 6,6,7,8,9,10,11,12,13,14,15,16,17,18,19,21
        !byte 22,23,25,26,27,29,30,32,33,35,36,38,40,41,43,45
        !byte 46,48,50,51,53,55,57,59,60,62,64,66,68,69,71,73
frame   !byte 0
buf     !byte 0
t       !byte 0
t2      !byte 0
