; A SID tune player for the Octophonic 64: the tune plays on SID 1
; at 50 frames a second; the screen shows its name, a clock and the
; sound's level (SID 1 voice 3's envelope) as the backdrop's glow.
; FX=1: OctoSID FX on - the tune spread over SIDs 1-4 (chorus + echo).
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
        sta $0400+6*40,x
        lda text+240,x
        sta $0400+6*40+240,x
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
        lda #0
        jsr INIT
loop    lda #251
-       cmp $d012
        bne -
        jsr PLAY
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
        sta $0400+18*40+18
        lda #$3a
        sta $0400+18*40+19
        lda secs
        lsr
        lsr
        lsr
        lsr
        ora #$30
        sta $0400+18*40+20
        lda secs
        and #15
        ora #$30
        sta $0400+18*40+21
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
