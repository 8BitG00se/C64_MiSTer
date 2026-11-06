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

BUILD   = 1             ; the build number (1-9): on the help page and at start; build.sh reads it

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
TPAL    = $C400         ; a loaded picture's palette waits here until the file is known to be good
TOPFREE = $A000         ; (the fill stack and the packer's buffer begin here)
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
sptr    = $69           ; 2  Koala import: screen / colour / bitmap pointers
cptr    = $6B           ; 2
bptr    = $6D           ; 2

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
        ldx #<m_title
        ldy #>m_title
        jsr msg
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
        inc frames
        bne .f
        inc frames+1
.f      jmp $ea81

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

; ptr = the address of palette entry A in PAL (3 * A + PAL)
!zone palptr
palptr  sta t0
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
        rts

; one palette entry (A = its number) from PAL to OctoVIC
!zone pal_set1
pal_set1
        pha
        lda #0
        sta PALSEL
        pla
        pha
        sta PALIDX
        jsr palptr
        ldy #0
        lda (ptr),y
        sta PALR
        iny
        lda (ptr),y
        sta PALG
        iny
        lda (ptr),y
        sta PALB
        pla
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

; wait until RETURN is up (it closed a prompt: it must not go on as the pen going down)
!zone relret
relret  jsr waittick
        jsr kscan
        lda kb+0
        and #2
        bne relret
        lda #$7f
        sta $dc00
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



; ================================================================================================ colour edit (E)
; R, G, B of the current colour: Q/A, W/S, E/D up / down by 4 (SHIFT: 1), live on the swatch; RETURN keeps, RUN/STOP puts it back
!zone c_edit
c_edit  lda col
        jsr palptr
        ldy #2
.sv     lda (ptr),y
        sta eorig,y
        dey
        bpl .sv
        lda #0
        sta erep
        jsr edit_show
.w      jsr waittick
        jsr kscan
        lda kn+0
        and #2                  ; RETURN: keep
        beq .nr
        jmp .keep
.nr     lda kn+7
        and #$80                ; RUN/STOP: back
        beq .ns
        jmp .back
.ns     lda #0                  ; which keys are held: b0 R+ b1 R- b2 G+ b3 G- b4 B+ b5 B-
        sta eh
        lda kb+7
        and #$40                ; Q
        beq .a
        lda #1
        ora eh
        sta eh
.a      lda kb+1
        and #4                  ; A
        beq .b
        lda #2
        ora eh
        sta eh
.b      lda kb+1
        and #2                  ; W
        beq .c
        lda #4
        ora eh
        sta eh
.c      lda kb+1
        and #$20                ; S
        beq .d
        lda #8
        ora eh
        sta eh
.d      lda kb+1
        and #$40                ; E
        beq .e
        lda #$10
        ora eh
        sta eh
.e      lda kb+2
        and #4                  ; D
        beq .f
        lda #$20
        ora eh
        sta eh
.f      lda eh
        bne .held
        lda #0
        sta erep
        jmp .w
.held   lda erep                ; act on the press, then after a pause every other frame
        beq .act
        cmp #12
        bcc .wait
        and #1
        bne .wait
.act    lda #4
        ldx kshift
        beq .st
        lda #1
.st     sta estep
        lda col
        jsr palptr
        ldx #0                  ; component 0, 1, 2
.cmp    lsr eh                  ; + ?
        bcc .nplus
        ldy ecomp,x
        jsr edit_add
.nplus  lsr eh                  ; - ?
        bcc .nminus
        jsr edit_sub
.nminus inx
        cpx #3
        bne .cmp
        lda col
        jsr pal_set1
        jsr edit_show
.wait   lda erep
        cmp #200
        bcs .j
        inc erep
.j      jmp .w
.back   lda col
        jsr palptr
        ldy #2
.rs     lda eorig,y
        sta (ptr),y
        dey
        bpl .rs
        lda col
        jsr pal_set1
.keep   jsr relret
        jsr kclear
        lda #0
        sta msgt
        jmp ui_all

; component X (0-2) up / down by estep, clamped
!zone edit_add
edit_add
        txa
        tay
        lda (ptr),y
        clc
        adc estep
        bcc .ok
        lda #255
.ok     sta (ptr),y
        rts
!zone edit_sub
edit_sub
        txa
        tay
        lda (ptr),y
        sec
        sbc estep
        bcs .ok
        lda #0
.ok     sta (ptr),y
        rts

!zone edit_show
edit_show
        lda col
        jsr palptr
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
        lda #18                 ; R
        jsr putc
        ldy #0
        jsr .num
        lda #7                  ; G
        jsr putc
        ldy #1
        jsr .num
        lda #2                  ; B
        jsr putc
        ldy #2
        jsr .num
        lda #15
        sta tcol
        +puts s_editkeys
        rts
.num    lda (ptr),y
        sta nv
        lda #0
        sta nv+1
        sta nv+2
        lda #1
        sta tcol
        ldx #3
        jsr prdec
        lda #15
        sta tcol
        lda #32
        jmp putc

!zone ecomp
ecomp   !byte 0,1,2
!zone s_editkeys
s_editkeys !scr " ret keep  stop back", $ff


; ================================================================================================ zoom (Z)
; 1x -> 2x -> 4x -> 1x, keeping the canvas pixel under the pointer where it is (clamped to the picture)
!zone c_zoom
c_zoom  lda zsh
        cmp #2
        bne .u
        lda #$ff
.u      clc
        adc #1
        sta zsh
        ldx #0
        jsr vset
        ldx #2
        jsr vset
        ldx #0
        jsr cpos
        ldx #2
        jsr cpos
        jmp ui_mark

; view origin on axis X = the canvas pixel there - the pointer / zoom, within 0 .. vmax
!zone vset
vset    lda sx,x
        sta t0
        lda sx+1,x
        sta t1
        ldy zsh
        beq .s
.l      lsr t1
        ror t0
        dey
        bne .l
.s      sec
        lda cx,x
        sbc t0
        sta vx,x
        lda cx+1,x
        sbc t1
        sta vx+1,x
        bmi .zero
        jsr vmax
        lda t2
        cmp vx,x
        lda t3
        sbc vx+1,x
        bcs .ok
        lda t2
        sta vx,x
        lda t3
        sta vx+1,x
.ok     rts
.zero   lda #0
        sta vx,x
        sta vx+1,x
        rts


; ================================================================================================ PAINT: flood fill (F)
; Scanline fill, 4-way, same colour: a stack of seeds in C64 RAM (at most 1024), the row being filled read through VDATA
; into RAM, runs written with the blitter's FILL. A seed is popped, its row read, the run of target-coloured pixels round it
; found and filled, and the rows above and below that run scanned for runs to seed. If the stack fills: FILL TOO BIG.
!zone do_fill
do_fill lda cx
        sta p_x
        lda cx+1
        sta p_x+1
        lda cy
        sta p_y
        lda cy+1
        sta p_y+1
        jsr readpixel
        sta tgt
        cmp scolr
        bne .go
        rts                     ; already that colour
.go     lda #0
        sta fsp
        sta fsp+1
        sta fover
        lda frames
        sta fstart
        lda frames+1
        sta fstart+1
        lda cx
        sta qx
        lda cx+1
        sta qx+1
        lda cy
        sta qy
        jsr push
.loop   lda fsp
        ora fsp+1
        bne .more
        jmp .done
.more   jsr pop
        lda qx                  ; still the target colour?
        sta p_x
        lda qx+1
        sta p_x+1
        lda qy
        sta p_y
        lda #0
        sta p_y+1
        jsr readpixel
        cmp tgt
        bne .loop
        jsr readrow             ; the whole row into ROWBUF
        lda tgt                 ; end stops: a byte that is never the target, either side of the row
        eor #1
        sta ROWBUF-1
        sta ROWBUF+CW
        clc                     ; ptr and ptr2 = ROWBUF + qx
        lda qx
        adc #<ROWBUF
        sta ptr2
        sta ptr
        lda qx+1
        adc #>ROWBUF
        sta ptr2+1
        sta ptr+1
        ldy #0
.left   lda ptr2                ; extend left
        bne .l1
        dec ptr2+1
.l1     dec ptr2
        lda (ptr2),y
        cmp tgt
        beq .left
        sec                     ; xl = (first non-target) + 1
        lda ptr2
        sbc #<(ROWBUF-1)
        sta xl
        lda ptr2+1
        sbc #>(ROWBUF-1)
        sta xl+1
.right  inc ptr                 ; extend right
        bne .r1
        inc ptr+1
.r1     lda (ptr),y
        cmp tgt
        beq .right
        sec                     ; xr = (first non-target) - 1
        lda ptr
        sbc #<(ROWBUF+1)
        sta xr
        lda ptr+1
        sbc #>(ROWBUF+1)
        sta xr+1
.rend   lda xl                  ; fill the run: one row
        sta f_x
        lda xl+1
        sta f_x+1
        lda qy
        sta f_y
        lda #0
        sta f_y+1
        sec
        lda xr
        sbc xl
        sta f_w
        lda xr+1
        sbc xl+1
        sta f_w+1
        inc f_w
        bne .w1
        inc f_w+1
.w1     lda #1
        sta f_h
        lda #0
        sta f_h+1
        lda scolr
        sta f_c
        lda #VR_CAN
        sta f_hb
        jsr fillrect
        lda qy                  ; the row above
        beq .noup
        sec
        sbc #1
        sta ny
        jsr scanrow
.noup   lda qy                  ; the row below
        cmp #CH-1
        bcs .nodn
        clc
        adc #1
        sta ny
        jsr scanrow
.nodn   lda fover
        bne .over
        jmp .loop
.over   ldx #<m_fillbig
        ldy #>m_fillbig
        jsr msg
        rts
.done   sec                     ; how long it took, in frames
        lda frames
        sbc fstart
        sta fillt
        lda frames+1
        sbc fstart+1
        sta fillt+1
        lda #1                  ; FILLED IN n FRAMES on row 24
        sta tcol
        ldx #0
        ldy #24
        jsr txtpos
        ldx #40
        jsr fillsp
        ldx #0
        ldy #24
        jsr txtpos
        +puts s_filled
        lda fillt
        sta nv
        lda fillt+1
        sta nv+1
        lda #0
        sta nv+2
        ldx #0
        jsr prdec
        +puts s_frames
        lda #150
        sta msgt
        rts

; the row ny, columns xl..xr, read straight from VDATA: seed every run of target-coloured pixels
!zone scanrow
scanrow lda qy
        sta sqy
        lda ny
        sta qy
        lda xl
        sta p_x
        sta qx
        lda xl+1
        sta p_x+1
        sta qx+1
        lda ny
        sta p_y
        lda #0
        sta p_y+1
        clc
        lda xr
        adc #1
        sta qe
        lda xr+1
        adc #0
        sta qe+1
        jsr vaddr_xy
        jsr vwait
        ldx #0                  ; X = 1 inside a run
.l      lda VDATA
        cmp tgt
        beq .hit
        ldx #0
.nx     inc qx
        bne .c
        inc qx+1
.c      lda qx
        cmp qe
        bne .l
        lda qx+1
        cmp qe+1
        bne .l
        lda sqy
        sta qy
        rts
.hit    cpx #0
        bne .nx
        ldx #1
        jsr push                ; push keeps X
        jmp .nx

; push (qx, qy); pop -> (qx, qy)
!zone push
push    lda fsp+1
        cmp #>STKMAX
        bcc .ok
        lda #1
        sta fover
        rts
.ok     clc
        adc #>STK_XL
        sta ptr2+1
        lda #0
        sta ptr2
        ldy fsp
        lda qx
        sta (ptr2),y
        lda fsp+1
        clc
        adc #>STK_XH
        sta ptr2+1
        lda qx+1
        sta (ptr2),y
        lda fsp+1
        clc
        adc #>STK_Y
        sta ptr2+1
        lda qy
        sta (ptr2),y
        inc fsp
        bne .r
        inc fsp+1
.r      rts

!zone pop
pop     lda fsp
        bne .a
        dec fsp+1
.a      dec fsp
        lda fsp+1
        clc
        adc #>STK_XL
        sta ptr2+1
        lda #0
        sta ptr2
        ldy fsp
        lda (ptr2),y
        sta qx
        lda fsp+1
        clc
        adc #>STK_XH
        sta ptr2+1
        lda (ptr2),y
        sta qx+1
        lda fsp+1
        clc
        adc #>STK_Y
        sta ptr2+1
        lda (ptr2),y
        sta qy
        rts

; ---- the read hooks (platform): a row, or a stretch of one, from the canvas into RAM through VDATA
; readrow: row p_y -> ROWBUF (320 bytes)
!zone readrow
readrow lda #0
        sta p_x
        sta p_x+1
        jsr vaddr_xy
        jsr vwait
        lda #<ROWBUF
        sta ptr2
        lda #>ROWBUF
        sta ptr2+1
        ldy #0
.a      lda VDATA
        sta (ptr2),y
        nop
        nop
        nop
        iny
        bne .a
        inc ptr2+1
.b      lda VDATA
        sta (ptr2),y
        nop
        nop
        nop
        iny
        cpy #CW-256
        bne .b
        rts

; readseg: scnt pixels from (p_x, p_y) -> NBUF
!zone readseg
readseg jsr vaddr_xy
        jsr vwait
        lda #<NBUF
        sta ptr2
        lda #>NBUF
        sta ptr2+1
        ldy #0
.l      lda VDATA
        sta (ptr2),y
        nop
        nop
        iny
        bne .n
        inc ptr2+1
.n      lda scnt
        bne .d
        dec scnt+1
.d      dec scnt
        lda scnt
        ora scnt+1
        bne .l
        rts

!zone m_fillbig
m_fillbig !scr "fill too big", $ff
s_filled !scr "filled in ", $ff
s_frames !scr " frames", $ff

; ================================================================================================ FILES (.OCT), new, debug
; Disk I/O is through the KERNAL (device 8, SEQ files), with the raster interrupt off while the drive is busy. The picture is
; never held in C64 RAM: it goes to and from the canvas through VDATA, packed / unpacked on the way (see docs/OCTOPAINT.md).

!macro dec16 .v { lda .v : sta nv : lda .v+1 : sta nv+1 : lda #0 : sta nv+2 }

; row 24 cleared, text position at its start (the message is put with puts / prdec / putc, then msg_end)
!zone msg_begin
msg_begin
        lda #1
        sta tcol
        ldx #0
        ldy #24
        jsr txtpos
        ldx #40
        jsr fillsp
        ldx #0
        ldy #24
        jmp txtpos

!zone msg_end
msg_end lda #150
        sta msgt
        rts

; the name prompt: X / Y = the prompt text. C set = a name is in fname (flen letters), C clear = cancelled.
; letters, digits, space, - and . ; DEL rubs out, RETURN accepts, RUN/STOP cancels
!zone askname
askname stx apr
        sty apr+1
.draw   jsr msg_begin
        lda apr
        sta str
        lda apr+1
        sta str+1
        jsr puts
        lda #7
        sta tcol
        ldx #0
.pn     cpx flen
        beq .pd
        lda fname,x
        stx ni
        jsr putc
        ldx ni
        inx
        bne .pn
.pd     lda #160                ; the cursor: a block
        jsr putc
.k      jsr waitkey
        cmp #63                 ; RUN/STOP
        beq .cancel
        cmp #1                  ; RETURN
        beq .ret
        cmp #0                  ; DEL
        beq .del
        tax
        lda keychr,x
        beq .k
        ldy flen
        cpy #12
        bcs .k
        sta fname,y
        inc flen
        jmp .draw
.del    lda flen
        beq .k
        dec flen
        jmp .draw
.ret    lda flen
        beq .k
        jsr relret
        lda #1
        sta msgt
        sec
        rts
.cancel lda #1
        sta msgt
        clc
        rts

; fname -> pbuf (PETSCII) + ".OCT" unless it already ends with that; plen = its length
!zone mkname
mkname  ldx #0
.c      cpx flen
        beq .e
        lda fname,x
        cmp #27
        bcs .p
        ora #$40
.p      sta pbuf,x
        inx
        bne .c
.e      stx plen
        cpx #4
        bcc .add
        txa
        sec
        sbc #4
        tax
        ldy #0
.cmp    lda pbuf,x
        cmp s_oct,y
        bne .add
        inx
        iny
        cpy #4
        bne .cmp
        rts
.add    ldx plen
        ldy #0
.a      lda s_oct,y
        sta pbuf,x
        inx
        iny
        cpy #4
        bne .a
        stx plen
        rts

; the file name on row 24 (screen codes)
!zone show_name
show_name
        ldx #0
.l      cpx plen
        beq .r
        lda pbuf,x
        cmp #$41
        bcc .p
        cmp #$5b
        bcs .p
        sec
        sbc #$40
.p      stx ni
        jsr putc
        ldx ni
        inx
        bne .l
.r      rts

; the command / file name builder: cbuf, clen
!zone cb_reset
cb_reset
        lda #0
        sta clen
        rts
!zone cb_add
cb_add  ldx clen
        sta cbuf,x
        inc clen
        rts
!zone cb_pb
cb_pb   ldy #0
.l      cpy plen
        beq .r
        lda pbuf,y
        jsr cb_add
        iny
        bne .l
.r      rts
!zone cb_str
cb_str  stx ptr
        sty ptr+1
        ldy #0
.l      lda (ptr),y
        cmp #$ff
        beq .r
        jsr cb_add
        iny
        bne .l
.r      rts
!zone setnm_cb
setnm_cb
        lda clen
        ldx #<cbuf
        ldy #>cbuf
        jmp SETNAM

; the drive's message into ebuf; A = 0 if it starts "00"
!zone rderr
rderr   ldx #15
        jsr CHKIN
        bcc .ok
        lda #0
        sta elen
        lda #1
        rts
.ok     lda #0
        sta elen
        sta ni
.l      inc ni
        beq .e
        jsr CHRIN
        cmp #13
        beq .e
        ldy elen
        cpy #38
        bcs .l
        sta ebuf,y
        inc elen
        jmp .l
.e      jsr CLRCHN
        lda elen
        cmp #2
        bcc .bad
        lda ebuf
        cmp #$30
        bne .bad
        lda ebuf+1
        cmp #$30
        bne .bad
        lda #0
        rts
.bad    lda #1
        rts

; both files closed, the default channels back
!zone io_fin
io_fin  jsr CLRCHN
        lda #2
        jsr CLOSE
        lda #15
        jsr CLOSE
        rts

!zone io_begin
io_begin
        lda #0
        sta $d01a               ; no raster interrupt while the drive is busy
        lda #$ff
        sta $d019
        lda #0
        sta ioerr
        sta bcnt
        sta bcnt+1
        sta bcnt+2
        sta pacc
        sta pcell
        rts

!zone io_end
io_end  lda #$ff
        sta $d019
        lda #1
        sta $d01a
        lda #$7f
        sta $dc00
        jsr kclear
        jsr bar_clear
        jmp ui_all

; the progress bar: VIC row 21, 40 cells
!zone bar_clear
bar_clear
        lda #1
        sta tcol
        ldx #0
        ldy #21
        jsr txtpos
        ldx #40
        jmp fillsp

; one more row of 200 done: every 5 rows one more cell
!zone barstep
barstep lda pacc
        clc
        adc #40
.p      cmp #200
        bcc .d
        sbc #200
        sta pacc
        ldx pcell
        lda #160
        sta SCREEN+21*40,x
        lda #7
        sta COLRAM+21*40,x
        inc pcell
        lda pacc
        jmp .p
.d      sta pacc
        rts

!zone diskask
diskask ldx #<m_disk
        ldy #>m_disk
        jmp askyn

; ---- the run-length packer (see mkoct.py: the same rule). A = the next pixel byte.
!zone rlein
rlein   ldx rcnt
        beq .new
        cmp rbyte
        bne .brk
        cpx #130
        bcs .brk
        inc rcnt
        rts
.brk    pha
        jsr endrun
        pla
.new    sta rbyte
        lda #1
        sta rcnt
        rts

!zone endrun
endrun  lda rcnt
        cmp #3
        bcc .lit
        jsr flushlit
        lda rcnt
        clc
        adc #125                ; 128 + n - 3
        jsr outb
        lda rbyte
        jmp outb
.lit    ldy lcnt
        lda rbyte
        sta LITBUF,y
        iny
        sty lcnt
        cpy #128
        bne .n
        jsr flushlit
.n      dec rcnt
        bne .lit
        rts

!zone flushlit
flushlit
        lda lcnt
        beq .r
        sec
        sbc #1
        jsr outb
        lda #0
        sta li
.b      ldy li
        lda LITBUF,y
        jsr outb
        inc li
        lda li
        cmp lcnt
        bne .b
        lda #0
        sta lcnt
.r      rts

!zone outb
outb    jsr CHROUT
        inc bcnt
        bne .r
        inc bcnt+1
        bne .r
        inc bcnt+2
.r      rts

; ---- S: save
!zone c_save
c_save  ldx #<s_saveas
        ldy #>s_saveas
        jsr askname
        bcs .g
        rts
.g      jsr mkname
        jsr diskask
        bcs .y
        ldx #<m_nosave
        ldy #>m_nosave
        jmp msg
.y      jsr bar_clear
        jsr io_begin
        jsr dosave
        jsr io_end
        lda ioerr
        bne .e
        jsr msg_begin
        +puts m_saved
        jsr show_name
        jmp result_bytes
.e      jmp show_ioerr

!zone result_bytes
result_bytes
        lda #32
        jsr putc
        lda bcnt
        sta nv
        lda bcnt+1
        sta nv+1
        lda bcnt+2
        sta nv+2
        lda #1
        sta dcomma
        ldx #0
        jsr prdec
        lda #0
        sta dcomma
        +puts m_bytes
        jmp msg_end

!zone show_ioerr
show_ioerr
        jsr msg_begin
        lda ioerr
        cmp #1
        bne .n2
        lda ioacc
        cmp #5
        bne .gen
        +puts m_e5
        jmp msg_end
.gen    +puts m_e1
        lda ioacc
        sta nv
        lda #0
        sta nv+1
        sta nv+2
        ldx #0
        jsr prdec
        jmp msg_end
.n2     cmp #2
        bne .n3
        lda elen
        beq .gd
        ldx #0
.dl     cpx elen
        beq .de
        lda ebuf,x
        cmp #$41
        bcc .dp
        cmp #$5b
        bcs .dp
        sec
        sbc #$40
.dp     stx ni
        jsr putc
        ldx ni
        inx
        bne .dl
.de     jmp msg_end
.gd     +puts m_e2
        jmp msg_end
.n3     sec
        sbc #3
        asl
        tax
        lda errtab,x
        sta str
        lda errtab+1,x
        sta str+1
        jsr puts
        jmp msg_end

!zone dosave
dosave  jsr cb_reset            ; scratch the old file: S0:NAME.OCT on the command channel
        ldx #<s_scr
        ldy #>s_scr
        jsr cb_str
        jsr cb_pb
        jsr setnm_cb
        lda #15
        ldx #8
        ldy #15
        jsr SETLFS
        jsr OPEN
        bcc .o15
        jmp .eopen
.o15    jsr rderr               ; (its answer, files scratched, is not needed)
        jsr cb_reset            ; NAME.OCT,S,W
        jsr cb_pb
        ldx #<s_sw
        ldy #>s_sw
        jsr cb_str
        jsr setnm_cb
        lda #2
        ldx #8
        ldy #2
        jsr SETLFS
        jsr OPEN
        bcc .o2
        jmp .eopen
.o2     jsr rderr
        beq .o3
        lda #2
        sta ioerr
        jmp io_fin
.o3     ldx #2
        jsr CHKOUT
        bcc .w
.eopen  sta ioacc
        lda #1
        sta ioerr
        jmp io_fin
.w      ldx #0                  ; the header
.h      stx ni
        lda hdr,x
        jsr outb
        ldx ni
        inx
        cpx #10
        bne .h
        lda #<PAL               ; the palette
        sta ptr2
        lda #>PAL
        sta ptr2+1
        lda #3
        sta cnt
.pg     lda #0
        sta ni
.pb     ldy ni
        lda (ptr2),y
        jsr outb
        inc ni
        bne .pb
        inc ptr2+1
        dec cnt
        bne .pg
        lda #0                  ; the pixels, row by row, packed
        sta frow
        sta rcnt
        sta lcnt
        lda #1
        sta VINC
.row    lda #0
        sta p_x
        sta p_x+1
        sta p_y+1
        lda frow
        sta p_y
        jsr vaddr_xy
        jsr vwait
        lda #<CW
        sta ccnt
        lda #>CW
        sta ccnt+1
.px     lda VDATA
        jsr rlein
        lda ccnt
        bne .c1
        dec ccnt+1
.c1     dec ccnt
        lda ccnt
        ora ccnt+1
        bne .px
        lda $90                 ; the drive still there?
        bne .werr
        jsr barstep
        inc frow
        lda frow
        cmp #CH
        bne .row
        lda rcnt
        beq .nl
        jsr endrun
.nl     jsr flushlit
        lda $90
        bne .werr
        jsr CLRCHN
        lda #2
        jsr CLOSE
        jsr rderr               ; DISK FULL and the like show up here
        beq .done
        lda #2
        sta ioerr
.done   jmp io_fin
.werr   lda #3
        sta ioerr
        jmp io_fin

; ---- O: open
!zone inb
inb     lda $90
        bne .e
        jsr CHRIN
        inc bcnt
        bne .r
        inc bcnt+1
        bne .r
        inc bcnt+2
.r      rts
.e      ldx iosp                ; the file ended (or the drive failed) early: unwind
        txs
        lda #6
        sta ioerr
        jmp io_fin

!zone vout
vout    ldx frow
        cpx #CH
        bcs .r
        sta VDATA
        inc fcol
        bne .a
        inc fcol+1
.a      lda fcol
        cmp #<CW
        bne .r
        lda fcol+1
        cmp #>CW
        bne .r
        lda #0
        sta fcol
        sta fcol+1
        inc frow
        jsr barstep
        lda frow
        cmp #CH
        bcs .r
        sta p_y
        lda #0
        sta p_x
        sta p_x+1
        sta p_y+1
        jsr vaddr_xy
.r      rts

!zone c_open
c_open  ldx #<s_openas
        ldy #>s_openas
        jsr askname
        bcs .g
        rts
.g      jsr mkname
        jsr diskask
        bcs .y
        ldx #<m_noopen
        ldy #>m_noopen
        jmp msg
.y      jsr bar_clear
        jsr io_begin
        jsr doload
        jsr io_end
        lda ioerr
        bne .e
        jsr msg_begin
        +puts m_loaded
        jsr show_name
        jmp result_bytes
.e      jmp show_ioerr

!zone doload
doload  tsx
        stx iosp
        lda #0
        jsr SETNAM              ; the command channel, to read the drive's messages
        lda #15
        ldx #8
        ldy #15
        jsr SETLFS
        jsr OPEN
        bcc .o15
        jmp .eopen
.o15    jsr cb_reset            ; NAME.OCT,S,R
        jsr cb_pb
        ldx #<s_sr
        ldy #>s_sr
        jsr cb_str
        jsr setnm_cb
        lda #2
        ldx #8
        ldy #2
        jsr SETLFS
        jsr OPEN
        bcc .o2
        jmp .eopen
.o2     jsr rderr
        beq .o3
        lda #2
        sta ioerr
        jmp io_fin
.o3     lda #0
        sta $90
        ldx #2
        jsr CHKIN
        bcc .rd
.eopen  sta ioacc
        lda #1
        sta ioerr
        jmp io_fin
.rd     ldx #0                  ; the header
.h      stx ni
        jsr inb
        ldx ni
        sta hbuf,x
        inx
        cpx #10
        bne .h
        ldx #3
.v      lda hbuf,x
        cmp s_oct1,x
        bne .b4
        dex
        bpl .v
        lda hbuf+4
        cmp #<CW
        bne .b5
        lda hbuf+5
        cmp #>CW
        bne .b5
        lda hbuf+6
        cmp #CH
        bne .b5
        lda hbuf+7
        bne .b5
        lda hbuf+8
        cmp #8
        bne .b5
        lda hbuf+9
        cmp #2
        bcs .b5
        bcc .pal
.b4     lda #4
        sta ioerr
        jmp io_fin
.b5     lda #5
        sta ioerr
        jmp io_fin
.pal    lda #<TPAL              ; the palette, first into a spare place
        sta ptr2
        lda #>TPAL
        sta ptr2+1
        lda #3
        sta cnt
.pg     lda #0
        sta ni
.pb     jsr inb
        ldy ni
        sta (ptr2),y
        inc ni
        bne .pb
        inc ptr2+1
        dec cnt
        bne .pg
        ldx #0                  ; now it is the picture's palette
.cp     lda TPAL,x
        sta PAL,x
        lda TPAL+256,x
        sta PAL+256,x
        lda TPAL+512,x
        sta PAL+512,x
        inx
        bne .cp
        jsr pal_upload
        jsr save_undo           ; (U brings the old picture back)
        lda #1
        sta VINC
        lda #0
        sta frow
        sta fcol
        sta fcol+1
        sta p_x
        sta p_x+1
        sta p_y
        sta p_y+1
        jsr vaddr_xy
        lda hbuf+9
        bne .rle
.raw    jsr inb
        jsr vout
        lda frow
        cmp #CH
        bne .raw
        beq .done
.rle    jsr inb
        cmp #128
        bcs .rep
        clc
        adc #1
        sta cnt
.lit    jsr inb
        jsr vout
        dec cnt
        bne .lit
        beq .chk
.rep    sec
        sbc #125
        sta cnt
        jsr inb
        sta rv
.rp     lda rv
        jsr vout
        dec cnt
        bne .rp
.chk    lda frow
        cmp #CH
        bne .rle
.done   jmp io_fin

; ---- N: new
!zone c_new
c_new   ldx #<m_clear
        ldy #>m_clear
        jsr askyn
        bcc .r
        jsr save_undo
        lda #VR_CAN
        sta f_hb
        +rect 0, 0, CW, CH, 0
.r      rts

; ---- D: the debug overlay
; the checksum of the 320 x 200 picture: crc = rotate left 1 (crc xor pixel), 16 bits (mkoct.py: csum)
!zone vsum
vsum    lda #0
        sta crc
        sta crc+1
        sta frow
.row    lda #0
        sta p_x
        sta p_x+1
        sta p_y+1
        lda frow
        sta p_y
        jsr vaddr_xy
        jsr vwait
        ldy #0
.a      lda VDATA
        eor crc
        sta crc
        asl crc
        rol crc+1
        bcc .a1
        inc crc
.a1     iny
        bne .a
        ldy #64
.b      lda VDATA
        eor crc
        sta crc
        asl crc
        rol crc+1
        bcc .b1
        inc crc
.b1     dey
        bne .b
        inc frow
        lda frow
        cmp #CH
        bne .row
        rts

!zone c_debug
c_debug lda flags
        eor #2
        sta flags
        and #2
        bne .on
        lda #7                  ; off: rows 0 and 1 cleared
        sta tcol
        ldx #0
        ldy #0
        jsr txtpos
        ldx #40
        jsr fillsp
        ldx #0
        ldy #1
        jsr txtpos
        ldx #40
        jmp fillsp
.on     lda #0
        sta crc
        sta crc+1
        jmp vsum                ; (about a second)

!zone dbg_draw
dbg_draw
        lda #7
        sta tcol
        ldx #0
        ldy #0
        jsr txtpos
        +puts d_late
        lda LATE
        sta nv
        lda #0
        sta nv+1
        sta nv+2
        ldx #3
        jsr prdec
        +puts d_tot
        lda LATETOT
        sta nv
        lda LATETOT+1
        sta nv+1
        lda #0
        sta nv+2
        ldx #5
        jsr prdec
        +puts d_crc
        lda crc+1
        jsr prhex
        lda crc
        jsr prhex
        +puts d_fill
        lda fillt
        sta nv
        lda fillt+1
        sta nv+1
        lda #0
        sta nv+2
        ldx #5
        jsr prdec
        ldx #0
        ldy #1
        jsr txtpos
        +puts d_ptr
        +dec16 sx
        ldx #3
        jsr prdec
        lda #44
        jsr putc
        +dec16 sy
        ldx #3
        jsr prdec
        +puts d_cvs
        +dec16 cx
        ldx #3
        jsr prdec
        lda #44
        jsr putc
        +dec16 cy
        ldx #3
        jsr prdec
        +puts d_free
        lda #<(TOPFREE-progend)
        sta nv
        lda #>(TOPFREE-progend)
        sta nv+1
        lda #0
        sta nv+2
        ldx #5
        jsr prdec
        rts


; ---- data
!zone keychr
keychr  !byte 0,0,0,0,0,0,0,0
        !byte $33,23,1,$34,26,19,5,0
        !byte $35,18,4,$36,3,6,20,24
        !byte $37,25,7,$38,2,8,21,22
        !byte $39,9,10,$30,13,11,15,14
        !byte 0,16,12,45,46,0,0,0
        !byte 0,0,0,0,0,0,0,0
        !byte $31,0,0,$32,32,0,17,0
!zone hdr
hdr     !byte $4f,$43,$54,$31, <CW,>CW, CH,0, 8,1
!zone s_oct
s_oct   !byte $2e,$4f,$43,$54, $ff
!zone s_oct1
s_oct1  !byte $4f,$43,$54,$31, $ff
!zone s_scr
s_scr   !byte $53,$30,$3a, $ff
!zone s_sw
s_sw    !byte $2c,$53,$2c,$57, $ff
!zone s_sr
s_sr    !byte $2c,$53,$2c,$52, $ff
!zone s_saveas
s_saveas !scr "save as: ", $ff
!zone s_openas
s_openas !scr "open: ", $ff
!zone m_disk
m_disk  !scr "disk in drive 8? y/n", $ff
!zone m_nosave
m_nosave !scr "not saved (no disk used)", $ff
!zone m_noopen
m_noopen !scr "not opened (no disk used)", $ff
!zone m_saved
m_saved !scr "saved ", $ff
!zone m_loaded
m_loaded !scr "loaded ", $ff
!zone m_bytes
m_bytes !scr " bytes", $ff
!zone m_clear
m_clear !scr "clear the picture? y/n", $ff
!zone m_e1
m_e1    !scr "disk error ", $ff
!zone m_e2
m_e2    !scr "drive error", $ff
!zone m_e5
m_e5    !scr "device not present", $ff
!zone m_e3
m_e3    !scr "write error: disk full?", $ff
!zone m_e4
m_e4    !scr "not an oct file", $ff
!zone m_e6
m_e6    !scr "picture size not supported", $ff
!zone m_e7
m_e7    !scr "file too short or read error", $ff
!zone errtab
errtab  !word m_e3, m_e4, m_e6, m_e7
!zone d_late
d_late  !scr "late ", $ff
!zone d_tot
d_tot   !scr " tot ", $ff
!zone d_crc
d_crc   !scr " crc ", $ff
!zone d_fill
d_fill  !scr " fill ", $ff
!zone d_ptr
d_ptr   !scr "ptr ", $ff
!zone d_cvs
d_cvs   !scr "  cvs ", $ff
!zone d_free
d_free  !scr "  free ", $ff

; ================================================================================================ I: import a Koala picture
; 10003 bytes: load address (2), bitmap 8000, screen 1000, colour 1000, background 1. Read into RAM ($A000, $C000, $C400), then
; each 4 x 8 multicolour cell is written to the canvas as 2-wide pixels (160 x 200 -> 320 x 200). C64 colour c = palette entry c.

; fname and kname change places (the import has a name of its own, used as typed)
!zone swapname
swapname
        ldx #11
.l      lda fname,x
        tay
        lda kname,x
        sta fname,x
        tya
        sta kname,x
        dex
        bpl .l
        lda flen
        ldy klen
        sta klen
        sty flen
        rts

; fname as typed -> pbuf (PETSCII), no extension
!zone mkraw
mkraw   ldx #0
.c      cpx flen
        beq .e
        lda fname,x
        cmp #27
        bcs .p
        ora #$40
.p      sta pbuf,x
        inx
        bne .c
.e      stx plen
        rts

; one more cell of the bar
!zone bardraw
bardraw ldx pcell
        cpx #40
        bcs .r
        lda #160
        sta SCREEN+21*40,x
        lda #7
        sta COLRAM+21*40,x
        inc pcell
.r      rts

; ccnt bytes from the file to (ptr2); the bar moves every 250 bytes
!zone rdblock
rdblock jsr inb
        ldy #0
        sta (ptr2),y
        inc ptr2
        bne .a
        inc ptr2+1
.a      inc pcnt
        lda pcnt
        cmp #250
        bcc .b
        lda #0
        sta pcnt
        jsr bardraw
.b      lda ccnt
        bne .c
        dec ccnt+1
.c      dec ccnt
        lda ccnt
        ora ccnt+1
        bne rdblock
        rts

!zone c_import
c_import
        jsr swapname
        ldx #<s_impas
        ldy #>s_impas
        jsr askname
        bcs .g
        jsr swapname
        rts
.g      jsr mkraw
        jsr swapname
        jsr diskask
        bcs .y
        ldx #<m_noimp
        ldy #>m_noimp
        jmp msg
.y      jsr bar_clear
        jsr io_begin
        lda #0
        sta pcnt
        jsr doimport
        jsr io_end
        lda ioerr
        bne .e
        jsr msg_begin
        +puts m_imported
        jsr show_name
        jmp result_bytes
.e      jmp show_ioerr

!zone doimport
doimport
        tsx
        stx iosp
        lda #0
        jsr SETNAM
        lda #15
        ldx #8
        ldy #15
        jsr SETLFS
        jsr OPEN
        bcc .o15
        jmp .eopen
.o15    jsr cb_reset            ; NAME,P,R
        jsr cb_pb
        ldx #<s_pr
        ldy #>s_pr
        jsr cb_str
        jsr setnm_cb
        lda #2
        ldx #8
        ldy #2
        jsr SETLFS
        jsr OPEN
        bcc .o2
        jmp .eopen
.o2     jsr rderr
        beq .o3
        lda #2
        sta ioerr
        jmp io_fin
.o3     lda #0
        sta $90
        ldx #2
        jsr CHKIN
        bcc .rd
.eopen  sta ioacc
        lda #1
        sta ioerr
        jmp io_fin
.rd     jsr inb                 ; the load address
        jsr inb
        lda #<KBMP
        sta ptr2
        lda #>KBMP
        sta ptr2+1
        lda #<8000
        sta ccnt
        lda #>8000
        sta ccnt+1
        jsr rdblock
        lda #<KSCR
        sta ptr2
        lda #>KSCR
        sta ptr2+1
        lda #<1000
        sta ccnt
        lda #>1000
        sta ccnt+1
        jsr rdblock
        lda #<KCOL
        sta ptr2
        lda #>KCOL
        sta ptr2+1
        lda #<1000
        sta ccnt
        lda #>1000
        sta ccnt+1
        jsr rdblock
        jsr inb                 ; the background colour
        and #15
        sta kbg
        jsr CLRCHN
        lda #2
        jsr CLOSE               ; (the drive is done with)
        jsr bar_clear
        lda #0
        sta pacc
        sta pcell
        jsr save_undo
        lda #1
        sta VINC
        lda #0
        sta frow
.row    lda frow                ; the row's cells: cy = row / 8, line = row mod 8
        lsr
        lsr
        lsr
        sta kcy
        tax
        lda rowlo,x             ; cy * 40
        sta sptr
        sta cptr
        lda rowhi,x
        sta sptr+1
        sta cptr+1
        lda sptr                ; bitmap: (cy * 40) * 8 + line
        asl
        sta bptr
        lda sptr+1
        rol
        sta bptr+1
        asl bptr
        rol bptr+1
        asl bptr
        rol bptr+1
        lda frow
        and #7
        clc
        adc bptr
        sta bptr
        bcc .b1
        inc bptr+1
.b1     clc
        lda bptr
        adc #<KBMP
        sta bptr
        lda bptr+1
        adc #>KBMP
        sta bptr+1
        clc                     ; screen and colour RAM copies
        lda sptr
        adc #<KSCR
        sta sptr
        lda sptr+1
        adc #>KSCR
        sta sptr+1
        clc
        lda cptr
        adc #<KCOL
        sta cptr
        lda cptr+1
        adc #>KCOL
        sta cptr+1
        lda #0
        sta p_x
        sta p_x+1
        sta p_y+1
        lda frow
        sta p_y
        jsr vaddr_xy
        ldx #0
        stx kcx
.cell   ldy kcx
        lda kbg
        sta ctab
        lda (sptr),y
        pha
        lsr
        lsr
        lsr
        lsr
        sta ctab+1
        pla
        and #15
        sta ctab+2
        lda (cptr),y
        and #15
        sta ctab+3
        ldy #0
        lda (bptr),y
        sta kbyte
        clc                     ; the next cell's bitmap: 8 on
        lda bptr
        adc #8
        sta bptr
        bcc .b2
        inc bptr+1
.b2     ldx #4
.px     lda #0
        asl kbyte
        rol
        asl kbyte
        rol
        tay
        lda ctab,y
        sta VDATA
        sta VDATA
        dex
        bne .px
        inc kcx
        lda kcx
        cmp #40
        bne .cell
        jsr barstep
        inc frow
        lda frow
        cmp #CH
        beq .fin
        jmp .row
.fin    lda #0
        sta ioerr
        jmp io_fin

!zone s_pr
s_pr    !byte $2c,$50,$2c,$52, $ff
!zone s_impas
s_impas !scr "import koala: ", $ff
!zone m_noimp
m_noimp !scr "not imported (no disk used)", $ff
!zone m_imported
m_imported !scr "imported ", $ff

; ================================================================================================ H: the help page
; VIC text, full screen: OctoVIC is switched off (CTRL = 0) while it shows, any key brings the picture back.

!zone c_help
c_help  lda OCTRL
        sta hsave
        lda #0
        sta OCTRL
        jsr clrscreen
        lda #<helptab
        sta ptr
        lda #>helptab
        sta ptr+1
.l      ldy #0
        lda (ptr),y
        cmp #$ff
        beq .done
        pha
        iny
        lda (ptr),y
        tax
        iny
        lda (ptr),y
        sta tcol
        pla
        tay
        jsr txtpos
        clc                     ; the text follows the three bytes
        lda ptr
        adc #3
        sta str
        lda ptr+1
        adc #0
        sta str+1
        jsr puts
        ldy #3                  ; on to the next line: past the $ff
.s      lda (ptr),y
        cmp #$ff
        beq .e
        iny
        bne .s
.e      iny
        tya
        clc
        adc ptr
        sta ptr
        bcc .l
        inc ptr+1
        jmp .l
.done   jsr kclear
        jsr waitkey
        jsr relret
        lda hsave
        sta OCTRL
        jsr clrscreen
        jsr ui_all
        jmp kclear

!zone helptab
helptab !byte 0,11,7 : !scr "octopaint build " : !byte $30+BUILD : !byte $ff
        !byte 1,1,15 : !scr "256-colour paint for the octophonic 64" : !byte $ff
        !byte 3,0,7 : !scr "pointer" : !byte $ff
        !byte 4,0,1 : !scr "mouse in port 1 (osd: pot 1/2 = mouse)" : !byte $ff
        !byte 5,0,1 : !scr "joystick 1/2 or cursor keys (c= = 8)" : !byte $ff
        !byte 6,0,1 : !scr "return = draw   space = rubber" : !byte $ff
        !byte 8,0,7 : !scr "tools" : !byte $ff
        !byte 9,0,1 : !scr "p pencil  b brush  1-4 = size 1 2 4 8" : !byte $ff
        !byte 10,0,1 : !scr "l line  r rect  c circle  f flood fill" : !byte $ff
        !byte 11,0,1 : !scr "shift+r / shift+c = filled shapes" : !byte $ff
        !byte 12,0,1 : !scr "k pick the colour under the pointer" : !byte $ff
        !byte 13,0,1 : !scr "+ - colour up/down   < > palette window" : !byte $ff
        !byte 14,0,1 : !scr "e edit colour: q/a w/s e/d = r g b" : !byte $ff
        !byte 15,0,1 : !scr "(shift = 1) return keeps, stop undoes" : !byte $ff
        !byte 16,0,1 : !scr "u undo  z zoom 1x 2x 4x  tab bar on/off" : !byte $ff
        !byte 18,0,7 : !scr "files (drive 8)" : !byte $ff
        !byte 19,0,1 : !scr "n new  s save  o open  i import koala" : !byte $ff
        !byte 20,0,1 : !scr "m mouse on/off   d debug   f7 quit" : !byte $ff
        !byte 21,0,1 : !scr "every disk action asks disk in drive 8?" : !byte $ff
        !byte 23,7,7 : !scr "any key: back to the picture" : !byte $ff
        !byte $ff

!zone m_title
m_title !scr "octopaint build " : !byte $30+BUILD : !scr " - h for help", $ff

; ================================================================================================ variables (zero at start)
!zone qe
qe      !fill 2
!zone sqy
sqy     !fill 1
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
eorig   !fill 3
erep    !fill 1
eh      !fill 1
estep   !fill 1
frames  !fill 2
fillt   !fill 2
fstart  !fill 2
fsp     !fill 2
fover   !fill 1
tgt     !fill 1
qx      !fill 2
qy      !fill 1
xl      !fill 2
xr      !fill 2
ny      !fill 1
scnt    !fill 2
inrun   !fill 1
fname   !fill 12
flen    !fill 1
pbuf    !fill 24
plen    !fill 1
cbuf    !fill 32
clen    !fill 1
ebuf    !fill 40
elen    !fill 1
apr     !fill 2
ni      !fill 1
ioerr   !fill 1
ioacc   !fill 1
iosp    !fill 1
bcnt    !fill 3
rbyte   !fill 1
rcnt    !fill 1
lcnt    !fill 1
li      !fill 1
ccnt    !fill 2
frow    !fill 1
fcol    !fill 2
pacc    !fill 1
pcell   !fill 1
cnt     !fill 1
rv      !fill 1
crc     !fill 2
hbuf    !fill 10
kname   !fill 12
klen    !fill 1
pcnt    !fill 1
kbg     !fill 1
kcy     !fill 1
kcx     !fill 1
kbyte   !fill 1
ctab    !fill 4
hsave   !fill 1
progend
