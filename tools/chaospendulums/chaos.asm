; CHAOS build 1 - eight double pendulums for the Octophonic 64 (OctoVIC 2+, 8 SIDs, REU). By Mong00se.
; They are let go from almost the same place - a hundred-millionth of a radian apart - and for a few seconds move as one;
; then the difference doubles and doubles and they fly apart: the butterfly effect, seen and heard.
; The motion is worked out on the PC (Lagrange's equations, Runge-Kutta, 400 steps a second) and kept in the REU: two
; angles a pendulum, 50 times a second, two minutes. Everything else is the 6502's, live, every frame: the arms from the
; angles (a sine table) drawn by the blitter into the back of two layers, the weights and the glow (sprites, the glow
; added to what is under it), a light trail behind every outer weight (lines on the back layer whose colours fade by
; the palette, 16 ages; each line rubbed out when its age comes round), and the sound - each pendulum is a SID: its
; inner arm's height plays a note on voice 1, its outer arm's on voice 2 and a higher one on voice 3, struck again
; whenever the arm reaches a new note. While they move as one, all 8 SIDs play the same; then the harmony comes apart.
!cpu 6502
BUILD   = 1
VADDR   = $D600
VINC    = $D603
VDATA   = $D604
OCTRL   = $D605
OKEY    = $D606
OSTATUS = $D608
OLINE   = $D609
SPRCOUNT= $D60F
SATBASE = $D613
SPRGFX  = $D616
PALSEL  = $D619
PALIDX  = $D61A
PALR    = $D61B
PALG    = $D61C
PALB    = $D61D
OID     = $D61E
OVER    = $D61F
L0      = $D620
L1      = $D630
LX0     = $D666
LY0     = $D668
LX1     = $D66A
LY1     = $D66C
BDST    = $D673
BW      = $D676
BH      = $D678
BDSTR   = $D67C
BFILL   = $D67E
BCTRL   = $D67F
REU     = $DF00
CHROUT  = $FFD2
SCREEN  = $0400
COLRAM  = $D800
V_TR    = $000000       ; layer 0: the trails, 512 x 512
V_ARMA  = $040000       ; layer 1: the arms, drawn into the one not shown
V_ARMB  = $080000
V_GFX   = $0C0000       ; sprites: inner weight k at GFX 8 k, outer at 8 (8 + k), the glow at 128
V_SATA  = $0D0000
V_SATB  = $0D0400
PALBUF  = $C800
HIST    = $C000         ; the trail lines: 16 slots x 8 pendulums x (xa, ya, xb, yb) 16 bits = 1 KB
ANG     = $C400         ; this frame's angles from the REU: 8 x (inner lo, hi, outer lo, hi)
X1L     = $C420
X1H     = $C428
Y1L     = $C430
Y1H     = $C438
X2L     = $C440
X2H     = $C448
Y2L     = $C450
Y2H     = $C458
PX2L    = $C460         ; last frame's outer weight
PX2H    = $C468
PY2L    = $C470
PY2H    = $C478
Q1      = $C480         ; the notes the arms are on
Q2      = $C488
frame   = $50           ; 2
slot    = $52
back    = $53
k       = $54
t0      = $55
t1      = $56
t2      = $57
vp      = $58           ; 2
sp      = $5a           ; 2: a sine table page
sv      = $5c           ; the sine's value
cv      = $5d           ; the cosine's value
hp      = $5e           ; 2: a history entry

        * = $0801
        !byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00
        jmp start

start   cld
        sei
        lda #$4f
        sta $d03f
        lda #$38
        sta $d03f
        lda OID
        cmp #$8c
        bne .no
        lda OVER
        cmp #2
        bcs .yes
.no     lda #0
        sta $d03f
        ldx #0
-       lda m_need,x
        beq +
        jsr CHROUT
        inx
        bne -
+       cli
        rts
.yes    lda #$36
        sta $01
        jsr init
        jmp main
m_need  !byte 13
        !pet "CHAOS NEEDS THE OCTOPHONIC 64 (OCTOVIC 2+)", 13, 0

; ================================================================================================================ init
init    lda #$7f
        sta $dc0d
        lda $dc0d
        lda #0
        sta $d01a
        ldx #$9a
.z      sta OCTRL,x
        dex
        cpx #$ff
        bne .z
        lda #1
        sta $d030
        sta VINC
        lda #0
        sta $d020
        sta $d021
        ldx #0
.cl     lda #$20
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
        bne .cl
        ldx #39
-       lda t_top,x
        sta SCREEN,x
        dex
        bpl -
        ldy #^V_TR
        jsr clear512
        ldy #^V_ARMA
        jsr clear512
        ldy #^V_ARMB
        jsr clear512
        ldy #^V_SATA
        jsr clear512
        ; the palette (REU -> RAM -> OctoVIC) and the sprites (REU -> VDATA)
        lda #<PALBUF
        sta REU+2
        lda #>PALBUF
        sta REU+3
        lda #<R_PAL
        sta REU+4
        lda #>R_PAL
        sta REU+5
        lda #^R_PAL
        sta REU+6
        lda #<768
        sta REU+7
        lda #>768
        sta REU+8
        lda #0
        sta REU+10
        lda #$91
        sta REU+1
        lda #0
        sta PALSEL
        sta PALIDX
        tax
-       lda PALBUF,x
        sta PALR
        lda PALBUF+256,x
        sta PALG
        lda PALBUF+512,x
        sta PALB
        inx
        bne -
        lda #2                  ; the backdrop: a deep night blue
        sta PALSEL
        lda #6
        sta PALR
        lda #6
        sta PALG
        lda #18
        sta PALB
        lda #0
        sta PALSEL
        lda #<V_GFX
        sta VADDR
        lda #>V_GFX
        sta VADDR+1
        lda #^V_GFX
        sta VADDR+2
        lda #<VDATA
        sta REU+2
        lda #>VDATA
        sta REU+3
        lda #<R_GFX
        sta REU+4
        lda #>R_GFX
        sta REU+5
        lda #^R_GFX
        sta REU+6
        lda #<LEN_GFX
        sta REU+7
        lda #>LEN_GFX
        sta REU+8
        lda #$80
        sta REU+10
        lda #$91
        sta REU+1
        ; the layers
        lda #$5b
        sta L0
        sta L1
        lda #<V_TR
        sta L0+4
        lda #>V_TR
        sta L0+5
        lda #^V_TR
        sta L0+6
        lda #<V_ARMA
        sta L1+4
        lda #>V_ARMA
        sta L1+5
        lda #^V_ARMA
        sta L1+6
        lda #32
        sta L0+8
        sta L1+8
        lda #35
        sta L0+10
        sta L1+10
        lda #<V_GFX
        sta SPRGFX
        lda #>V_GFX
        sta SPRGFX+1
        lda #^V_GFX
        sta SPRGFX+2
        lda #<V_SATA
        sta SATBASE
        lda #>V_SATA
        sta SATBASE+1
        lda #^V_SATA
        sta SATBASE+2
        lda #24
        sta SPRCOUNT
        lda #0
        sta OKEY
        lda #$09
        sta OCTRL
        ldx #7                  ; the SIDs: loud
-       lda sidlo,x
        sta vp
        lda sidhi,x
        sta vp+1
        ldy #$18
        lda #$0f
        sta (vp),y
        dex
        bpl -
        lda #0
        sta back
        jmp restart

; the show from the beginning: trails rubbed out, the first frame
restart lda #0
        sta frame
        sta frame+1
        ldy #^V_TR
        jsr clear512
        ldx #0
        lda #0
-       sta HIST,x
        sta HIST+$100,x
        sta HIST+$200,x
        sta HIST+$300,x
        inx
        bne -
        ldx #7
        lda #$ff
-       sta Q1,x
        sta Q2,x
        dex
        bpl -
        jsr fetch
        jsr place
        ldx #7
-       lda X2L,x
        sta PX2L,x
        lda X2H,x
        sta PX2H,x
        lda Y2L,x
        sta PY2L,x
        lda Y2H,x
        sta PY2H,x
        dex
        bpl -
        rts

clear512
        jsr bwait
        lda #0
        sta BDST
        sta BDST+1
        sty BDST+2
        sta BFILL
        sta BW
        sta BH
        sta BDSTR
        lda #2
        sta BW+1
        sta BH+1
        sta BDSTR+1
        lda #3
        sta BCTRL
bwait   lda OSTATUS
        and #4
        bne bwait
        rts

; ================================================================================================================ the frame
main    lda OLINE+1
        beq main
        lda OLINE
        cmp #<300
        bcc main
        lda back                ; show what was drawn
        bne .sb
        lda #<V_SATB
        sta SATBASE
        lda #>V_SATB
        sta SATBASE+1
        lda #^V_ARMB
        sta L1+6
        jmp .fl
.sb     lda #<V_SATA
        sta SATBASE
        lda #>V_SATA
        sta SATBASE+1
        lda #^V_ARMA
        sta L1+6
.fl     lda back
        eor #1
        sta back
        lda frame
        and #15
        sta slot
        jsr fade
        jsr fetch               ; this frame's angles
        jsr place               ; where the arms and weights are
        jsr sound
        jsr trails
        jsr arms
        jsr sprites
        inc frame
        bne +
        inc frame+1
+       lda frame+1             ; two minutes: from the beginning again
        cmp #>NF
        bne .wt
        lda frame
        cmp #<NF
        bne .wt
        jsr restart
.wt     lda OLINE+1
        bne .wt
        jmp main

; the trails' colours: pendulum k's 16 entries 32 + 16 k + s, age (slot - s) & 15
fade    lda #0
        sta PALSEL
        ldx #0
.ff     txa
        asl
        asl
        asl
        asl
        sta t0
        clc
        adc #32
        sta PALIDX
        ldy #0
.fs     tya
        eor #$ff
        sec
        adc slot
        and #15
        ora t0
        stx t2
        tax
        lda tr_r,x
        sta PALR
        lda tr_g,x
        sta PALG
        lda tr_b,x
        sta PALB
        ldx t2
        iny
        cpy #16
        bne .fs
        inx
        cpx #NPD
        bne .ff
        rts

; 32 bytes of angles for this frame from the REU (frame * 32)
fetch   lda #<ANG
        sta REU+2
        lda #>ANG
        sta REU+3
        lda frame               ; frame * 32 = (frame << 5)
        asl
        asl
        asl
        asl
        asl
        sta REU+4
        lda frame+1
        sta t0
        lda frame
        lsr t0
        ror
        lsr t0
        ror
        lsr t0
        ror
        sta REU+5
        lda t0
        sta REU+6
        lda #32
        sta REU+7
        lda #0
        sta REU+8
        sta REU+10
        lda #$91
        sta REU+1
        rts

; the sine and cosine (x72) of the angle at ANG,y (lo, hi): sv, cv
sincos  lda ANG+1,y             ; index = angle >> 6 (10 bits): page = hi >> 6, low = (hi << 2) | (lo >> 6)
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        tax
        lda ANG+1,y
        asl
        asl
        sta t1
        lda ANG,y
        rol
        rol
        rol
        and #3
        ora t1
        sta t1
        lda pglo,x
        sta sp
        lda pghi,x
        sta sp+1
        sty t2
        ldy t1
        lda (sp),y
        sta sv
        lda pglo+1,x
        sta sp
        lda pghi+1,x
        sta sp+1
        lda (sp),y
        sta cv
        ldy t2
        rts
pglo    !byte <sint0, <sint1, <sint2, <sint3, <sint4
pghi    !byte >sint0, >sint1, >sint2, >sint3, >sint4

; the arms: inner weight = pivot + 72 (sin, cos) of the inner angle, outer = that + 72 (sin, cos) of the outer
place   ldx #0
.pl     stx k
        txa
        asl
        asl
        tay                     ; ANG + 4 k
        jsr sincos
        ldx k
        lda sv
        jsr sext                ; t0 (lo), t1 (hi) = the signed byte
        clc
        lda #<PIVX
        adc t0
        sta X1L,x
        lda #>PIVX
        adc t1
        sta X1H,x
        lda cv
        jsr sext
        clc
        lda #<PIVY
        adc t0
        sta Y1L,x
        lda #>PIVY
        adc t1
        sta Y1H,x
        iny
        iny
        jsr sincos
        ldx k
        lda sv
        jsr sext
        clc
        lda X1L,x
        adc t0
        sta X2L,x
        lda X1H,x
        adc t1
        sta X2H,x
        lda cv
        jsr sext
        clc
        lda Y1L,x
        adc t0
        sta Y2L,x
        lda Y1H,x
        adc t1
        sta Y2H,x
        inx
        cpx #NPD
        bne .pl
        rts
sext    sta t0
        lda #0
        bit t0
        bpl +
        lda #$ff
+       sta t1
        rts

; each arm's note: 12 steps round by its height (qstep); a new one strikes its voice
sound   ldx #0
.so     stx k
        lda sidlo,x
        sta vp
        lda sidhi,x
        sta vp+1
        txa
        asl
        asl
        tay
        lda ANG+1,y             ; the inner arm
        tay
        lda qstep,y
        cmp Q1,x
        beq .o2
        sta Q1,x
        tay
        lda n1l,y               ; voice 1: the inner arm's note
        sta t0
        lda n1h,y
        sta t1
        ldy #0
        jsr strike
        ldx k
        ldy Q1,x
        lda n3l,y               ; voice 3: higher
        sta t0
        lda n3h,y
        sta t1
        ldy #14
        jsr strike
.o2     ldx k
        txa
        asl
        asl
        tay
        lda ANG+3,y             ; the outer arm
        tay
        lda qstep,y
        cmp Q2,x
        beq .on
        sta Q2,x
        tay
        lda n2l,y
        sta t0
        lda n2h,y
        sta t1
        ldy #7
        jsr strike
.on     ldx k
        inx
        cpx #NPD
        bne .so
        rts
; voice at (vp)+Y: the frequency t0/t1, a soft pluck (triangle on 1 and 3, a pulse on 2)
strike  lda t0
        sta (vp),y
        iny
        lda t1
        sta (vp),y
        iny
        lda #$00
        sta (vp),y              ; pulse width (low)
        iny
        lda #$06
        sta (vp),y              ; (high: 1536)
        iny
        sty t2
        iny
        lda #$1a                ; attack 1, decay a long ring
        sta (vp),y
        iny
        lda #$00
        sta (vp),y
        ldy t2
        cpy #11                 ; voice 2 (the outer arm): a pulse, else a triangle
        beq +
        lda #$10
        sta (vp),y
        lda #$11
        sta (vp),y
        rts
+       lda #$40
        sta (vp),y
        lda #$41
        sta (vp),y
        rts

; the trails: rub out the line this slot drew 16 frames ago, draw the new one (last frame's outer weight to this one)
trails  jsr bwait
        lda #<V_TR
        sta BDST
        lda #>V_TR
        sta BDST+1
        lda #^V_TR
        sta BDST+2
        lda #0
        sta BW
        sta BH
        lda #2
        sta BW+1
        sta BH+1
        lda #0
        sta BDSTR
        lda #2
        sta BDSTR+1
        lda slot                ; hp = HIST + slot * 64
        asl
        asl
        asl
        asl
        asl
        asl
        sta hp
        lda slot
        lsr
        lsr
        clc
        adc #>HIST
        sta hp+1
        ldx #0
.tr     stx k
        txa
        asl
        asl
        asl
        tay                     ; the entry: + 8 k
        jsr bwait
        lda #0                  ; the old line, in see-through
        sta BFILL
        jsr hline
        lda #7
        sta BCTRL
        ldx k                   ; the new line: from last frame's place to this one
        ldy #0
        txa
        asl
        asl
        asl
        tay
        lda PX2L,x
        sta (hp),y
        iny
        lda PX2H,x
        sta (hp),y
        iny
        lda PY2L,x
        sta (hp),y
        iny
        lda PY2H,x
        sta (hp),y
        iny
        lda X2L,x
        sta (hp),y
        sta PX2L,x
        iny
        lda X2H,x
        sta (hp),y
        sta PX2H,x
        iny
        lda Y2L,x
        sta (hp),y
        sta PY2L,x
        iny
        lda Y2H,x
        sta (hp),y
        sta PY2H,x
        jsr bwait
        txa                     ; colour 32 + 16 k + slot
        asl
        asl
        asl
        asl
        clc
        adc #32
        ora slot
        sta BFILL
        txa
        asl
        asl
        asl
        tay
        jsr hline
        lda #7
        sta BCTRL
        ldx k
        inx
        cpx #NPD
        bne .tr
        rts
; the line's ends from (hp)+Y .. +7 into LX0..LY1
hline   lda (hp),y
        sta LX0
        iny
        lda (hp),y
        sta LX0+1
        iny
        lda (hp),y
        sta LY0
        iny
        lda (hp),y
        sta LY0+1
        iny
        lda (hp),y
        sta LX1
        iny
        lda (hp),y
        sta LX1+1
        iny
        lda (hp),y
        sta LY1
        iny
        lda (hp),y
        sta LY1+1
        rts

; the arms, into the layer not shown: clear it, the pivot, 16 lines
arms    jsr bwait
        lda back
        bne .a
        lda #^V_ARMB
        bne +
.a      lda #^V_ARMA
+       sta BDST+2
        lda #0
        sta BDST
        sta BDST+1
        sta BFILL
        lda #<400               ; clear the top 300 rows
        sta BW
        lda #>400
        sta BW+1
        lda #<300
        sta BH
        lda #>300
        sta BH+1
        lda #0
        sta BDSTR
        lda #2
        sta BDSTR+1
        lda #3
        sta BCTRL
        jsr bwait
        lda #0
        sta BW
        sta BH
        lda #2
        sta BW+1
        sta BH+1
        ldx #NPD-1              ; (drawn last to first: pendulum 0 on top)
.ar     jsr bwait
        txa
        clc
        adc #16
        sta BFILL
        lda #<PIVX
        sta LX0
        lda #>PIVX
        sta LX0+1
        lda #<PIVY
        sta LY0
        lda #>PIVY
        sta LY0+1
        lda X1L,x
        sta LX1
        lda X1H,x
        sta LX1+1
        lda Y1L,x
        sta LY1
        lda Y1H,x
        sta LY1+1
        lda #7
        sta BCTRL
        jsr bwait
        lda X1L,x
        sta LX0
        lda X1H,x
        sta LX0+1
        lda Y1L,x
        sta LY0
        lda Y1H,x
        sta LY0+1
        lda X2L,x
        sta LX1
        lda X2H,x
        sta LX1+1
        lda Y2L,x
        sta LY1
        lda Y2H,x
        sta LY1+1
        lda #7
        sta BCTRL
        dex
        bpl .ar
        rts

; the sprite table not shown: 8 outer weights, 8 inner, 8 glows
sprites lda back
        bne .wa
        lda #<V_SATB
        ldx #>V_SATB
        bne +
.wa     lda #<V_SATA
        ldx #>V_SATA
+       sta VADDR
        stx VADDR+1
        lda #^V_SATA
        sta VADDR+2
        ldx #0
.so     lda X2L,x
        ldy X2H,x
        sta t0
        sty t1
        lda Y2L,x
        ldy Y2H,x
        jsr spr16
        txa
        clc
        adc #8
        asl
        asl
        asl
        sta VDATA
        lda #0
        sta VDATA
        lda #$c5
        sta VDATA
        lda #0
        sta VDATA
        inx
        cpx #NPD
        bne .so
        ldx #0
.si     lda X1L,x
        ldy X1H,x
        sta t0
        sty t1
        lda Y1L,x
        ldy Y1H,x
        jsr spr16
        txa
        asl
        asl
        asl
        sta VDATA
        lda #0
        sta VDATA
        lda #$c5
        sta VDATA
        lda #0
        sta VDATA
        inx
        cpx #NPD
        bne .si
        ldx #0
.sg     lda X2L,x               ; the glow, 32 x 32
        sec
        sbc #48
        sta VDATA
        lda X2H,x
        sbc #0
        sta VDATA
        lda Y2L,x
        sec
        sbc #51
        sta VDATA
        lda Y2H,x
        sbc #0
        sta VDATA
        lda #128
        sta VDATA
        lda #0
        sta VDATA
        lda #$ca
        sta VDATA
        lda #$80
        sta VDATA
        inx
        cpx #NPD
        bne .sg
        rts
; X, Y of a 16 x 16 sprite centred on (t0/t1, A/Y): X - 40, Y - 43
spr16   sta t2
        sty vp
        lda t0
        sec
        sbc #40
        sta VDATA
        lda t1
        sbc #0
        sta VDATA
        lda t2
        sec
        sbc #43
        sta VDATA
        lda vp
        sbc #0
        sta VDATA
        rts

t_top   !scr "                 chaos                  "

!source "data.inc"
