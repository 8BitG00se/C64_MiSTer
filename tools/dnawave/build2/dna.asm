; DNA WAVE build 2 - Pendulum Wave's maths and music as a double helix, in chrome and metal, with an equaliser and three
; looks, for the Octophonic 64 (OctoVIC 2+, 8 SIDs, REU). By Mong00se.
; 24 base pairs turn about the helix's axis, rung i 30 + i times a minute, so the ladder twists tighter and tighter and
; after exactly 60 seconds it is flat again; each rung rings its SID voice (8 SIDs x 3) as it turns edge-on, where the
; strands cross. Each minute, as the ladder goes flat, the look changes:
;   GOLD AND STEEL  a studio, the screen split: the helix on a mirror floor above, its full reflection below - the copper
;                   re-reads both layers upside down line by line under the floor, mixed half and half with the dark
;   CHROME IN DEEP SPACE  a nebula and stars          CHROME SYNTHWAVE  a striped sun, a neon grid
; The 6502 does it all live, every frame: the turning (24-bit phases), the sound, the chrome beads (the blitter copies
; them see-through onto the rung layer in depth order: the far ones, the rungs, the near ones), the rungs (steel rods
; with coloured glass, lit up when they ring), the equaliser (a bar per voice under its rung, jumping when it rings), and
; a glow where the strands cross (added sprites). The REU brings the three looks: backgrounds, palettes, chrome beads.
!cpu 6502
BUILD   = 2
VADDR   = $D600
VINC    = $D603
VDATA   = $D604
OCTRL   = $D605
OKEY    = $D606
OSTATUS = $D608
OLINE   = $D609
OFRAME  = $D60B
COPCTL  = $D60E
SPRCOUNT= $D60F
COPBASE = $D610
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
BSRC    = $D670
BDST    = $D673
BW      = $D676
BH      = $D678
BSSTR   = $D67A
BDSTR   = $D67C
BFILL   = $D67E
BCTRL   = $D67F
REU     = $DF00
CHROUT  = $FFD2
SCREEN  = $0400
COLRAM  = $D800
V_BG    = $000000       ; the three backgrounds at 0, $04, $08 (banks)
V_RGA   = $0C0000       ; the rung layer, drawn into the one not shown
V_RGB   = $100000
V_BEADS = $140000       ; the chrome beads, 16 x 16: look l, strand s, depth d at + 2048 l + 256 (4 s + d)
V_GLOW  = $150000       ; the sprites' graphics: the glow
V_SATA  = $160000
V_SATB  = $160400
V_COP   = $170000
PALBUF  = $C800
GEO     = $C400         ; this look's numbers (from the REU)
YCOS    = GEO
DEP     = GEO+256
AYB     = GEO+512
AYR     = GEO+576
EQYL    = GEO+608
EQYH    = GEO+609
EQH     = GEO+610
BACK    = GEO+611
PH0     = $C300
PH1     = $C318
PH2     = $C330
OLDP    = $C348
FLASH   = $C360
EQL     = $C378
BP      = $C390         ; 47
frame   = $50
back    = $51
nspr    = $52
nsprA   = $53
nsprB   = $54
lastf   = $55
steps   = $56
t0      = $57
t1      = $58
t2      = $59
vp      = $5a           ; 2
pass    = $5c
ya      = $5d
yb      = $5e
ax      = $5f
yy      = $60
j       = $61
bank    = $62
xh      = $63
look    = $64
newlook = $65
minute  = $66           ; 2
by      = $68           ; a bead's top row
bs      = $69           ; its image (4 s + d)

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
        inx
        bne .cl
        ldy #^V_RGA
        jsr clear512
        ldy #^V_RGB
        jsr clear512
        ldy #^V_SATA
        jsr clear512
        ; the three backgrounds, the beads, the glow, the copper: REU -> VDATA
        ldx #0
.bgs    stx look
        lda #0
        sta VADDR
        sta VADDR+1
        txa
        asl
        asl
        sta VADDR+2             ; bank 0, 4, 8
        lda rbg0,x
        ldy rbg2,x
        sta t0
        lda rbg1,x
        tax
        lda t0
        jsr rset
        lda #0
        tax
        jsr rgo                 ; 64 KB
        lda #0
        tax
        jsr rgo                 ; 64 KB
        lda #<(LEN_BG-131072)
        ldx #>(LEN_BG-131072)
        jsr rgo
        ldx look
        inx
        cpx #3
        bne .bgs
        lda #<V_BEADS
        ldx #>V_BEADS
        ldy #^V_BEADS
        jsr vset
        lda #<R_BEADS
        ldx #>R_BEADS
        ldy #^R_BEADS
        jsr rset
        lda #<LEN_BEADS
        ldx #>LEN_BEADS
        jsr rgo
        lda #<V_GLOW
        ldx #>V_GLOW
        ldy #^V_GLOW
        jsr vset
        lda #<R_GLOW
        ldx #>R_GLOW
        ldy #^R_GLOW
        jsr rset
        lda #<1024
        ldx #>1024
        jsr rgo
        lda #<V_COP
        ldx #>V_COP
        ldy #^V_COP
        jsr vset
        lda #<R_COP
        ldx #>R_COP
        ldy #^R_COP
        jsr rset
        lda #<LEN_COP
        ldx #>LEN_COP
        jsr rgo
        ; the layers: 512 x 512 bitmaps, picture (0,0) at the top left
        lda #$5b
        sta L0
        sta L1
        lda #^V_RGA
        sta L1+6
        lda #32
        sta L0+8
        sta L1+8
        lda #<V_GLOW
        sta SPRGFX
        lda #>V_GLOW
        sta SPRGFX+1
        lda #^V_GLOW
        sta SPRGFX+2
        lda #<V_SATA
        sta SATBASE
        lda #>V_SATA
        sta SATBASE+1
        lda #^V_SATA
        sta SATBASE+2
        lda #<V_COP
        sta COPBASE
        lda #>V_COP
        sta COPBASE+1
        lda #^V_COP
        sta COPBASE+2
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
        sta EQL,x
        dex
        bpl -
        sta back
        sta nsprA
        sta nsprB
        sta minute
        sta minute+1
        sta look
        jsr setlook
        lda OFRAME
        sta lastf
        rts

; the look: its palette and numbers from the REU, its background on layer 0, the mirror's copper on or off
setlook lda #0
        sta COPCTL
        ldx look
        lda #<PALBUF
        sta REU+2
        lda #>PALBUF
        sta REU+3
        lda rpal0,x
        sta REU+4
        lda rpal1,x
        sta REU+5
        lda rpal2,x
        sta REU+6
        lda #<768
        sta REU+7
        lda #>768
        sta REU+8
        lda #0
        sta REU+10
        lda #$91
        sta REU+1
        lda #<GEO
        sta REU+2
        lda #>GEO
        sta REU+3
        lda rgeo0,x
        sta REU+4
        lda rgeo1,x
        sta REU+5
        lda rgeo2,x
        sta REU+6
        lda #<1024
        sta REU+7
        lda #>1024
        sta REU+8
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
        lda #2                  ; the backdrop
        sta PALSEL
        lda BACK
        sta PALR
        lda BACK+1
        sta PALG
        lda BACK+2
        sta PALB
        lda #0
        sta PALSEL
        lda look                ; layer 0: this look's background
        asl
        asl
        sta L0+6
        lda #35
        sta L0+10
        sta L1+10
        lda #0
        sta L0+11
        sta L1+11
        sta L0+15
        sta L1+15
        lda look
        bne +
        lda #1                  ; gold and steel: the mirror
        sta COPCTL
+       rts

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
        lda back
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
        lda newlook
        beq +
        lda #0
        sta newlook
        jsr setlook
+       lda OFRAME
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
        jsr draw
        jsr glows
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
+       lda EQL,x
        beq +
        dec EQL,x
+       inx
        cpx #NP
        bne .ph
        inc minute              ; 3000 steps: the minute is up, all in line: the next look
        bne +
        inc minute+1
+       lda minute+1
        cmp #>3000
        bne +
        lda minute
        cmp #<3000
        bne +
        lda #0
        sta minute
        sta minute+1
        ldx look
        inx
        cpx #3
        bne .lk
        ldx #0
.lk     stx look
        lda #1
        sta newlook
+       rts

ring    lda #24
        sta FLASH,x
        lda EQH
        sta EQL,x
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


; ---------------------------------------------------------------------------------------------- the rung layer, all of it
draw    jsr bwait
        lda back
        bne .a
        lda #^V_RGB
        bne +
.a      lda #^V_RGA
+       sta bank
        sta BDST+2
        lda #0
        sta BDST
        sta BDST+1
        sta BFILL
        sta BDSTR
        lda #<400
        sta BW
        lda #>400
        sta BW+1
        lda #<284
        sta BH
        lda #>284
        sta BH+1
        lda #2
        sta BDSTR+1
        lda #3
        sta BCTRL
        lda #0                  ; the far beads
        sta pass
        jsr strands
        jsr rungs
        lda #1                  ; the near beads
        sta pass
        jsr strands
        jmp eq

; both strands' beads of this pass (0 far: depth 0-1, 1 near: depth 2-3), copied see-through onto the layer
strands ldx #0
.q      stx j
        ldy BP,x
        lda DEP,y               ; strand A
        sta bs
        lsr
        cmp pass
        bne ._b
        lda AYB,x
        clc
        adc YCOS,y
        jsr blit
._b     ldx j
        lda BP,x
        eor #$80
        tay
        lda DEP,y               ; strand B, half a turn on
        ora #4
        sta bs
        and #3
        lsr
        cmp pass
        bne ._n
        ldy BP,x
        lda AYB,x
        sec
        sbc YCOS,y
        jsr blit
._n     ldx j
        inx
        cpx #NB
        beq +
        jmp .q
+       rts
; bead j (X) centred on row A, image bs
blit    sec
        sbc #8
        sta by
        jsr bwait
        lda #0
        sta BSRC
        lda look
        asl
        asl
        asl
        ora bs
        sta BSRC+1
        lda #^V_BEADS
        sta BSRC+2
        lda #16
        sta BSSTR
        sta BW
        sta BH
        lda #0
        sta BSSTR+1
        sta BW+1
        sta BH+1
        lda bxl,x
        sta BDST
        lda by
        asl
        ora bxh,x
        sta BDST+1
        lda #0
        rol
        ora bank
        sta BDST+2
        lda #5                  ; go, COPY0 (see-through)
        sta BCTRL
        rts

; the rungs: a steel rod, coloured glass in four stripes inset from its ends (the steel shows as collars), a highlight
rungs   ldx #0
.r      stx j
        ldy PH2,x
        lda AYR,x
        sta ax
        clc
        adc YCOS,y
        sta ya
        lda ax
        sec
        sbc YCOS,y
        sta yb
        lda ya                  ; the steel: the whole rod
        sta t0
        lda yb
        sta t1
        lda #184
        ldy #0
        jsr bar
        lda #0
        ldy FLASH,x
        beq +
        lda #2
+       sta t2
        lda ya
        sta t0
        clc
        adc ax
        ror
        sta t1
        lda rc0,x
        jsr glass
        lda t1
        sta t0
        lda ax
        sta t1
        lda rc1,x
        jsr glass
        lda ax
        sta t0
        clc
        adc yb
        ror
        sta t1
        lda rc2,x
        jsr glass
        lda t1
        sta t0
        lda yb
        sta t1
        lda rc3,x
        jsr glass
        ldx j
        lda ya                  ; the highlight down the rod
        sta t0
        lda yb
        sta t1
        lda #185
        ldy #1
        jsr bar
        ldx j
        inx
        cpx #NP
        beq +
        jmp .r
+       rts
; a glass stripe from t0 to t1, colour A + t2, one row in at each end
glass   clc
        adc t2
        pha
        lda t0
        cmp t1
        bcc +
        ldy t1
        sta t1
        sty t0
+       inc t0
        lda t1
        beq +
        dec t1
+       pla
        ldy #0
; a bar of rung j (X) from row t0 to t1 (either way round), colour A: Y = 0 the rod (5 wide), 1 the highlight (1 wide)
bar     sta yy
        jsr bwait
        lda t0
        cmp t1
        bcc +
        beq .x
        ldx t1
        sta t1
        stx t0
+       lda t1
        sec
        sbc t0
        beq .x
        sta BH
        lda #0
        sta BH+1
        sta BW+1
        lda yy
        sta BFILL
        ldx j
        lda rxl,x
        sec
        sbc #2
        lda rxh,x
        sbc #0
        sta xh
        lda rxl,x
        sec
        sbc #2
        cpy #0
        beq +
        clc
        adc #1
+       sta BDST
        lda t0
        asl
        ora xh
        sta BDST+1
        lda #0
        rol
        ora bank
        sta BDST+2
        lda #5
        cpy #0
        beq +
        lda #1
+       sta BW
        lda #0
        sta BDSTR
        lda #2
        sta BDSTR+1
        lda #3
        sta BCTRL
.x      ldx j
        rts

; the equaliser: a bar per voice under its rung, its height the voice's level (it jumps when the voice rings)
eq      ldx #0
.e      stx j
        lda EQL,x
        beq .en
        sta t1                  ; height
        jsr bwait
        lda rc0,x               ; the glass colour of its rung's first stripe, lit
        clc
        adc #2
        sta BFILL
        lda EQYL
        sec
        sbc t1
        sta t0                  ; the top row (16 bits: EQY - h)
        lda EQYH
        sbc #0
        sta yy
        lda rxl,x
        sec
        sbc #4
        sta BDST
        lda rxh,x
        sbc #0
        sta xh
        lda t0
        asl
        sta BDST+1
        lda yy
        rol
        sta t2
        lda BDST+1
        ora xh
        sta BDST+1
        lda t2
        ora bank
        sta BDST+2
        lda #9
        sta BW
        lda #0
        sta BW+1
        sta BH+1
        lda t1
        sta BH
        lda #3
        sta BCTRL
        jsr bwait               ; its chrome cap
        lda #185
        sta BFILL
        lda #2
        sta BH
        lda #3
        sta BCTRL
.en     ldx j
        inx
        cpx #NP
        bne .e
        rts

; the glows: rungs that rang lately, where the strands crossed (added sprites)
glows   lda back
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
        ldx #0
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
        lda AYR,x
        sec
        sbc #51
        sta VDATA
        lda #0
        sbc #0
        sta VDATA
        lda #0
        sta VDATA
        sta VDATA               ; GFX 0
        lda #$ca
        sta VDATA
        lda #$80
        sta VDATA
        inc nspr
.ng     inx
        cpx #NP
        bne .g
        lda back
        bne +
        lda nspr
        sta nsprB
        rts
+       lda nspr
        sta nsprA
        rts

!source "data.inc"
