; (C) 2026 Mong00se
; SHOW.ASM - the stock C64 / 2-SID show of ODYSSEY.ASM, by Mong00se.
; An Andromeda-style spiral galaxy of our own (GALAXY on the disk, made
; by GALAXY.PY - no photo), loaded behind the loading screen, which
; goes straight into it on the beat. The 6502 turns the galaxy and
; draws it anew, moves its live stars (GALAXY.ASM), twinkles the stars
; behind it, flashes glints on the brightest, scrolls the text and
; shows the equaliser (FX.ASM). All of it is done here, by the 6502.
!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }
!if odyp = 0 {
        !src "odyssey.asm"
} else {

; VIC bank 1 ($4000): screen $4000, the text screen $4400 (the loading
; screen; then the last row's), sprites $4800, letters $5800, bitmap
; $6000. Bank 2 ($8000): screen $8000, sprites $8800, bitmap $A000.
; GALAXY.ASM lists the rest.
SPST    = $cb00         ; the sparkles' state
TWT     = $cb40         ; the twinkles' timers (30)
MSGBUF  = $cd00         ; the scroll text's "detected" line

; zero page for the galaxy (GALAXY.ASM)
front   = $60           ; the bitmap shown (0: $6000, 1: $A000)
flipat  = $61           ; the frame it may swap at
flipreq = $62           ; 1: swap at the top of the next frame
alpha   = $63           ; 2: the galaxy's angle (65536 a turn)
flipped = $65           ; 1: swapped (the drawing stops for the stars)
p1      = $66           ; 2: SQH + r
p3      = $68           ; 2: NSQH + 255 - r
pp      = $6a           ; 2: the star's byte
th      = $6c
rlo2    = $6d
mk      = $6e
xm      = $6f
rth     = $70
ringk   = $71
rend    = $72
nst0    = $73           ; the stars plotted in $6000, in $A000
nst1    = $74
rr      = $75           ; the next star to check against its arm
tp      = $76           ; 2: the texture's line
ufr     = $78
vfr     = $79
ry      = $7a           ; the line being drawn
rcnt    = $7b           ; its bytes still to draw
c8x     = $7c           ; the byte's offset (+8 a byte)
rstate  = $7d           ; 0 a new quarter, 1 the next line, 2 in a line
ysave   = $7e
rk      = $7f           ; the quarter (lines k, k+4, ...)
ra      = $80           ; its angle
rc8     = $81           ; cos, sin x 127
rs8     = $82
m1      = $83           ; smul: m1 x m2 -> res
m2      = $84
res     = $85           ; 2
acc     = $87           ; 2
nquar   = $89           ; quarters drawn
sgn     = $8a
alphaf  = $8b           ; the angle's fraction
nflip   = $c4f0         ; 2: the swaps (to count the frame rate)
nfr     = $c4f2         ; 2: the frames since the show began


; zero page (the show's own)
bank    = $1a           ; the bank shown: 0 ($4000) or 1 ($8000)
view    = $1b           ; the view shown
nview   = $1c           ; the view loading
fxon    = $1d           ; 1: twinkles, sparkles, comet
mptr    = $20           ; 2: the scroll text
qview   = $22           ; a view's name to scroll next (+1)
vtime   = $23           ; 2: frames this view has been shown
irisr   = $25           ; the iris: its radius (x2)
trans   = $26           ; counts the changes (iris / fade)
lvn     = $27           ; loading: the view
lvb     = $28           ; loading: the bank
spnext  = $29           ; the next sparkle star
cometx  = $2a           ; 2
comety  = $2c
cometw  = $2d           ; 2: frames to the next comet
inname  = $2f
iptr    = $30           ; 2: the interrupt's
iptr2   = $32           ; 2
it      = $34           ; 2
sprx    = $38           ; 8: sprites' x (lo)
sprxh   = $40           ; 8: x bit 8
spry    = $48           ; 8
r2      = $50           ; 2: the iris: radius squared
dy2     = $52           ; 2
msave   = $54           ; 2
loading = $56
colbit  = $57
glyph   = $58           ; 2
lvw     = $5a
lverr   = $5b           ; loading: the drive failed
lvpage  = $5c           ; loading: pages of the view unpacked so far (the bar)
lvdr    = $5d           ; the bar: cells drawn
eqn     = $5e           ; the equaliser: bars
LST     = $cf00         ; the loading screen's stars: offset lo, hi, timers (72 each)

TIMING  = 0             ; 1: the border shows the time the stars take (red)

!zone b_dd00
b_dd00  !byte 2, 1        ; $DD00's bank bits: $4000, $8000

; ======================================================== the show
!zone show
show    lda #<irq_t     ; the title's interrupt: the music only
        sta $0314
        lda #>irq_t
        sta $0315
        lda #3
        ldx mode
        beq +
        lda #6
+       sta eqn
        jsr pl_init
        jsr mkmsg
        jsr irqon
        lda #0
        sta spnext
        jsr setup       ; letters, sprites, black screens
        jsr loadscr     ; the loading screen: stars, the title, the equaliser, a bar
-       jsr loadgal     ; the galaxy, its tables, the glints
        bcc +
        ldx #<t_disk
        ldy #>t_disk
        lda #7
        jsr print2
        jmp -
+       lda #81         ; the bar full
        sta lvpage
        ldx #<t_ready
        ldy #>t_ready
        lda #1
        jsr print2
        jsr galinit     ; the screens, the stars, the whole galaxy drawn once
-       jsr atcut       ; the galaxy comes up on the music's next phrase
        bcc -
        jsr showon
; the stars a step on in the bitmap not shown, then swap at the top of a frame,
; 2 frames after the last swap; the galaxy is drawn on until it has swapped
!zone galloop
galloop !if TIMING { lda $d012
        sta $c4f6
        lda $d011
        sta $c4f7
        lda nfr
        sta $c4f8 }
        lda front
        bne +
        !if TIMING { lda #2
        sta $d020 }
        jsr serase1
        jsr rings
        jsr respawn
        jsr splot1
        jmp ++
+       !if TIMING { lda #2
        sta $d020 }
        jsr serase0
        jsr rings
        jsr respawn
        jsr splot0
++      !if TIMING { lda #0
        sta $d020
        lda $d012
        sta $c4f9
        lda $d011
        sta $c4fa
        lda nfr
        sta $c4fb }
        lda #0
        sta flipped
        lda #1
        sta flipreq
        jsr render
        jmp galloop

; ================================================= loading the galaxy
; GALAXY on the disk: 2 bytes, then pieces: where (2), how long (2), packed (STOCKPIC.PY's pack());
; where = 0 ends. Carry set: it failed
!zone loadgal
loadgal sei
        lda #0
        sta lvpage
        sta lverr
        sta lvdr
        cli
        lda #6
        ldx #<gname
        ldy #>gname
        jsr SETNAM
        lda #2
        ldx $ba         ; the drive it was loaded from (8 if none)
        cpx #8
        bcs +
        ldx #8
+       ldy #2
        jsr SETLFS
        jsr OPEN
        bcs .err
        ldx #2
        jsr CHKIN
        bcs .err
        jsr getb        ; (its two address bytes)
        jsr getb
        lda lverr
        bne .err
.seg    jsr getb
        sta ptr
        jsr getb
        sta ptr+1
        beq .ok
        jsr getb
        pha
        jsr getb
        tax
        pla
        jsr unpack
        bcs .err
        jmp .seg
.ok     jsr CLRCHN
        lda #2
        jsr CLOSE
        clc
        rts
.err    jsr CLRCHN
        lda #2
        jsr CLOSE
        sec
        rts
!zone gname
gname   !pet "galaxy"

; A/X bytes unpacked to (ptr) (the packing: STOCKPIC.PY, pack()): a token $00-$7F is
; a run of token+1 bytes to copy; $80-$BF copies (token & $3F) + 2 bytes from a distance
; (the next byte, 1-255) back; $C0-$FF the same with a 16 bit distance (lo, hi). It is
; unpacked as it comes off the drive, so there is no second buffer. Carry set: failed.
!zone unpack
unpack  sta cnt
        stx cnt+1
.next   lda cnt
        ora cnt+1
        beq .ok
        jsr getb
        sta tmp
        bmi .match
        sta tmp+1
.lit    jsr getb
        ldy #0
        sta (ptr),y
        jsr .adv
        bcs .ok
        dec tmp+1
        bpl .lit
        bmi .chk
.match  and #$3f
        clc
        adc #2
        sta tmp+1
        jsr getb
        sta tmp+2
        lda #0
        sta tmp+3
        lda tmp
        and #$40
        beq +
        jsr getb
        sta tmp+3
+       sec
        lda ptr
        sbc tmp+2
        sta ptr3
        lda ptr+1
        sbc tmp+3
        sta ptr3+1
.cp     ldy #0
        lda (ptr3),y
        sta (ptr),y
        inc ptr3
        bne +
        inc ptr3+1
+       jsr .adv
        bcs .ok
        dec tmp+1
        bne .cp
.chk    lda lverr
        beq .next
        sec
        rts
.ok     lda lverr
        cmp #1          ; carry set if the drive failed
        rts
; one byte out: ptr up, cnt down; carry set when all are done
.adv    inc ptr
        bne +
        inc ptr+1
        inc lvpage
+       lda cnt
        bne +
        dec cnt+1
+       dec cnt
        lda cnt
        ora cnt+1
        beq +
        clc
        rts
+       sec
        rts
; the next byte of the file (A); a failed drive is remembered in lverr
!zone getb
getb    lda lverr
        bne .z
        jsr drready
        jsr CHRIN
        pha
        jsr READST
        and #$83        ; (the end of the file, $40, is fine on the last byte)
        beq +
        sta lverr
+       pla
        rts
.z      lda #0
        rts
; wait (the interrupt running) until the drive is ready to send: it
; lets go of the CLK line. The KERNAL's CHRIN waits for this with the
; interrupt held off - for a whole directory search or the next
; sector that would stop the music. (At most 4 seconds.)
drready lda frame
        sta lvw
-       bit $dd00       ; bit 6: CLK in
        bvs +
        lda frame
        sec
        sbc lvw
        cmp #200
        bcc -
+       rts

; ===================================================== the phrases
; The pictures change on the music's phrases (8 bars), a little early so the new one is
; in on the beat. phtab: the song frames (mfr) at which a change starts: the phrases
; begin at frame 549 (the end of the introduction), 240 frames (4 bars) apart; scaled
; to SONGLEN if the song's length changes (song.asm).
PHN     = 16
PHLEAD  = 0
!zone atcut
atcut   ldx #0
.l      lda mfr
        sec
        sbc phtab,x
        sta tmp
        lda mfr+1
        sbc phtab+1,x
        bcc .n
        bne .n
        lda tmp
        cmp #16         ; in the first 16 frames of the window
        bcc .y
.n      inx
        inx
        cpx #PHN*2
        bne .l
        clc
        rts
.y      sec
        rts
!zone phtab
phtab   !for k, 0, PHN-1 { !word ((549 + 240*k) * songlen / 4816) - PHLEAD }

; ============================================== the loading screen
; Text mode in bank 1 (screen $4400, the letters at $5800 with a few of our own: star glints, the bar's
; pieces), the whole screen: a starfield (many faint stars, 16 bright ones that twinkle - a glint that
; grows and fades), the title block in the middle with a light running through the title, a bar
; that fills as the picture comes off the disk, and below it the equaliser (a bar a voice, built of
; block characters in a colour ramp).
!zone loadscr
loadscr sei
        ldx #0          ; colour RAM black
        lda #0
-       sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne -
        sta lvdr
        ldx #127        ; our own characters 64-79
-       lda glyphs,x
        sta $5a00,x
        dex
        bpl -
        ldx #0          ; 72 stars: not in the middle (rows 3-21, columns 5-34: the text)
.st     jsr random
        and #31
        cmp #24
        bcs .st
        sta tmp
        jsr random
        and #63
        cmp #40
        bcs .st
        sta tmp+1
        lda tmp         ; the text (rows 3-14, columns 5-34) and the equaliser (rows 15-21, 10-29) stay clear
        cmp #3
        bcc .ok
        cmp #15
        bcs .eqr
        lda tmp+1
        cmp #5
        bcc .ok
        cmp #35
        bcc .st
        bcs .ok
.eqr    cmp #22
        bcs .ok
        lda tmp+1
        cmp #10
        bcc .ok
        cmp #30
        bcc .st
.ok     ldy tmp
        lda tmp+1
        clc
        adc rowlo,y
        sta LST,x
        lda rowhi,y
        adc #0
        sta LST+72,x
        lda #0
        sta LST+144,x
        stx tmp+2
        jsr ltwput
        ldx tmp+2
        inx
        cpx #72
        bne .st
        ldx #29         ; the bar's track (row 13, columns 5-34)
        lda #68
-       sta $4400+13*40+5,x
        dex
        bpl -
        ldx #29
        lda #11
-       sta $d800+13*40+5,x
        dex
        bpl -
        ldx #16         ; the equaliser's colours (rows 16-20, white at the top, blue at the foot)
.er     lda rowlo,x
        sta ptr3
        lda rowhi,x
        clc
        adc #$d8
        sta ptr3+1
        lda eqramp-16,x
        ldy #8
-       sta (ptr3),y
        iny
        cpy #32
        bne -
        inx
        cpx #21
        bne .er
        lda $dd00       ; bank 1, the text screen
        and #$fc
        ora #2
        sta $dd00
        lda #$16
        sta $d018
        lda #$08
        sta $d016
        lda #$1b
        sta $d011
        lda #0
        sta $d020
        sta $d021
        lda #$7c        ; the glint sprites (the show's): multicolour, light blue and cyan spikes
        sta $d01c
        lda #14
        sta $d025
        lda #3
        sta $d026
        ldx #<t_title
        ldy #>t_title
        lda #6
        jsr print2
        ldx #<t_copy
        ldy #>t_copy
        lda #12
        jsr print2
        ldx #<t_1sid
        ldy #>t_1sid
        lda mode
        beq +
        ldx #<t_2sid
        ldy #>t_2sid
+       lda #14
        jsr print2
        ldx #<t_load
        ldy #>t_load
        lda #12
        jsr print2
        lda #<irq_l
        sta $0314
        lda #>irq_l
        sta $0315
        cli
        rts
!zone eqramp
eqramp  !byte 1,3,14,14,6
; our characters: star glints 64-67 (a dot, a cross, a bigger cross, a bright 8-point), the bar's track
; 68 and fill 69, 72-79 a block 1-8 lines high from the foot
!zone glyphs
glyphs  !byte $00,$00,$00,$18,$00,$00,$00,$00
        !byte $00,$00,$18,$3c,$3c,$18,$00,$00
        !byte $00,$18,$18,$7e,$7e,$18,$18,$00
        !byte $18,$5a,$3c,$ff,$ff,$3c,$5a,$18
        !byte $00,$00,$00,$ff,$ff,$00,$00,$00
        !byte $00,$ff,$ff,$ff,$ff,$ff,$ff,$00
        !fill 16, 0
        !byte $00,$00,$00,$00,$00,$00,$00,$ff
        !byte $00,$00,$00,$00,$00,$00,$ff,$ff
        !byte $00,$00,$00,$00,$00,$ff,$ff,$ff
        !byte $00,$00,$00,$00,$ff,$ff,$ff,$ff
        !byte $00,$00,$00,$ff,$ff,$ff,$ff,$ff
        !byte $00,$00,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $00,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
; star X at its state: the glint's character and colour from its timer (LST+144,x); the faint ones stay dots
!zone ltwput
ltwput  lda LST,x
        sta iptr
        sta iptr2
        lda LST+72,x
        clc
        adc #$44
        sta iptr+1
        lda LST+72,x
        adc #$d8
        sta iptr2+1
        cpx #16
        bcs .faint
        lda LST+144,x
        lsr
        tay
        lda lwc,y
        pha
        lda lwch,y
        ldy #0
        sta (iptr),y
        pla
        sta (iptr2),y
        rts
.faint  txa
        and #3
        tay
        lda faintc,y
        pha
        lda #64
        ldy #0
        sta (iptr),y
        pla
        sta (iptr2),y
        rts
!zone lwch
lwch    !byte 64,65,66,67,67,66,65,64
!zone lwc
lwc     !byte 12,15,1,1,1,1,15,12
!zone faintc
faintc  !byte 11,6,12,11
; the twinkles: now and then a bright star starts, all that are going go on
!zone ltw
ltw     jsr random
        and #63
        cmp #16
        bcs .go
        tax
        lda LST+144,x
        bne .go
        lda #16
        sta LST+144,x
.go     ldx #15
.l      lda LST+144,x
        beq .nx
        dec LST+144,x
        stx it+1
        jsr ltwput
        ldx it+1
.nx     dex
        bpl .l
        rts
; the title's shine: its colours run along a ramp
!zone lshine
lshine  lda frame
        lsr
        sta it
        ldx #0
.l      txa
        clc
        adc it
        and #15
        tay
        lda shw,y
        sta $d800+4*40+6,x
        inx
        cpx #27
        bne .l
        rts
!zone shw
shw     !byte 6,6,14,14,3,3,1,1,3,3,14,14,6,6,6,6
; the bar: a cell for each pages of the galaxy unpacked (30 cells for its 81 pages: 3/8 a page)
!zone lbar
lbar    ldx lvdr
.l      lda lvpage
        lsr
        lsr
        sta it
        lsr
        clc
        adc it
        sta it
        cpx it
        bcs .x
        cpx #30
        bcs .x
        lda #69
        sta $4400+13*40+5,x
        txa
        lsr
        lsr
        lsr
        tay
        lda barc,y
        sta $d800+13*40+5,x
        inx
        stx lvdr
        jmp .l
.x      rts
!zone barc
barc    !byte 6,14,3,1
; the equaliser (rows 16-20): a bar a voice, 2 characters wide, centred
!zone eqtxt
eqtxt   lda #3
        ldy #16
        ldx mode
        beq +
        lda #6
        ldy #11
+       sta eqn
        sty it+1
        ldx #0
.j      stx glyph
        lda pv_eq,x
        asl
        sta glyph+1     ; its height in 1/8 characters
        lda glyph
        asl
        clc
        adc glyph
        adc it+1
        sta it          ; its column
        ldy #0
.r      sty iptr2       ; the row's number from the foot
        lda #20
        sec
        sbc iptr2
        tax
        lda rowlo,x
        clc
        adc it
        sta iptr
        lda rowhi,x
        adc #$44
        sta iptr+1
        lda iptr2
        asl
        asl
        asl
        sta iptr2+1
        lda glyph+1
        sec
        sbc iptr2+1
        bcc .e
        beq .e
        cmp #8
        bcc +
        lda #8
+       clc
        adc #71
        bne .w
.e      lda #32
.w      ldy #0
        sta (iptr),y
        iny
        sta (iptr),y
        ldy iptr2
        iny
        cpy #5
        bne .r
        ldx glyph
        inx
        cpx eqn
        bne .j
        rts

; print the text at X/Y (row, column, the letters, 0 ends) in colour A on the text screen at $4400
!zone print2
print2  stx ptr2
        sty ptr2+1
        sta tmp+3
        ldy #0
        lda (ptr2),y
        tax
        lda rowlo,x
        sta ptr
        sta ptr3
        lda rowhi,x
        clc
        adc #$44
        sta ptr+1
        lda rowhi,x
        adc #$d8
        sta ptr3+1
        iny
        lda (ptr2),y
        clc
        adc ptr
        sta ptr
        sta ptr3
        bcc +
        inc ptr+1
        inc ptr3+1
+       lda ptr2
        clc
        adc #2
        sta ptr2
        bcc +
        inc ptr2+1
+       ldy #0
-       lda (ptr2),y
        beq +
        sta (ptr),y
        lda tmp+3
        sta (ptr3),y
        iny
        bne -
+       rts

; ==================================================== the interrupts
!zone irqon
irqon   sei
        lda #$fc
        sta $d012
        lda $d011
        and #$7f
        sta $d011
        lda #1
        sta $d01a
        sta $d019
        cli
        rts

; the music only (while the screens are set up)
!zone irq_t
irq_t   lda $d019
        sta $d019
        inc frame
        jsr pl_play
        jmp irqret

; the loading screen's: the music, the equaliser, the twinkling stars, the title's shine, the bar
!zone irq_l
irq_l   lda $d019
        sta $d019
        inc frame
        jsr pl_play
        jsr eqtxt
        jsr ltw
        jsr lshine
        jsr lbar
        jmp irqret

; the show's, at the top (line 16): the bitmap shown (swapped if one is ready), hires
!zone irq_top
irq_top lda $d019
        sta $d019
        lda flipreq
        beq +
        lda frame
        sec
        sbc flipat
        bmi +
        lda front
        eor #1
        sta front
        lda #0
        sta flipreq
        lda #1
        sta flipped
        inc nflip
        bne +++
        inc nflip+1
+++     lda frame
        clc
        adc #2
        sta flipat
+       ldx front
        lda $dd00
        and #$fc
        ora b_dd00,x
        sta $dd00
        lda #$3b
        sta $d011
        lda #$08
        sta $d018
        sta $d016
        lda alphaf      ; the galaxy turns
        sec
        sbc #<DALPHA
        sta alphaf
        lda alpha
        sbc #>DALPHA
        sta alpha
        lda alpha+1
        sbc #DALPHA >> 16
        sta alpha+1
        lda #<irq_bot
        sta $0314
        lda #>irq_bot
        sta $0315
        lda #238
        sta $d012
        jmp irqret

; and at line 238: the last row a text row of bank 1 (the scroll text), the music, the effects
!zone irq_bot
irq_bot lda $d019
        sta $d019
        lda $dd00
        and #$fc
        ora #2
        sta $dd00
        lda #$1b
        sta $d011
        lda #$16
        sta $d018
        lda xscr
        ora #8
        sta $d016
        lda #<irq_top   ; the top's interrupt may come in while this one still runs
        sta $0314
        lda #>irq_top
        sta $0315
        lda #16
        sta $d012
        cli
        !if TIMING { lda #6
        sta $d020 }
        inc nfr
        bne +
        inc nfr+1
+       inc frame
        jsr pl_play
        jsr scroll
        jsr eqdraw
        jsr twinkle
        jsr sparkle
        jsr sprites
        !if TIMING { lda #0
        sta $d020
        lda $d012
        sta $c4f4
        lda $d011
        sta $c4f5 }
        jmp irqret
; the end of an interrupt (the KERNAL's, for when it is switched off)
!zone irqret
irqret  pla
        tay
        pla
        tax
        pla
nmirti  rti
; the way in with the KERNAL off ($FFFE)
!zone irqin
irqin   pha
        txa
        pha
        tya
        pha
        jmp ($0314)

; the galaxy ready behind the loading screen: the screens, the bitmaps, the KERNAL off
; (the texture is under it), the stars, the galaxy drawn whole once, the stars in both
!zone galinit
galinit sei
        lda #<irqin
        sta $fffe
        lda #>irqin
        sta $ffff
        lda #<nmirti
        sta $fffa
        lda #>nmirti
        sta $fffb
        lda #$35        ; the KERNAL off: the texture goes to $E000 (loaded into $6000)
        sta $01
        cli
        lda #$60
        ldx #>TEX
        ldy #16
        jsr copypg
        ldx #0          ; the colours of both screens (loaded into $8000)
-       lda $8000,x
        sta $4000,x
        lda $8100,x
        sta $4100,x
        lda $8200,x
        sta $4200,x
        lda $82e8,x
        sta $42e8,x
        inx
        bne -
        lda #$a0        ; the still parts of the bitmap (loaded into $A000) to $6000
        ldx #$60
        ldy #32
        jsr copypg
        jsr starinit
        lda #0
        sta front
        sta flipreq
        sta flipped
        sta rstate
        sta nquar
        sta alpha
        sta alpha+1
        lda #3
        sta rk
        lda #1
        sta noyield
        jsr render      ; the whole galaxy, into both
        lda #0
        sta noyield
        sta rstate
        jsr splot0      ; and the stars into both
        jsr splot1
        rts

; Y pages from page A to page X
!zone copypg
copypg  sta ptr+1
        stx ptr2+1
        ldx #0
        stx ptr
        stx ptr2
        tya
        tax
        ldy #0
-       lda (ptr),y
        sta (ptr2),y
        iny
        bne -
        inc ptr+1
        inc ptr2+1
        dex
        bne -
        rts

; the show on (on the beat): its interrupts; the loading screen stays up until
; the top of the next frame, then the galaxy is there
!zone showon
showon  ldx #39         ; the text row: blank, its colours fading at the ends;
-       lda scrcol,x    ; row 23 black (the change to text happens in it)
        sta $dbc0,x
        lda #0
        sta $db98,x
        lda #$20
        sta TROW,x
        sta TROW-40,x
        dex
        bpl -
        lda #<msg0
        sta mptr
        lda #>msg0
        sta mptr+1
        ldx #7
-       lda sprptr,x
        sta $43f8,x
        sta $47f8,x
        sta $83f8,x
        dex
        bpl -
        lda #<296       ; the equaliser: sprite 7, twice as wide (columns 34-39)
        sta sprx+7
        lda #>296
        sta sprxh+7
        lda #230
        sta spry+7
        lda #14
        sta $d02e
        ldx #5
-       lda glcol,x
        sta $d027,x
        dex
        bpl -
        lda #0
        sta $d01c
        sta $d017
        lda #$80
        sta $d01d
        sta $d01b
        sei
        lda #<irq_top
        sta $0314
        lda #>irq_top
        sta $0315
        lda #16
        sta $d012
        lda frame
        clc
        adc #2
        sta flipat
        lda #0
        sta nflip
        sta nflip+1
        sta nfr
        sta nfr+1
        cli
        rts
!zone scrcol
scrcol  !byte 0,11,12,15,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
        !byte 1,1,1,1,1,1,1,1,1,1,15,12,11,0,0,0,0,0,0,0
glcol   !byte 1,14,1,14,1,14
sprptr  !byte $22,$23,$22,$23,$22,$23,$20,$20

; ======================================================= texts
!zone t_1sid
t_1sid  !byte 8, 12
        !scr "1 sid detected", 0
!zone t_2sid
t_2sid  !byte 8, 8
        !scr "2 sids detected: stereo", 0
!zone t_load
t_load  !byte 11, 10
        !scr "loading the galaxy...", 0
!zone t_ready
t_ready !byte 11, 10
        !scr "the galaxy is ready! ", 0
!zone t_title
t_title !byte 4, 6
        !scr "2026: an octophonic odyssey", 0
!zone t_copy
t_copy  !byte 6, 11
        !scr "(c) 2026 mong00se", 0
!zone t_disk
t_disk  !byte 22, 2
        !scr "put the odyssey disk in drive 8", 0

}
