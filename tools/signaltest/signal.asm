; SIGNAL TEST build 1 - a capture and sound test for the Octophonic 64 (OctoVIC 2+, 8 SIDs, REU). By Mong00se.
; A moonlit valley scrolls past at steady speeds, so any judder or dropped frame shows straight away:
;   layer 0: four bands the copper scrolls at their own speeds - stars 1/8 px a frame, mountains 1/4, hills 1/2, forest 1
;   layer 1: the valley floor (a meadow and a river) in perspective, TURNED AND SIZED, 1.5 px a frame far off, 6 close up
;   sprites: fir trees in front (7 px a frame), the moon, the 8 SID meters, the 50 Hz ticker
;   the VIC's text, in front: the frame counter, OctoVIC's late lines (LATETOTAL), what is playing
; The sound (a register stream from the REU, 4 DMA transfers a frame): a level tone (everything at full volume - set the
; capture's gain so it peaks just below the top), each SID on its own (SID 1 to 8), then a tune on all 24 voices. Loops.
; The 50 Hz ticker: one dot of 50 lights a frame; a capture played frame by frame should show it move one dot a frame -
; two the same is a repeated frame, a gap is a dropped one.
; 6502, ACME (-f cbm), loads at $0801 (10 SYS2061).
!cpu 6502
BUILD   = 1
!src "data.inc"
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
BDST    = $D673
BW      = $D676
BH      = $D678
BDSTR   = $D67C
BFILL   = $D67E
BCTRL   = $D67F
U0      = $D688
LATETOT = $D6A6
REU     = $DF00
CHROUT  = $FFD2
SCREEN  = $0400
COLRAM  = $D800
V_L0    = $000000       ; layer 0: the scenery, 512 x 512 (rows 0-199 the picture, the rest see-through)
V_FL    = $100000       ; layer 1: the floor, 2048 x 512 (rows 0-83 the picture)
V_GFX   = $200000
V_SATA  = $210000
V_SATB  = $210400
V_COP   = $220000
PALBUF  = $C000
METBUF  = $C400         ; the 8 meters this frame (0-16)
NSPR    = 70            ; 0 the moon, 1-3 spare, 4-11 trees, 12-19 meters, 20-69 the ticker
TREEY   = 156

; zero page
t       = $50           ; 2: frames
cam     = $52           ; 2: the floor's camera, texels (4 a frame)
dt      = $54
lastf   = $55
back    = $56           ; the sprite table being written: 0 A, 1 B
tk      = $57           ; the ticker, 0-49
secn    = $58           ; the section shown on the status line
vp      = $59           ; 2
tmp     = $5B           ; 4
copp      = $5F           ; 2: the copper entry being written (VRAM low 16 bits)
tx      = $61           ; 8: the trees' x (4 x 16 bits)
ti      = $69
mfr     = $6A           ; 2: the music's frame
kk      = $6C

        * = $0801
        !byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00
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
        !pet "SIGNAL TEST NEEDS THE OCTOPHONIC 64 (OCTOVIC 2+)", 13, 0

; ================================================================================================================ init
init    lda #$7f
        sta $dc0d
        lda $dc0d
        lda #0
        sta $d01a
        ldx #$9a                ; OctoVIC: everything off
.z      sta OCTRL,x
        dex
        cpx #$ff
        bne .z
        lda #1
        sta $d030               ; turbo
        sta VINC
        lda #0
        sta $d020
        sta $d021
        lda #$15
        sta $d018
        ldx #0
.cl     lda #$20
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x
        lda #15
        sta COLRAM,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$2e8,x
        inx
        bne .cl
        ldx #39
-       lda t_title,x
        sta SCREEN,x
        lda #1
        sta COLRAM,x
        lda t_info,x
        sta SCREEN+120,x
        lda t_lab,x
        sta SCREEN+520,x
        lda #12
        sta COLRAM+520,x
        lda #7
        sta COLRAM+80,x
        dex
        bpl -
        ; the palette (REU -> RAM -> OctoVIC)
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
        lda #2                  ; the backdrop: black until the copper paints the sky
        sta PALSEL
        lda #0
        sta PALR
        sta PALG
        sta PALB
        ; both layers cleared (see-through), then the pictures, sprites and copper list from the REU
        lda #<512
        ldx #>512
        ldy #^V_L0
        jsr clear
        lda #<2048
        ldx #>2048
        ldy #^V_FL
        jsr clear
        lda #<V_GFX
        ldx #>V_GFX
        ldy #^V_GFX
        jsr vset
        lda #<R_GFX
        ldx #>R_GFX
        ldy #^R_GFX
        jsr rset
        lda #<REM_GFX
        ldx #>REM_GFX
        jsr rgo
        lda #<V_L0
        ldx #>V_L0
        ldy #^V_L0
        jsr vset
        lda #<R_L0
        ldx #>R_L0
        ldy #^R_L0
        jsr rset
        ldy #NCH_L0
        jsr chunks
        lda #<REM_L0
        ldx #>REM_L0
        jsr rgo
        lda #<V_FL
        ldx #>V_FL
        ldy #^V_FL
        jsr vset
        lda #<R_FL
        ldx #>R_FL
        ldy #^R_FL
        jsr rset
        ldy #NCH_FL
        jsr chunks
        lda #<REM_FL
        ldx #>REM_FL
        jsr rgo
        lda #<V_COP
        ldx #>V_COP
        ldy #^V_COP
        jsr vset
        lda #<R_COP
        ldx #>R_COP
        ldy #^R_COP
        jsr rset
        lda #<REM_COP
        ldx #>REM_COP
        jsr rgo
        ; the state
        lda #0
        sta t
        sta t+1
        sta cam
        sta cam+1
        sta tk
        sta back
        sta mfr
        sta mfr+1
        lda #$ff
        sta secn
        ldx #7
-       lda tx0,x
        sta tx,x
        dex
        bpl -
        ldx #7
        lda #0
-       sta METBUF,x
        dex
        bpl -
        lda #1
        sta dt
        jsr build               ; both sprite tables (B, then A: A is shown first)
        jsr build
        ; the layers
        lda #$5b                ; layer 0: on, 256 colours, bitmap, 512 x 512
        sta L0
        lda #<V_L0
        sta L0+4
        lda #>V_L0
        sta L0+5
        lda #^V_L0
        sta L0+6
        lda #32
        sta L0+8
        lda #35
        sta L0+10
        lda #$7b                ; layer 1: on, 256 colours, bitmap, 2048 x 512, TURNED AND SIZED (the copper sets each line)
        sta L1
        lda #<V_FL
        sta L1+4
        lda #>V_FL
        sta L1+5
        lda #^V_FL
        sta L1+6
        lda #4
        sta L1+15
        ldx #23                 ; U0 V0 DUX DVX DUY DVY: V0 = -216.0 and DVY = 1.0 (line 216 is the floor's row 0)
-       lda regs0,x
        sta U0,x
        dex
        bpl -
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
        lda #NSPR
        sta SPRCOUNT
        lda #<V_COP
        sta COPBASE
        lda #>V_COP
        sta COPBASE+1
        lda #^V_COP
        sta COPBASE+2
        lda #1
        sta COPCTL
        lda #0
        sta OKEY
        lda #$09                ; on, the VIC's black see-through
        sta OCTRL
        lda OFRAME
        sta lastf
        rts

regs0   !byte 0,0,0,0, 0,0,$28,$ff, 0,0,1,0, 0,0,0,0, 0,0,0,0, 0,0,1,0
tx0     !word 40, 300, 560, 790

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
chunks  cpy #0
        beq +
        tya
        pha
        lda #0
        tax
        jsr rgo
        pla
        tay
        dey
        jmp chunks
+       rts
; clear a 512-row bitmap at bank Y (VRAM Y*65536), A/X bytes a row
clear   sta BW
        stx BW+1
        sta BDSTR
        stx BDSTR+1
        lda #0
        sta BDST
        sta BDST+1
        sty BDST+2
        sta BFILL
        sta BH
        lda #2
        sta BH+1
        lda #3
        sta BCTRL
bwait   lda OSTATUS
        and #4
        bne bwait
        rts

; ================================================================================================================ the frame
main    lda OLINE+1             ; wait for line 300 (below the picture)
        beq main
        lda OLINE
        cmp #<300
        bcc main
        lda back                ; show the sprite table built last time (0 A, 1 B)
        bne +
        lda #<V_SATA
        ldx #>V_SATA
        bne ++
+       lda #<V_SATB
        ldx #>V_SATB
++      sta SATBASE
        stx SATBASE+1
        lda OFRAME              ; frames since last time (the time keeps up if this ever runs late)
        sec
        sbc lastf
        bne +
        lda #1
+       cmp #5
        bcc +
        lda #4
+       sta dt
        lda OFRAME
        sta lastf
        clc
        lda t
        adc dt
        sta t
        bcc +
        inc t+1
+       lda dt
        asl
        asl
        clc
        adc cam
        sta cam
        bcc +
        inc cam+1
+       jsr bands               ; first: band 0's scroll is read at line 0
        jsr floor
        jsr meters
        jsr music_play
        jsr build
        jsr texts
.wt     lda OLINE+1             ; wait until the beam is back in the picture
        bne .wt
        jmp main

; the bands' scroll: 32 + t/8, t/4, t/2, t - the copper entries' values (VINC 4: each entry's value byte)
bands   lda #4
        sta VINC
        ldx #3
.b      lda t
        sta tmp
        lda t+1
        sta tmp+1
        ldy bsh,x
        beq +
-       lsr tmp+1
        ror tmp
        dey
        bne -
+       lda bal,x
        sta VADDR
        lda bah,x
        sta VADDR+1
        lda #^V_COP
        sta VADDR+2
        clc
        lda tmp
        adc #32
        sta VDATA
        lda tmp+1
        adc #0
        sta VDATA
        dex
        bpl .b
        rts
bsh     !byte 3, 2, 1, 0
bal     !byte <(V_COP + C_B0), <(V_COP + C_B1), <(V_COP + C_B2), <(V_COP + C_B3)
bah     !byte >(V_COP + C_B0), >(V_COP + C_B1), >(V_COP + C_B2), >(V_COP + C_B3)

; the floor: each line's U0 (its top 16 bits) = the line's own value + the camera
floor   lda #4
        sta VINC
        lda #<(V_COP + C_FL)
        sta copp
        lda #>(V_COP + C_FL)
        sta copp+1
        ldx #0
-       lda copp
        sta VADDR
        lda copp+1
        sta VADDR+1
        lda #^V_COP
        sta VADDR+2
        clc
        lda flhl,x
        adc cam
        sta VDATA
        lda flhh,x
        adc cam+1
        sta VDATA
        clc
        lda copp
        adc #32
        sta copp
        bcc +
        inc copp+1
+       inx
        cpx #FLN
        bne -
        lda #1
        sta VINC
        rts

; the meters: this frame's 8 levels from the REU (R_MET + frame * 8)
meters  lda mfr
        sta tmp
        lda mfr+1
        sta tmp+1
        lda #0
        sta tmp+2
        ldx #3
-       asl tmp
        rol tmp+1
        rol tmp+2
        dex
        bne -
        clc
        lda tmp
        adc #<R_MET
        sta REU+4
        lda tmp+1
        adc #>R_MET
        sta REU+5
        lda tmp+2
        adc #^R_MET
        sta REU+6
        lda #<METBUF
        sta REU+2
        lda #>METBUF
        sta REU+3
        lda #8
        sta REU+7
        lda #0
        sta REU+8
        sta REU+10
        lda #$91
        sta REU+1
        rts

; the music: 256 bytes a frame from the REU (R_MUS = 0), into the 4 windows of 2 SIDs; it loops
music_play
        ldx #3
.l      lda .dst,x
        sta REU+2
        lda .dsth,x
        sta REU+3
        lda .off,x
        sta REU+4
        lda mfr
        sta REU+5
        lda mfr+1
        sta REU+6
        lda #64
        sta REU+7
        lda #0
        sta REU+8
        sta REU+10
        lda #$91
        sta REU+1
        dex
        bpl .l
        inc mfr
        bne +
        inc mfr+1
+       lda mfr
        cmp #<NMUS
        bne +
        lda mfr+1
        cmp #>NMUS
        bne +
        lda #0
        sta mfr
        sta mfr+1
+       rts
.dst    !byte $00, $80, $00, $80
.dsth   !byte $d4, $d4, $d5, $d5
.off    !byte $00, $40, $80, $c0

; ---------------------------------------------------------------------------------------------------- the sprite table
; build: the whole table (70 entries) into the one not shown
build   lda back
        bne +
        lda #<V_SATB            ; A was built last (and is shown): write B
        ldx #>V_SATB
        bne ++
+       lda #<V_SATA
        ldx #>V_SATA
++      sta VADDR
        stx VADDR+1
        lda #^V_SATA
        sta VADDR+2
        lda #1
        sta VINC
        ; 0-3: the halo (added, behind layer 0), the moon (behind layer 0), 2 spare
        ldx #0
-       lda sky,x
        sta VDATA
        inx
        cpx #32
        bne -
        ; 4-11: the trees, 7 px a frame to the left, round a loop of 1000 px
        ldx #0
.tr     stx ti
        lda dt
        sta kk
-       sec
        lda tx,x
        sbc #7
        sta tx,x
        bcs +
        dec tx+1,x
+       dec kk
        bne -
        lda tx+1,x              ; off the left (x < -96): on round the loop
        bpl .on
        lda tx,x
        cmp #<(-96)
        bcs .on
        clc
        lda tx,x
        adc #<1000
        sta tx,x
        lda tx+1,x
        adc #>1000
        sta tx+1,x
.on     ldy #0                  ; the top half, then the bottom half
.th     sec
        lda tx,x
        sbc #32
        sta VDATA
        lda tx+1,x
        sbc #0
        sta VDATA
        lda trY,y
        sta VDATA
        lda #0
        sta VDATA
        lda trG,y
        sta VDATA
        lda trGh,y
        sta VDATA
        txa                     ; every other tree turned round
        and #2
        asl
        asl
        asl
        ora #$cf
        sta VDATA
        lda #0
        sta VDATA
        iny
        cpy #2
        bne .th
        ldx ti
        inx
        inx
        cpx #8
        bne .tr
        ; 12-19: the meters
        ldx #0
-       lda metx,x
        sta VDATA
        lda methx,x
        sta VDATA
        lda #76-35
        sta VDATA
        lda #0
        sta VDATA
        lda METBUF,x            ; GFX = G_MET0 + 32 x level
        sta tmp
        lda #0
        sta tmp+1
        ldy #5
--      asl tmp
        rol tmp+1
        dey
        bne --
        clc
        lda tmp
        adc #<G_MET0
        sta VDATA
        lda tmp+1
        adc #>G_MET0
        sta VDATA
        lda #$cd
        sta VDATA
        lda #$00
        sta VDATA
        inx
        cpx #8
        bne -
        ; 20-69: the ticker - dot tk lit, the one before it half lit
        clc
        lda tk
        adc dt
-       cmp #50
        bcc +
        sbc #50
        bcs -
+       sta tk
        tay
        dey
        bpl +
        ldy #49
+       sty kk                  ; the one before
        ldx #0
        lda #16
        sta tmp                 ; X (16 bits)
        lda #0
        sta tmp+1
.tk     lda tmp
        sta VDATA
        lda tmp+1
        sta VDATA
        lda #44-35
        sta VDATA
        lda #0
        sta VDATA
        lda #<G_TICK0
        cpx tk
        bne +
        lda #<G_TICK2
        bne ++
+       cpx kk
        bne ++
        lda #<G_TICK1
++      sta VDATA
        lda #>G_TICK0
        sta VDATA
        lda #$c0
        sta VDATA
        lda #0
        sta VDATA
        clc
        lda tmp
        adc #6
        sta tmp
        bcc +
        inc tmp+1
+       inx
        cpx #50
        bne .tk
        lda back                ; this one is now the newest
        eor #1
        sta back
        rts

sky     !word 166-32        ; the moon and its halo, behind layer 0
        !word 64-35
        !word G_MOON
        !byte $cf, $20
        !byte 0,0,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,0
trY     !byte TREEY-35, TREEY+64-35
trG     !byte <G_TREET, <G_TREEB
trGh    !byte >G_TREET, >G_TREEB
metx    !byte <(40-32), <(64-32), <(88-32), <(112-32), <(264-32), <(288-32), <(312-32), <(336-32)
methx   !byte >(40-32), >(64-32), >(88-32), >(112-32), >(264-32), >(288-32), >(312-32), >(336-32)

; ---------------------------------------------------------------------------------------------------- the text
texts   ldx #5                  ; the frame counter, dt on
        ldy dt
.inc    lda SCREEN+120+7,x
        clc
        adc #1
        cmp #$3a
        bcc +
        lda #$30
        sta SCREEN+120+7,x
        dex
        bpl .inc
        bmi .nd
+       sta SCREEN+120+7,x
.nd     ldx #5
        dey
        bne .inc
        lda LATETOT+1           ; OctoVIC's late lines since reset, in hex
        lsr
        lsr
        lsr
        lsr
        tax
        lda hex,x
        sta SCREEN+120+35
        lda LATETOT+1
        and #15
        tax
        lda hex,x
        sta SCREEN+120+36
        lda LATETOT
        lsr
        lsr
        lsr
        lsr
        tax
        lda hex,x
        sta SCREEN+120+37
        lda LATETOT
        and #15
        tax
        lda hex,x
        sta SCREEN+120+38
        ; the status line: which section the music is in
        ldx #0
-       lda mfr+1
        cmp sech+1,x
        bcc +
        bne ++
        lda mfr
        cmp secl+1,x
        bcc +
++      inx
        bne -
+       cpx secn
        beq .sx
        stx secn
        txa                     ; 40 bytes a line of t_stat
        asl
        asl
        asl
        sta tmp                 ; x8
        lda #0
        sta tmp+1
        lda tmp
        asl
        rol tmp+1
        asl
        rol tmp+1               ; x32
        clc
        adc tmp
        sta vp
        lda tmp+1
        adc #0
        sta vp+1
        clc
        lda vp
        adc #<t_stat
        sta vp
        lda vp+1
        adc #>t_stat
        sta vp+1
        ldy #39
-       lda (vp),y
        sta SCREEN+80,y
        dey
        bpl -
.sx     rts
hex     !scr "0123456789abcdef"

!src "tables.inc"
t_title !scr "      signal test b1 . octophonic 64    "
t_info  !scr " frame 000000                 late 0000 "
t_lab   !scr "  1  2  3  4                  5  6  7  8"
t_stat  !scr " level tone: set gain to peak below top "
        !scr "        sid 1 of 8, on its own          "
        !scr "        sid 2 of 8, on its own          "
        !scr "        sid 3 of 8, on its own          "
        !scr "        sid 4 of 8, on its own          "
        !scr "        sid 5 of 8, on its own          "
        !scr "        sid 6 of 8, on its own          "
        !scr "        sid 7 of 8, on its own          "
        !scr "        sid 8 of 8, on its own          "
        !scr " moonlit valley . 8 sids . 24 voices    "
