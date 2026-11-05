; BOUNCE.ASM - a bouncing logo that
; squashes when it lands: the classic
; FLD/stretch trick, done by OctoVIC's
; copper. Every raster line of the logo
; gets its own vertical scroll, so a
; line of the logo can be shown twice
; (stretched) or skipped (squashed).
; RUN/STOP+RESTORE: back to the editor.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

logo    !scr "octophonic 64"  ; 13 max
        !byte 0
floor   = 250   ; where it lands (line)
height  = 32    ; the logo's height
squash  = 14    ; how flat it lands
speed   = 1     ; 1 slow, 2 fast

; its colours top to bottom (16 of
; them: red, green, blue)
cols    !byte 200,255,255, 160,240,255
        !byte 120,220,255, 90,200,255
        !byte 70,170,255,  60,140,250
        !byte 60,110,240,  80,90,230
        !byte 255,255,255, 255,230,150
        !byte 255,200,90,  255,170,60
        !byte 250,140,50,  240,110,40
        !byte 220,80,40,   190,60,40

; ======== the program ================

font    = $2000
lctrl   = $13   ; layer on, 256 colours,
                ; 64 tiles wide

start   sei
        jsr screen
        jsr getfont
        jsr octoon
        jsr palette
        jsr tiles
        jsr map
        jsr layer
main    jsr physics     ; make the next
        jsr copper      ; list, then
        lda #floor+2    ; under the logo
-       cmp $d012       ; switch to it
        bne -
        jsr show
        inc t0
        jmp main

; ---- black VIC screen, a line of text
screen  lda #0
        sta $d020
        sta $d021
        ldx #0
-       lda #32
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        lda #7
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne -
        ldx #0
-       lda msg,x
        beq +
        sta $0400+2*40+6,x
        inx
        bne -
+       rts
msg     !scr "fld: a scroll on every line", 0

getfont lda #$33        ; the font ROM
        sta $01
        ldx #0
-       lda $d000,x
        sta font,x
        lda $d100,x
        sta font+256,x
        inx
        bne -
        lda #$37
        sta $01
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
        lda #9          ; on; the VIC in
        sta $d605       ; front, its black
        lda #0          ; see-through
        sta $d606
        lda #1
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
        cpx #48
        bne -
        rts

; ---- tiles: a letter is 2x2 tiles,
; each font pixel 2x2 pixels.
; tile = char*4 + ty*2 + tx, at $040000
tiles   lda #0
        sta $d600
        sta $d601
        lda #4
        sta $d602
        lda #0
        sta ch
        sta ty
        sta tx
nexttl  lda #0
        sta r
-       jsr tilerow
        inc r
        lda r
        cmp #8
        bne -
        inc tx
        lda tx
        cmp #2
        bne nexttl
        lda #0
        sta tx
        inc ty
        lda ty
        cmp #2
        bne nexttl
        lda #0
        sta ty
        inc ch
        lda ch
        cmp #64
        bne nexttl
        rts

tilerow lda ch          ; font row:
        and #31         ; (ch&31)*8
        asl             ; + ty*4 + r/2
        asl
        asl
        sta t
        lda ty
        asl
        asl
        clc
        adc t
        sta t
        lda r
        lsr
        clc
        adc t
        tay
        lda ch
        cmp #32
        bcs +
        lda font,y
        jmp ++
+       lda font+256,y
++      ldx tx          ; the right half:
        beq +           ; 4 bits along
        asl
        asl
        asl
        asl
+       sta bits
        lda ty          ; colour 1-16:
        asl             ; ty*8 + r + 1
        asl
        asl
        sec
        adc r
        sta colr
        ldy #4          ; four font pixels
--      asl bits
        lda #0
        bcc +
        lda colr
+       sta $d604       ; each 2 wide
        sta $d604
        dey
        bne --
        rts

; ---- the map: 64 x 32, all blank but
; the logo in rows 30 and 31
map     lda #0          ; map $030000
        sta $d600
        sta $d601
        lda #3
        sta $d602
        ldy #16         ; 4096 bytes
--      ldx #0
-       lda #128        ; tile 128 = the
        sta $d604       ; space (blank)
        lda #0
        sta $d604
        inx
        inx
        bne -
        dey
        bne --
        lda #0
        sta ty
--      lda ty          ; row 30+ty at
        clc             ; $030000 +
        adc #30         ; row*128
        lsr
        sta $d601
        lda #0
        ror
        sta $d600
        lda #3
        sta $d602
        ldy #0
-       lda logo,y
        beq +
        and #63
        asl             ; tile = char*4
        asl             ; + ty*2
        sta t
        lda ty
        asl
        ora t
        sta $d604       ; left tile
        lda #0
        sta $d604
        lda t
        ora #1
        sta t
        lda ty
        asl
        ora t
        sta $d604       ; right tile
        lda #0
        sta $d604
        iny
        bne -
+       sty len
        inc ty
        lda ty
        cmp #2
        bne --
        rts

; ---- layer 0 (off until the copper
; turns it on for the logo's lines)
layer   lda #0
        sta $d621       ; map $030000
        sta $d622
        lda #3
        sta $d623
        lda #0
        sta $d624       ; tiles $040000
        sta $d625
        lda #4
        sta $d626
        lda len         ; centre it:
        asl             ; SCROLLX = len*8
        asl             ; - 165
        asl
        sec
        sbc #165
        sta $d628
        lda #$ff
        sta $d629
        lda #0
        sta $d62b
        rts

; ---- the bounce: t0 0-63 is one hop;
; the hop's height is a parabola; near
; the ground the logo gets flatter
physics lda t0
        ldy #speed
-       dey
        beq +
        clc
        adc t0
        jmp -
+       and #63
        tax
        lda hop,x       ; how high (0-120)
        sta up
        lda #height     ; flat near the
        sta h           ; ground:
        lda up          ; h = height -
        cmp #squash     ; (squash - up)
        bcs +
        lda #squash
        sec
        sbc up
        sta t
        lda #height
        sec
        sbc t
        sta h
+       lda #floor      ; top line =
        sec             ; floor - up - h
        sbc up
        sec
        sbc h
        sta top
        rts

; ---- the copper list, made each frame
; (two lists, used in turn): the layer
; on at the top line, a SCROLLY on each
; logo line, off after the last
copper  lda #0
        sta $d600
        lda buf         ; $02xx00
        sta $d601
        lda #2
        sta $d602
        lda top
        ldx #$20
        ldy #lctrl
        jsr entry       ; layer on
        lda #0
        sta n           ; line in the logo
-       lda n           ; logo row =
        sta $d652       ; n * 16 / h
        lda #16         ; (the maths unit)
        sta $d650
        lda #0
        sta $d651
        sta $d653
        sta $d65c       ; n*16 / h:
        lda $d654
        sta $d659
        lda $d655
        sta $d65a
        lda #0
        sta $d65b
        lda h
        sta $d65d
        lda #0
        sta $d65e       ; divide now
        lda $d660       ; the row
        clc
        adc #240        ; + 240 (map row 30)
        sec             ; - y (y = line-51)
        sbc top
        sec
        sbc n
        clc
        adc #51
        tay
        lda top
        clc
        adc n
        ldx #$2a
        jsr entry       ; SCROLLY low
        inc n
        lda n
        cmp h
        bne -
        lda top
        clc
        adc h
        ldx #$20
        ldy #0
        jsr entry       ; layer off
        lda #$ff
        sta $d604
        sta $d604
        sta $d604
        sta $d604
        rts

; the new list: from the next frame
show    lda #0
        sta $d610
        lda buf
        sta $d611
        lda #2
        sta $d612
        lda #1          ; the copper on
        sta $d60e
        lda buf
        eor #1
        sta buf
        rts

; one step: line A, register X, value Y
entry   sta $d604
        lda #0
        sta $d604
        stx $d604
        sty $d604
        rts

hop     !byte 0,7,14,21,27,33,39,45
        !byte 50,55,60,65,69,73,77,80
        !byte 84,87,89,92,94,96,97,99
        !byte 100,101,102,102,102,102
        !byte 102,101,100,99,97,96,94
        !byte 92,89,87,84,80,77,73,69
        !byte 65,60,55,50,45,39,33,27
        !byte 21,14,7,0,0,0,0,0,0,0,0

t0      !byte 0
buf     !byte 0
up      !byte 0
h       !byte 0
top     !byte 0
n       !byte 0
len     !byte 0
ch      !byte 0
tx      !byte 0
ty      !byte 0
r       !byte 0
t       !byte 0
bits    !byte 0
colr    !byte 0
