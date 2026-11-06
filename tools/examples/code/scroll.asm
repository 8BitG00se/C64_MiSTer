; SCROLL.ASM - a big smooth scroller
; on an OctoVIC layer: 32x32 letters
; in 256 colours, made from the C64's
; own font, moved one pixel at a time,
; with a wave through it (a scroll for
; every raster line) and colours that
; cycle. RUN/STOP+RESTORE: the editor.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

message !scr "edit me!  change this "
        !scr "text in octocode, then "
        !scr "press f1 to run it...   "
        !byte 0

speed   = 2     ; pixels a frame (1-4)
wave    = 3     ; the wave's size (0-7)
cycle   = 3     ; frames a colour step

; the letters' colours, top to bottom
; (16 colours: red, green, blue)
cols    !byte 255,255,140, 255,240,100
        !byte 255,220,60,  255,200,40
        !byte 255,170,30,  255,140,20
        !byte 255,110,20,  250,80,30
        !byte 240,60,60,   220,40,90
        !byte 200,30,120,  170,30,150
        !byte 140,40,180,  110,50,200
        !byte 80,60,220,   60,80,240

; ======== the program ================

font    = $2000         ; chars 0-63
txtrow  = 12            ; map row
line0   = 51+txtrow*8   ; raster line

start   sei
        jsr screen
        jsr getfont
        jsr octoon
        jsr palette
        jsr tiles
        jsr clrmap
        jsr layer
main    lda #250        ; wait for the
-       cmp $d012       ; bottom of the
        bne -           ; picture
        jsr move
        jsr wobble
        jsr colours
        inc frame
        jmp main

; ---- black VIC screen
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

; ---- the C64's font (letters, digits)
getfont lda #$33        ; the character
        sta $01         ; ROM in view
        ldx #0
-       lda $d000,x
        sta font,x
        lda $d100,x
        sta font+256,x
        inx
        bne -
        lda #$37        ; back as it was
        sta $01
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
        lda #9          ; on, the VIC in
        sta $d605       ; front, its black
        lda #0          ; see-through
        sta $d606       ; (KEY colour 0)
        lda #2          ; the backdrop:
        sta $d619       ; dark blue
        lda #0
        sta $d61a
        lda #5
        sta $d61b
        lda #5
        sta $d61c
        lda #30
        sta $d61d
        lda #1
        sta $d603       ; VRAM step 1
        rts

; ---- palette 1-16: the letter colours
palette lda #0
        sta $d619       ; main palette
        lda #1
        sta $d61a
        ldx #0
-       lda cols,x
        sta $d61b
        lda cols+1,x
        sta $d61c
        lda cols+2,x
        sta $d61d       ; stores, next
        inx
        inx
        inx
        cpx #48
        bne -
        rts

; ---- the tiles: each letter is 4x4
; tiles of 8x8; each font pixel is
; 4x4 pixels. Tile = char*16 + ty*4+tx
vset    sta $d600
        stx $d601
        sty $d602
        rts
tiles   lda #0
        ldx #0
        ldy #4          ; VRAM $040000
        jsr vset
        lda #0
        sta ch
        sta ty
        sta tx
nexttl  lda #0
        sta r
-       jsr tilerow     ; 8 rows a tile
        inc r
        lda r
        cmp #8
        bne -
        inc tx          ; next tile:
        lda tx          ; tx, ty, char
        cmp #4
        bne nexttl
        lda #0
        sta tx
        inc ty
        lda ty
        cmp #4
        bne nexttl
        lda #0
        sta ty
        inc ch
        lda ch
        cmp #64
        bne nexttl
        rts

; one row of a tile: 8 pixels
tilerow lda ch          ; the font row:
        and #31         ; (ch&31)*8
        asl             ; + ty*2 + r/4
        asl
        asl
        sta t
        lda ty
        asl
        adc t
        sta t
        lda r
        lsr
        lsr
        clc
        adc t
        tay
        lda ch
        cmp #32
        bcs +
        lda font,y      ; chars 0-31
        jmp ++
+       lda font+256,y  ; chars 32-63
++      ldx tx          ; the two pixels
        beq +           ; we want, to
-       asl             ; the top
        asl
        dex
        bne -
+       sta bits
        lda ty          ; colour 1-16:
        asl             ; ty*4 + r/2 + 1
        asl
        sta t
        lda r
        lsr
        sec
        adc t
        sta colr
        ldy #2          ; two font pixels
--      asl bits
        lda #0
        bcc +
        lda colr
+       ldx #4          ; each 4 wide
-       sta $d604
        dex
        bne -
        dey
        bne --
        rts

; ---- the map (64x32 tiles): all blank
; (tile 512 = the space's first tile)
clrmap  lda #0
        ldx #0
        ldy #3          ; VRAM $030000
        jsr vset
        ldy #16         ; 4096 bytes
--      ldx #0
-       lda #0
        sta $d604
        lda #2          ; 512 = $0200
        sta $d604
        inx
        inx
        bne -
        dey
        bne --
        ; the line scrolls: all 0
        lda #0
        ldx #$80
        ldy #3          ; VRAM $038000
        jsr vset
        ldx #0
        lda #0
-       sta $d604
        sta $d604
        sta $d604
        inx
        bne -
        rts

; ---- layer 0: 256 colours, 64 tiles
; wide, its own scroll on each line
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
        lda #0
        sta $d62c       ; line scrolls
        lda #$80        ; $038000
        sta $d62d
        lda #3
        sta $d62e
        lda #0
        sta $d628
        sta $d629
        sta $d62a
        sta $d62b
        lda #$17        ; on, 256 colours,
        sta $d620       ; line scroll, 64
        rts

; ---- one step left; a new letter
; every 32 pixels
move    lda x
        clc
        adc #speed
        sta x
        bcc +
        inc x+1
+       lda x+1
        and #1          ; 0-511 (the map
        sta x+1         ; is 512 wide)
        lda x
        sta $d628
        lda x+1
        sta $d629
        lda x
        and #31
        cmp #speed
        bcs +
        jsr letter
+       rts

; the next letter, out of sight on the
; right: map column (x+416)/8
letter  ldy pos
        lda message,y
        bne +
        ldy #0
        sty pos
        lda message
+       inc pos
        and #63         ; tile = char*16:
        pha
        lsr             ; high byte
        lsr
        lsr
        lsr
        sta t+1
        pla
        asl             ; low byte
        asl
        asl
        asl
        sta t
        lda x
        clc
        adc #<416
        sta col
        lda x+1
        adc #>416
        lsr
        ror col
        lsr
        ror col
        lsr
        ror col         ; /8
        lda col
        and #60         ; 0-63, in 4s
        sta col
        lda #0
        sta ty
--      lda #txtrow     ; address: $030000
        clc             ; + (row*64+col)*2
        adc ty
        sta a
        lda #0
        sta a+1
        ldx #6          ; *64
-       asl a
        rol a+1
        dex
        bne -
        lda a
        ora col
        asl
        sta $d600
        lda a+1
        rol
        sta $d601
        lda #3
        sta $d602
        ldx #0
-       txa             ; tile = t + ty*4+tx
        sta tx
        lda ty
        asl
        asl
        ora tx
        ora t
        sta $d604
        lda t+1
        sta $d604
        inx
        cpx #4
        bne -
        inc ty
        lda ty
        cmp #4
        bne --
        rts

; ---- the wave: each of the letters'
; 32 lines its own scroll
wobble  lda #<(line0*2)
        sta $d600
        lda #>(line0*2)
        clc
        adc #$80        ; $038000+line*2
        sta $d601
        lda #3
        sta $d602
        ldx #0
-       txa
        asl
        clc
        adc frame
        adc frame
        and #63
        tay
        lda sine,y      ; -32..32
        ldy #7-wave
        beq +
--      cmp #$80        ; smaller
        ror
        dey
        bne --
+       sta $d604
        and #$80        ; the high byte
        beq +
        lda #$ff
+       sta $d604
        inx
        cpx #32
        bne -
        rts

; ---- colour cycling: every few frames
; the 16 colours move round one place
colours dec wait
        bpl +
        lda #cycle
        sta wait
        lda #0
        sta $d619
        lda #1
        sta $d61a
        inc shift
        ldy shift
        ldx #16
-       tya
        and #15
        sta t
        asl
        adc t           ; *3
        sta t
        sty t+1
        ldy t
        lda cols,y
        sta $d61b
        lda cols+1,y
        sta $d61c
        lda cols+2,y
        sta $d61d
        ldy t+1
        iny
        dex
        bne -
+       rts

sine    !byte 0,6,12,18,23,27,30,32
        !byte 32,32,30,27,23,18,12,6
        !byte 0,250,244,238,233,229
        !byte 226,224,224,224,226,229
        !byte 233,238,244,250
        !byte 0,6,12,18,23,27,30,32
        !byte 32,32,30,27,23,18,12,6
        !byte 0,250,244,238,233,229
        !byte 226,224,224,224,226,229
        !byte 233,238,244,250

x       !word 0
pos     !byte 0
frame   !byte 0
wait    !byte 0
shift   !byte 0
ch      !byte 0
tx      !byte 0
ty      !byte 0
r       !byte 0
t       !word 0
a       !word 0
col     !byte 0
bits    !byte 0
colr    !byte 0
