; DNA WAVE build 1 - Pendulum Wave's maths and music as a double helix, for the Octophonic 64 (OctoVIC 2+, 8 SIDs,
; REU). By Mong00se. 24 base pairs turn about the helix's axis, rung i 30 + i times a minute, so the ladder twists
; tighter and tighter as the minute goes on - flat at the start, a slow twist, a tight one, a tangle - and after exactly
; 60 seconds it is flat again. Each rung is one of the 24 SID voices and rings its note as it turns edge-on (where the
; two strands cross). The 6502 does it all live: the phases (24 bits), the sound, the beads of the two strands (sprites,
; shaded and sized by depth: the near side in front of the rungs, the far side behind them), the rungs (the blitter, in
; stripes, into the back of two layers; they light up when they ring) and a glow where the strands cross (added
; sprites). The REU brings the sprite graphics, the palette and the background (a night of out-of-focus lights).
!cpu 6502
BUILD   = 1
VADDR   = $D600
VINC    = $D603
VDATA   = $D604
OCTRL   = $D605
OKEY    = $D606
OSTATUS = $D608
OLINE   = $D609
OFRAME  = $D60B
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
V_BG    = $000000       ; layer 0: the night (from the REU)
V_RGA   = $040000       ; layer 1: the rungs, drawn into the one not shown
V_RGB   = $080000
V_GFX   = $0C0000       ; sprites: bead (hue h, depth d) at GFX 8 (4 h + d), the glow at 256
V_SATA  = $0D0000
V_SATB  = $0D0400
PALBUF  = $C800
PH0     = $C300
PH1     = $C318
PH2     = $C330
OLDP    = $C348
FLASH   = $C360         ; a rung's light after it rings (frames)
BP      = $C380         ; the beads' phases (top byte), 47
frame   = $50
back    = $51
nspr    = $52           ; sprites in the table being written
nsprA   = $53
nsprB   = $54
lastf   = $55
steps   = $56
t0      = $57
t1      = $58
t2      = $59
vp      = $5a           ; 2
pass    = $5c
ya      = $5d           ; a rung's ends
yb      = $5e
ax      = $5f
yy      = $60
j       = $61
bank    = $62
xh      = $63

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
        !pet "DNA WAVE NEEDS THE OCTOPHONIC 64 (OCTOVIC 2+)", 13, 0

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
        lda #15
        sta COLRAM,x
        dex
        bpl -
        ldy #^V_BG
        jsr clear512
        ldy #^V_RGA
        jsr clear512
        ldy #^V_RGB
        jsr clear512
        ldy #^V_SATA
        jsr clear512
        ; the palette
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
        ; the sprites' graphics and the background, REU -> VDATA
        lda #<V_GFX
        ldx #>V_GFX
        ldy #^V_GFX
        jsr vset
        lda #<R_GFX
        ldx #>R_GFX
        ldy #^R_GFX
        jsr rset
        lda #<LEN_GFX
        ldx #>LEN_GFX
        jsr rgo
        lda #<V_BG
        ldx #>V_BG
        ldy #^V_BG
        jsr vset
        lda #<R_BG
        ldx #>R_BG
        ldy #^R_BG
        jsr rset
        lda #0                  ; 284 rows of 512: 145408 bytes = 2 x 65536 + 14336 (the REU's address goes on by itself)
        ldx #0
        jsr rgo
        lda #0
        ldx #0
        jsr rgo
        lda #<14336
        ldx #>14336
        jsr rgo
        ; the layers
        lda #$5b
        sta L0
        sta L1
        lda #^V_BG
        sta L0+6
        lda #^V_RGA
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
        lda #0
        sta SPRCOUNT
        sta OKEY
        lda #$09
        sta OCTRL
        ldx #7
-       lda sidlo,x
        sta vp
        lda sidhi,x
        sta vp+1
        ldy #$18
        lda #$0f
        sta (vp),y
        dex
        bpl -
        ldx #NP-1
        lda #0
-       sta PH0,x
        sta PH1,x
        sta PH2,x
        sta OLDP,x
        sta FLASH,x
        dex
        bpl -
        sta back
        sta nsprA
        sta nsprB
        lda OFRAME
        sta lastf
        rts

vset    sta VADDR
        stx VADDR+1
        sty VADDR+2
        rts
rset    sta REU+4
        stx REU+5
        sty REU+6
        lda #<VDATA
        sta REU+2
        lda #>VDATA
        sta REU+3
        lda #$80
        sta REU+10
        rts
rgo     sta REU+7
        stx REU+8
        lda #$91
        sta REU+1
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
        lda nsprB
        sta SPRCOUNT
        lda #^V_RGB
        sta L1+6
        jmp .fl
.sb     lda #<V_SATA
        sta SATBASE
        lda #>V_SATA
        sta SATBASE+1
        lda nsprA
        sta SPRCOUNT
        lda #^V_RGA
        sta L1+6
.fl     lda back
        eor #1
        sta back
        ; the physics: as many steps as frames have gone by (the minute keeps its time even if drawing runs late)
        lda OFRAME
        sec
        sbc lastf
        beq .dr
        cmp #5
        bcc +
        lda #4
+       sta steps
        lda OFRAME
        sta lastf
-       jsr physics
        dec steps
        bne -
.dr     jsr beads
        jsr rungs
        jsr sprites
.wt     lda OLINE+1
        bne .wt
        jmp main

; one frame of the turning: every phase on by its step; a rung turning edge-on (phase through 64 or 192) rings
physics ldx #0
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
        tay
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
        lda FLASH,x
        beq +
        dec FLASH,x
+       inx
        cpx #NP
        bne .ph
        rts

ring    lda #24
        sta FLASH,x
        lda vlo,x
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
        lda #$0a
        sta (vp),y
        iny
        lda #$00
        sta (vp),y
        ldy #4
        lda #$10
        sta (vp),y
        lda #$11
        sta (vp),y
        ldy t2
        rts

; the beads' phases: on a rung its phase; half way between two, the phase half way round from one to the next
beads   ldx #0
        ldy #0
.b      lda PH2,x
        sta BP,y
        iny
        cpx #NP-1
        beq .bd
        lda PH1+1,x             ; (next - this) / 2 + this, 16 bits
        sec
        sbc PH1,x
        sta t0
        lda PH2+1,x
        sbc PH2,x
        cmp #$80
        ror
        sta t1
        ror t0
        lda PH1,x
        clc
        adc t0
        lda PH2,x
        adc t1
        sta BP,y
        iny
        inx
        bne .b
.bd     rts

; the rungs, into the layer not shown: clear it, each rung in four stripes and a highlight, lit up when it rings
rungs   jsr bwait
        lda back
        bne .a
        lda #^V_RGB
        bne +
.a      lda #^V_RGA
+       sta BDST+2
        sta bank
        lda #0
        sta BFILL
        lda #0
        sta BDST
        lda #40*2               ; rows 40 .. 279
        sta BDST+1
        lda #<400
        sta BW
        lda #>400
        sta BW+1
        lda #240
        sta BH
        lda #0
        sta BH+1
        sta BDSTR
        lda #2
        sta BDSTR+1
        lda #3
        sta BCTRL
        jsr bwait
        lda #0
        sta BW+1
        ldx #0
.r      stx j
        ldy PH2,x               ; the ends: axis + / - ycos
        lda ayr,x
        sta ax
        clc
        adc ycos,y
        sta ya
        lda ax
        sec
        sbc ycos,y
        sta yb
        lda #0                  ; lit: + 2 in the colour
        ldy FLASH,x
        beq +
        lda #2
+       sta t2
        ; stripes: ya .. (ya+ax)/2, .. ax, .. (ax+yb)/2, .. yb, in rc0..rc3
        lda ya
        sta t0
        clc
        adc ax
        ror
        sta t1
        lda rc0,x
        jsr stripe
        lda t1
        sta t0
        lda ax
        sta t1
        lda rc1,x
        jsr stripe
        lda ax
        sta t0
        clc
        adc yb
        ror
        sta t1
        lda rc2,x
        jsr stripe
        lda t1
        sta t0
        lda yb
        sta t1
        lda rc3,x
        jsr stripe
        ldx j
        inx
        cpx #NP
        bne .r
        rts
; a stripe of rung j from row t0 to row t1 (either way round), colour A + t2: a 5-wide body, a highlight on its left
stripe  clc
        adc t2
        sta yy                  ; (the colour)
        jsr bwait
        lda t0
        cmp t1
        beq .x
        bcc +
        ldy t1                  ; swap: t0 the top
        sta t1
        sty t0
+       lda t1
        sec
        sbc t0
        sta BH
        ldx j
        lda yy
        sta BFILL
        lda rxl,x               ; x - 2
        sec
        sbc #2
        sta BDST
        lda rxh,x
        sbc #0
        sta xh
        lda t0                  ; + row * 512 (into the layer's bank)
        asl
        ora xh
        sta BDST+1
        lda #0
        rol
        ora bank
        sta BDST+2
        lda #5
        sta BW
        lda #3
        sta BCTRL
        jsr bwait
        jsr bwait
        inc yy                  ; the highlight: 1 wide, one in
        lda yy
        sta BFILL
        inc BDST
        lda #1
        sta BW
        lda #3
        sta BCTRL
.x      rts

; the sprite table not shown: the near beads (in front of the rungs), the glows, the far beads (behind the rungs)
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
        lda #0
        sta nspr
        lda #1                  ; pass 1: near (depth 2-3), priority 0
        sta pass
        jsr strands
        ldx #0                  ; the glows: rungs that rang lately, where the strands crossed
.g      lda FLASH,x
        cmp #8
        bcc .ng
        lda rxl,x
        sec
        sbc #48
        sta VDATA
        lda rxh,x
        sbc #0
        sta VDATA
        lda ayr,x
        sec
        sbc #51
        sta VDATA
        lda #0
        sbc #0
        sta VDATA
        lda #0
        sta VDATA
        lda #1
        sta VDATA               ; GFX 256
        lda #$ca
        sta VDATA
        lda #$80
        sta VDATA
        inc nspr
.ng     inx
        cpx #NP
        bne .g
        lda #0                  ; pass 2: far (depth 0-1), priority 2 (behind the rungs)
        sta pass
        jsr strands
        lda back                ; how many, for when this table is shown
        bne +
        lda nspr
        sta nsprB
        rts
+       lda nspr
        sta nsprA
        rts

; both strands' beads of this pass: strand A at axis + ycos, strand B at axis - ycos (half a turn on)
strands ldx #0
.q      stx j
        ldy BP,x
        lda dep,y               ; strand A
        sta t0
        lsr
        cmp pass
        bne ._b
        lda ayb,x
        clc
        adc ycos,y
        jsr bead0
        lda hueA,x
        jsr bead1
._b     ldx j
        lda BP,x
        eor #$80
        tay
        lda dep,y               ; strand B: its depth half a turn on
        sta t0
        lsr
        cmp pass
        bne ._n
        lda BP,x
        tay
        lda ayb,x
        sec
        sbc ycos,y
        jsr bead0
        lda hueB,x
        jsr bead1
._n     ldx j
        inx
        cpx #NB
        bne .q
        rts
; a bead at row A (the bead's centre): X, Y
bead0   sec
        sbc #43
        sta t1
        lda bxl,x
        sta VDATA
        lda bxh,x
        sta VDATA
        lda t1
        sta VDATA
        lda #0
        bcs +
        lda #$ff
+       sta VDATA
        rts
; its graphics: hue A, depth t0: GFX 8 (4 hue + depth); 16 x 16, 256 colours; priority by the pass
bead1   asl
        asl
        ora t0
        asl
        asl
        asl
        sta VDATA
        lda #0
        rol
        sta VDATA
        lda #$c5
        sta VDATA
        lda pass
        bne +
        lda #$10                ; between the layers: behind the rungs, over the night
        sta VDATA
        inc nspr
        rts
+       lda #0
        sta VDATA
        inc nspr
        rts

t_top   !scr "  dna wave . 24 base pairs . 24 voices  "

!source "data.inc"
