; (C) 2026 Mong00se
; SHOW.ASM - the stock C64 / 2-SID show of ODYSSEY.ASM, by Mong00se.
; A tour of the Webb "Cosmic Cliffs" (NASA, ESA, CSA, STScI): four
; multicolour bitmaps (VIEW0-VIEW3 on the disk: the whole picture,
; then three close-ups), each loaded while the one before is shown,
; into the other VIC bank, then swapped in with an iris or a fade -
; a step zoom. Stars twinkle (colour RAM), sparkles flash on the
; brightest ones and a comet crosses now and then (sprites), the
; scroll text names each view, and the equaliser shows each voice
; (3 bars a SID). All of it is done here, by the 6502.
!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }
!if odyp = 0 {
        !src "odyssey.asm"
} else {

; VIC bank 1 ($4000): screen $4000, text row screen $4400, sprites
; $4800, letters $5800, bitmap $6000. Bank 2 ($8000): screen $8000,
; text $8400, sprites $8800, the ROM's letters, bitmap $A000.
; A view file: 2 bytes, screen colours (1000), colour RAM (1000),
; its table (256: twinkles, sparkles), the bitmap (8000). The screen
; and colour bytes go to the bank's own buffer (bank 1: $9000, bank
; 2: $C000), so the iris and the fades can bring them in.
FADET   = $c900         ; this step's fade, a byte for each byte
SQ      = $ce00         ; squares 0-49 (lo), then hi: 100 bytes
SPST    = $cb00         ; the sparkles' state
TWT     = $cb40         ; the twinkles' timers (24)
HW      = $cb60         ; the iris: half widths of rows 0-23
LINEC   = $cc00         ; the raster bars: a colour a line
MSGBUF  = $cd00         ; the scroll text's "detected" line

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

MINVIEW = 700           ; the least frames from one cut to the next (12 s: a view loads in about 15 s on a 1541)
NVIEW   = 4             ; the views on the disk (VIEW0-VIEW3)

!zone b_dd00
b_dd00  !byte 2, 1
!zone b_scr
b_scr   !byte $40, $80
!zone b_buf
b_buf   !byte $90, $c0
!zone b_bmp
b_bmp   !byte $60, $a0
!zone b_d018
b_d018  !byte $16, $14  ; the text row: screen +$400, letters

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
+       jsr pl_init
        jsr mkmsg
        jsr irqon
        lda #0
        sta bank
        sta view
        sta trans
        sta fxon
        sta qview
        sta inname
        jsr setup       ; letters, sprites, black screens
        lda #0          ; (the equaliser is not sprites any more)
        sta spry
        sta spry+1
        jsr loadscr     ; the loading screen: stars, the title, the equaliser, a bar
        ; the first view, into bank 1
-       lda #0
        ldx #0
        jsr loadview
        bcc +
        ldx #<t_disk
        ldy #>t_disk
        lda #7
        jsr print2
        jmp -
+       lda #40         ; the bar full
        sta lvpage
        ldx #<t_ready
        ldy #>t_ready
        lda #1
        jsr print2
-       jsr atcut       ; the picture comes up on the music's next phrase
        bcc -
        jsr showon      ; the bitmap (all black)
        lda #1
        jsr iris_open   ; the iris opens on the whole picture, straight from the loading screen
        lda #1
        sta qview
        sta fxon
; the tour: load the next view into the bank not shown, wait,
; swap them with an iris or a fade
!zone tour
tour    lda #0
        sta vtime
        sta vtime+1
        ldx view
        inx
        cpx #NVIEW
        bcc +
        ldx #0
+       stx nview
        lda bank
        eor #1
        tax
        lda nview
        jsr loadview
        bcs tour        ; (no disk: stay on this view, try again)
-       lda vtime+1     ; at least MINVIEW frames since the last cut ...
        cmp #>MINVIEW
        bcc -
        bne +
        lda vtime
        cmp #<MINVIEW
        bcc -
+       jsr atcut       ; ... then on the music's next phrase
        bcc -
        lda #0
        sta fxon
        jsr fxoff
        inc trans
        lda trans
        and #1
        beq +
        lda #1
        jsr iris_close
        jsr swap
        lda #1
        jsr iris_open
        jmp ++
+       jsr fade_out
        jsr swap
        jsr fade_in
++      lda nview
        sta view
        clc
        adc #1
        sta qview
        lda #1
        sta fxon
        jmp tour

; the new bank on show (both are black now)
!zone swap
swap    sei
        jsr scrswap
        lda bank
        eor #1
        sta bank
        tax
        lda $dd00
        and #$fc
        ora b_dd00,x
        sta $dd00
        lda #0
        ldx #23
-       sta HW,x
        dex
        bpl -
        cli
        rts

; ================================================== loading a view
; A = the view (0-4), X = the bank (0/1); carry set: it failed
!zone loadview
loadview
        sta lvn
        stx lvb
        sei             ; while a view loads: one sparkle, no comet -
        lda #1          ; more sprites on the bad lines steal so many
        sta loading     ; cycles the KERNAL misses the 1541's bits
        lda #0
        sta lvpage
        sta lverr
        lda #1
        lda #0
        sta comety
        ldx #4
-       sta SPST,x
        sta SPST+8,x
        sta spry+2,x
        dex
        bne -
        sta spry+7
        cli
        lda lvn
        clc
        adc #$30
        sta vname+4
        lda #5
        ldx #<vname
        ldy #>vname
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
        jsr drready     ; (its two address bytes)
        jsr CHRIN
        jsr drready
        jsr CHRIN
        jsr READST
        bne .err
        ldx lvb         ; the colours into the bank's buffer
        lda b_buf,x
        sta ptr+1
        lda #0
        sta ptr
        lda #<2256
        ldx #>2256
        jsr unpack
        bcs .err
        ldx lvb         ; the bitmap into the bank
        lda b_bmp,x
        sta ptr+1
        lda #0
        sta ptr
        lda #<8000
        ldx #>8000
        jsr unpack
        bcs .err
        jsr CLRCHN
        lda #2
        jsr CLOSE
        lda #0
        sta loading
        clc
        rts
.err    jsr CLRCHN
        lda #2
        jsr CLOSE
        lda #0
        sta loading
        sec
        rts
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
!zone vname
vname   !pet "view0"
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
PHLEAD  = 40
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
; the bar: a cell for each pages of the picture unpacked (30 cells for 40 pages)
!zone lbar
lbar    ldx lvdr
.l      lda lvpage
        lsr
        lsr
        sta it
        lda lvpage
        sec
        sbc it
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
        jmp $ea81

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
        jmp $ea81

; the show's: once a frame at line $FC, below the picture
!zone irq_s
irq_s   lda $d019
        sta $d019
        inc frame
        inc vtime
        bne +
        inc vtime+1
+       jsr pl_play
        jsr scroll
        jsr eqdraw
        lda fxon
        beq +
        jsr twinkle
        jsr sparkle
        lda loading     ; (no comet while a view loads)
        bne +
        jsr comet
+       jsr sprites
        jmp $ea81

; the show on: the bitmap (black), the interrupt
!zone showon
showon  sei
        lda #0
        sta colbit
        sta qview       ; (the scroll text starts with the interrupt: these must be clear)
        sta inname
        lda #<msg0
        sta mptr
        lda #>msg0
        sta mptr+1
        ldx #39         ; the scroll text's colours: fading through the greys at the ends
-       lda scrcol,x
        sta $dbc0,x
        lda scrscr,x
        sta $43c0,x
        sta $83c0,x
        dex
        bpl -
        ldx #0          ; its row of the bitmap: empty
        lda #0
-       sta $7e00,x
        sta $7f00,x
        sta $be00,x
        sta $bf00,x
        inx
        bne -
        ldx #0          ; colour RAM black (rows 0-23)
        lda #0
-       sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dac0,x
        inx
        bne -
        lda $dd00
        and #$fc
        ora #2
        sta $dd00
        lda #$3b
        sta $d011
        lda #$08
        sta $d018
        lda #$18
        sta $d016
        lda #0
        sta $d020
        sta $d021
        lda #<irq_s
        sta $0314
        lda #>irq_s
        sta $0315
        lda #$fc
        sta $d012
        cli
        rts
!zone scrcol
scrcol  !byte 0,11,11,12,12,15,15,1,1,1,1,1,1,1,1,1,1,1,1,1
        !byte 1,1,1,1,1,15,15,12,12,11,11,0     ; the scroll text: cells 0-31, fading through the greys at its ends
        !byte 1,1,1,1,1,1,1,1                   ; the equaliser's cells 32-39: white (bits 11)
!zone scrscr
scrscr  !fill 32, 0
        !fill 8, $6e                            ; the equaliser: bits 01 blue, 10 light blue

; ======================================================= texts
!zone t_1sid
t_1sid  !byte 8, 12
        !scr "1 sid detected", 0
!zone t_2sid
t_2sid  !byte 8, 8
        !scr "2 sids detected: stereo", 0
!zone t_load
t_load  !byte 11, 9
        !scr "loading the cliffs...", 0
!zone t_ready
t_ready !byte 11, 9
        !scr "the cliffs are ready!", 0
!zone t_title
t_title !byte 4, 6
        !scr "2026: an octophonic odyssey", 0
!zone t_copy
t_copy  !byte 6, 11
        !scr "(c) 2026 mong00se", 0
!zone t_disk
t_disk  !byte 22, 2
        !scr "put the odyssey disk in drive 8", 0

; the sparkles (4 sizes) and the comet: sprites $22-$26
!zone sprdata
sprdata
; glint, smallest (multicolour: white core, cyan and light blue spikes)
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; glint, small (multicolour: white core, cyan and light blue spikes)
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$30,$00,$00,$ec
        !byte $00,$00,$30,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; glint, big (multicolour: white core, cyan and light blue spikes)
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $00,$00,$00,$10,$00,$00,$10,$00,$00,$30,$00,$00,$fc,$00,$01,$ed
        !byte $00,$00,$fc,$00,$00,$30,$00,$00,$10,$00,$00,$10,$00,$00,$00,$00
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; glint, biggest (multicolour: white core, cyan and light blue spikes)
        !byte $00,$00,$00,$00,$10,$00,$00,$10,$00,$00,$10,$00,$00,$10,$00,$00
        !byte $10,$00,$00,$30,$00,$00,$30,$00,$01,$31,$00,$00,$ec,$00,$17,$ab
        !byte $50,$00,$ec,$00,$01,$31,$00,$00,$30,$00,$00,$30,$00,$00,$10,$00
        !byte $00,$10,$00,$00,$10,$00,$00,$10,$00,$00,$10,$00,$00,$00,$00,$00
; the comet
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        !byte $00,$00,$00,$02,$00,$00,$00,$00,$00,$a0,$00,$02,$00,$00,$38,$00
        !byte $01,$c0,$00,$3e,$00,$00,$3e,$00,$00,$38,$00,$00,$00,$00,$00,$00
}
