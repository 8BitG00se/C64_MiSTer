; The eight-SID player for the Octophonic 64: a SIDWeaver tune on all eight SIDs.
; SID 1 plays the tune; OctoSID FX (chorus + echo) makes SIDs 2-4 from it; SIDs 5, 6 and 7
; each play one voice of it alone (voice 1, 2, 3), and SID 8 plays all of it a little softer.
; (mkmix.py makes the tune write to the extra SIDs too.) The equaliser shows all eight:
; a bar jumps up when that SID starts a note and falls away.
; By Octophonic 64 / Mong00se.
* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"
        !byte 0,0,0
        jmp start

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
        lda #1
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne -
        ldx #0
-       lda text,x
        sta $0400+1*40,x
        lda text+240,x
        sta $0400+1*40+240,x
        inx
        cpx #240
        bne -
        lda #$4f        ; OctoVIC: the VIC's black shows the backdrop
        sta $d03f
        lda #$38
        sta $d03f
        lda #9
        sta $d605
        lda #0
        sta $d606
        lda #FX*3       ; OctoSID FX: chorus + echo, or off
        sta $d6c0
        lda #2
        sta $d619
        ldx #24         ; SIDs 5-8 clean
        lda #0
-       sta $d480,x
        sta $d4a0,x
        sta $d580,x
        sta $d5a0,x
        dex
        bpl -
        lda #15         ; the volumes of SIDs 5-8 (the tune's own volume writes, a sample player in its NMI, stay on SID 1)
        sta $d498
        sta $d4b8
        sta $d598
        lda #12
        sta $d5b8
        jsr eqinit
        lda #0
        jsr INIT
loop    lda #251
-       cmp $d012
        bne -
        jsr PLAY
        jsr eqdraw
        jsr glow
        jsr clock
        jmp loop

; the backdrop: a slow hue, brighter with the sound
glow    lda $d41c       ; voice 3's envelope (0-255)
        lsr
        lsr
        sta lvl
        inc hue
        lda hue
        lsr
        lsr
        tax
        lda #0
        sta $d61a
        lda sine,x
        lsr
        lsr
        clc
        adc lvl
        sta $d61b
        txa
        clc
        adc #21
        and #63
        tay
        lda sine,y
        lsr
        lsr
        lsr
        clc
        adc lvl
        sta $d61c
        txa
        clc
        adc #42
        and #63
        tay
        lda sine,y
        lsr
        lsr
        clc
        adc lvl
        sta $d61d
        rts

; the clock m:ss at row 18
clock   inc fr
        lda fr
        cmp #50
        bne +
        lda #0
        sta fr
        sed
        lda secs
        clc
        adc #1
        cmp #$60
        bne ++
        lda mins
        clc
        adc #1
        sta mins
        lda #0
++      sta secs
        cld
+       lda mins
        and #15
        ora #$30
        sta $0400+23*40+18
        lda #$3a
        sta $0400+23*40+19
        lda secs
        lsr
        lsr
        lsr
        lsr
        ora #$30
        sta $0400+23*40+20
        lda secs
        and #15
        ora #$30
        sta $0400+23*40+21
        rts

sine    !byte 128,140,152,165,176,188,198,208,218,226,234,240,245,250,253,254
        !byte 255,254,253,250,245,240,234,226,218,208,198,188,176,165,152,140
        !byte 128,115,103,90,79,67,57,47,37,29,21,15,10,5,2,1
        !byte 0,1,2,5,10,15,21,29,37,47,57,67,79,90,103,115
lvl     !byte 0
hue     !byte 0
fr      !byte 0
secs    !byte 0
mins    !byte 0
text    !source "text.inc"
        !fill 480-(*-text),32
* = $1000
        !binary TUNE
; ---------------------------------------------------------------- the eight SIDs (above the tune)
; the stubs: the tune's own store, then the copy
!macro stuba .k {
        sta $d400+.k
        php
        pha
        sty ys
        stx xs
        ldx #.k
        jsr mix
        ldy ys
        ldx xs
        pla
        plp
        rts
}
!macro stuby .k {
        sta $d400+.k,y
        php
        pha
        sty ys
        stx xs
        tya
        clc
        adc #.k
        tax
        pla
        pha
        jsr mix
        ldy ys
        ldx xs
        pla
        plp
        rts
}


        !source "mixstubs.inc"
* = $c300
ys      !byte 0
xs      !byte 0
mv      !byte 0
rg      !byte 0
vn      !byte 0
t4      !byte 0
tickq   !byte 0
pg      !byte 0,0,0
eql     !fill 8,0
hgt     !byte 8,8,4,4,8,8,8,6       ; the echoes at half height, SID 8 a little lower
ring    !fill 128,0
barcol  !byte 2,7,12,17,22,27,32,37
barclr  !byte 7,13,3,14,10,8,5,2
rowlo   !for i,0,7 { !byte <($0400+(13+i)*40) }
rowhi   !for i,0,7 { !byte >($0400+(13+i)*40) }
vreg    !for v,0,2 { !for r,0,6 { !byte r } }
vnum    !for v,0,2 { !for r,0,6 { !byte v } }
ry      !byte 0
bc      !byte 0

; A = the value just stored, X = the register 0-24: copy it to SIDs 5-8, note the note-ons
mix     sta mv
        stx rg
        cpx #25
        bcs mixret
        cpx #21
        bcc voices
        lda mv                  ; filter and volume: SIDs 5-7 as they are, SID 8 softer
        sta $d480,x
        sta $d4a0,x
        sta $d580,x
        cpx #24
        bne +
        and #$0f
        lsr
        sta t4
        lda mv
        and #$f0
        ora t4
+       sta $d5a0,x
mixret  rts
voices  lda vnum,x
        sta vn
        ldy vreg,x
        lda mv
        sta $d5a0,x             ; SID 8: all of it
        ldx vn                  ; the voice's own SID, as its voice 1: SID 5, 6, 7
        lda mv
        cpx #1
        beq +
        bcs ++
        sta $d480,y
        jmp +++
+       sta $d4a0,y
        jmp +++
++      sta $d580,y
+++     lda mv
        cpy #4                  ; a control register: a note starting?
        bne mixret
        and #1
        beq gateoff
        lda pg,x
        bne mixret
        lda #1
        sta pg,x
        lda #0
        ldx #0
        jsr trig                ; SID 1
        lda #0
        ldx #1
        jsr trig                ; SID 2: the chorus
        lda #7
        ldx #2
        jsr trig                ; SID 3: the echo, 140 ms later
        lda #10
        ldx #3
        jsr trig                ; SID 4: 200 ms later
        lda #0
        ldx vn
        inx
        inx
        inx
        inx
        jsr trig                ; SID 5, 6 or 7: its voice
        lda #0
        ldx #7
trig    clc                     ; A = frames later, X = the bar
        adc tickq
        and #15
        asl
        asl
        asl
        stx t4
        clc
        adc t4
        tay
        lda #1
        sta ring,y
        rts
gateoff lda #0
        sta pg,x
        rts

eqinit  ldx #0                  ; the colours (rows 13-20 of each bar) and the labels 1-8 (row 21)
-       lda barcol,x
        sta bc
        lda #0
        sta ry
--      ldy ry
        lda rowlo,y
        clc
        adc bc
        sta cdst+1
        lda rowhi,y
        adc #0
        clc
        adc #$d4                ; the colour RAM: $D800 + (the same offset)
        sta cdst+2
        lda barclr,x
        ldy #3
---     
cdst    sta $d800,y
        dey
        bpl cdst
        inc ry
        lda ry
        cmp #8
        bne --
        txa
        clc
        adc #$31                ; the label
        ldy bc
        sta $0400+21*40+1,y
        lda #1
        sta $d800+21*40+1,y
        inx
        cpx #8
        bne -
        rts

; the equaliser: this frame's note-ons raise their bars, 8 rows high, and they fall away
eqdraw  lda tickq
        and #15
        asl
        asl
        asl
        tay
        ldx #0
-       lda ring,y
        beq +
        lda #0
        sta ring,y
        lda hgt,x
        cmp eql,x
        bcc +
        sta eql,x
+       iny
        inx
        cpx #8
        bne -
        ldx #0
bar     lda barcol,x
        sta bc
        lda #0
        sta ry
rw      ldy ry
        lda rowlo,y
        clc
        adc bc
        sta dst+1
        lda rowhi,y
        adc #0
        sta dst+2
        lda eql,x
        clc
        adc ry                  ; lit if level + row >= 8 (row 0 is the top)
        cmp #8
        lda #$20
        bcc +
        lda #$a0
+       ldy #3
dst     sta $0400,y
        dey
        bpl dst
        inc ry
        lda ry
        cmp #8
        bne rw
        lda tickq
        and #1
        bne +
        lda eql,x
        beq +
        dec eql,x
+       inx
        cpx #8
        bne bar
        inc tickq
        rts
