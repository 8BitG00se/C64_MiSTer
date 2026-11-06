; PILLAR.ASM - a wavy pillar, twisting
; down the screen: OctoVIC's line
; scroll. One layer holds a pillar 64
; pixels wide (8 shaded tiles); every
; raster line has its own scroll
; number, taken from a table of a wave.
; The table is written ONCE. To move
; the wave we only move where the table
; starts, one entry a frame - no
; writing to VRAM while the screen runs.
; RUN/STOP+RESTORE: back to the editor.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

speed   = 2     ; table entries a frame (1-4)

; the pillar's colours 1-8, left to right:
; red, green, blue (dark at the edges,
; bright in the middle: that is the shading)
cols    !byte 20,10,60,   60,30,150
        !byte 120,80,230, 220,200,255
        !byte 190,150,250, 100,60,200
        !byte 50,25,120,  15,5,50

; ======== the program ================

t       = $fd

start   sei
        jsr screen
        jsr octoon
        jsr palette
        jsr tiles
        jsr map
        jsr wave
        jsr layer
main    lda #250        ; wait for the bottom
-       cmp $d012
        bne -
        lda frame       ; where the table starts:
        asl             ; $038000 + 2 * frame
        sta $d62c
        lda #$80
        adc #0
        sta $d62d
        lda frame
        clc
        adc #speed
        sta frame
        jmp main

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

octoon  lda #$4f
        sta $d03f
        lda #$38
        sta $d03f
        ldx #$4b
        lda #0
-       sta $d605,x
        dex
        bpl -
        lda #9          ; on, the VIC in front,
        sta $d605       ; its black see-through
        lda #0
        sta $d606
        lda #2          ; the backdrop: night blue
        sta $d619
        lda #0
        sta $d61a
        lda #4
        sta $d61b
        lda #4
        sta $d61c
        lda #26
        sta $d61d
        lda #1          ; VRAM step 1
        sta $d603
        rts

palette lda #0
        sta $d619
        lda #1
        sta $d61a
        ldx #0
-       lda cols,x
        sta $d61b
        lda cols+1,x
        sta $d61c
        lda cols+2,x
        sta $d61d
        inx
        inx
        inx
        cpx #24
        bne -
        rts

; ---- tile 0 blank, tiles 1-8 one solid
; colour each (16 colours: two pixels
; a byte, 32 bytes a tile) at $040000
tiles   lda #0
        sta $d600
        sta $d601
        lda #4
        sta $d602
        ldx #0
-       lda #0
        sta $d604
        inx
        cpx #32
        bne -
        ldy #1          ; tile 1-8
--      tya
        asl
        asl
        asl
        asl
        sta t
        tya
        ora t           ; colour in both pixels
        ldx #32
-       sta $d604
        dex
        bne -
        iny
        cpy #9
        bne --
        rts

; ---- the map: 64 x 32 tiles. The pillar
; is tiles 1-8 in columns 26-33
map     lda #0
        sta $d600
        sta $d601
        lda #3          ; $030000
        sta $d602
        ldy #0          ; row
--      ldx #0          ; column
-       txa
        sec
        sbc #26
        cmp #8
        bcs +           ; not 0-7: blank
        adc #1          ; tile 1-8
        jmp ++
+       lda #0
++      sta $d604       ; tile low
        lda #0
        sta $d604       ; tile high
        inx
        cpx #64
        bne -
        iny
        cpy #32
        bne --
        rts

; ---- the line scroll table at $038000:
; 456 numbers of 2 bytes (a signed
; 16-bit offset), a wave of 256 that
; repeats. Raster line n reads entry
; n from wherever the table starts.
wave    lda #0
        sta $d600
        lda #$80
        sta $d601
        lda #3
        sta $d602
        ldx #0
-       lda table,x
        sta $d604
        inx
        bne -
-       lda table+256,x
        sta $d604
        inx
        bne -
-       lda table+512,x
        sta $d604
        inx
        cpx #<912
        bne -
        rts

; ---- layer 0: 16 colours, 64 wide, line
; scroll on, its table at $038000
layer   lda #0
        sta $d621
        sta $d622
        lda #3
        sta $d623
        lda #0
        sta $d624
        sta $d625
        lda #4
        sta $d626
        lda #0
        sta $d62c
        lda #$80
        sta $d62d
        lda #3
        sta $d62e
        lda #0
        sta $d628
        sta $d629
        sta $d62a
        sta $d62b
        lda #$15        ; on, 16 colours, line
        sta $d620       ; scroll, 64 wide
        rts

frame   !byte 0

; the wave: 90 + 60 sin(x) + 30 sin(3x),
; as the low byte and a 0 high byte
table   !byte 90,0,94,0,97,0,101,0,105,0,108,0,112,0,115,0
        !byte 118,0,122,0,125,0,128,0,131,0,133,0,136,0,138,0
        !byte 141,0,143,0,145,0,147,0,148,0,150,0,151,0,152,0
        !byte 153,0,153,0,154,0,154,0,155,0,155,0,154,0,154,0
        !byte 154,0,153,0,152,0,151,0,151,0,149,0,148,0,147,0
        !byte 146,0,144,0,143,0,141,0,140,0,138,0,137,0,135,0
        !byte 134,0,132,0,131,0,130,0,128,0,127,0,126,0,125,0
        !byte 124,0,123,0,122,0,122,0,121,0,121,0,120,0,120,0
        !byte 120,0,120,0,120,0,121,0,121,0,122,0,122,0,123,0
        !byte 124,0,125,0,126,0,127,0,128,0,130,0,131,0,132,0
        !byte 134,0,135,0,137,0,138,0,140,0,141,0,143,0,144,0
        !byte 146,0,147,0,148,0,149,0,151,0,151,0,152,0,153,0
        !byte 154,0,154,0,154,0,155,0,155,0,154,0,154,0,153,0
        !byte 153,0,152,0,151,0,150,0,148,0,147,0,145,0,143,0
        !byte 141,0,138,0,136,0,133,0,131,0,128,0,125,0,122,0
        !byte 118,0,115,0,112,0,108,0,105,0,101,0,97,0,94,0
        !byte 90,0,86,0,83,0,79,0,75,0,72,0,68,0,65,0
        !byte 62,0,58,0,55,0,52,0,49,0,47,0,44,0,42,0
        !byte 39,0,37,0,35,0,33,0,32,0,30,0,29,0,28,0
        !byte 27,0,27,0,26,0,26,0,25,0,25,0,26,0,26,0
        !byte 26,0,27,0,28,0,29,0,29,0,31,0,32,0,33,0
        !byte 34,0,36,0,37,0,39,0,40,0,42,0,43,0,45,0
        !byte 46,0,48,0,49,0,50,0,52,0,53,0,54,0,55,0
        !byte 56,0,57,0,58,0,58,0,59,0,59,0,60,0,60,0
        !byte 60,0,60,0,60,0,59,0,59,0,58,0,58,0,57,0
        !byte 56,0,55,0,54,0,53,0,52,0,50,0,49,0,48,0
        !byte 46,0,45,0,43,0,42,0,40,0,39,0,37,0,36,0
        !byte 34,0,33,0,32,0,31,0,29,0,29,0,28,0,27,0
        !byte 26,0,26,0,26,0,25,0,25,0,26,0,26,0,27,0
        !byte 27,0,28,0,29,0,30,0,32,0,33,0,35,0,37,0
        !byte 39,0,42,0,44,0,47,0,49,0,52,0,55,0,58,0
        !byte 62,0,65,0,68,0,72,0,75,0,79,0,83,0,86,0
        !byte 90,0,94,0,97,0,101,0,105,0,108,0,112,0,115,0
        !byte 118,0,122,0,125,0,128,0,131,0,133,0,136,0,138,0
        !byte 141,0,143,0,145,0,147,0,148,0,150,0,151,0,152,0
        !byte 153,0,153,0,154,0,154,0,155,0,155,0,154,0,154,0
        !byte 154,0,153,0,152,0,151,0,151,0,149,0,148,0,147,0
        !byte 146,0,144,0,143,0,141,0,140,0,138,0,137,0,135,0
        !byte 134,0,132,0,131,0,130,0,128,0,127,0,126,0,125,0
        !byte 124,0,123,0,122,0,122,0,121,0,121,0,120,0,120,0
        !byte 120,0,120,0,120,0,121,0,121,0,122,0,122,0,123,0
        !byte 124,0,125,0,126,0,127,0,128,0,130,0,131,0,132,0
        !byte 134,0,135,0,137,0,138,0,140,0,141,0,143,0,144,0
        !byte 146,0,147,0,148,0,149,0,151,0,151,0,152,0,153,0
        !byte 154,0,154,0,154,0,155,0,155,0,154,0,154,0,153,0
        !byte 153,0,152,0,151,0,150,0,148,0,147,0,145,0,143,0
        !byte 141,0,138,0,136,0,133,0,131,0,128,0,125,0,122,0
        !byte 118,0,115,0,112,0,108,0,105,0,101,0,97,0,94,0
        !byte 90,0,86,0,83,0,79,0,75,0,72,0,68,0,65,0
        !byte 62,0,58,0,55,0,52,0,49,0,47,0,44,0,42,0
        !byte 39,0,37,0,35,0,33,0,32,0,30,0,29,0,28,0
        !byte 27,0,27,0,26,0,26,0,25,0,25,0,26,0,26,0
        !byte 26,0,27,0,28,0,29,0,29,0,31,0,32,0,33,0
        !byte 34,0,36,0,37,0,39,0,40,0,42,0,43,0,45,0
        !byte 46,0,48,0,49,0,50,0,52,0,53,0,54,0,55,0
        !byte 56,0,57,0,58,0,58,0,59,0,59,0,60,0,60,0
        !byte 60,0,60,0,60,0,59,0,59,0,58,0,58,0,57,0
