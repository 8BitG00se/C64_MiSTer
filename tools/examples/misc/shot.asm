; TAKE A SCREENSHOT - SPACE asks Octophonic Main for a screenshot (mailbox command $10, SHOT):
; it is saved as games/C64/Screenshots/SHOT-n.png on the SD card (always; the F1 browser lists it) and also on the network share's
; Octophonic/Screenshots). Rainbow blocks to have something to take. Octophonic 64 / Mong00se.
* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"
        !byte 0,0,0
        jmp start

MB      = $D6F0
p       = $fb
start   lda #0
        sta $d020
        sta $d021
        ldx #0
-       lda #160                ; solid blocks
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        inx
        bne -
        jsr message
loop    lda #250
-       cmp $d012
        bne -
        inc phase
        jsr colours
        lda $cb
        cmp #60                 ; SPACE
        bne loop
        lda held
        bne loop2
        inc held
        jsr shot
        jmp loop
loop2   jmp loop
colours ldx #0                  ; a diagonal rainbow, moving
        lda #<$d800
        sta p
        lda #>$d800
        sta p+1
        ldy #0
row     tya
        pha
        ldy #0
-       tya
        clc
        adc rowc
        adc phase
        lsr
        lsr
        and #15
        tax
        lda cols,x
        sta (p),y
        iny
        cpy #40
        bne -
        lda p
        clc
        adc #40
        sta p
        bcc +
        inc p+1
+       inc rowc
        pla
        tay
        iny
        cpy #22
        bne row
        lda #0
        sta rowc
        lda $cb                 ; let go of SPACE: another can be taken
        cmp #64
        bne +
        lda #0
        sta held
+       rts
cols    !byte 2,8,10,7,13,5,3,14,6,4,11,9,2,8,10,7

message ldx #0
-       lda m1,x
        sta $0400+22*40,x
        lda #1
        sta $d800+22*40,x
        sta $d800+23*40,x
        sta $d800+24*40,x
        lda #32
        sta $0400+23*40,x
        sta $0400+24*40,x
        inx
        cpx #40
        bne -
        rts

shot    lda #$4f                ; the mailbox is on OctoVIC's page
        sta $d03f
        lda #$38
        sta $d03f
        inc count
        lda #0
        sta MB+9                ; the name: SHOT-n
        ldx #0
-       lda name,x
        sta MB+8
        inx
        cpx #5
        bne -
        lda count
        ora #$30
        sta MB+8
        inc seq
        lda seq
        sta MB+$D
        lda #$10
        sta MB                  ; SHOT
        ldy #0                  ; wait for the answer (a few seconds at most)
        ldx #0
-       lda MB+1
        cmp #2
        beq ok
        dex
        bne -
        dey
        bne -
        ldx #0
-       lda m3,x
        sta $0400+24*40,x
        inx
        cpx #40
        bne -
        rts
ok      ldx #0
-       lda m2,x
        sta $0400+23*40,x
        inx
        cpx #40
        bne -
        ldx #0
-       lda m4,x
        sta $0400+24*40,x
        inx
        cpx #40
        bne -
        lda count
        ora #$30
        sta $0400+23*40+26
        rts

name    !pet "SHOT-"
m1      !scr "  space: take a screenshot of this      "
m2      !scr "  saved: screenshots/shot-1.png         "
m4      !scr "  sd card: games/c64/screenshots  (f1)  "
m3      !scr "  no answer from octophonic main        "
phase   !byte 0
rowc    !byte 0
held    !byte 0
count   !byte 0
seq     !byte $80
