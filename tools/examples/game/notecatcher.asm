; NOTE CATCHER - a small game for the
; Octophonic 64. Catch the falling
; notes with the bar: each one you
; catch plays, on one of the eight
; SIDs, so you make a tune as you go.
; Miss three and it is over.
; Keys: Z left, X right (or a joystick
; in port 2), SPACE / fire to start.
; Run from its disk, it keeps the best
; score on the disk (file HISCORE).
; By Octophonic 64 / Mong00se.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"
        !byte 0,0,0
        jmp start

p       = $fb           ; a pointer
gfx     = $05           ; sprite pictures
table   = $06           ; sprite tables
list    = $020000       ; the sky
notes   = 6             ; falling at once
bary    = 196           ; the bar's line

start   sei
        lda $ba         ; run from drive 8?
        sta drive
        jsr octoon
        jsr palette
        jsr pictures
        jsr sky
        jsr sids
        jsr loadhi
        cli
title   lda #0          ; no notes
        ldx #notes-1
-       sta ny,x
        dex
        bpl -
        jsr screen
        ldx #0
-       lda m_title,x
        beq +
        sta $0400+11*40+5,x
        inx
        bne -
+       ldx #0
-       lda m_keys,x
        beq +
        sta $0400+13*40+5,x
        inx
        bne -
+       jsr score       ; (the best so far)
        lda #0          ; 4 seconds, then
        sta demo        ; it plays itself
        lda #200
        sta t
-       jsr frame       ; wait for SPACE
        jsr fire
        bne +
        dec t
        bne -
        inc demo        ; the demo game
+       jsr newgame
        lda demo
        beq game
        ldx #0
-       lda m_demo,x
        beq game
        sta $0400+2*40+7,x
        inx
        bne -
game    jsr frame
        lda demo        ; demo: SPACE plays
        beq +
        jsr fire
        beq +
        lda #0
        sta demo
        jsr newgame
+       jsr movebar
        jsr fall
        jsr spawn
        jsr score
        lda lives
        bne game
        lda demo        ; (the demo keeps
        bne +           ; no score)
        jsr savehi      ; over: keep a new
+       jsr screen      ; best, then say so
        ldx #0
-       lda m_over,x
        beq +
        sta $0400+11*40+8,x
        inx
        bne -
+       lda #100
        sta t
-       jsr frame
        dec t
        bne -
        jmp title

; ---- one frame: wait for the bottom,
; then show the sprite table just made
frame   jsr place
-       lda $d012
        cmp #250
        bne -
        lda #0
        sta $d613
        lda buf
        sta $d614
        lda #table
        sta $d615
        lda buf
        eor #2
        sta buf
        inc tick
        jsr sidsoff
        rts

; ---- the keys: Z X SPACE (the KERNAL's
; key code in $cb), or the joystick
fire    lda $dc00
        and #16
        beq +
        lda $cb
        cmp #60         ; SPACE
        beq +
        lda #0
        rts
+       lda #1
        rts

movebar lda demo        ; the demo steers to
        bne steer       ; the lowest note
        lda $dc00
        and #4
        beq left
        lda $cb
        cmp #12         ; Z
        beq left
        lda $dc00
        and #8
        beq right
        lda $cb
        cmp #23         ; X
        beq right
        rts
steer   ldx #0
        ldy #$ff        ; Y: the lowest
        lda #0
        sta t
-       lda ny,x
        cmp t
        bcc +
        sta t
        txa
        tay
+       inx
        cpx #notes
        bne -
        cpy #$ff
        beq +++
        lda nx,y        ; bar centre = note
        sec
        sbc #8
        bcs +
        lda #0
+       cmp barx
        beq +++
        bcc left
        sec             ; (not past it)
        sbc barx
        cmp #5
        bcc +++
        jmp right
+++     rts
left    lda barx
        sec
        sbc #5
        bcc +
        sta barx
+       rts
right   lda barx
        clc
        adc #5
        cmp #230
        bcs +
        sta barx
+       rts

; ---- the notes fall; a note on the
; bar is caught, one past it is lost
fall    ldx #0
--      lda ny,x
        beq next        ; 0: not in use
        clc
        adc speed
        sta ny,x
        cmp #bary-12
        bcc next
        cmp #bary+4
        bcs miss
        lda nx,x        ; on the bar?
        sec
        sbc barx
        clc
        adc #14
        cmp #42
        bcs next
        lda #0          ; caught!
        sta ny,x
        jsr play
        inc points
        lda points
        and #7
        bne next
        inc speed       ; faster every 8
        lda speed
        cmp #6
        bcc next
        lda #6
        sta speed
        jmp next
miss    cmp #230
        bcc next
        lda #0          ; gone
        sta ny,x
        dec lives
        jsr buzz
next    inx
        cpx #notes
        bne --
        rts

; ---- a new note now and then
spawn   dec wait
        bne ++
        lda #36
        sec
        sbc speed
        sbc speed
        sbc speed
        sta wait
        ldx #0
-       lda ny,x        ; a free one
        beq +
        inx
        cpx #notes
        bne -
        rts
+       jsr random
        and #127
        sta t
        jsr random
        and #63
        clc
        adc t
        adc #16
        sta nx,x
        lda #8
        sta ny,x
        jsr random
        and #3
        sta nc,x        ; its colour
++      rts

random  lda seed        ; 8-bit LFSR
        asl
        bcc +
        eor #$1d
+       sta seed
        rts

; ---- a caught note: the bar's place
; picks the note, the colour the SID
play    stx t
        lda nx,x
        lsr
        lsr
        lsr
        lsr             ; 0-15
        tay
        lda nc,x
        asl             ; colour*2 (+1 on
        ora tick        ; odd frames) =
        and #7          ; SID 0-7
        tax
        lda sidlo,x
        sta p
        lda sidhi,x
        sta p+1
        tya
        tax
        ldy #0
        lda freqlo,x
        sta (p),y
        iny
        lda freqhi,x
        sta (p),y
        ldy #4
        lda #$11        ; triangle, gate
        sta (p),y
        ldx t
        rts

buzz    lda #$d4        ; SID 1: a low
        sta p+1         ; noise
        lda #0
        sta p
        ldy #1
        lda #4
        sta (p),y
        ldy #4
        lda #$81
        sta (p),y
        rts

; every 8 frames the gates go off
sidsoff lda tick
        and #7
        bne +
        ldx #7
-       lda sidlo,x
        sta p
        lda sidhi,x
        sta p+1
        ldy #4
        lda #$10        ; gate off
        sta (p),y
        dex
        bpl -
+       rts

; ---- the eight SIDs: loud, a plucked
; note on voice 1
sids    ldx #7
-       lda sidlo,x
        sta p
        lda sidhi,x
        sta p+1
        ldy #$18
        lda #15
        sta (p),y
        ldy #5
        lda #$0a        ; attack 0 decay 10
        sta (p),y
        ldy #6
        lda #$00
        sta (p),y
        dex
        bpl -
        rts
sidlo   !byte $00,$20,$00,$20,$80,$a0,$80,$a0
sidhi   !byte $d4,$d4,$d5,$d5,$d4,$d4,$d5,$d5

newgame lda #3
        sta lives
        lda #0
        sta points
        ldx #notes-1
-       sta ny,x
        dex
        bpl -
        lda #2
        sta speed
        lda #20
        sta wait
        lda #110
        sta barx
        jsr screen
        rts

; ---- the score line (screen codes)
score   ldx #0
-       lda m_score,x
        sta $0400,x
        inx
        cpx #40
        bne -
        lda points
        ldx #7
        jsr number
        lda best
        ldx #17
        jsr number
        lda lives
        ora #$30
        sta $0400+28
        rts
; A as 3 digits at $0400+X
number  ldy #$2f
        sec
-       iny
        sbc #100
        bcs -
        adc #100
        pha
        tya
        sta $0400,x
        pla
        ldy #$2f
        sec
-       iny
        sbc #10
        bcs -
        adc #10+$30
        sta $0400+2,x
        tya
        sta $0400+1,x
        lda demo        ; (not in the demo)
        bne +
        lda points
        cmp best
        bcc +
        sta best
+       rts

m_score !scr " score 000  best 000  lives 3            "
m_title !scr "n o t e   c a t c h e r", 0
m_keys  !scr "z x move, space to start", 0
m_over  !scr "game over - well played", 0
m_demo  !scr "demo - space to play", 0

; ---- the best score on the disk
loadhi  lda drive
        cmp #8
        bne ++
        lda #7
        ldx #<f_read
        ldy #>f_read
        jsr $ffbd       ; SETNAM
        lda #2
        ldx #8
        ldy #2
        jsr $ffba       ; SETLFS
        jsr $ffc0       ; OPEN
        bcs +
        ldx #2
        jsr $ffc6       ; CHKIN
        bcs +
        jsr $ffcf       ; CHRIN
        tax
        jsr $ffb7       ; READST
        bne +
        stx best
+       lda #2
        jsr $ffc3       ; CLOSE
        jsr $ffcc       ; CLRCHN
++      rts
savehi  lda drive
        cmp #8
        bne ++
        lda points
        cmp best
        bcc ++
        beq ++
        sta best
        lda #13
        ldx #<f_write
        ldy #>f_write
        jsr $ffbd
        lda #2
        ldx #8
        ldy #2
        jsr $ffba
        jsr $ffc0
        bcs +
        ldx #2
        jsr $ffc9       ; CHKOUT
        bcs +
        lda best
        jsr $ffd2
+       lda #2
        jsr $ffc3
        jsr $ffcc
++      rts
f_read  !pet "hiscore"
f_write !pet "@0:hiscore,s,w"

; ---- black screen
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
        rts

; ---- OctoVIC on
octoon  lda #$4f
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
        lda #0
        sta $d616
        sta $d617
        lda #gfx
        sta $d618
        lda #notes+1
        sta $d60f
        lda #1
        sta $d603
        rts

; palette: 4 note colours x 16 shades,
; the bar in 64-79
palette lda #0
        sta $d619
        sta $d651
        sta $d653
        ldx #0
-       txa
        and #15
        sta t
        asl
        asl
        asl
        asl
        ora t
        sta $d652
        txa
        lsr
        lsr
        lsr
        lsr
        sta t
        asl
        adc t
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
        cpx #80
        bne -
        rts
cols    !byte 255,90,70, 90,220,255, 255,220,70
        !byte 170,255,100, 255,255,255

; the pictures: 4 balls (256 bytes each)
; then the bar (32x8, 256 bytes)
pictures
        lda #0
        sta $d600
        sta $d601
        lda #gfx
        sta $d602
        ldx #0
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
        ldy #0          ; the bar: shaded
-       tya             ; top to bottom
        lsr
        lsr
        lsr
        lsr
        lsr             ; row 0-7
        tax
        lda barsh,x
        sta $d604
        iny
        bne -
        rts
barsh   !byte 79,78,76,74,72,70,68,66

; ---- the sprite table (two, in turn)
place   lda #0
        sta $d600
        lda buf
        sta $d601
        lda #table
        sta $d602
        lda barx        ; sprite 0: the bar
        clc
        adc #40
        sta $d604
        lda #0
        adc #0
        sta $d604
        lda #bary
        sta $d604
        lda #0
        sta $d604
        lda #32         ; picture 32
        sta $d604
        lda #0
        sta $d604
        lda #$c2        ; on, 256, 32x8
        sta $d604
        lda #0
        sta $d604
        ldx #0          ; the notes
-       lda nx,x
        clc
        adc #48
        sta $d604
        lda #0
        adc #0
        sta $d604
        lda ny,x
        sta $d604
        lda #0
        sta $d604
        lda nc,x
        asl
        asl
        asl
        sta $d604
        lda #0
        sta $d604
        lda ny,x        ; on if in use
        beq +
        lda #$c5
+       sta $d604
        lda #0
        sta $d604
        inx
        cpx #notes
        bne -
        rts

; ---- the sky (as PARALLAX.ASM)
sky     lda #2
        sta $d619
        lda #<list
        sta $d600
        lda #>list
        sta $d601
        lda #^list
        sta $d602
        lda #16
        sta ln
-       lda ln          ; dusk: red t/2,
        sec             ; green t/4, blue
        sbc #16         ; 90-t (t 0-117)
        lsr
        sta t
        lsr
        sta rgb+1       ; red
        lsr
        sta rgb+2       ; green
        lda #90
        sec
        sbc t
        bcs +
        lda #0
+       sta rgb+3       ; blue
        lda #0
        sta rgb         ; (PALIDX 0)
        ldx #0
--      lda ln
        sta $d604
        lda #0
        sta $d604
        lda reg,x
        sta $d604
        lda rgb,x
        sta $d604
        inx
        cpx #4
        bne --
        inc ln
        lda ln
        cmp #250
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
freqlo  !byte 103,137,237,19,69,206,17,218,38,137,157,35,181,77,19,57
freqhi  !byte 17,19,21,26,29,34,39,43,52,58,69,78,87,104,117,139

drive   !byte 0
demo    !byte 0
buf     !byte 0
tick    !byte 0
barx    !byte 110
lives   !byte 0
points  !byte 0
best    !byte 0
speed   !byte 2
wait    !byte 20
seed    !byte $5a
t       !byte 0
ln      !byte 0
rgb     !byte 0,0,0,0
nx      !fill notes,0
ny      !fill notes,0
nc      !fill notes,0
