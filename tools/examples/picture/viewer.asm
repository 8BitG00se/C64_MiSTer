; MOONLIGHT - a picture for the Octophonic 64: 320 x 200 in 253 of
; OctoVIC's 256 colours, on a bitmap layer, packed (runs) in 42 KB
; (the packed picture runs up under the BASIC ROM, which is switched out while it is unpacked).
; It fades up, stays, and SPACE fades it out to READY.
; Original picture: Octophonic 64 / Mong00se.
* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"
        !byte 0,0,0
        jmp start

src     = $fb           ; the packed picture
pic     = $10           ; VRAM $100000, 512 bytes a row

start   sei
        lda #0
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
        lda #$4f
        sta $d03f
        lda #$38
        sta $d03f
        ldx #$4b
        lda #0
-       sta $d605,x
        dex
        bpl -
        lda #9
        sta $d605
        lda #2          ; a black backdrop
        sta $d619
        lda #0
        sta $d61a
        sta $d61b
        sta $d61c
        sta $d61d
        lda #1
        sta $d603
        lda #0
        sta level
        jsr setpal      ; all black first
        lda #$36        ; BASIC out: the packed picture is under it
        sta $01
        jsr unpack
        lda #$37
        sta $01
        lda #0          ; layer 0: the bitmap
        sta $d624
        sta $d625
        lda #pic
        sta $d626
        lda #$1b        ; on, 256 colours, bitmap, 512 wide
        sta $d620
        cli
up      jsr vbl         ; fade up
        jsr setpal
        lda level
        clc
        adc #8
        sta level
        bcc up
        lda #255
        sta level
        jsr setpal
-       lda $cb         ; SPACE: fade out
        cmp #60
        bne -
down    jsr vbl
        lda level
        sec
        sbc #8
        sta level
        bcc +
        jsr setpal
        jmp down
+       lda #0
        sta $d620
        sta $d605
        lda #14
        sta $d020
        lda #6
        sta $d021
        lda #0
        sta $d03f       ; OctoVIC away
        jmp ($a002)     ; to READY

vbl     lda $d012
        cmp #250
        bne vbl
-       lda $d012
        cmp #250
        beq -
        rts

; the palette at level/256 (the maths unit)
setpal  lda #0
        sta $d619
        sta $d651
        sta $d653
        lda #1
        sta $d61a
        lda level
        sta $d652
        lda #<pal
        sta src
        lda #>pal
        sta src+1
        ldx #255
        ldy #0
-       ldy #0
        lda (src),y
        sta $d650
        lda $d655
        sta $d61b
        iny
        lda (src),y
        sta $d650
        lda $d655
        sta $d61c
        iny
        lda (src),y
        sta $d650
        lda $d655
        sta $d61d
        lda src
        clc
        adc #3
        sta src
        bcc +
        inc src+1
+       dex
        bne -
        rts

; runs: n<128: n times the next byte; n>=128: n-128 bytes as they are; 0 ends
unpack  lda #<packed
        sta src
        lda #>packed
        sta src+1
        lda #0
        sta row
        sta row+1
        jsr rowstart
next    ldy #0
        lda (src),y
        beq done
        jsr inc1
        cmp #128
        bcs lit
        tax             ; a run
        lda (src),y
        jsr inc1
-       jsr put
        dex
        bne -
        jmp next
lit     and #127
        tax
-       ldy #0
        lda (src),y
        jsr inc1
        jsr put
        dex
        bne -
        jmp next
done    rts

inc1    inc src
        bne +
        inc src+1
+       rts

put     sta $d604       ; one pixel; after 320 the next row
        dec left
        beq +
        rts
+       pha
        lda left+1
        beq +
        dec left+1
        pla
        rts
+       inc row
        jsr rowstart
        pla
        rts

rowstart                ; VADDR = $100000 + row*512
        lda #<320
        sta left
        lda #>320
        sta left+1
        lda #0
        sta $d600
        lda row
        asl
        sta $d601
        lda #0
        rol
        clc
        adc #pic
        sta $d602
        rts

level   !byte 0
row     !word 0
left    !word 0
pal     !binary "moonlight.pal"
packed  !binary "moonlight.rle"
