; PENDULUM WAVE build 1 - a physics demo for the Octophonic 64 (OctoVIC 2+, 8 SIDs, REU). By Mong00se.
; 24 pendulums, each a little shorter than the last: pendulum i swings 30 + i times a minute, so after 60 seconds they all
; line up again; between, they drift into a snake, waves, apparent chaos, and back. The 6502 runs it all live, every
; frame: each pendulum's phase (24 bits, so the minute comes round exactly), its swing (a cosine) and the rise at the
; ends of its arc (the maths unit multiplies), the strings (the blitter draws them into the back of two layers), the
; balls and their glows (sprites; the glow is ADDED to what is under it), and a light trail behind every ball (dots on
; the back layer whose colours fade by the palette - eight ages, and the 6502 rubs out each dot when its age comes
; round again). Each pendulum is one of the 24 SID voices (8 SIDs x 3): it rings its note as it swings through the
; bottom of its arc, so the pattern you see is the pattern you hear - one great chord when they line up.
; The REU brings the sprite graphics (to the VRAM) and the palette. gen.py makes the tables (data.inc).
!cpu 6502
BUILD   = 1
OV      = $D600
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
MULA    = $D650
MULB    = $D652
MULR    = $D654
MATHCTL = $D658
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
V_BG    = $000000       ; layer 0: the night and the trails, 512 x 512
V_STRA  = $040000       ; layer 1: the strings, drawn into the one not shown
V_STRB  = $080000
V_GFX   = $0C0000       ; the sprites' graphics (ball i at GFX 8 i, the glow at 192)
V_SATA  = $0D0000       ; the sprite table, two of them (one shown, one written)
V_SATB  = $0D0400
PALBUF  = $C800         ; the palette from the REU (768)
HXL     = $C000         ; the trail dots' history: 8 slots x 24 (x low, x high, y)
HXH     = $C100
HY      = $C200
PH0     = $C300         ; the phases (24 bits)
PH1     = $C318
PH2     = $C330
OLDP    = $C348         ; last frame's top byte (for the bottom-of-the-swing test)
BXL     = $C360         ; this frame's ball positions
BXH     = $C378
BYY     = $C390
frame   = $50
slot    = $51
back    = $52
i       = $53
t0      = $54
t1      = $55
t2      = $56
vp      = $57           ; 2: a SID voice
up_r    = $59           ; 3
up_n    = $5c           ; 3
yy      = $5f
xx      = $60           ; 2

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
        !pet "PENDULUM WAVE NEEDS THE OCTOPHONIC 64 (OCTOVIC 2+)", 13, 0

; ================================================================================================================ init
init    lda #$7f
        sta $dc0d
        lda $dc0d
        lda #0
        sta $d01a
        ldx #$9a                ; OctoVIC: all off, then what is needed
.z      sta OCTRL,x
        dex
        cpx #$ff
        bne .z
        lda #1
        sta $d030               ; turbo
        sta VINC
        ldx #0                  ; the C64's screen: blank, the words
        lda #0
        sta $d020
        sta $d021
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
        ; the VRAM: the three bitmaps cleared
        lda #<V_BG
        ldx #>V_BG
        ldy #^V_BG
        jsr clear512
        ldy #^V_STRA
        jsr clear512
        ldy #^V_STRB
        jsr clear512
        ldy #^V_SATA            ; (the sprite tables: nothing in them yet)
        jsr clear512
        ; the palette: from the REU into RAM, then into OctoVIC
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
        ; the sprites' graphics: from the REU straight into VDATA
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
        lda #$80                ; the C64 address stays (VDATA)
        sta REU+10
        lda #$91
        sta REU+1
        ; the night: 32 bands of the background colours, top to bottom (layer 0)
        lda #0
        sta yy
.bg     lda yy                  ; a band of 9 rows from row yy, its colour bgrow[yy]
        tax
        lda bgrow,x
        sta BFILL
        lda #<396
        sta BW
        lda #>396
        sta BW+1
        lda #9
        sta BH
        lda #0
        sta BH+1
        lda #<512
        sta BDSTR
        lda #>512
        sta BDSTR+1
        lda #0                  ; BDST = V_BG + yy * 512
        sta BDST
        lda yy
        asl
        sta BDST+1
        lda #0
        rol
        sta BDST+2
        lda #3
        sta BCTRL
        jsr bwait
        lda yy
        clc
        adc #9
        sta yy
        cmp #252
        bcc .bg
        lda #32                 ; and the rest, to below the bottom of the screen, the darkest
        sta BFILL
        lda #0
        sta BDST
        lda #<(252*512 >> 8)
        sta BDST+1
        lda #>(252*512 >> 8)
        sta BDST+2
        lda #40
        sta BH
        lda #3
        sta BCTRL
        jsr bwait
        ; the bar the pendulums hang from: six rows of brass, a pivot under each pendulum
        ldx #5
.bar    lda barcol,x
        sta BFILL
        lda #20
        sta BDST
        txa
        clc
        adc #BARY-3
        asl
        sta BDST+1
        lda #0
        rol
        sta BDST+2
        lda #<360
        sta BW
        lda #>360
        sta BW+1
        lda #1
        sta BH
        lda #0
        sta BH+1
        lda #3
        sta BCTRL
        jsr bwait
        dex
        bpl .bar
        ; the layers: both bitmaps 512 x 512, picture (0,0) at the top left of the screen
        lda #$5b
        sta L0
        sta L1
        lda #<V_BG
        sta L0+4
        lda #>V_BG
        sta L0+5
        lda #^V_BG
        sta L0+6
        lda #<V_STRA
        sta L1+4
        lda #>V_STRA
        sta L1+5
        lda #^V_STRA
        sta L1+6
        lda #32
        sta L0+8
        sta L1+8
        lda #35
        sta L0+10
        sta L1+10
        ; the sprites
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
        lda #48
        sta SPRCOUNT
        lda #0
        sta OKEY                ; the VIC's black is see-through
        lda #$09                ; on, the VIC in front with its black see-through
        sta OCTRL
        ; the SIDs: loud, every voice a triangle bell
        ldx #7
-       lda sidhi,x
        sta vp+1
        lda sidlo,x
        sta vp
        ldy #$18
        lda #$0f
        sta (vp),y
        dex
        bpl -
        ; the start: every pendulum pulled back to the same side, all phases 0
        ldx #NP-1
        lda #0
-       sta PH0,x
        sta PH1,x
        sta PH2,x
        sta OLDP,x
        dex
        bpl -
        ldx #0
-       sta HXL,x
        sta HXH,x
        sta HY,x
        inx
        bne -
        sta frame
        sta back
        rts

barcol  !byte 36, 35, 34, 33, 37, 38

; clear 512 x 512 bytes at VRAM Y * 65536 (the blitter)
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
main    lda OLINE+1             ; wait for raster line 300 (below the picture)
        beq main
        lda OLINE
        cmp #<300
        bcc main
        ; --- in the gap: show what was drawn, fade the trails' colours
        lda back
        bne .sb
        lda #<V_SATB            ; we drew B: show B, draw into A next
        sta SATBASE
        lda #>V_SATB
        sta SATBASE+1
        lda #<V_STRB
        sta L1+4
        lda #>V_STRB
        sta L1+5
        lda #^V_STRB
        sta L1+6
        jmp .fade
.sb     lda #<V_SATA
        sta SATBASE
        lda #>V_SATA
        sta SATBASE+1
        lda #<V_STRA
        sta L1+4
        lda #>V_STRA
        sta L1+5
        lda #^V_STRA
        sta L1+6
.fade   lda back
        eor #1
        sta back
        lda frame               ; this frame's trail slot
        and #7
        sta slot
        lda #0
        sta PALSEL
        ldx #0                  ; family f: entries 64 + 8 f + s', age (slot - s') & 7
.ff     txa
        asl
        asl
        asl
        sta t0                  ; 8 f
        clc
        adc #64
        sta PALIDX
        ldy #0
.fs     tya
        eor #$ff
        sec
        adc slot                ; slot - s'
        and #7
        clc
        adc t0
        sta t1
        stx t2
        ldx t1
        lda tr_r,x
        sta PALR
        lda tr_g,x
        sta PALG
        lda tr_b,x
        sta PALB
        ldx t2
        iny
        cpy #8
        bne .fs
        inx
        cpx #8
        bne .ff
        ; --- the physics: every phase on by its step; the ones passing the bottom of the swing ring
        ldx #0
.ph     clc
        lda PH0,x
        adc inc0,x
        sta PH0,x
        lda PH1,x
        adc inc1,x
        sta PH1,x
        lda PH2,x
        adc inc2,x
        sta PH2,x
        tay                     ; the top byte: through 64 or 192 since last frame?
        lda OLDP,x
        cmp #64
        bcs +
        cpy #64
        bcs .ring
+       cmp #192
        bcs .nr
        cpy #192
        bcc .nr
.ring   jsr ring
.nr     tya
        sta OLDP,x
        inx
        cpx #NP
        bne .ph
        ; --- where the balls are: x = px + zx, y = rest + zy - the rise (cos^2 x rk / 2048)
        lda #0
        sta MATHCTL
        ldx #0
.bp     ldy PH2,x
        lda zx,y                ; x (zx signed)
        sta t0
        clc
        adc pxl,x
        sta BXL,x
        lda #0
        bit t0
        bpl +
        lda #$ff
+       adc pxh,x
        sta BXH,x
        lda cos2,y              ; the rise
        sta MULA
        lda #0
        sta MULA+1
        sta MULB+1
        lda rk,x
        sta MULB
        lda MULR+1
        lsr
        lsr
        lsr
        sta t1
        lda resty,x
        clc
        adc zy,y
        sec
        sbc t1
        sta BYY,x
        inx
        cpx #NP
        bne .bp
        ; --- the trails: rub out this slot's old dots (back to the night's colour), put the new ones down
        lda slot                ; history index = slot * 24
        asl
        asl
        asl
        sta t0
        asl
        clc
        adc t0
        sta t2                  ; slot * 24
        ldx #0
.tr     stx i
        txa
        clc
        adc t2
        tay                     ; history index
        lda HY,y
        beq .new                ; (nothing there yet)
        sta yy
        lda HXL,y
        sta xx
        lda HXH,y
        sta xx+1
        ldx yy
        lda bgrow,x
        jsr dot
.new    ldx i
        lda BXL,x
        sec
        sbc #1
        sta xx
        lda BXH,x
        sbc #0
        sta xx+1
        lda BYY,x
        sec
        sbc #1
        sta yy
        txa                     ; family = i / 3: colour 64 + 8 f + slot
        jsr div3
        asl
        asl
        asl
        clc
        adc #64
        adc slot
        jsr dot
        ldx i
        txa
        clc
        adc t2
        tay
        lda xx
        sta HXL,y
        lda xx+1
        sta HXH,y
        lda yy
        sta HY,y
        inx
        cpx #NP
        bne .tr
        ; --- the strings, into the layer not shown: clear it, 24 lines from the pivots to the balls
        jsr bwait
        lda back                ; back = 1: draw A (B is shown) ... after the flip above, back says what to draw
        bne .da
        lda #^V_STRB
        bne +
.da     lda #^V_STRA
+       sta t0
        lda #20                 ; clear rows BARY+3 .. 280, x 20 .. 380
        sta BDST
        lda #(BARY+3)*2 & 255
        sta BDST+1
        lda t0
        sta BDST+2
        lda #0
        sta BFILL
        lda #<360
        sta BW
        lda #>360
        sta BW+1
        lda #<(280-BARY-3)
        sta BH
        lda #>(280-BARY-3)
        sta BH+1
        lda #<512
        sta BDSTR
        lda #>512
        sta BDSTR+1
        lda #3
        sta BCTRL
        jsr bwait
        lda #0                  ; the lines: the whole bitmap, clipped to it
        sta BDST
        sta BDST+1
        sta BW
        sta BH
        lda #2
        sta BW+1
        sta BH+1
        lda #39
        sta BFILL
        ldx #0
.ln     jsr bwait
        lda pxl,x
        sta LX0
        lda pxh,x
        sta LX0+1
        lda #BARY+3
        sta LY0
        lda #0
        sta LY0+1
        sta LY1+1
        lda BXL,x
        sta LX1
        lda BXH,x
        sta LX1+1
        lda BYY,x
        sec
        sbc #5
        sta LY1
        lda #7
        sta BCTRL
        inx
        cpx #NP
        bne .ln
        ; --- the sprite table not shown: 24 balls, then their 24 glows
        lda back
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
.sp     lda BXL,x               ; X = x - 8 - 32
        sec
        sbc #40
        sta VDATA
        lda BXH,x
        sbc #0
        sta VDATA
        lda BYY,x               ; Y = y - 8 - 35
        sec
        sbc #43
        sta VDATA
        lda #0
        sbc #0
        sta VDATA
        txa                     ; GFX = 8 i
        asl
        asl
        asl
        sta VDATA
        lda #0
        sta VDATA
        lda #$c5                ; on, 256 colours, 16 x 16
        sta VDATA
        lda #0
        sta VDATA
        inx
        cpx #NP
        bne .sp
        ldx #0
.sg     lda BXL,x               ; the glow: 32 x 32, X = x - 16 - 32
        sec
        sbc #48
        sta VDATA
        lda BXH,x
        sbc #0
        sta VDATA
        lda BYY,x
        sec
        sbc #51
        sta VDATA
        lda #0
        sbc #0
        sta VDATA
        lda #192
        sta VDATA
        lda #0
        sta VDATA
        lda #$ca                ; on, 256 colours, 32 x 32
        sta VDATA
        lda #$80                ; added to what is under it
        sta VDATA
        inx
        cpx #NP
        bne .sg
        inc frame
.wt     lda OLINE+1             ; wait until the beam is back at the top before looking for 300 again
        bne .wt
        jmp main

; pendulum X rings: its SID voice, its note, a triangle bell
ring    lda vlo,x
        sta vp
        lda vhi,x
        sta vp+1
        sty t2
        ldy #0
        lda frql,x
        sta (vp),y
        iny
        lda frqh,x
        sta (vp),y
        ldy #5
        lda #$0a                ; attack 0, decay a long ring
        sta (vp),y
        iny
        lda #$00
        sta (vp),y
        ldy #4
        lda #$10                ; the gate off, then on: it strikes again
        sta (vp),y
        lda #$11
        sta (vp),y
        ldy t2
        rts

; a 2 x 2 dot of colour A at (xx, yy) on layer 0: address = yy * 512 + xx
dot     sta t1
        lda xx
        sta VADDR
        lda yy
        asl
        ora xx+1
        sta VADDR+1
        lda #0
        rol
        sta VADDR+2
        lda t1
        sta VDATA
        sta VDATA
        lda xx                  ; the row under it
        sta VADDR
        lda yy
        clc
        adc #1
        asl
        ora xx+1
        sta VADDR+1
        lda #0
        rol
        sta VADDR+2
        lda t1
        sta VDATA
        sta VDATA
        rts

; A / 3 (A < 24)
div3    ldy #0
-       cmp #3
        bcc +
        sbc #3
        iny
        bne -
+       tya
        rts

t_top   !scr "             pendulum wave              "

!source "data.inc"
