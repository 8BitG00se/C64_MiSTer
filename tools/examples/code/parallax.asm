; PARALLAX.ASM - three depths moving at
; three speeds: a sky made by the
; copper (a colour a line), mountains
; on layer 0 (16 colours, slow) and
; hills on layer 1 (256 colours, fast).
; Every tile is worked out here, pixel
; by pixel, from a sine wave. One
; 16-colour and one 256-colour layer:
; well inside OctoVIC's line budget.
; RUN/STOP+RESTORE: back to the editor.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

far     = 1     ; mountains: pixels a step
near    = 3     ; hills: pixels a frame
slow    = 2     ; mountains step every N
peaks   = 3     ; mountain bumpiness 1-5
; the sky, top to bottom: red, green,
; blue at the top and at the horizon
skytop  !byte 10,20,80
skylow  !byte 255,150,90

; ======== the program ================

sine    = $3000         ; 256 bytes
h0      = $3100         ; mountain tops
h1      = $3300         ; hill tops
gmin    = $3500         ; per 8 columns
gmax    = $3540
edges   = $3600         ; the edge tiles
p       = $fb
list    = $020000

start   sei
        jsr screen
        jsr octoon
        jsr mksine
        jsr heights
        jsr colours
        jsr sky
        jsr layers
main    lda #255
-       cmp $d012
        bne -
        lda x1          ; the hills
        clc
        adc #near
        sta x1
        sta $d638
        bcc +
        inc x1+1
+       lda x1+1
        and #1
        sta x1+1
        sta $d639
        inc wait        ; the mountains
        lda wait
        cmp #slow
        bne main
        lda #0
        sta wait
        lda x0
        clc
        adc #far
        sta x0
        sta $d628
        bcc +
        inc x0+1
+       lda x0+1
        and #1
        sta x0+1
        sta $d629
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
        lda #9          ; on, the VIC's
        sta $d605       ; black see-through
        lda #1
        sta $d603
        rts

; ---- a sine 0-255 (parabolas)
mksine  ldx #0
-       txa
        and #127
        sta t
        eor #127        ; i*(127-i)/64
        sta $d652
        lda t
        sta $d650
        lda #0
        sta $d651
        sta $d653
        lda $d654
        asl
        lda $d655
        rol
        asl             ; 0-127
        cpx #128
        bcs +
        lsr
        clc
        adc #128
        jmp ++
+       lsr
        eor #$ff
        sec
        adc #127
++      sta sine,x
        inx
        bne -
        rts

; ---- the tops: 512 columns each.
; mountains 30-110 (from map row 8),
; hills 130-175
heights ldx #0
-       txa             ; mountains:
        ldy #peaks      ; sine(x) / 4 +
        jsr times       ; sine(x*peaks)/8
        tay
        lda sine,y
        lsr
        lsr
        lsr
        sta t
        lda sine,x
        lsr
        lsr
        clc
        adc t
        adc #100
        sta h0,x
        sta h0+256,x
        txa             ; hills: a slow
        asl             ; wave
        tay
        lda sine,y
        lsr
        lsr
        lsr
        lsr
        lsr             ; 0-7
        sta t
        lda sine,x
        lsr
        lsr             ; 0-63
        clc
        adc t
        adc #170
        sta h1,x
        sta h1+256,x
        inx
        bne -
        rts

times   sta t2
        lda #0
-       clc
        adc t2
        dey
        bne -
        rts

; ---- the palette: 1-15 the rock
; (bank 0, layer 0), 32-63 the hills
colours lda #0
        sta $d619
        lda #1
        sta $d61a
        ldx #0
-       lda rock,x
        sta $d61b
        lda rock+1,x
        sta $d61c
        lda rock+2,x
        sta $d61d
        inx
        inx
        inx
        cpx #45
        bne -
        lda #32         ; hills: green,
        sta $d61a       ; darker going
        ldx #0          ; down
-       txa
        eor #31
        asl
        asl
        sta t           ; 4-124
        lda #10
        sta $d61b
        lda t
        clc
        adc #90
        sta $d61c       ; green
        lda t
        lsr
        lsr
        sta $d61d
        inx
        cpx #32
        bne -
        rts
rock    !byte 255,255,255, 230,230,245
        !byte 170,160,200, 150,140,185
        !byte 135,125,175, 120,110,165
        !byte 108,98,155,  96,86,145
        !byte 86,76,135,   76,66,125
        !byte 68,58,115,   60,50,105
        !byte 54,44,98,    48,38,90
        !byte 42,32,82

; ---- the sky: the copper sets the
; backdrop on every line from 16 to 200
; (a list made once, never touched)
sky     lda #2
        sta $d619       ; the backdrop
        lda #<list
        sta $d600
        lda #>list
        sta $d601
        lda #^list
        sta $d602
        lda #16
        sta ln
-       lda ln          ; mix 0-230:
        sec             ; (line-16)*5/4
        sbc #16
        sta t
        lsr
        lsr
        clc
        adc t
        sta mix
        lda #0
        sta $d651
        sta $d653
        ldx #0
--      lda skylow,x    ; top + (low-top)
        sec             ; *mix/256
        sbc skytop,x
        php
        bcs +
        eor #$ff
        adc #1
+       sta $d650
        lda mix
        sta $d652
        lda $d655
        plp
        bcs +
        eor #$ff
        adc #1
+       clc
        adc skytop,x
        sta rgb,x
        inx
        cpx #3
        bne --
        ldx #0
--      lda ln
        sta $d604
        lda #0
        sta $d604
        lda reg,x
        sta $d604
        lda rgb-1,x
        cpx #0
        bne +
        lda #0
+       sta $d604
        inx
        cpx #4
        bne --
        inc ln
        lda ln
        cmp #200
        bne -
        ldx #0          ; under the hills:
-       lda ground,x    ; dark green
        sta $d604
        inx
        cpx #16
        bne -
        lda #$ff
        sta $d604
        sta $d604
        sta $d604
        sta $d604
        lda #<list
        sta $d610
        lda #>list
        sta $d611
        lda #^list
        sta $d612
        lda #1
        sta $d60e
        rts
reg     !byte $1a,$1b,$1c,$1d
ground  !byte 15,1,$1a,0, 15,1,$1b,10
        !byte 15,1,$1c,154, 15,1,$1d,16

; ---- a layer's map and tiles. Each
; map tile is sky (tile 0), deep rock
; (tile 1, one colour) or an edge: its
; own tile, worked out pixel by pixel.
build   jsr groups
        lda layer       ; the map:
        asl             ; $030000/$031000
        asl
        asl
        asl
        sta $d601
        lda #0
        sta $d600
        lda #3
        sta $d602
        lda #2          ; edges from 2
        sta next
        lda #0
        sta next+1
        sta nedge
        sta nedge+1
        lda #<edges
        sta p
        lda #>edges
        sta p+1
        lda #0
        sta row
--      lda #0
        sta col
-       jsr classify    ; A/X: the tile
        sta $d604
        stx $d604
        inc col
        lda col
        cmp #64
        bne -
        inc row
        lda row
        cmp #32
        bne --
        ; the tiles: 0 sky, 1 rock, then
        ; each edge in the list
        lda layer
        clc
        adc #4
        sta $d602       ; $040000/$050000
        lda #0
        sta $d600
        sta $d601
        ldx #0          ; tile 0: all 0
        lda layer
        beq +
        ldx #64         ; (64 bytes or
+       lda #0          ; 32 a tile)
        jsr fill
        lda solid       ; tile 1: rock
        ldx #64
        ldy layer
        bne +
        asl             ; 16 colours: two
        asl             ; pixels a byte
        asl
        asl
        ora solid
        ldx #0
+       jsr fill
        lda #<edges
        sta p
        lda #>edges
        sta p+1
-       lda nedge
        ora nedge+1
        beq +
        ldy #0
        lda (p),y
        sta col
        iny
        lda (p),y
        sta row
        jsr onetile
        lda p
        clc
        adc #2
        sta p
        bcc ++
        inc p+1
++      lda nedge
        bne ++
        dec nedge+1
++      dec nedge
        jmp -
+       rts

; X+32 bytes (or 64) of A
fill    ldy #32
        cpx #64
        bne +
        ldy #64
+
-       sta $d604
        dey
        bne -
        rts

; each 8 columns' highest and lowest top
groups  ldx #0          ; group
-       txa
        asl
        asl
        asl
        sta x
        lda #255
        sta gmin,x
        lda #0
        sta gmax,x
        ldy #8
--      stx t2
        jsr top         ; A = top at x
        ldx t2
        cmp gmin,x
        bcs +
        sta gmin,x
+       cmp gmax,x
        bcc +
        sta gmax,x
+       inc x
        dey
        bne --
        inx
        cpx #64
        bne -
        rts

; the top at column x (group in X: >=32
; is the second 256)
top     lda layer
        bne +
        cpx #32
        bcs ++
        ldx x
        lda h0,x
        rts
++      ldx x
        lda h0+256,x
        rts
+       cpx #32
        bcs ++
        ldx x
        lda h1,x
        rts
++      ldx x
        lda h1+256,x
        rts

; the map entry for (col, row) in A/X
classify
        ldx col
        lda row         ; the tile's last
        asl             ; line: row*8+7
        asl
        asl
        sta y
        clc
        adc #7
        cmp gmin,x      ; above every top:
        bcs +           ; sky
        lda #0
        tax
        rts
+       lda gmax,x      ; below the deepest
        clc             ; top + the fade:
        adc deep        ; all rock
        bcs +
        cmp y
        beq ++
        bcs +
++      lda #1
        ldx #0
        rts
+       ldy #0          ; an edge: note it
        lda col
        sta (p),y
        iny
        lda row
        sta (p),y
        lda p
        clc
        adc #2
        sta p
        bcc +
        inc p+1
+       inc nedge
        bne +
        inc nedge+1
+       lda next
        ldx next+1
        inc next
        bne +
        inc next+1
+       rts

; one tile: 8 rows of 8 pixels
onetile lda col
        and #31
        asl
        asl
        asl
        sta x0t
        lda row
        asl
        asl
        asl
        sta y
        lda #8
        sta py
--      lda x0t
        sta x
        ldy #8
-       jsr pixel
        ldx layer
        bne +
        jsr nibble      ; 16 colours
        jmp ++
+       sta $d604       ; 256: a byte
++      inc x
        dey
        bne -
        inc y
        dec py
        bne --
        rts

; 16 colours: two pixels a byte
nibble  sta t
        tya
        and #1
        bne +
        lda t           ; the left pixel
        asl
        asl
        asl
        asl
        sta byte
        rts
+       lda t           ; the right one
        ora byte
        sta $d604
        rts

; the colour at (x, y): sky above the
; top, then darker going down
pixel   ldx col
        jsr top
        sta t
        lda y
        sec
        sbc t
        bcc sky0
        lsr             ; depth/2
        ldx layer
        bne +
        clc             ; mountains:
        adc #1          ; 1 + depth/2
        cmp #15
        bcc ++
        lda #15
++      rts
+       asl             ; hills: 32 +
        cmp #15         ; depth
        bcc ++
        lda #15
++      clc
        adc #32
        rts
sky0    lda #0
        rts

; ---- the two layers
layers  lda #0          ; layer 0
        sta layer
        lda #15
        sta solid
        lda #28
        sta deep
        jsr build
        lda #1          ; layer 1
        sta layer
        lda #47
        sta solid
        lda #15
        sta deep
        jsr build
        lda #0
        sta $d621       ; layer 0: map
        sta $d622       ; $030000
        lda #3
        sta $d623
        lda #0          ; tiles $040000
        sta $d624
        sta $d625
        lda #4
        sta $d626
        lda #0          ; layer 1: map
        sta $d631       ; $031000
        lda #$10
        sta $d632
        lda #3
        sta $d633
        lda #0          ; tiles $050000
        sta $d634
        sta $d635
        lda #5
        sta $d636
        lda #35         ; map line 0 at
        sta $d62a       ; the top line
        sta $d63a
        lda #$11        ; 16 colours, 64
        sta $d620       ; wide, on
        lda #$13        ; 256 colours, 64
        sta $d630       ; wide, on
        rts

x0      !word 0
x1      !word 0
wait    !byte 0
layer   !byte 0
next    !word 0
nedge   !word 0
col     !byte 0
solid   !byte 0
deep    !byte 0
x0t     !byte 0
x       !byte 0
y       !byte 0
py      !byte 0
row     !byte 0
byte    !byte 0
ln      !byte 0
mix     !byte 0
rgb     !byte 0,0,0
t       !byte 0
t2      !byte 0
