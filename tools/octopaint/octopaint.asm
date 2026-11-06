; OCTOPAINT - a paint program for the Octophonic 64 (OctoVIC 2+). By Mong00se.
; Original project by Mong00se - Octophonic 64 and OctoVIC by Mong00se (github.com/8BitG00se). GPL v3 or later.
; 6502, ACME (-f cbm). Loads at $0801 with a "10 SYS2061" stub. Build 1: OCTOPAINT.PRG only.
;
; Layers (spec docs/OCTOPAINT_SPEC.md):
;   the canvas   OctoVIC layer 0, a 256-colour BITMAP, 512 x 256 in VRAM $000000; the picture is the top-left 320 x 200
;   the toolbar  OctoVIC layer 1, a 256-colour bitmap at VRAM $040000 (320 x 24 used) + VIC-II text over it (VIC in front,
;                KEYEN, KEY = black: only the letters show)
;   the pointer  OctoVIC sprite 0 (arrow), sprite 1 (a crosshair marking where a line / box / circle began)
;   VRAM         $000000 canvas, $020000 undo copy, $040000 toolbar, $060000 sprite graphics, $061000 sprite table
;
; The source is laid out as
;   PLATFORM  OctoVIC registers, the blitter, input (mouse / joystick / keys), the VIC text, KERNAL disk I/O, the toolbar
;   PAINT     the tools' maths (Bresenham brush, circle, flood fill, run-length packing, Koala decode)
; and PAINT touches the picture only through these hooks (coordinates and colours in the variables named here):
;   plot       p_x, p_y (signed 16), p_col          one pixel, clipped to 0..319 x 0..199
;   fillrect   f_x, f_y (signed 16), f_w, f_h, f_c  a filled rectangle, clipped (the blitter's FILL)
;   readpixel  p_x, p_y                  -> A       one pixel (VDATA read)
;   readrow    p_y, rowbuf                          a whole row of 320 pixels into RAM (fast sequential VDATA read)
;   drawline   l_x0, l_y0, l_x1, l_y1, p_col        a one-pixel line (the blitter's LINE, clipped by the blitter)
; The Windows version starts from tools/octopaint/mkoct.py and docs/OCTOPAINT.md (the .OCT format, the packing).

!cpu 6502

BUILD   = 1

; ------------------------------------------------------------------------------------------------ OctoVIC
VADDR   = $D600
VINC    = $D603
VDATA   = $D604
OCTRL   = $D605
OKEY    = $D606
OSTATUS = $D608
COPCTL  = $D60E
SPRCNT  = $D60F
SATBASE = $D613
SPRGFX  = $D616
PALSEL  = $D619
PALIDX  = $D61A
PALR    = $D61B
PALG    = $D61C
PALB    = $D61D
OID     = $D61E
OVER    = $D61F
L0      = $D620         ; layer 0: LCTRL +0, TILEBASE +4, SCROLLX +8, SCROLLY +$A, LMODE +$F
L1      = $D630
LX0     = $D666
LY0     = $D668
LX1     = $D66A
LY1     = $D66C
BSRC    = $D670
BDST    = $D673
BW      = $D676
BH      = $D678
BSSTR   = $D67A
BDSTR   = $D67C
BFILL   = $D67E
BCTRL   = $D67F
IRQEN   = $D682
U0      = $D688
V0      = $D68C
DUX     = $D690
DVY     = $D69C
LATE    = $D6A0
LATETOT = $D6A6

; ------------------------------------------------------------------------------------------------ KERNAL
CHROUT  = $FFD2
CHRIN   = $FFCF
SETLFS  = $FFBA
SETNAM  = $FFBD
OPEN    = $FFC0
CLOSE   = $FFC3
CHKIN   = $FFC6
CHKOUT  = $FFC9
CLRCHN  = $FFCC
READST  = $FFB7

SCREEN  = $0400
COLRAM  = $D800

; ------------------------------------------------------------------------------------------------ layout
CW      = 320           ; the picture
CH      = 200
VR_CAN  = $00           ; VRAM high bytes
VR_UNDO = $02
VR_TB   = $04
VR_SPR  = $06
TBTOP   = 176           ; the toolbar: pixel rows 176-199 (VIC text rows 22-24)

; C64 RAM
STK_XL  = $A000         ; flood fill stack: 1024 entries in three arrays (x low, x high, y)
STK_XH  = $A400
STK_Y   = $A800
LITBUF  = $AC00         ; run-length: pending literal bytes (128)
KBMP    = $A000         ; Koala import: bitmap 8000 bytes ($A000-$BF3F), screen, colour
KSCR    = $C000
KCOL    = $C400
ROWBUF  = $C000         ; flood fill: the row being filled (320) and a neighbouring row (320)
NBUF    = $C200
PAL     = $CA00         ; the working palette, 768 bytes (r, g, b) - what is in OctoVIC, and what is saved
STKMAX  = 1024

; ------------------------------------------------------------------------------------------------ zero page
; (BASIC's pointers $2B-$38 are left alone so that READY after quitting is a normal BASIC)
tick    = $3A           ; the raster IRQ counts frames here
t0      = $3B
t1      = $3C
t2      = $3D
t3      = $3E
str     = $3F           ; 2  text pointer
tp      = $41           ; 2  VIC screen RAM pointer
cp      = $43           ; 2  colour RAM pointer
ptr     = $45           ; 2
ptr2    = $47           ; 2
sx      = $49           ; 2  pointer, screen pixels 0-319
sy      = $4B           ; 2  0-199
vx      = $4D           ; 2  view: the canvas pixel at the screen's top-left
vy      = $4F           ; 2
cx      = $51           ; 2  canvas pixel under the pointer
cy      = $53           ; 2
zsh     = $55           ; zoom shift: 0 = 1x, 1 = 2x, 2 = 4x
tool    = $56
bsize   = $57           ; brush size 1, 2, 4, 8
col     = $58           ; current colour
palwin  = $59           ; first colour of the palette window (multiple of 32)
btn     = $5A           ; b0 left button, b1 right button (this frame)
btnp    = $5B           ; ... last frame
ddx     = $5C           ; 2  the pointer's move this frame (signed)
ddy     = $5E           ; 2
flags   = $60           ; b0 toolbar shown, b1 debug on, b2 mouse reading on, b3 a mouse has been seen, b4 fill filled/outline
uidirty = $61           ; b0 text, b1 swatches
msgt    = $62           ; frames the message on row 24 stays
tcol    = $63           ; text colour
kshift  = $64           ; a shift key is down
kx      = $65
ky      = $66
t4      = $67
t5      = $68

; tools
T_PENCIL = 0
T_BRUSH  = 1
T_LINE   = 2
T_RECT   = 3
T_CIRCLE = 4
T_FILL   = 5

; ================================================================================================ start
        * = $0801
        !byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00      ; 10 SYS2061
start   cld
        sei
        lda #$4f                ; switch OctoVIC on
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
.pm     lda m_need,x
        beq .pd
        jsr CHROUT
        inx
        bne .pm
.pd     cli
        rts
.yes    lda #$36                ; BASIC off, KERNAL and I/O on
        sta $01
        jsr init
        jmp main

!zone m_need
m_need  !byte 13
        !pet "OCTOPAINT NEEDS THE OCTOPHONIC 64 (OCTOVIC 2+)", 13, 0

; ================================================================================================ init
!zone init
init    lda #$7f                ; no CIA interrupts (the keys are read by the matrix, the frame by the raster IRQ)
        sta $dc0d
        lda $dc0d
        lda #0
        sta $d01a
        lda #$ff
        sta $d019
        ; everything in OctoVIC to zero (the copper off, layers off, sprites 0, IRQEN 0), then 1.0 for the unit scale
        ldx #$9a
        lda #0
.z      sta OCTRL,x
        dex
        cpx #$ff
        bne .z
        lda #1
        sta DUX+2
        sta DVY+2
        sta VINC
        ; the VIC: black screen, the standard upper case set, no VIC sprites
        lda #0
        sta $d020
        sta $d021
        sta $d015
        lda #$15
        sta $d018
        lda #<nmi
        sta $0318
        lda #>nmi
        sta $0319
        jsr clrscreen
        ; OctoVIC: VIC in front, black is see-through (KEYEN), the backdrop black
        lda #2
        sta PALSEL
        lda #0
        sta PALIDX
        sta PALR
        sta PALG
        sta PALB
        sta PALSEL
        ; clear the three VRAM areas (blitter, 512 x 256 each)
        lda #VR_CAN
        jsr hw_clear
        lda #VR_UNDO
        jsr hw_clear
        lda #VR_TB
        jsr hw_clear
        ; the default palette
        ldx #0
.cp     lda defpal,x
        sta PAL,x
        lda defpal+256,x
        sta PAL+256,x
        lda defpal+512,x
        sta PAL+512,x
        inx
        bne .cp
        jsr pal_upload
        jsr spr_load
        ; the variables
        lda #T_PENCIL
        sta tool
        lda #1
        sta bsize
        sta flags               ; toolbar shown
        lda #C_WHITE
        sta col
        lda #(1<<2) | 1
        sta flags
        lda #0
        sta zsh
        sta vx
        sta vx+1
        sta vy
        sta vy+1
        sta btn
        sta btnp
        sta msgt
        lda col
        and #$e0
        sta palwin
        lda #<160
        sta sx
        lda #>160
        sta sx+1
        lda #88
        sta sy
        lda #0
        sta sy+1
        jsr input_init
        ; the layers
        lda #$1b                ; on, 256 colours, BITMAP, 512 wide, 256 tall
        sta L0
        lda #VR_TB
        sta L1+6
        lda #$1b
        sta L1
        lda #2
        sta SPRCNT
        lda #<$1000             ; sprite table at VRAM $061000
        sta SATBASE
        lda #>$1000
        sta SATBASE+1
        lda #VR_SPR
        sta SATBASE+2
        lda #0
        sta SPRGFX
        sta SPRGFX+1
        lda #VR_SPR
        sta SPRGFX+2
        lda #$09                ; ENABLE + KEYEN, the VIC in front
        sta OCTRL
        lda #0
        sta OKEY
        jsr tb_draw
        jsr ui_all
        ; the raster interrupt: one per frame, at line 252 (below the picture)
        lda #<irq
        sta $0314
        lda #>irq
        sta $0315
        lda #252
        sta $d012
        lda $d011
        and #$7f
        sta $d011
        lda #1
        sta $d01a
        lda #$ff
        sta $d019
        lda #1
        sta $d030               ; turbo
        cli
        rts

!zone nmi
nmi     rti

!zone irq
irq     lda $d019
        sta $d019
        inc tick
        jmp $ea81

; ================================================================================================ main loop
!zone main
main    jsr waittick
        jsr input
        jsr pointer
        jsr tools
        jsr keycmds
        jsr view_update
        jsr sprites
        jsr ui_update
        jmp main

!zone waittick
waittick
.w      lda tick
        beq .w
        lda #0
        sta tick
        rts

; ================================================================================================ quit
; every OctoVIC setting undone, the KERNAL's interrupt back, the VIC normal, BASIC's warm start
!zone quit
quit    sei
        lda #0
        sta $d01a
        lda #$ff
        sta $d019
        ldx #$9a
        lda #0
.z      sta OCTRL,x
        dex
        cpx #$ff
        bne .z
        sta $d030
        lda #0
        sta $d03f               ; OctoVIC away
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
        jsr $e544               ; clear the screen
        lda #$0e
        sta 646                 ; light blue text, as BASIC starts
        jmp ($a002)             ; BASIC warm start: READY

; ================================================================================================ PLATFORM: the blitter
!zone bwait
bwait   lda OSTATUS
        and #4
        bne bwait
        rts

; clear one 512 x 256 VRAM area (A = its high byte) to colour 0
!zone hw_clear
hw_clear
        pha
        jsr bwait
        lda #0
        sta BDST
        sta BDST+1
        pla
        sta BDST+2
        lda #<512
        sta BW
        lda #>512
        sta BW+1
        lda #<256
        sta BH
        lda #>256
        sta BH+1
        lda #<512
        sta BDSTR
        lda #>512
        sta BDSTR+1
        lda #0
        sta BFILL
        lda #3                  ; go, FILL
        sta BCTRL
        jmp bwait

; fillrect: f_x, f_y (signed), f_w, f_h (positive), f_c, f_hb (the VRAM area's high byte). Clipped to 320 x 200.
; C is set if nothing was left to draw.
!zone fillrect
fillrect
        lda #<CW
        sta f_lim
        lda #>CW
        sta f_lim+1
        ldx #0
        jsr clipaxis
        bcs .r
        lda #<CH
        sta f_lim
        lda #>CH
        sta f_lim+1
        ldx #2
        jsr clipaxis
        bcs .r
        jsr bwait
        lda f_x
        sta BDST
        lda f_y
        asl
        ora f_x+1
        sta BDST+1
        lda #0
        rol
        clc
        adc f_hb
        sta BDST+2
        lda f_w
        sta BW
        lda f_w+1
        sta BW+1
        lda f_h
        sta BH
        lda f_h+1
        sta BH+1
        lda #<512
        sta BDSTR
        lda #>512
        sta BDSTR+1
        lda f_c
        sta BFILL
        lda #3
        sta BCTRL
        clc
.r      rts

; pos at f_x+X (signed 16), length at f_x+4+X, limit f_lim. C set: nothing left
!zone clipaxis
clipaxis
        lda f_x+1,x
        bpl .nn
        clc                     ; negative start: shorten, start at 0
        lda f_x+4,x
        adc f_x,x
        sta f_x+4,x
        lda f_x+5,x
        adc f_x+1,x
        sta f_x+5,x
        lda #0
        sta f_x,x
        sta f_x+1,x
.nn     lda f_x+5,x
        bmi .e
        ora f_x+4,x
        beq .e
        lda f_x,x               ; start >= limit?
        cmp f_lim
        lda f_x+1,x
        sbc f_lim+1
        bcs .e
        clc                     ; end = start + length
        lda f_x,x
        adc f_x+4,x
        sta t0
        lda f_x+1,x
        adc f_x+5,x
        sta t1
        lda f_lim               ; limit >= end: fine
        cmp t0
        lda f_lim+1
        sbc t1
        bcs .ok
        sec                     ; else length = limit - start
        lda f_lim
        sbc f_x,x
        sta f_x+4,x
        lda f_lim+1
        sbc f_x+1,x
        sta f_x+5,x
.ok     clc
        rts
.e      sec
        rts

; drawline: l_x0, l_y0, l_x1, l_y1 (signed 16), p_col - the blitter's LINE on the canvas, clipped by it to 320 x 200
!zone drawline
drawline
        jsr bwait
        ldx #7
.l      lda l_x0,x
        sta LX0,x
        dex
        bpl .l
        lda #0
        sta BDST
        sta BDST+1
        lda #VR_CAN
        sta BDST+2
        lda #<CW
        sta BW
        lda #>CW
        sta BW+1
        lda #<CH
        sta BH
        lda #>CH
        sta BH+1
        lda #<512
        sta BDSTR
        lda #>512
        sta BDSTR+1
        lda p_col
        sta BFILL
        lda #7                  ; go, LINE
        sta BCTRL
        rts

; copy the picture (320 x 200, rows 512 apart) from VRAM area X to area Y (high bytes)
!zone hw_copy
hw_copy stx t0
        sty t1
        jsr bwait
        lda #0
        sta BSRC
        sta BSRC+1
        sta BDST
        sta BDST+1
        lda t0
        sta BSRC+2
        lda t1
        sta BDST+2
        lda #<CW
        sta BW
        lda #>CW
        sta BW+1
        lda #<CH
        sta BH
        lda #>CH
        sta BH+1
        lda #<512
        sta BSSTR
        sta BDSTR
        lda #>512
        sta BSSTR+1
        sta BDSTR+1
        lda #1                  ; go, COPY
        sta BCTRL
        jmp bwait

; plot: p_x, p_y (signed), p_col - one pixel, clipped
!zone plot
plot    lda p_x+1
        cmp #>CW
        bcc .a
        bne .r
        lda p_x
        cmp #<CW
        bcs .r
.a      lda p_y+1
        bne .r
        lda p_y
        cmp #CH
        bcs .r
        jsr vaddr_xy
        lda p_col
        sta VDATA
.r      rts

; VADDR = canvas pixel (p_x, p_y), both in range
!zone vaddr_xy
vaddr_xy
        lda p_x
        sta VADDR
        lda p_y
        asl
        ora p_x+1
        sta VADDR+1
        lda #0
        rol
        sta VADDR+2             ; (the canvas is at $000000)
        rts

; readpixel: p_x, p_y (in range) -> A
!zone readpixel
readpixel
        jsr vaddr_xy
        jsr vwait
        lda VDATA
        rts

; allow the VRAM read to arrive (2 us, with a margin for the turbo)
!zone vwait
vwait   nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        rts

; ================================================================================================ PLATFORM: palette and sprites
!zone pal_upload
pal_upload
        lda #0
        sta PALSEL
        sta PALIDX
        lda #<PAL
        sta ptr
        lda #>PAL
        sta ptr+1
        ldx #0                  ; 256 entries
.l      ldy #0
        lda (ptr),y
        sta PALR
        iny
        lda (ptr),y
        sta PALG
        iny
        lda (ptr),y
        sta PALB                ; (this stores the entry and moves PALIDX on)
        clc
        lda ptr
        adc #3
        sta ptr
        bcc .n
        inc ptr+1
.n      dex
        bne .l
        rts

; one palette entry (A = its number) from PAL to OctoVIC
!zone pal_set1
pal_set1
        sta PALIDX
        sta t0
        lda #0
        sta PALSEL
        lda t0
        sta ptr
        lda #0
        sta ptr+1
        asl ptr                 ; 2n
        rol ptr+1
        clc
        lda ptr                 ; 3n
        adc t0
        sta ptr
        lda ptr+1
        adc #0
        sta ptr+1
        clc                     ; + PAL
        lda ptr
        adc #<PAL
        sta ptr
        lda ptr+1
        adc #>PAL
        sta ptr+1
        ldy #0
        lda (ptr),y
        sta PALR
        iny
        lda (ptr),y
        sta PALG
        iny
        lda (ptr),y
        sta PALB
        rts

!zone spr_load
spr_load                        ; sprite graphics to VRAM $060000: the arrow, then the crosshair (256 bytes each)
        lda #0
        sta VADDR
        sta VADDR+1
        lda #VR_SPR
        sta VADDR+2
        ldx #0
.a      lda spr_arrow,x
        sta VDATA
        inx
        bne .a
.b      lda spr_cross,x
        sta VDATA
        inx
        bne .b
        rts

; ================================================================================================ PLATFORM: input
; mouse: a 1351 in port 1 (core menu: Pot 1/2 = Mouse) - POTX/POTY, the 6-bit difference, noise bit left out
; joystick: ports 1 and 2; keys: cursor keys, RETURN = left button, SPACE = right button
; The keyboard is read straight from the matrix (CIA 1), so keys can be held and released.
!zone input_init
input_init
        lda #$7f
        sta $dc00               ; port 1's pots feed the SID (bit 6 high) between scans
        lda #0
        ldx #7
.c      sta kb,x
        sta kn,x
        sta kbp,x
        dex
        bpl .c
        sta ftime
        sta kheld
        lda #1
        sta mfirst
        lda #25
        sta minit
        rts

!zone input
input   lda #0
        sta ddx
        sta ddx+1
        sta ddy
        sta ddy+1
        ; ---- the mouse (the pots were selected to port 1 since the last scan)
        lda flags
        and #4
        beq .nomouse
        lda $d419
        lsr
        and #$3f
        tax
        lda $d41a
        lsr
        and #$3f
        tay
        lda mfirst
        beq .m1
        lda #0
        sta mfirst
        stx moldx
        sty moldy
        beq .nomouse
.m1     txa
        sec
        sbc moldx
        stx moldx
        jsr sext6
        sta t0
        tya
        sec
        sbc moldy
        sty moldy
        jsr sext6
        sta t1
        lda minit
        beq .m2
        dec minit
        jmp .nomouse
.m2     lda t0
        ora t1
        beq .nomouse
        lda flags               ; something moved: there is a mouse
        ora #8
        sta flags
        lda t0
        jsr addx
        lda t1                  ; (the pot counts up when the mouse moves away from you: up the screen)
        eor #$ff
        clc
        adc #1
        jsr addy
.nomouse
        ; ---- joysticks: every keyboard column off
        lda #$ff
        sta $dc00
        jsr vwait
        lda $dc01
        eor #$ff
        and #$1f
        sta joy1
        lda $dc00
        eor #$ff
        and #$1f
        sta joy2
        jsr kscan
        lda #$7f                ; port 1's pots again
        sta $dc00
        ; ---- the mouse's buttons: fire = left; up = right (once a mouse is known; else up is a direction)
        lda joy1
        sta t2
        lda flags
        and #8
        beq .nm
        lda joy1
        and #1
        sta mright
        lda t2
        and #$fe
        sta t2
        jmp .jj
.nm     lda #0
        sta mright
.jj     lda t2
        ora joy2
        sta jm                  ; b0 up, b1 down, b2 left, b3 right, b4 fire
        ; ---- the cursor keys: RIGHT / DOWN, with a SHIFT they are LEFT / UP
        lda kshift
        sta t3
        lda kb+0
        sta t4
        lda #0
        sta t5
        lda t4
        and #4                  ; RIGHT
        beq .k1
        lda t3
        bne .kl
        lda #8
        bne .k1a
.kl     lda #4
.k1a    ora t5
        sta t5
.k1     lda t4
        and #$80                ; DOWN
        beq .k2
        lda t3
        bne .ku
        lda #2
        bne .k2a
.ku     lda #1
.k2a    ora t5
        sta t5
.k2     lda t5
        cmp kd
        beq .k3
        lda #0                  ; a different direction: the held time starts again
        sta kheld
.k3     lda t5
        sta kd
        ; how long a cursor key / the fire button has been held
        lda t5
        beq .kh0
        lda kheld
        cmp #200
        bcs .kh1
        inc kheld
        jmp .kh1
.kh0    lda #0
        sta kheld
.kh1    lda jm
        and #$10
        beq .f0
        lda ftime
        cmp #200
        bcs .f1
        inc ftime
        jmp .f1
.f0     lda #0
        sta ftime
.f1     ; the step: 1, or 4 after half a second, or 8 with C=
        lda #1
        ldx ftime
        cpx #25
        bcs .s4
        ldx kheld
        cpx #25
        bcc .s5
.s4     lda #4
.s5     sta t4
        lda kb+7
        and #$20                ; C=
        beq .s6
        lda #8
        sta t4
.s6     lda t4
        ldx zsh
        beq .s7
.s8     asl
        dex
        bne .s8
.s7     sta t4                  ; step (screen pixels)
        lda jm
        ora kd
        sta t3                  ; direction bits from joystick and keys
        and #8                  ; right
        beq .d1
        lda t4
        jsr addx
.d1     lda t3
        and #4                  ; left
        beq .d2
        lda t4
        eor #$ff
        clc
        adc #1
        jsr addx
.d2     lda t3
        and #2                  ; down
        beq .d3
        lda t4
        jsr addy
.d3     lda t3
        and #1                  ; up
        beq .d4
        lda t4
        eor #$ff
        clc
        adc #1
        jsr addy
.d4     ; ---- the buttons
        lda #0
        sta btn
        lda jm
        and #$10
        bne .bl
        lda kb+0
        and #2                  ; RETURN
        beq .br
.bl     lda #1
        sta btn
.br     lda mright
        bne .br1
        lda kb+7
        and #$10                ; SPACE
        beq .bx
.br1    lda btn
        ora #2
        sta btn
.bx     rts

!zone sext6
sext6   and #$3f                ; a 6-bit difference to a signed byte; a jump of 24 or more is noise (0)
        cmp #32
        bcc .p
        ora #$c0
        cmp #$e9
        bcs .ok
        lda #0
        rts
.p      cmp #24
        bcc .ok
        lda #0
.ok     rts

; ddx / ddy += A (signed 8)
!zone addx
addx    ldy #0
        cmp #$80
        bcc .a
        ldy #$ff
.a      clc
        adc ddx
        sta ddx
        tya
        adc ddx+1
        sta ddx+1
        rts
!zone addy
addy    ldy #0
        cmp #$80
        bcc .a
        ldy #$ff
.a      clc
        adc ddy
        sta ddy
        tya
        adc ddy+1
        sta ddy+1
        rts

; the keyboard matrix: kb[col] has a bit for each key down, kn[col] the keys newly down since the last scan
!zone kscan
kscan   lda #$fe
        sta t0
        ldx #0
.c      lda t0
        sta $dc00
        ldy #6
.w      dey
        bne .w
        lda $dc01
        eor #$ff
        sta kb,x
        sec
        rol t0
        inx
        cpx #8
        bne .c
        ldx #7
.n      lda kbp,x
        eor #$ff
        and kb,x
        sta kn,x
        lda kb,x
        sta kbp,x
        dex
        bpl .n
        lda #0                  ; a shift key
        sta kshift
        lda kb+1
        and #$80                ; left shift
        sta t0
        lda kb+6
        and #$10                ; right shift
        ora t0
        beq .r
        lda #1
        sta kshift
.r      rts

!zone kclear
kclear  ldx #7                  ; forget keys that are new (after a prompt)
        lda #0
.l      sta kn,x
        dex
        bpl .l
        sta kcur
        rts

; wait for a key press: A = its id (column * 8 + row), SHIFT in kshift
!zone waitkey
waitkey jsr waittick
        jsr kscan
        lda #$7f
        sta $dc00
        ldx #0
.c      lda kn,x
        bne .f
        inx
        cpx #8
        bne .c
        beq waitkey
.f      ldy #0
.b      lsr
        bcs .g
        iny
        bne .b
.g      txa
        asl
        asl
        asl
        sta t0
        tya
        clc
        adc t0
        pha
        jsr kclear
        pla
        rts

; ================================================================================================ the pointer
!zone pointer
pointer ldx #0
        jsr axis
        ldx #2
        jsr axis
        ; the canvas pixel under it: view + pointer / zoom
        ldx #0
        jsr cpos
        ldx #2
        jsr cpos
        ; over the toolbar?
        lda #0
        sta inbar
        lda flags
        and #1
        beq .r
        lda sy
        cmp #TBTOP
        bcc .r
        lda #1
        sta inbar
.r      rts

; move one axis (X = 0 across, 2 down) by ddx/ddy, clamped to the screen; pushing past the edge pans the view when zoomed
!zone axis
axis    clc
        lda sx,x
        adc ddx,x
        sta t0
        lda sx+1,x
        adc ddx+1,x
        sta t1
        bmi .neg
        lda t0
        cmp axlim,x
        lda t1
        sbc axlim+1,x
        bcc .ok
        sec                     ; past the far edge
        lda axlim,x
        sbc #1
        sta sx,x
        lda axlim+1,x
        sbc #0
        sta sx+1,x
        lda ddx,x               ; (only when really pushing that way)
        ora ddx+1,x
        beq .r
        jsr vmax
        clc
        lda vx,x
        adc #2
        sta vx,x
        lda vx+1,x
        adc #0
        sta vx+1,x
        lda t2                  ; clamp to vmax
        cmp vx,x
        lda t3
        sbc vx+1,x
        bcs .r
        lda t2
        sta vx,x
        lda t3
        sta vx+1,x
.r      rts
.ok     lda t0
        sta sx,x
        lda t1
        sta sx+1,x
        rts
.neg    lda #0
        sta sx,x
        sta sx+1,x
        sec
        lda vx,x
        sbc #2
        sta vx,x
        lda vx+1,x
        sbc #0
        sta vx+1,x
        bpl .r
        lda #0
        sta vx,x
        sta vx+1,x
        rts

; t2/t3 = the view's largest origin on this axis: the picture less what the screen shows
!zone vmax
vmax    lda zsh
        asl
        sta t5
        txa
        lsr
        clc
        adc t5
        tay
        lda vmaxt,y
        sta t2
        lda #0
        sta t3
        rts

; cx / cy = view + pointer >> zoom
!zone cpos
cpos    lda sx,x
        sta t0
        lda sx+1,x
        sta t1
        ldy zsh
        beq .s
.l      lsr t1
        ror t0
        dey
        bne .l
.s      clc
        lda vx,x
        adc t0
        sta cx,x
        lda vx+1,x
        adc t1
        sta cx+1,x
        rts

; ================================================================================================ the sprites
; sprite 0 the arrow at the pointer; sprite 1 the crosshair at (mkx, mky) while a line / box / circle is being drawn
!zone sprites
sprites lda #0
        sta VADDR
        lda #$10
        sta VADDR+1
        lda #VR_SPR
        sta VADDR+2
        lda sx
        sta VDATA
        lda sx+1
        sta VDATA
        lda sy
        sta VDATA
        lda sy+1
        sta VDATA
        lda #0                  ; graphics 0
        sta VDATA
        sta VDATA
        lda #$c5                ; on, 256 colours, 16 x 16
        sta VDATA
        lda #0                  ; priority 0: in front of both layers
        sta VDATA
        ; the mark: screen position = (mark - view) * zoom + half a pixel, less 8 (the crosshair's centre)
        ldx #0
        jsr mscr
        sec
        lda t0
        sbc #8
        sta VDATA
        lda t1
        sbc #0
        sta VDATA
        ldx #2
        jsr mscr
        sec
        lda t0
        sbc #8
        sta VDATA
        lda t1
        sbc #0
        sta VDATA
        lda #8                  ; graphics 8 (the crosshair, at +256 bytes)
        sta VDATA
        lda #0
        sta VDATA
        lda mkon
        beq .off
        lda #$c5
        bne .w
.off    lda #$45                ; off
.w      sta VDATA
        lda #0
        sta VDATA
        rts

!zone mscr
mscr    sec
        lda mkx,x
        sbc vx,x
        sta t0
        lda mkx+1,x
        sbc vx+1,x
        sta t1
        ldy zsh
        beq .h
.l      asl t0
        rol t1
        dey
        bne .l
.h      lda zsh                 ; + half a canvas pixel (1 << zsh) / 2
        beq .r
        lda #1
        ldy zsh
        dey
        beq .a
        lda #2
.a      clc
        adc t0
        sta t0
        bcc .r
        inc t1
.r      rts

; ================================================================================================ the view (zoom)
; zoom 1: the plain bitmap layer, no scroll. 2x / 4x: layer 0 TURNED AND SIZED with DUX = DVY = 1 / zoom and U0 / V0 so
; that canvas pixel (vx, vy) is at the screen's top-left: U0 = (vx - 32/z) * 65536, V0 = vy * 65536 - 51 * DVY.
!zone view_update
view_update
        lda zsh
        bne .z
        lda #0
        sta L0+$f               ; LMODE: nothing special
        sta L0+8
        sta L0+9
        sta L0+$a
        sta L0+$b
        rts
.z      lda #4                  ; turned and sized, the picture repeats (it is surrounded by colour 0)
        sta L0+$f
        lda #0
        sta DUX
        sta DUX+2
        sta DUX+3
        sta DVY
        sta DVY+2
        sta DVY+3
        sta U0
        sta U0+1
        lda zsh
        cmp #1
        bne .z4
        lda #$80                ; 1/2
        sta DUX+1
        sta DVY+1
        lda #16                 ; 32 / 2
        sta t0
        lda #$80                ; 51 / 2 pixels = $198000
        sta t1
        lda #$19
        sta t2
        bne .go
.z4     lda #$40                ; 1/4
        sta DUX+1
        sta DVY+1
        lda #8                  ; 32 / 4
        sta t0
        lda #$c0                ; 51 / 4 = $0cc000
        sta t1
        lda #$0c
        sta t2
.go     sec
        lda vx
        sbc t0
        sta U0+2
        lda vx+1
        sbc #0
        sta U0+3
        sec
        lda #0
        sta V0
        sbc t1
        sta V0+1
        lda vy
        sbc t2
        sta V0+2
        lda vy+1
        sbc #0
        sta V0+3
        rts

; ================================================================================================ PLATFORM: the VIC text
!zone clrscreen
clrscreen
        ldx #0
.l      lda #32
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
        bne .l
        rts

; tp / cp at column X, row Y
!zone txtpos
txtpos  lda rowlo,y
        stx t0
        clc
        adc t0
        sta tp
        sta cp
        lda rowhi,y
        adc #>SCREEN
        sta tp+1
        adc #(>COLRAM)-(>SCREEN)-0
        sta cp+1
        rts

; str -> text at tp, ends at $FF; tp / cp move on
!zone puts
puts    ldy #0
.l      lda (str),y
        cmp #$ff
        beq .d
        sta (tp),y
        lda tcol
        sta (cp),y
        iny
        bne .l
.d      tya
        clc
        adc tp
        sta tp
        bcc .a
        inc tp+1
.a      tya
        clc
        adc cp
        sta cp
        bcc .b
        inc cp+1
.b      rts

; A = a screen code at tp, which moves on
!zone putc
putc    ldy #0
        sta (tp),y
        lda tcol
        sta (cp),y
        inc tp
        bne .a
        inc tp+1
.a      inc cp
        bne .b
        inc cp+1
.b      rts

; X spaces at tp
!zone fillsp
fillsp  ldy #0
.l      lda #32
        sta (tp),y
        lda tcol
        sta (cp),y
        iny
        dex
        bne .l
        rts

!macro puts .s { lda #<.s : sta str : lda #>.s : sta str+1 : jsr puts }

; decimal: nv (3 bytes, 0-99999) at tp; X = width (padded with spaces on the left), 0 = no padding; dcomma: thousands comma
!zone prdec
prdec   stx pwid
        lda #0
        sta pstart
        ldy #0
.p      lda #0
        sta pdig
.s      lda nv                  ; nv >= 10^n ?
        cmp pw0,y
        lda nv+1
        sbc pw1,y
        lda nv+2
        sbc #0
        bcc .e
        sec
        lda nv
        sbc pw0,y
        sta nv
        lda nv+1
        sbc pw1,y
        sta nv+1
        lda nv+2
        sbc #0
        sta nv+2
        inc pdig
        jmp .s
.e      sty ptmp                ; y = 0..4: 5 - y digits left including this one
        cpy #4
        beq .show
        lda pdig
        bne .show
        lda pstart
        bne .show
        ; a leading zero: a space if padding reaches it, else nothing
        sec
        lda #5
        sbc ptmp
        cmp pwid
        beq .sp
        bcs .skip
.sp     lda #32
        jsr putc
.skip   jmp .nx
.show   lda ptmp
        cmp #2
        bne .nc
        lda pstart
        beq .nc
        lda dcomma
        beq .nc
        lda #44                 ; ,
        jsr putc
.nc     lda pdig
        clc
        adc #$30
        jsr putc
        lda #1
        sta pstart
.nx     ldy ptmp
        iny
        cpy #5
        beq .done
        jmp .p
.done   rts

; A = a byte, 2 hex digits at tp
!zone prhex
prhex   pha
        lsr
        lsr
        lsr
        lsr
        jsr .d
        pla
        and #15
.d      cmp #10
        bcc .n
        sbc #9                  ; 10 -> screen code 1 (A)
        jmp putc
.n      adc #$30
        jmp putc

!macro dec8 .v { lda .v : sta nv : lda #0 : sta nv+1 : sta nv+2 }

; ================================================================================================ PLATFORM: the toolbar
!macro rect .x, .y, .w, .h, .c {
        lda #<(.x)
        sta f_x
        lda #>(.x)
        sta f_x+1
        lda #<(.y)
        sta f_y
        lda #>(.y)
        sta f_y+1
        lda #<(.w)
        sta f_w
        lda #>(.w)
        sta f_w+1
        lda #<(.h)
        sta f_h
        lda #>(.h)
        sta f_h+1
        lda #.c
        sta f_c
        jsr fillrect
}

!zone tb_draw
tb_draw lda #VR_TB
        sta f_hb
        +rect 0, TBTOP, CW, 24, C_UIBG
        ; (falls on)
!zone tb_swatches
tb_swatches
        lda #VR_TB
        sta f_hb
        +rect 3, TBTOP, 18, 16, C_WHITE         ; the current colour: a white frame, then the colour
        lda col
        bne .c1
        lda #C_BLACK
.c1     sta f_c
        lda #4
        sta f_x
        lda #0
        sta f_x+1
        lda #TBTOP+1
        sta f_y
        lda #0
        sta f_y+1
        lda #16
        sta f_w
        lda #14
        sta f_h
        lda #0
        sta f_w+1
        sta f_h+1
        jsr fillrect
        lda #0                  ; the 32 colours of the window, two rows of 16, 8 x 8 each
        sta sidx
.s      lda sidx
        and #15
        asl
        asl
        asl
        clc
        adc #24
        sta f_x
        lda #0
        sta f_x+1
        lda sidx
        and #16
        lsr
        clc
        adc #TBTOP
        sta f_y
        lda #0
        sta f_y+1
        sta f_w+1
        sta f_h+1
        lda palwin
        clc
        adc sidx
        sta scol
        bne .nz
        lda #C_BLACK
.nz     sta f_c
        lda scol
        cmp col
        bne .plain
        lda #8                  ; the current one: a white frame round it
        sta f_w
        sta f_h
        lda f_c
        pha
        lda #C_WHITE
        sta f_c
        jsr fillrect
        pla
        sta f_c
        inc f_x
        inc f_y
        lda #6
        sta f_w
        sta f_h
        jsr fillrect
        jmp .nx
.plain  lda #8
        sta f_w
        sta f_h
        jsr fillrect
.nx     inc sidx
        lda sidx
        cmp #32
        beq .sd
        jmp .s
.sd     rts

; ================================================================================================ the text on the toolbar
!zone ui_all
ui_all  lda #3
        sta uidirty
        rts

!zone ui_mark
ui_mark lda #1                  ; text only
        ora uidirty
        sta uidirty
        rts
!zone ui_sw
ui_sw   lda #3
        sta uidirty
        rts

!zone ui_update
ui_update
        lda msgt
        beq .nm
        dec msgt
        bne .nm
        lda #1
        ora uidirty
        sta uidirty
.nm     lda uidirty
        beq .d
        lda flags
        and #1
        beq .nb
        lda uidirty
        and #2
        beq .t
        jsr tb_swatches
.t      jsr ui_text
.nb     lda #0
        sta uidirty
.d      lda flags
        and #2
        beq .r
        jsr dbg_draw
.r      rts

!zone ui_text
ui_text lda #15
        sta tcol
        ldx #20                 ; row 22: TOOL <name>
        ldy #22
        jsr txtpos
        ldx #20
        jsr fillsp
        ldx #20
        ldy #22
        jsr txtpos
        +puts s_tool
        lda #7
        sta tcol
        lda tool
        tax
        lda flags
        and #$10
        beq .tn
        cpx #T_RECT
        beq .tf
        cpx #T_CIRCLE
        bne .tn
.tf     inx
        inx
        inx
.tn     lda tnlo,x
        sta str
        lda tnhi,x
        sta str+1
        jsr puts
        lda #15                 ; row 23: BRUSH n  ZOOM nX
        sta tcol
        ldx #20
        ldy #23
        jsr txtpos
        ldx #20
        jsr fillsp
        ldx #20
        ldy #23
        jsr txtpos
        +puts s_brush
        lda #7
        sta tcol
        +dec8 bsize
        ldx #0
        jsr prdec
        lda #15
        sta tcol
        +puts s_zoom
        lda #7
        sta tcol
        lda #1
        ldx zsh
        beq .z
.zs     asl
        dex
        bne .zs
.z      sta nv
        lda #0
        sta nv+1
        sta nv+2
        ldx #0
        jsr prdec
        lda #24                 ; X
        jsr putc
        lda msgt                ; row 24: the colour number and the keys (unless a message is up)
        bne .r
        lda #15
        sta tcol
        ldx #0
        ldy #24
        jsr txtpos
        ldx #40
        jsr fillsp
        ldx #0
        ldy #24
        jsr txtpos
        lda #1
        sta tcol
        +dec8 col
        ldx #3
        jsr prdec
        lda #15
        sta tcol
        +puts s_keys
.r      rts

; a message on row 24 (X / Y = the string's address) for about 3 seconds
!zone msg
msg     stx str
        sty str+1
        lda #1
        sta tcol
        ldx #0
        ldy #24
        jsr txtpos
        ldx #40
        jsr fillsp
        ldx #0
        ldy #24
        jsr txtpos
        jsr puts
        lda #150
        sta msgt
        rts

; clear rows 22-24 (the toolbar hidden)
!zone tb_notext
tb_notext
        lda #22
        sta sidx
.r      ldy sidx
        ldx #0
        jsr txtpos
        ldx #40
        jsr fillsp
        inc sidx
        lda sidx
        cmp #25
        bne .r
        rts

; ask Y/N on row 24 (X / Y = the question): C set = yes
!zone askyn
askyn   jsr msg
.w      jsr waitkey
        cmp #25                 ; Y
        beq .y
        cmp #39                 ; N
        beq .n
        cmp #63                 ; RUN/STOP
        bne .w
.n      lda #1
        sta msgt
        clc
        rts
.y      lda #1
        sta msgt
        sec
        rts

; ================================================================================================ the keys
; (column * 8 + row, handler - 1): see the key matrix in docs/OCTOPAINT.md
!macro cmd .c, .r, .h { !byte .c*8+.r : !word .h-1 }
!zone cmdtab
cmdtab  +cmd 5,1, c_pencil              ; P
        +cmd 3,4, c_brush               ; B
        +cmd 7,0, c_s1                  ; 1
        +cmd 7,3, c_s2                  ; 2
        +cmd 1,0, c_s4                  ; 3
        +cmd 1,3, c_s8                  ; 4
        +cmd 5,2, c_line                ; L
        +cmd 2,1, c_rect                ; R
        +cmd 2,4, c_circle              ; C
        +cmd 2,5, c_fill                ; F
        +cmd 4,5, c_pick                ; K
        +cmd 5,0, c_colup               ; +
        +cmd 5,3, c_coldn               ; -
        +cmd 5,7, c_palleft             ; , (SHIFT: <)
        +cmd 5,4, c_palright            ; . (SHIFT: >)
        +cmd 1,6, c_edit                ; E
        +cmd 3,6, c_undo                ; U
        +cmd 1,4, c_zoom                ; Z
        +cmd 7,1, c_bar                 ; <- (TAB)
        +cmd 7,2, c_bar                 ; CTRL (TAB)
        +cmd 4,7, c_new                 ; N
        +cmd 1,5, c_save                ; S
        +cmd 4,6, c_open                ; O
        +cmd 4,1, c_import              ; I
        +cmd 3,5, c_help                ; H
        +cmd 2,2, c_debug               ; D
        +cmd 0,3, c_quit                ; F7
        +cmd 4,4, c_mouse               ; M
        !byte $ff

!zone keycmds
keycmds ldx #0
.c      lda kn,x
        sta kcur
        beq .n
        stx kx
        ldy #0
.b      lsr kcur
        bcc .nb
        sty ky
        lda kx
        asl
        asl
        asl
        clc
        adc ky
        jsr dispatch
        ldx kx
        ldy ky
.nb     iny
        cpy #8
        bne .b
.n      inx
        cpx #8
        bne .c
        rts

!zone dispatch
dispatch
        sta t0
        ldy #0
.f      lda cmdtab,y
        cmp #$ff
        beq .r
        cmp t0
        beq .g
        iny
        iny
        iny
        bne .f
.r      rts
.g      lda cmdtab+2,y
        pha
        lda cmdtab+1,y
        pha
        rts                     ; (jumps to the handler, which returns to keycmds)

!zone c_pencil
c_pencil
        lda #T_PENCIL
        jmp settool
!zone c_brush
c_brush lda #T_BRUSH
        jmp settool
!zone c_line
c_line  lda #T_LINE
        jmp settool
!zone c_fill
c_fill  lda #T_FILL
        jmp settool
!zone c_rect
c_rect  lda kshift
        jsr setfill
        lda #T_RECT
        jmp settool
!zone c_circle
c_circle
        lda kshift
        jsr setfill
        lda #T_CIRCLE
        jmp settool
!zone setfill
setfill lda flags
        and #$ef
        ldx kshift
        beq .s
        ora #$10
.s      sta flags
        rts
!zone settool
settool sta tool
        jmp ui_mark

!zone c_s1
c_s1    lda #1
        bne setsize
!zone c_s2
c_s2    lda #2
        bne setsize
!zone c_s4
c_s4    lda #4
        bne setsize
!zone c_s8
c_s8    lda #8
!zone setsize
setsize sta bsize
        lda tool                ; a number key means a brush
        bne .s
        lda #T_BRUSH
        sta tool
.s      jmp ui_mark

!zone c_colup
c_colup lda col
        clc
        adc #1
        jmp setcol
!zone c_coldn
c_coldn lda col
        sec
        sbc #1
!zone setcol
setcol  sta col
        and #$e0
        sta palwin
        jmp ui_sw
!zone c_palleft
c_palleft
        lda kshift
        beq .r
        lda palwin
        sec
        sbc #32
        sta palwin
        jmp ui_sw
.r      rts
!zone c_palright
c_palright
        lda kshift
        beq .r
        lda palwin
        clc
        adc #32
        sta palwin
        jmp ui_sw
.r      rts

!zone c_bar
c_bar   lda flags
        eor #1
        sta flags
        and #1
        beq .hide
        lda #$1b
        sta L1
        jmp ui_all
.hide   lda #0
        sta L1
        jmp tb_notext

!zone c_mouse
c_mouse lda flags
        eor #4
        sta flags
        lda #1
        sta mfirst
        ldx #<m_mouse
        ldy #>m_mouse
        lda flags
        and #4
        bne .on
        ldx #<m_mouseoff
        ldy #>m_mouseoff
.on     jmp msg

!zone c_quit
c_quit  ldx #<m_quit
        ldy #>m_quit
        jsr askyn
        bcc .n
        jmp quit
.n      rts

; ---- not yet: (replaced step by step)
!zone c_edit
c_edit
!zone c_zoom
c_zoom
!zone c_new
c_new
!zone c_save
c_save
!zone c_open
c_open
!zone c_import
c_import
!zone c_help
c_help
!zone c_debug
c_debug
!zone dbg_draw
dbg_draw
        rts

; ================================================================================================ data
!zone rowlo
rowlo   !for r, 0, 24 { !byte <(r*40) }
!zone rowhi
rowhi   !for r, 0, 24 { !byte >(r*40) }
!zone axlim
axlim   !word CW, CH
!zone vmaxt
vmaxt   !byte 0,0, 160,100, 240,150         ; per zoom: the view's largest x, y origin
!zone pw0
pw0     !byte <10000, <1000, <100, <10, <1
!zone pw1
pw1     !byte >10000, >1000, >100, >10, >1

!zone tnlo
tnlo    !byte <tn0, <tn1, <tn2, <tn3, <tn4, <tn5, <tn6, <tn7
!zone tnhi
tnhi    !byte >tn0, >tn1, >tn2, >tn3, >tn4, >tn5, >tn6, >tn7
!zone tn0
tn0     !scr "pencil", $ff
!zone tn1
tn1     !scr "brush", $ff
!zone tn2
tn2     !scr "line", $ff
!zone tn3
tn3     !scr "rect", $ff
!zone tn4
tn4     !scr "circle", $ff
!zone tn5
tn5     !scr "flood fill", $ff
!zone tn6
tn6     !scr "rect filled", $ff
!zone tn7
tn7     !scr "circle filled", $ff
!zone s_tool
s_tool  !scr "tool ", $ff
!zone s_brush
s_brush !scr "brush ", $ff
!zone s_zoom
s_zoom  !scr "  zoom ", $ff
!zone s_keys
s_keys  !scr " h help  ", $1f, " bar  f7 quit", $ff
!zone m_quit
m_quit  !scr "quit? y/n", $ff
!zone m_mouse
m_mouse !scr "mouse on", $ff
!zone m_mouseoff
m_mouseoff !scr "mouse off", $ff

!source "palette.inc"

spr_arrow:
        !byte C_BLACK,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        !byte C_BLACK,C_BLACK,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        !byte C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0,0,0,0,0,0,0,0
        !byte C_BLACK,C_WHITE,C_WHITE,C_BLACK,0,0,0,0,0,0,0,0,0,0,0,0
        !byte C_BLACK,C_WHITE,C_WHITE,C_WHITE,C_BLACK,0,0,0,0,0,0,0,0,0,0,0
        !byte C_BLACK,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_BLACK,0,0,0,0,0,0,0,0,0,0
        !byte C_BLACK,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_BLACK,0,0,0,0,0,0,0,0,0
        !byte C_BLACK,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_BLACK,0,0,0,0,0,0,0,0
        !byte C_BLACK,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_BLACK,0,0,0,0,0,0,0
        !byte C_BLACK,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte C_BLACK,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_BLACK,C_BLACK,C_BLACK,C_BLACK,C_BLACK,0,0,0,0,0
        !byte C_BLACK,C_WHITE,C_WHITE,C_BLACK,C_WHITE,C_WHITE,C_BLACK,0,0,0,0,0,0,0,0,0
        !byte C_BLACK,C_WHITE,C_BLACK,0,C_BLACK,C_WHITE,C_WHITE,C_BLACK,0,0,0,0,0,0,0,0
        !byte C_BLACK,C_BLACK,0,0,C_BLACK,C_WHITE,C_WHITE,C_BLACK,0,0,0,0,0,0,0,0
        !byte C_BLACK,0,0,0,0,C_BLACK,C_WHITE,C_WHITE,C_BLACK,0,0,0,0,0,0,0
        !byte 0,0,0,0,0,C_BLACK,C_BLACK,C_BLACK,0,0,0,0,0,0,0,0
spr_cross:
        !byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte 0,C_BLACK,C_BLACK,C_BLACK,C_BLACK,C_BLACK,C_BLACK,0,0,0,C_BLACK,C_BLACK,C_BLACK,C_BLACK,C_BLACK,C_BLACK
        !byte 0,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,0,0,0,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE,C_WHITE
        !byte 0,C_BLACK,C_BLACK,C_BLACK,C_BLACK,C_BLACK,C_BLACK,0,0,0,C_BLACK,C_BLACK,C_BLACK,C_BLACK,C_BLACK,C_BLACK
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,C_BLACK,C_WHITE,C_BLACK,0,0,0,0,0,0


; ================================================================================================ the tools (main side)
; A stroke begins when a button goes down on the canvas (the picture is copied to the undo copy first), carries on while it is
; held, and ends when it is let go. The left button draws in the current colour, the right button in colour 0 (a rubber).
!zone tools
tools   lda stroke
        bne .stroke
        lda inbar               ; not drawing: a click on the toolbar?
        beq .canvas
        lda btn
        and #1
        beq .end
        lda btnp
        and #1
        bne .end
        jsr bar_click
        jmp .end
.canvas lda btn
        and #3
        beq .end
        jsr tool_press
        jmp .end
.stroke lda btn
        and #3
        bne .held
        jsr tool_release
        lda #0
        sta stroke
        sta mkon
        jmp .end
.held   jsr tool_move
.end    lda btn
        sta btnp
        rts

!zone tool_press
tool_press
        jsr save_undo
        lda #1
        sta stroke
        lda #0                  ; the right button alone: colour 0
        ldx btn
        txa
        and #1
        beq .c
        lda col
.c      sta scolr
        lda cx
        sta sx0
        sta lastx
        lda cx+1
        sta sx0+1
        sta lastx+1
        lda cy
        sta sy0
        sta lasty
        lda cy+1
        sta sy0+1
        sta lasty+1
        lda tool
        cmp #T_PENCIL
        beq .pen
        cmp #T_BRUSH
        beq .brush
        cmp #T_FILL
        beq .fill
        lda cx                  ; line, box, circle: mark where it began
        sta mkx
        lda cx+1
        sta mkx+1
        lda cy
        sta mky
        lda cy+1
        sta mky+1
        lda #1
        sta mkon
        rts
.pen    lda cx
        sta p_x
        lda cx+1
        sta p_x+1
        lda cy
        sta p_y
        lda cy+1
        sta p_y+1
        lda scolr
        sta p_col
        jmp plot
.brush  jmp stamp_last
.fill   lda #0                  ; one fill per click
        sta mkon
        jmp do_fill

!zone tool_move
tool_move
        lda tool
        cmp #T_PENCIL
        beq .pen
        cmp #T_BRUSH
        beq .brush
        rts
.moved  lda cx                  ; carry set: the pointer is on another canvas pixel than last frame
        cmp lastx
        bne .y
        lda cx+1
        cmp lastx+1
        bne .y
        lda cy
        cmp lasty
        bne .y
        lda cy+1
        cmp lasty+1
        bne .y
        clc
        rts
.y      sec
        rts
.pen    jsr .moved
        bcc .r
        lda lastx
        sta l_x0
        lda lastx+1
        sta l_x0+1
        lda lasty
        sta l_y0
        lda lasty+1
        sta l_y0+1
        lda cx
        sta l_x1
        lda cx+1
        sta l_x1+1
        lda cy
        sta l_y1
        lda cy+1
        sta l_y1+1
        lda scolr
        sta p_col
        jsr drawline
        jmp .last
.brush  jsr .moved
        bcc .r
        lda bsize
        cmp #1
        beq .pen                ; size 1 is the pencil
        jsr brushline
.last   lda cx
        sta lastx
        lda cx+1
        sta lastx+1
        lda cy
        sta lasty
        lda cy+1
        sta lasty+1
.r      rts

!zone tool_release
tool_release
        lda tool
        cmp #T_LINE
        beq .line
        cmp #T_RECT
        beq .rect
        cmp #T_CIRCLE
        beq .circ
        rts
.line   lda scolr
        sta p_col
        lda sx0
        sta l_x0
        lda sx0+1
        sta l_x0+1
        lda sy0
        sta l_y0
        lda sy0+1
        sta l_y0+1
        lda cx
        sta l_x1
        lda cx+1
        sta l_x1+1
        lda cy
        sta l_y1
        lda cy+1
        sta l_y1+1
        jmp drawline
.rect   jmp p_rect
.circ   jmp p_circle

save_undo
        ldx #VR_CAN
        ldy #VR_UNDO
        jmp hw_copy

!zone c_undo
c_undo  ldx #VR_UNDO
        ldy #VR_CAN
        jmp hw_copy

!zone c_pick
c_pick  lda inbar
        bne .r
        lda cx+1                ; (the pointer is always on the canvas, but be safe)
        sta p_x+1
        lda cx
        sta p_x
        lda cy
        sta p_y
        lda cy+1
        sta p_y+1
        jsr readpixel
        jmp setcol
.r      rts

; a click on a colour swatch on the toolbar
!zone bar_click
bar_click
        lda sy                  ; rows TBTOP..TBTOP+15, columns 24..151
        sec
        sbc #TBTOP
        cmp #16
        bcs .r
        lsr
        lsr
        lsr
        sta t4                  ; row 0 or 1
        lda sx+1
        bne .r
        lda sx
        sec
        sbc #24
        bcc .r
        cmp #128
        bcs .r
        lsr
        lsr
        lsr
        sta t5                  ; column 0-15
        lda t4
        asl
        asl
        asl
        asl
        clc
        adc t5
        clc
        adc palwin
        jmp setcol
.r      rts

; ================================================================================================ PAINT: brush, box, circle
; (these take their coordinates and colour in variables and draw through the hooks: plot, fillrect, drawline)

; the brush stamp at (lastx, lasty)
!zone stamp_last
stamp_last
        lda lastx
        sta bx
        lda lastx+1
        sta bx+1
        lda lasty
        sta by
        lda lasty+1
        sta by+1
        ; falls on into stamp
; a bsize x bsize square centred on (bx, by), in colour scolr
stamp   lda bsize
        lsr                     ; half the size
        sta t4
        sec
        lda bx
        sbc t4
        sta f_x
        lda bx+1
        sbc #0
        sta f_x+1
        sec
        lda by
        sbc t4
        sta f_y
        lda by+1
        sbc #0
        sta f_y+1
        lda bsize
        sta f_w
        sta f_h
        lda #0
        sta f_w+1
        sta f_h+1
        lda scolr
        sta f_c
        lda #VR_CAN
        sta f_hb
        jmp fillrect

!macro scmp .a, .b {            ; signed 16-bit: N set afterwards if a < b
        sec
        lda .a
        sbc .b
        lda .a+1
        sbc .b+1
        bvc .v
        eor #$80
.v
}

; Bresenham from (lastx, lasty) to (cx, cy), a stamp at every step
!zone brushline
brushline
        lda lastx
        sta bx
        lda lastx+1
        sta bx+1
        lda lasty
        sta by
        lda lasty+1
        sta by+1
        lda cx
        sta ex
        lda cx+1
        sta ex+1
        lda cy
        sta ey
        lda cy+1
        sta ey+1
        sec                     ; dx = |ex - bx|, step x = +-1
        lda ex
        sbc bx
        sta bdx
        lda ex+1
        sbc bx+1
        sta bdx+1
        bpl .xp
        lda #$ff
        sta bsx
        sec
        lda #0
        sbc bdx
        sta bdx
        lda #0
        sbc bdx+1
        sta bdx+1
        jmp .dy
.xp     lda #1
        sta bsx
.dy     sec                     ; dy = -|ey - by|, step y = +-1
        lda ey
        sbc by
        sta bdy
        lda ey+1
        sbc by+1
        sta bdy+1
        bpl .yp
        lda #$ff
        sta bsy
        jmp .e
.yp     lda #1
        sta bsy
        sec
        lda #0
        sbc bdy
        sta bdy
        lda #0
        sbc bdy+1
        sta bdy+1
.e      clc                     ; err = dx + dy
        lda bdx
        adc bdy
        sta berr
        lda bdx+1
        adc bdy+1
        sta berr+1
.loop   jsr stamp
        lda bx
        cmp ex
        bne .go
        lda bx+1
        cmp ex+1
        bne .go
        lda by
        cmp ey
        bne .go
        lda by+1
        cmp ey+1
        bne .go
        rts
.go     lda berr                ; e2 = 2 err
        asl
        sta be2
        lda berr+1
        rol
        sta be2+1
        +scmp be2, bdy          ; e2 >= dy ?
        bmi .no1
        clc                     ; err += dy, x += step
        lda berr
        adc bdy
        sta berr
        lda berr+1
        adc bdy+1
        sta berr+1
        lda bsx
        bmi .xm
        inc bx
        bne .no1
        inc bx+1
        jmp .no1
.xm     lda bx
        bne +
        dec bx+1
+       dec bx
.no1    +scmp bdx, be2          ; e2 <= dx ?
        bmi .no2
        clc                     ; err += dx, y += step
        lda berr
        adc bdx
        sta berr
        lda berr+1
        adc bdx+1
        sta berr+1
        lda bsy
        bmi .ym
        inc by
        bne .no2
        inc by+1
        jmp .no2
.ym     lda by
        bne +
        dec by+1
+       dec by
.no2    jmp .loop

; ---- a box from the press point (stx, sty) to (cx, cy): outline (4 lines) or filled (one FILL)
!zone p_rect
p_rect  lda sx0                 ; x0, x1 = the smaller, the larger
        sta bx
        lda sx0+1
        sta bx+1
        lda cx
        sta ex
        lda cx+1
        sta ex+1
        +scmp bx, ex
        bmi .xo
        lda bx
        ldx ex
        sta ex
        stx bx
        lda bx+1
        ldx ex+1
        sta ex+1
        stx bx+1
.xo     lda sy0
        sta by
        lda sy0+1
        sta by+1
        lda cy
        sta ey
        lda cy+1
        sta ey+1
        +scmp by, ey
        bmi .yo
        lda by
        ldx ey
        sta ey
        stx by
        lda by+1
        ldx ey+1
        sta ey+1
        stx by+1
.yo     lda flags
        and #$10
        beq .outl
        jmp .fill
.outl   lda scolr
        sta p_col
        ldx #0                  ; top: (bx,by)-(ex,by); right: (ex,by)-(ex,ey); bottom: (ex,ey)-(bx,ey); left: (bx,ey)-(bx,by)
        lda bx
        sta l_x0
        lda bx+1
        sta l_x0+1
        lda by
        sta l_y0
        lda by+1
        sta l_y0+1
        lda ex
        sta l_x1
        lda ex+1
        sta l_x1+1
        lda by
        sta l_y1
        lda by+1
        sta l_y1+1
        jsr drawline
        lda ex                  ; right
        sta l_x0
        lda ex+1
        sta l_x0+1
        lda ey
        sta l_y1
        lda ey+1
        sta l_y1+1
        jsr drawline
        lda ey                  ; bottom
        sta l_y0
        lda ey+1
        sta l_y0+1
        lda bx
        sta l_x1
        lda bx+1
        sta l_x1+1
        jsr drawline
        lda by                  ; left
        sta l_y1
        lda by+1
        sta l_y1+1
        lda bx
        sta l_x0
        lda bx+1
        sta l_x0+1
        jmp drawline
.fill   lda bx
        sta f_x
        lda bx+1
        sta f_x+1
        lda by
        sta f_y
        lda by+1
        sta f_y+1
        sec
        lda ex
        sbc bx
        sta f_w
        lda ex+1
        sbc bx+1
        sta f_w+1
        inc f_w
        bne +
        inc f_w+1
+       sec
        lda ey
        sbc by
        sta f_h
        lda ey+1
        sbc by+1
        sta f_h+1
        inc f_h
        bne +
        inc f_h+1
+       lda scolr
        sta f_c
        lda #VR_CAN
        sta f_hb
        jmp fillrect

; ---- a circle: centre = the press point, radius = the distance to (cx, cy), by the midpoint method
!zone p_circle
p_circle
        sec                     ; |dx|, |dy|
        lda cx
        sbc sx0
        sta t0
        lda cx+1
        sbc sx0+1
        sta t1
        bpl +
        sec
        lda #0
        sbc t0
        sta t0
        lda #0
        sbc t1
        sta t1
+       sec
        lda cy
        sbc sy0
        sta t2
        lda cy+1
        sbc sy0+1
        sta t3
        bpl +
        sec
        lda #0
        sbc t2
        sta t2
        lda #0
        sbc t3
        sta t3
+       lda t0                  ; d2 = dx*dx + dy*dy with the maths unit
        sta $d650
        sta $d652
        lda t1
        sta $d651
        sta $d653
        lda $d654
        sta d2
        lda $d655
        sta d2+1
        lda $d656
        sta d2+2
        lda t2
        sta $d650
        sta $d652
        lda t3
        sta $d651
        sta $d653
        clc
        lda $d654
        adc d2
        sta d2
        lda $d655
        adc d2+1
        sta d2+1
        lda $d656
        adc d2+2
        sta d2+2
        ; r = floor(sqrt(d2)): bit by bit, from 256 down
        lda #0
        sta cr
        sta cr+1
        lda #<256
        sta t0
        lda #>256
        sta t1
.sq     lda cr                  ; t = r | bit
        ora t0
        sta t2
        lda cr+1
        ora t1
        sta t3
        lda t2
        sta $d650
        sta $d652
        lda t3
        sta $d651
        sta $d653
        sec                     ; d2 >= t*t ?
        lda d2
        sbc $d654
        lda d2+1
        sbc $d655
        lda d2+2
        sbc $d656
        bcc .no                 ; (d2 is 24 bits: t*t < 2^24 as r < 512; the top byte of MULR is 0 then)
        lda t2
        sta cr
        lda t3
        sta cr+1
.no     lsr t1
        ror t0
        lda t0
        ora t1
        bne .sq
        ; the circle: x = 0, y = r, d = 3 - 2r
        lda #0
        sta ccx
        sta ccx+1
        lda cr
        sta ccy
        lda cr+1
        sta ccy+1
        lda cr                  ; d = 3 - 2r
        asl
        sta t0
        lda cr+1
        rol
        sta t1
        sec
        lda #3
        sbc t0
        sta cd
        lda #0
        sbc t1
        sta cd+1
.cl     +scmp ccy, ccx          ; while x <= y (stop when y < x)
        bpl .draw
        rts
.draw   jsr c_points
        inc ccx                 ; x++
        bne +
        inc ccx+1
+       lda cd+1                ; d > 0 ?
        bmi .neg
        ora cd
        beq .neg
        lda ccy                 ; y--
        bne +
        dec ccy+1
+       dec ccy
        sec                     ; d += 4 (x - y) + 10
        lda ccx
        sbc ccy
        sta t0
        lda ccx+1
        sbc ccy+1
        sta t1
        asl t0
        rol t1
        asl t0
        rol t1
        clc
        lda cd
        adc t0
        sta cd
        lda cd+1
        adc t1
        sta cd+1
        clc
        lda cd
        adc #10
        sta cd
        bcs +
        jmp .cl
+       inc cd+1
        jmp .cl
.neg    lda ccx                 ; d += 4 x + 6
        sta t0
        lda ccx+1
        sta t1
        asl t0
        rol t1
        asl t0
        rol t1
        clc
        lda cd
        adc t0
        sta cd
        lda cd+1
        adc t1
        sta cd+1
        clc
        lda cd
        adc #6
        sta cd
        bcs +
        jmp .cl
+       inc cd+1
        jmp .cl

; the eight symmetric points of the circle at (ccx, ccy): outline plots, filled spans
!zone c_points
c_points
        lda ccx
        sta ax
        lda ccx+1
        sta ax+1
        lda ccy
        sta ay
        lda ccy+1
        sta ay+1
        jsr c_four
        lda ccy
        sta ax
        lda ccy+1
        sta ax+1
        lda ccx
        sta ay
        lda ccx+1
        sta ay+1
        ; falls on

; (stx + ax, sty + ay) and its mirrors; filled: the two rows stx - ax .. stx + ax at sty +- ay
c_four  lda flags
        and #$10
        bne .fill
        lda scolr
        sta p_col
        ; outline: four plots
        jsr c_p1                ; (+, +)
        jsr c_negax
        jsr c_p1                ; (-, +)
        jsr c_negay
        jsr c_p1                ; (-, -)
        jsr c_negax
        jsr c_p1                ; (+, -)
        jsr c_negay             ; (restore)
        rts
.fill   lda scolr
        sta f_c
        lda #VR_CAN
        sta f_hb
        ; row sty + ay
        sec
        lda sx0
        sbc ax
        sta f_x
        lda sx0+1
        sbc ax+1
        sta f_x+1
        lda ax
        asl
        sta f_w
        lda ax+1
        rol
        sta f_w+1
        inc f_w
        bne +
        inc f_w+1
+       lda #1
        sta f_h
        lda #0
        sta f_h+1
        clc
        lda sy0
        adc ay
        sta f_y
        lda sy0+1
        adc ay+1
        sta f_y+1
        jsr fillrect
        sec                     ; row sty - ay
        lda sx0
        sbc ax
        sta f_x
        lda sx0+1
        sbc ax+1
        sta f_x+1
        lda ax
        asl
        sta f_w
        lda ax+1
        rol
        sta f_w+1
        inc f_w
        bne +
        inc f_w+1
+       lda #1
        sta f_h
        lda #0
        sta f_h+1
        sec
        lda sy0
        sbc ay
        sta f_y
        lda sy0+1
        sbc ay+1
        sta f_y+1
        jmp fillrect

; plot (stx + ax, sty + ay)
c_p1    clc
        lda sx0
        adc ax
        sta p_x
        lda sx0+1
        adc ax+1
        sta p_x+1
        clc
        lda sy0
        adc ay
        sta p_y
        lda sy0+1
        adc ay+1
        sta p_y+1
        jmp plot
c_negax sec
        lda #0
        sbc ax
        sta ax
        lda #0
        sbc ax+1
        sta ax+1
        rts
c_negay sec
        lda #0
        sbc ay
        sta ay
        lda #0
        sbc ay+1
        sta ay+1
        rts

; the flood fill (a later step)
do_fill rts

; ================================================================================================ variables (zero at start)
!zone f_x
f_x     !fill 2                 ; fillrect: x, y, width, height (in this order)
!zone f_y
f_y     !fill 2
!zone f_w
f_w     !fill 2
!zone f_h
f_h     !fill 2
!zone f_c
f_c     !fill 1
!zone f_hb
f_hb    !fill 1
!zone f_lim
f_lim   !fill 2
!zone l_x0
l_x0    !fill 2                 ; drawline: (x0, y0) - (x1, y1)
!zone l_y0
l_y0    !fill 2
!zone l_x1
l_x1    !fill 2
!zone l_y1
l_y1    !fill 2
!zone p_x
p_x     !fill 2                 ; plot / readpixel
!zone p_y
p_y     !fill 2
!zone p_col
p_col   !fill 1
!zone kb
kb      !fill 8
!zone kn
kn      !fill 8
!zone kbp
kbp     !fill 8
!zone kcur
kcur    !fill 1
!zone joy1
joy1    !fill 1
!zone joy2
joy2    !fill 1
!zone jm
jm      !fill 1
!zone kd
kd      !fill 1
!zone mright
mright  !fill 1
!zone ftime
ftime   !fill 1
!zone kheld
kheld   !fill 1
!zone mfirst
mfirst  !fill 1
!zone minit
minit   !fill 1
!zone moldx
moldx   !fill 1
!zone moldy
moldy   !fill 1
!zone inbar
inbar   !fill 1
!zone mkx
mkx     !fill 2                 ; where a line / box / circle began (canvas pixel)
!zone mky
mky     !fill 2
!zone mkon
mkon    !fill 1
!zone sidx
sidx    !fill 1
!zone scol
scol    !fill 1
!zone nv
nv      !fill 3
!zone pwid
pwid    !fill 1
!zone pstart
pstart  !fill 1
!zone pdig
pdig    !fill 1
!zone ptmp
ptmp    !fill 1
!zone dcomma
dcomma  !fill 1
stroke  !fill 1
scolr   !fill 1
sx0     !fill 2
sy0     !fill 2
lastx   !fill 2
lasty   !fill 2
bx      !fill 2
by      !fill 2
ex      !fill 2
ey      !fill 2
bdx     !fill 2
bdy     !fill 2
berr    !fill 2
be2     !fill 2
bsx     !fill 1
bsy     !fill 1
d2      !fill 3
cr      !fill 2
ccx     !fill 2
ccy     !fill 2
cd      !fill 2
ax      !fill 2
ay      !fill 2
progend
