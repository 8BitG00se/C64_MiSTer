; front.asm - Octo Weaver Lite: the platform library and the PLAY program, at FRONT (after the song).  ACME.  By Mong00se (Octophonic 64).
; The editor (weaver.asm) uses this code too, and NAME PLAY is this region plus the player and the song (a memory image).
;   start / OctoVIC check and init / the 24-bar eq (a tile layer on OctoVIC layer 1) / text / keyboard / the frame interrupt
!zone front

; ---- where the eq lives
VR_TILES = $01                  ; VRAM $010000: the bar tiles
VR_MAP   = $01                  ; VRAM $018000: the 32 x 32 tile map
EQ_MAPLO = $80
SCREEN   = $0400
COLRAM   = $D800
BACKCOL  = 6                    ; the VIC's background colour = OctoVIC's KEY: it is see-through, the navy backdrop shows

; ================================================================================================ start
; checks for OctoVIC 2+; on a stock machine prints a line and returns to BASIC (pops its caller)
start   sei
        cld
        lda #$4f
        sta $d03f
        lda #$38
        sta $d03f
        lda OID
        cmp #$8c
        bne @no
        lda OVER
        cmp #2
        bcs @yes
@no     lda #0
        sta $d03f
        ldx #0
@m      lda m_need,x
        beq @d
        jsr $ffd2
        inx
        bne @m
@d      pla
        pla
        cli
        rts
@yes    lda #$7f                ; no CIA interrupts: the frame is the raster's
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d
        lda #$35                ; RAM and I/O, no ROMs: the KERNAL comes back only for the disk
        sta $01
        lda #<irq
        sta $fffe
        lda #>irq
        sta $ffff
        lda #<nmi
        sta $fffa
        lda #>nmi
        sta $fffb
        lda #0
        sta $d015
        lda #BACKCOL
        sta $d020
        sta $d021
        lda #$15
        sta $d018
        lda #$1b
        sta $d011
        lda #250
        sta $d012
        rts
m_need  !byte 13
        !pet "OCTO WEAVER NEEDS THE OCTOPHONIC 64 (OCTOVIC 2+)", 13, 0

nmi     rti

irq     pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta $d019
        inc frame
        jsr pl_play
        jsr scankeys
        pla
        tay
        pla
        tax
        pla
        rti

irq_on  lda #1
        sta $d01a
        lda #$ff
        sta $d019
        cli
        rts

; ================================================================================================ OctoVIC and the eq
; eq_rows (tile rows), eq_top (first screen row) are set by the caller
octo_init
        ldx #$9a                ; everything to zero (copper off, layers off, sprites 0, interrupt off)
        lda #0
@z      sta OCTRL,x
        dex
        cpx #$ff
        bne @z
        lda #1
        sta VINC
        lda #2                  ; the backdrop: navy
        sta PALSEL
        lda #0
        sta PALIDX
        lda #8
        sta PALR
        lda #12
        sta PALG
        lda #44
        sta PALB
        lda #BACKCOL
        sta OKEY
        ; the eq's palette: bank n (16 entries), entry j is the SID's colour at (j+1)/16 of full
        lda #0
        sta PALSEL
        sta PALIDX
        sta t7                  ; bank
@bank   lda #0
        sta PALR
        sta PALG
        sta PALB                ; entry 0
        lda #1
        sta t6                  ; j
@ent    ldx t7
        lda t6
        clc
        adc #1
        sta MULB
        lda #0
        sta MULB+1
        sta MULA+1
        lda sidr,x
        jsr @scale
        sta PALR
        lda sidg,x
        jsr @scale
        sta PALG
        lda sidb,x
        jsr @scale
        sta PALB
        inc t6
        lda t6
        cmp #16
        bne @ent
        inc t7
        lda t7
        cmp #8
        bne @bank
        ; the bar tiles
        jsr mktiles
        ; the map: all tile 0
        jsr eq_clearmap
        ; layer 1: 16-colour tiles, 32 x 32 map
        lda #$11                ; on, 16 colours, a 64 x 32 tile map
        sta L1
        lda #0
        sta L1+1
        lda #EQ_MAPLO
        sta L1+2
        lda #VR_MAP
        sta L1+3
        lda #0
        sta L1+4
        sta L1+5
        lda #VR_TILES
        sta L1+6
        lda #$09                ; ENABLE + KEYEN, the VIC in front
        sta OCTRL
        rts
@scale  sta MULA                ; A * (j+1) / 16
        lda MULR
        lsr
        lsr
        lsr
        lsr
        sta t5
        lda MULR+1
        asl
        asl
        asl
        asl
        ora t5
        rts

mktiles lda #0
        sta VADDR
        sta VADDR+1
        lda #VR_TILES
        sta VADDR+2
        lda #0
        sta t0                  ; r
@r      lda #0
        sta t1                  ; k
@k      lda #0
        sta t2                  ; y
@y      lda t0
        asl
        asl
        asl
        clc
        adc #7
        sec
        sbc t2                  ; the pixel's height above the bar's foot
        ldx eq_gs
        beq @g
@sh     lsr
        dex
        bne @sh
@g      clc
        adc #1
        cmp #16
        bcc @c
        lda #15
@c      sta t3
        asl
        asl
        asl
        asl
        ora t3                  ; two pixels of that colour
        sta t3
        lda t2
        clc
        adc t1
        cmp #8
        bcs @f
        lda #0
        sta t3
@f      lda t3                  ; pixels 1-6 of the tile (a gap each side): 0c cc cc c0
        and #$0f
        sta VDATA
        lda t3
        sta VDATA
        sta VDATA
        and #$f0
        sta VDATA
        inc t2
        lda t2
        cmp #8
        bne @y
        inc t1
        lda t1
        cmp #9
        bne @k
        inc t0
        lda t0
        cmp eq_rows
        bne @r
        rts

eq_clearmap
        lda #0
        sta VADDR
        lda #EQ_MAPLO
        sta VADDR+1
        lda #VR_MAP
        sta VADDR+2
        ldy #8
@o      ldx #0
@i      lda #0
        sta VDATA
        sta VDATA
        dex
        bne @i
        dey
        bne @o
        rts

octo_off
        sei
        lda #0
        sta $d01a
        ldx #$9a
@z      sta OCTRL,x
        dex
        cpx #$ff
        bne @z
        sta $d03f
        rts

; ---- the eq's state: 24 voices (index = track + 8 * voice)
eq_reset
        ldx #23
        lda #0
@l      sta eqst,x
        sta eqlo,x
        sta eqhi,x
        sta eqh,x
        dex
        bpl @l
        ldx #7
@e      sta ev,x
        dex
        bpl @e
        jmp eq_clearmap

; once a frame: events from the player, the envelope models, the bars
eq_frame
        lda #0                  ; ---- events: 1 struck, 2 gates off
        sta t5
@trk    ldx t5
        lda ev,x
        beq @nxt
        sta t0
        lda #0
        sta ev,x
        ldy t5
        ldx #3
@v      lda bst,y
        beq @nv
        lda t0
        cmp #1
        bne @rel
        lda #1
        sta eqst,y
        lda #0
        sta eqlo,y
        sta eqhi,y
        beq @nv
@rel    lda eqst,y
        beq @nv
        lda #4
        sta eqst,y
@nv     tya
        clc
        adc #8
        tay
        dex
        bne @v
@nxt    inc t5
        lda t5
        cmp #8
        bne @trk
        ; ---- the models
        ldx #23
@m      lda eqst,x
        bne @mg
        jmp @next
@mg        cmp #2
        bcc @atk
        beq @dec
        cmp #4
        beq @relz
        jmp @sus
@atk    lda bad,x               ; attack
        lsr
        lsr
        lsr
        lsr
        tay
        clc
        lda eqlo,x
        adc atk_lo,y
        sta eqlo,x
        lda eqhi,x
        adc atk_hi,y
        sta eqhi,x
        bcc @ca
        lda #$ff
        sta eqhi,x
@ca     lda eqhi,x
        cmp #$ff
        bne @nextj
        lda #0
        sta eqlo,x
        lda #2
        sta eqst,x
@nextj  jmp @next
@dec    lda bad,x               ; decay to the sustain level
        and #15
        tay
        sec
        lda eqlo,x
        sbc dec_lo,y
        sta eqlo,x
        lda eqhi,x
        sbc dec_hi,y
        sta eqhi,x
        bcc @tosus
        sta t1
        jsr susl
        cmp t1
        bcc @nextj2
        beq @tosus
@tosus  jsr susl
        sta eqhi,x
        lda #0
        sta eqlo,x
        lda #3
        sta eqst,x
        lda eqhi,x
        bne @nextj
        sta eqst,x              ; sustain 0: the note is over
@nextj2 jmp @next
@sus    jmp @next
@relz   lda bsr,x               ; release
        and #15
        tay
        sec
        lda eqlo,x
        sbc dec_lo,y
        sta eqlo,x
        lda eqhi,x
        sbc dec_hi,y
        sta eqhi,x
        bcs @nextj
        lda #0
        sta eqhi,x
        sta eqlo,x
        sta eqst,x
@next   dex
        bmi @mdone
        jmp @m
@mdone
        ; ---- the bars
        ldx #23
@b      lda eqhi,x              ; height in pixels = level * rows * 8 / 256
        sta MULA
        lda #0
        sta MULA+1
        lda eq_px
        sta MULB
        lda #0
        sta MULB+1
        lda MULR+1
        cmp eqh,x
        beq @bn
        sta t0                  ; new height
        jsr eq_put
@bn     dex
        bpl @b
        rts

; the sustain level of voice X (0-255) from its SR byte
susl    lda bsr,x
        and #$f0
        sta t2
        lsr
        lsr
        lsr
        lsr
        ora t2
        rts

; bar X: from height eqh,x to height t0 (pixels): the tiles in between
eq_put  lda eqh,x
        lsr
        lsr
        lsr
        sta t1                  ; old tile row
        lda t0
        lsr
        lsr
        lsr
        sta t2                  ; new tile row
        lda t1
        cmp t2
        bcc @lo
        lda t2                  ; first = min, last = max
        sta t3
        lda t1
        sta t4
        jmp @go
@lo     lda t1
        sta t3
        lda t2
        sta t4
@go     lda t0
        sta eqh,x
        txa
        and #7
        asl
        asl
        asl
        asl
        sta t5                  ; the palette bank in the tile entry's top nibble
        lda eqcol,x
        sta t6                  ; column
@row    ldy t3                  ; tile row t3 (from the foot)
        cpy t2
        bcc @full
        bne @empty
        lda t0                  ; the partly filled tile
        and #7
        jmp @tile
@full   lda #8
        jmp @tile
@empty  lda #0
@tile   clc
        adc mul9,y              ; tile = row * 9 + filled lines
        sta t7
        ; map address: ((eq_top + rows - 1 - row) * 32 + col) * 2
        lda eq_rows
        clc
        adc eq_top
        sec
        sbc #1
        sec
        sbc t3
        tay
        lda mapoff_lo,y
        clc
        adc t6
        adc t6
        sta VADDR
        lda mapoff_hi,y
        clc
        adc #EQ_MAPLO
        sta VADDR+1
        lda #VR_MAP
        sta VADDR+2
        lda t7
        sta VDATA
        lda t5
        sta VDATA
        inc t3
        lda t3
        cmp t4
        bcc @row
        beq @row
        rts

; ================================================================================================ text
; X = column, Y = row -> tp (screen), cp (colour)
txtpos  lda scrlo,y
        sta tp
        sta cp
        lda scrhi,y
        sta tp+1
        clc
        adc #$d4
        sta cp+1
        txa
        clc
        adc tp
        sta tp
        sta cp
        bcc @n
        inc tp+1
        inc cp+1
@n      rts

; A = screen code at tp in colour tcol, tp moves on
putc    ora rvf                 ; (rvf = $80 prints reversed)
        ldy #0
        sta (tp),y
        lda tcol
        sta (cp),y
        inc tp
        inc cp
        bne @r
        inc tp+1
        inc cp+1
@r      rts

; the text after the JSR (screen codes, ends with a 0 byte) at tp
pstr    pla
        sta ip
        pla
        sta ip+1
        ldy #1
@l      lda (ip),y
        beq @d
        sty t0
        jsr putc
        ldy t0
        iny
        bne @l
@d      tya
        clc
        adc ip
        sta ip
        lda ip+1
        adc #0
        pha
        lda ip
        pha
        rts                     ; (the address is the 0 byte: RTS goes one on)

; A = number 0-99 as two digits, A = hex digit
pdec2   ldx #0
@t      cmp #10
        bcc @o
        sbc #10
        inx
        bne @t
@o      pha
        txa
        jsr pdig
        pla
pdig    ora #$30
        jmp putc
phex1   and #15
        cmp #10
        bcc pdig
        sbc #9                  ; screen codes: A = 1
        jmp putc
phex2   pha
        lsr
        lsr
        lsr
        lsr
        jsr phex1
        pla
        jmp phex1

; A = number 0-255 as three digits
pdec3   ldx #0
@h      cmp #100
        bcc @a
        sbc #100
        inx
        bne @h
@a      pha
        txa
        jsr pdig
        pla
        jmp pdec2

; X spaces
pspaces lda #$20
        jsr putc
        dex
        bne pspaces
        rts

clrscr  ldx #0
@l      lda #$20
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x
        lda #1
        sta COLRAM,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$2e8,x
        inx
        bne @l
        rts

; ================================================================================================ the keyboard
; scans the matrix 50 times a second, with repeat; keys go into a ring of 8: code in kbuf, SHIFT in kbufs
scankeys
        lda #0
        sta kshift
        lda #$ff
        sta kfound
        lda #7
        sta ks2
@col    ldx ks2
        lda ksel,x
        sta $dc00
        lda $dc01
        eor #$ff
        beq @nx
        sta ks0
        ldy #7
@bit    asl ks0
        bcc @nb
        lda ks2
        asl
        asl
        asl
        sta ks1
        tya
        ora ks1                 ; the key's number: column * 8 + row
        cmp #15                 ; left SHIFT
        beq @sh
        cmp #52                 ; right SHIFT
        beq @sh
        ldx kfound
        cpx #$ff
        bne @nb
        sta kfound
        jmp @nb
@sh     lda #1
        sta kshift
@nb     dey
        bpl @bit
@nx     dec ks2
        bpl @col
        lda #$ff
        sta $dc00
        lda kquiet
        beq @q
        dec kquiet
        lda kfound
        sta klast
        rts
@q      lda kfound
        cmp #$ff
        bne @k
        sta klast
        rts
@k      cmp klast
        beq @same
        sta klast
        lda #18
        sta krep
        bne @emit
@same   dec krep
        beq @rep
        rts
@rep    lda #4
        sta krep
@emit   ldx kfound
        lda keymap,x
        beq @r
        ldx kshift
        beq @ok
        cmp #$1d                ; shifted cursor keys go the other way, the odd F keys are the even ones
        bne @s1
        lda #$9d
        bne @ok
@s1     cmp #$11
        bne @s2
        lda #$91
        bne @ok
@s2     cmp #$85
        bcc @ok
        cmp #$89
        bcs @ok
        adc #4
@ok     ldx khead
        sta kbuf,x
        lda kshift
        sta kbufs,x
        inx
        txa
        and #7
        sta khead
@r      rts

; the next key: A = code (0 if none), kshiftn = SHIFT
getkey  ldx ktail
        cpx khead
        bne @g
        lda #0
        rts
@g      lda kbuf,x
        pha
        lda kbufs,x
        sta kshiftn
        inx
        txa
        and #7
        sta ktail
        pla
        rts

ksel    !byte $fe, $fd, $fb, $f7, $ef, $df, $bf, $7f
; index = column * 8 + row.  $14 DEL, $0d RETURN, $1d right, $11 down, $85 F1 $86 F3 $87 F5 $88 F7, $03 STOP, $5f left arrow, $5e up arrow, $13 HOME
keymap  !byte $14, $0d, $1d, $88, $85, $86, $87, $11
        !byte '3', 'W', 'A', '4', 'Z', 'S', 'E', 0
        !byte '5', 'R', 'D', '6', 'C', 'F', 'T', 'X'
        !byte '7', 'Y', 'G', '8', 'B', 'H', 'U', 'V'
        !byte '9', 'I', 'J', '0', 'M', 'K', 'O', 'N'
        !byte '+', 'P', 'L', '-', '.', ':', '@', ','
        !byte '#', '*', ';', $13, 0, '=', $5e, '/'
        !byte '1', $5f, 0, '2', $20, 0, 'Q', $03

; ================================================================================================ data
sidr    !byte 235, 255, 255, 110, 80, 110, 200, 255
sidg    !byte 70, 160, 225, 225, 200, 120, 100, 100
sidb    !byte 70, 50, 70, 100, 255, 255, 255, 190
vcol    !byte 2, 8, 7, 13, 3, 14, 4, 10         ; the VIC text colour of each SID's job name
mul9    !for N, 0, 24 { !byte N*9 }
scrlo   !for N, 0, 24 { !byte <(SCREEN + N*40) }
scrhi   !for N, 0, 24 { !byte >(SCREEN + N*40) }
mapoff_lo !for N, 0, 31 { !byte <(N*128) }
mapoff_hi !for N, 0, 31 { !byte >(N*128) }
eqcol   !for V, 0, 23 { !byte 4 + (V & 7)*4 + (V >> 3) }
!source "eqtab.inc"

; ---- variables
frame   !byte 0
tcol    !byte 1
rvf     !byte 0
eq_rows !byte 8
eq_top  !byte 1
eq_px   !byte 64                ; rows * 8
eq_gs   !byte 2                 ; the gradient: pixel height >> this
kshift  !byte 0
ks0     !byte 0
ks1     !byte 0
ks2     !byte 0
kshiftn !byte 0
kfound  !byte 0
klast   !byte $ff
kquiet  !byte 0
krep    !byte 0
khead   !byte 0
ktail   !byte 0
kbuf    !fill 8, 0
kbufs   !fill 8, 0
eqst    !fill 24, 0
eqlo    !fill 24, 0
eqhi    !fill 24, 0
eqh     !fill 24, 0

; ================================================================================================ the PLAY program
; NAME PLAY: the eq full screen and the song.  SPACE pause / play, RUN/STOP or F7 quit.
play_start
        jsr start
        jsr clrscr
        lda #15
        sta eq_rows
        lda #2
        sta eq_top
        lda #120
        sta eq_px
        lda #3
        sta eq_gs
        jsr octo_init
        jsr eq_reset
        ldx #0
        ldy #0
        jsr txtpos
        lda #7
        sta tcol
        jsr pstr
        !scr "octo weaver lite ", 0
        lda #3
        sta tcol
        jsr pstr
        !scr "build 1", 0
        ldx #12
        ldy #20
        jsr txtpos
        lda #1
        sta tcol
        ldx #0
@sn     lda SONG+H_SNAME,x
        and #$3f
        stx t7
        jsr putc
        ldx t7
        inx
        cpx #16
        bne @sn
        ; the job names under the bars, two rows staggered
        ldx #0
@jn     stx t7
        lda vcol,x
        sta tcol
        txa
        asl
        asl
        clc
        adc #2
        pha
        txa
        and #1
        clc
        adc #17
        tay
        pla
        tax
        jsr txtpos
        ldx t7
        lda jnoff,x
        tax
        lda #6
        sta t5
@jc     stx t6
        lda SONG+H_NAMES,x
        and #$3f
        jsr putc
        ldx t6
        inx
        dec t5
        bne @jc
        ldx t7
        inx
        cpx #8
        bne @jn
        ldx #4
        ldy #23
        jsr txtpos
        lda #11
        sta tcol
        jsr pstr
        !scr "space pause   f7 or run/stop exit", 0
        lda #0
        jsr pl_init
        jsr irq_on
@loop   lda frame
        beq @loop
        lda #0
        sta frame
        jsr eq_frame
        jsr getkey
        cmp #$20
        beq @space
        cmp #$88
        beq @quit
        cmp #$03
        bne @loop
@quit   jmp quit
@space  lda playing
        beq @go
        sei
        jsr pl_stop
        cli
        jsr eq_reset
        jmp @loop
@go     sei
        lda #0
        jsr pl_init
        cli
        jmp @loop
jnoff   !for N, 0, 7 { !byte N*6 }

; back to BASIC: every SID quiet, OctoVIC off, the KERNAL's own interrupt
quit    sei
        jsr pl_stop
        jsr octo_off
        lda #<$ea31
        sta $0314
        lda #>$ea31
        sta $0315
        lda #<$fe47
        sta $0318
        lda #>$fe47
        sta $0319
        lda #$81
        sta $dc0d
        lda #$7f
        sta $dc00
        lda #14
        sta $d020
        lda #6
        sta $d021
        lda #$15
        sta $d018
        lda #$37
        sta $01
        lda #0
        sta $c6
        jsr $e544               ; clear the screen
        lda #$0e
        sta 646
        jmp ($a002)             ; BASIC's warm start: READY
front_end
