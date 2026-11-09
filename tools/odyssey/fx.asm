; (C) 2026 Mong00se
; FX.ASM - the stock show's effects: the scroll text, the equaliser, the
; twinkles, the sparkles, the comet, the sprites (with SHOW.ASM)
; A part of ODYSSEY.ASM (2026: An Octophonic Odyssey), by Mong00se:
; F2 on it builds the whole demo.
!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }
!if odyp = 0 {
        !src "odyssey.asm"
} else {
; =============================================== the scroll text
; In the bitmap's last row (no split screen: a KERNAL load holds the
; interrupt back, so a split would jump about). Each letter twice as
; wide (a multicolour pixel a bit of the letter), colour RAM's
; colour. Every frame the row moves a pixel left (scrshift, below)
; and the letter's next column comes in on the right.
!zone scroll
scroll  jsr scrshift
        lda colbit
        bne .col
.get    ldy #0
        lda (mptr),y
        bne +
        jsr nextmsg
        jmp .get
+       inc mptr
        bne +
        inc mptr+1
+       sta iptr        ; the letter's shape: $5800 + 8 x code
        lda #0
        asl iptr
        rol
        asl iptr
        rol
        asl iptr
        rol
        adc #$58
        sta glyph+1
        lda iptr
        sta glyph
.col    lda glyph       ; its column colbit into the row's right end
        sta iptr
        lda glyph+1
        sta iptr+1
        ldx bank
        lda b_bmp,x
        clc
        adc #$1e
        sta iptr2+1
        lda #$f8        ; bitmap + $1EF8: the last cell (31) of the scroll text in row 24
        sta iptr2
        ldy #7
-       lda (iptr),y
        ldx colbit
        and bitmask,x
        beq +
        lda (iptr2),y
        ora #3
        sta (iptr2),y
+       dey
        bpl -
        lda colbit
        clc
        adc #1
        and #7
        sta colbit
        rts
bitmask !byte $80,$40,$20,$10,$08,$04,$02,$01
; the message after this one. A view's name (queued by the tour in qview) goes in only here, at the end of
; a message - the "..." gap between two sentences - so a sentence always reads whole. After the name the
; message list goes on where it was. The list: each message's end (its 0) and the one that follows it.
!zone nextmsg
nextmsg lda inname
        beq +
        lda #0          ; the name is done: back to the end of the message it came after
        sta inname
        lda msave
        sta mptr
        lda msave+1
        sta mptr+1
        rts
+       lda qview       ; a view's name waits: now
        beq +
        sec
        sbc #1
        asl
        tax
        lda #0
        sta qview
        lda mptr
        sta msave
        lda mptr+1
        sta msave+1
        lda vnames,x
        sta mptr
        lda vnames+1,x
        sta mptr+1
        lda #1
        sta inname
        rts
+       lda mptr+1
        cmp #>MSGBUF
        bne +
        lda #<msg0
        sta mptr
        lda #>msg0
        sta mptr+1
        rts
+       ldx #0          ; which of the list ended?
-       lda msgs,x
        cmp mptr
        bne +
        lda msgs+1,x
        cmp mptr+1
        beq ++
+       inx
        inx
        inx
        inx
        cpx #NMSG*4
        bne -
        ldx #0
        beq +++
++      inx
        inx
+++     lda msgs,x
        sta mptr
        lda msgs+1,x
        sta mptr+1
        rts
NMSG    = 7
!zone msgs
msgs    !word msg0e, msg1, msg1e, msg2, msg2e, msg3, msg3e, msg4
        !word msg4e, msg5, msg5e, msg6, msg6e, MSGBUF
!zone msg0
msg0    !scr "      2026: an octophonic odyssey  -  (c) 2026 mong00se    ...    "
msg0e   !byte 0
msg1    !scr "the cosmic cliffs of the carina nebula, seen by the james webb space telescope    ...    "
msg1e   !byte 0
msg2    !scr "image: nasa, esa, csa, stsci    ...    "
msg2e   !byte 0
msg3    !scr "music: the blue danube, johann strauss ii (1866), arranged by mong00se    ...    "
msg3e   !byte 0
msg4    !scr "every star, sparkle and note is done by the 6502    ...    "
msg4e   !byte 0
msg5    !scr "the pictures are loaded from the disk while you watch, and change with the music    ...    "
msg5e   !byte 0
msg6    !scr "on an octophonic 64 this disk zooms through the cliffs in 256 colours on 8 sids    ...    "
msg6e   !byte 0
!zone vnames
vnames  !word vn0, vn1, vn2, vn3
vn0     !scr "   * the cliff edge *    ...    ", 0
vn1     !scr "   * the western peak *    ...    ", 0
vn2     !scr "   * the golden ridge *    ...    ", 0
vn3     !scr "   * the eastern stars *    ...    ", 0
!zone t_m1
t_m1    !scr "1 sid detected - a stock commodore 64    ...    ", 0
!zone t_m2
t_m2    !scr "2 sids detected - the second at $", 0
!zone t_m2b
t_m2b   !scr ", the music in stereo    ...    ", 0

; the row a multicolour pixel left: 2 x 8 x 40 ROLs (unrolled; the
; addresses are bank 1's, swap turns them to bank 2's and back)
!zone scrshift
scrshift
!for p, 1, 2 {
!for r, 0, 7 {
        clc
!for c, 0, 31 {
        rol $7e00+(31-c)*8+r
}
}
}
        rts

; swap's work for the scroll text: scrshift's addresses to the other
; bank ($7Exx <-> $BExx), and the row copied across
!zone scrswap
scrswap lda #<scrshift
        sta ptr
        lda #>scrshift
        sta ptr+1
        ldx #16         ; 16 runs of: CLC, 32 x ROL abs
.run    inc ptr
        bne +
        inc ptr+1
+       ldy #32
-       sty tmp
        ldy #2
        lda (ptr),y
        eor #$c0
        sta (ptr),y
        clc
        lda ptr
        adc #3
        sta ptr
        bcc +
        inc ptr+1
+       ldy tmp
        dey
        bne -
        dex
        bne .run
        ldx #0          ; the row: from the bank shown to the new one
        lda bank
        bne .b2
-       lda $7e00,x
        sta $be00,x
        lda $7f00,x
        sta $bf00,x
        inx
        bne -
        rts
.b2
-       lda $be00,x
        sta $7e00,x
        lda $bf00,x
        sta $7f00,x
        inx
        bne -
        rts

; ================================================= the equaliser
; A slim meter in the last row of the bitmap, right of the scroll text (cells 32-39): a thin bar a voice
; (3, or 6 with a second SID), 8 lines high, blue at the foot, light blue, then white at the top (the
; three colours a cell has: screen RAM's two nibbles and colour RAM). Drawn into both banks' bitmaps.
!zone eqdraw
eqdraw  lda #3
        ldy #2          ; the first bar's cell - 32
        ldx mode
        beq +
        lda #6
        ldy #1
+       sta eqn
        sty it+1
        ldx #0
.j      stx it
        lda pv_eq,x
        tay
        lda eqh,y       ; the bar's height in lines
        sta iptr
        lda #8
        sec
        sbc iptr
        sta iptr+1      ; its first line from the top
        lda it
        clc
        adc it+1
        asl
        asl
        asl
        tay             ; the cell's 8 bytes
        ldx #0
.l      lda #0
        cpx iptr+1
        bcc +
        lda eqv,x
+       sta $7f00,y
        sta $bf00,y
        iny
        inx
        cpx #8
        bne .l
        ldx it
        inx
        cpx eqn
        bne .j
        rts
!zone eqv
eqv     !byte $3c,$3c,$28,$28,$28,$14,$14,$14
!zone eqh
eqh     !byte 0,0,1,1,2,2,2,3,3,4,4,4,5,5,6,6,6,7,7,8,8

; ================================================== the twinkles
; the view's table: n, then n x (colour RAM lo, hi, its colour)
!zone twinkle
twinkle ldx bank
        lda b_buf,x
        clc
        adc #7          ; the table: buffer + $7D0
        sta iptr+1
        lda #$d0
        sta iptr
        ldy #0
        lda (iptr),y
        beq .x
        sta it+1        ; how many
        ldx #0
.l      lda TWT,x
        bne .on
        jsr random      ; 1 in 96 a frame: a twinkle starts
        cmp #3
        bcs .nx
        lda #16
        sta TWT,x
.on     dec TWT,x
        txa
        sta it
        asl
        adc it
        tay
        iny
        lda (iptr),y
        sta iptr2
        iny
        lda (iptr),y
        sta iptr2+1
        iny
        lda TWT,x       ; the colour: the sequence, or its own at 0
        beq +
        lsr
        tay
        lda twseq,y
        jmp ++
+       lda (iptr),y
++      ldy #0
        sta (iptr2),y
.nx     inx
        cpx it+1
        bne .l
.x      rts
!zone twseq
twseq   !byte 1,15,12,11,12,15,1,7

; fx off: every twinkle back to its own colour, the sparkles and
; the comet away
!zone fxoff
fxoff   lda #3
        sta $d015
        lda mode
        bne +
        lda #1
        sta $d015
+       ldx #23
        lda #0
-       sta TWT,x
        dex
        bpl -
        ldx #63
-       sta SPST,x
        dex
        bpl -
        ldx #7
-       sta spry,x
        dex
        cpx #1
        bne -
        rts

; =================================================== the sparkles
; 5 sprites (2-6); each waits, then flashes on the view's next
; bright star: sizes 0 1 2 3 3 2 1 0, 4 frames each
; SPST: +0 frames left of the flash, +8 frames to wait
!zone sparkle
sparkle ldx bank
        lda b_buf,x
        clc
        adc #8
        sta iptr+1
        lda #$20        ; the sparkle stars: buffer + $7D0 + 80
        sta iptr
        ldx #4
.l      lda SPST,x
        beq .wait
        dec SPST,x
        lda SPST,x
        lsr
        lsr
        tay
        lda spsize,y
        clc
        adc #$22
        sta $43fa,x
        sta $47fa,x
        sta $83fa,x
        sta $87fa,x
        lda SPST,x
        bne .nx
        lda #0          ; finished: off
        sta spry+2,x
        jsr random
        and #63
        adc #20
        sta SPST+8,x
        jmp .nx
.wait   lda SPST+8,x
        beq .new0
        dec SPST+8,x
        jmp .nx
.new0   cpx #0          ; (while loading only sparkle 0)
        beq .new
        lda loading
        bne .nx
.new    ldy #0          ; the next star
        lda (iptr),y
        beq .nx
        sta it
        lda spnext
        cmp it
        bcc +
        lda #0
+       tay
        iny
        sty spnext
        dey
        sty it
        tya
        asl
        adc it
        tay
        iny
        lda (iptr),y
        sta sprx+2,x
        iny
        lda (iptr),y
        sta sprxh+2,x
        iny
        lda (iptr),y
        sta spry+2,x
        lda #32
        sta SPST,x
.nx     dex
        bpl .l
        rts
!zone spsize
spsize  !byte 0,1,2,3,3,2,1,0

; ===================================================== the comet
!zone comet
comet   lda comety
        bne .fly
        lda cometw
        bne +
        dec cometw+1
+       dec cometw
        lda cometw
        ora cometw+1
        bne .x
        lda #<350       ; off it goes, from the top right
        sta cometx
        lda #>350
        sta cometx+1
        jsr random
        and #31
        adc #46
        sta comety
.x      rts
.fly    sec             ; 3 across, 1 down a frame
        lda cometx
        sbc #3
        sta cometx
        lda cometx+1
        sbc #0
        sta cometx+1
        bcc .end
        inc comety
        lda cometx
        sta sprx+7
        lda cometx+1
        sta sprxh+7
        lda comety
        sta spry+7
        cmp #200
        bcc .x
.end    lda #0
        sta comety
        sta spry+7
        jsr random
        sta cometw
        lda #2          ; 512-767 frames to the next
        sta cometw+1
        rts

; =================================== the sprites into the VIC-II
; a sprite with y = 0 is off
!zone sprites
sprites lda #0
        sta it
        sta it+1
        ldx #7
.l      lda sprx,x
        pha
        txa
        asl
        tay
        pla
        sta $d000,y
        lda spry,x
        sta $d001,y
        cmp #1          ; on (y not 0)
        rol it
        lda sprxh,x
        lsr
        rol it+1        ; x bit 8
        dex
        bpl .l
        lda mode        ; (the second equaliser: only with 2 SIDs)
        bne +
        lda it
        and #$fd
        sta it
+       lda it
        sta $d015
        lda it+1
        sta $d010
        rts

; a random number (A), 16-bit Galois LFSR
!zone random
random  lda rnd
        ora rnd+1
        bne +
        lda #$e1
        sta rnd
+       lsr rnd+1
        ror rnd
        bcc +
        lda rnd+1
        eor #$b4
        sta rnd+1
+       lda rnd
        rts
}
