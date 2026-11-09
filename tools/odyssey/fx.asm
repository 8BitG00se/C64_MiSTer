; (C) 2026 Mong00se
; FX.ASM - the stock show's effects: the scroll text, the equaliser, the
; twinkles, the glints, the sprites (with SHOW.ASM)
; A part of ODYSSEY.ASM (2026: An Octophonic Odyssey), by Mong00se:
; F2 on it builds the whole demo.
!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }
!if odyp = 0 {
        !src "odyssey.asm"
} else {

; =============================================== the scroll text
; The screen's last row is a text row (the interrupt at line 238 turns
; it on, under the galaxy): bank 1's text screen $4400 (row 24 at
; $47C0), our letters at $5800, a pixel a frame with the fine scroll,
; columns 0-33 (34-39: the equaliser). Colour RAM fades it at the ends.
TROW    = $47c0
!zone scroll
scroll  dec xscr
        bpl .x
        lda #7
        sta xscr
        ldx #0
-       lda TROW+1,x
        sta TROW,x
        inx
        cpx #33
        bne -
.get    ldy #0
        lda (mptr),y
        bne +
        jsr nextmsg
        jmp .get
+       sta TROW+33
        inc mptr
        bne .x
        inc mptr+1
.x      rts
xscr    !byte 7

; the message after this one (the list: each message's end and the one that follows it)
!zone nextmsg
nextmsg lda mptr+1
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
msg1    !scr "a spiral galaxy like andromeda, tilted 60 degrees: a bright core, two arms with dark dust lanes, blue clusters in the outer arms and a soft halo    ...    "
msg1e   !byte 0
msg2    !scr "its two small companions keep it company, and the stars of our own galaxy twinkle in front    ...    "
msg2e   !byte 0
msg3    !scr "music: the blue danube, johann strauss ii (1866), arranged by mong00se    ...    "
msg3e   !byte 0
msg4    !scr "the 6502 draws the galaxy anew as it turns, half a turn a song, and moves the stars in its arms: the ones near the core go round faster, so the arms wind    ...    "
msg4e   !byte 0
msg5    !scr "nothing here is a photo: every pixel, star and note is made by formulas and done by the 6502    ...    "
msg5e   !byte 0
msg6    !scr "on an octophonic 64 this disk zooms through the cosmic cliffs in 256 colours on 8 sids    ...    "
msg6e   !byte 0
!zone t_m1
t_m1    !scr "1 sid detected - a stock commodore 64    ...    ", 0
!zone t_m2
t_m2    !scr "2 sids detected - the second at $", 0
!zone t_m2b
t_m2b   !scr ", the music in stereo    ...    ", 0

; ================================================= the equaliser
; Sprite 7 at the bottom right (lines 243-250: its rows 13-20): a bar a
; voice, 3 pixels wide, as high as the voice is loud (0-8 lines).
EQS     = $4800         ; its graphics (bank 1: the text row is bank 1's)
!zone eqdraw
eqdraw  lda #0
        ldx #23
-       sta EQS+39,x
        dex
        bpl -
        ldx #0
.j      stx eqi
        lda pv_eq,x
        tay
        lda eqh,y       ; the bar's height
        beq .nx
        tay
        lda mode
        beq +
        lda eqb6,x      ; 6 bars: 2 a byte
        sta it
        lda eqm6,x
        jmp ++
+       stx it          ; 3 bars: one a byte
        lda #$38
++      sta it+1
        lda it
        clc
        adc #60         ; row 20's byte
        sta iptr
-       ldx iptr
        lda EQS,x
        ora it+1
        sta EQS,x
        lda iptr
        sec
        sbc #3
        sta iptr
        dey
        bne -
.nx     ldx eqi
        inx
        cpx eqn
        bne .j
        rts
eqi     !byte 0
!zone eqh
eqh     !byte 0,0,1,1,2,2,2,3,3,4,4,4,5,5,6,6,6,7,7,8,8
eqb6    !byte 0,0,1,1,2,2
eqm6    !byte $e0,$0e,$e0,$0e,$e0,$0e

; ================================================== the twinkles
; TWTAB: n, then n x (screen offset lo, hi, its colour); a twinkle runs
; a star's cell through the twinkle colours (in both screens)
!zone twinkle
twinkle lda TWTAB
        beq .x
        sta it+1
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
        lda TWTAB+1,y
        sta iptr
        lda TWTAB+2,y
        ora #$40
        sta iptr+1
        lda TWT,x       ; the colour: the sequence, or its own at 0
        beq +
        lsr
        tay
        lda twseq,y
        jmp ++
+       lda TWTAB+3,y
++      asl
        asl
        asl
        asl
        ldy #0
        sta (iptr),y
        pha
        lda iptr+1
        eor #$c0        ; $40xx -> $80xx
        sta iptr+1
        pla
        sta (iptr),y
.nx     inx
        cpx it+1
        bne .l
.x      rts
!zone twseq
twseq   !byte 1,15,12,11,12,15,1,7

; =================================================== the glints
; 3 glints, each 2 sprites (0+1, 2+3, 4+5: the white middle over the
; light blue spikes); each waits, then flashes on the next bright star of
; GLTAB (n, then n x (x lo, x hi, y)): 4 sizes up and down, 3 frames each.
; SPST: +0 frames left of the flash, +8 frames to wait
!zone sparkle
sparkle ldx #2
.l      lda SPST,x
        beq .wait
        dec SPST,x
        lda SPST,x
        lsr
        lsr
        tay
        lda spsize,y
        asl
        clc
        adc #$22        ; the white middle; the spikes are the next one
        ldy glspr,x
        sta $43f8,y
        sta $47f8,y
        sta $83f8,y
        adc #1
        sta $43f9,y
        sta $47f9,y
        sta $83f9,y
        lda SPST,x
        bne .nx
        ldy glspr,x     ; finished: off
        lda #0
        sta spry,y
        sta spry+1,y
        jsr random
        and #63
        adc #30
        sta SPST+8,x
        jmp .nx
.wait   lda SPST+8,x
        beq .new
        dec SPST+8,x
.nxj    jmp .nx
.new    lda GLTAB       ; the next star
        beq .nxj
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
        stx it
        lda glspr,x
        tax
        lda GLTAB+1,y
        sta sprx,x
        sta sprx+1,x
        lda GLTAB+2,y
        sta sprxh,x
        sta sprxh+1,x
        lda GLTAB+3,y
        sta spry,x
        sta spry+1,x
        ldx it
        lda #32
        sta SPST,x
.nx     dex
        bmi +
        jmp .l
+       rts
!zone spsize
spsize  !byte 0,1,2,3,3,2,1,0
glspr   !byte 0,2,4

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
        lda it
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
