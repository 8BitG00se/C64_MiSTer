; GREAT WAVE build 2 - a picture-viewer demo for the Octophonic 64 (OctoVIC 2+). By Mong00se.
; Katsushika Hokusai, "The Great Wave off Kanagawa", about 1831 (public domain; a scan of the print, via Wikimedia Commons).
; 6502, ACME (-f cbm), loads at $0801 (10 SYS2061). The picture, its two smaller copies for the zoomed-out views, the copper
; lists of the wipes and the palette are in "Great Wave.reu" (gen.py makes it); the 6502 uploads them into the VRAM before
; the show, while the screen is still black:
;   VRAM $000000  the picture, 1024 x 702, 256 colours, rows 1024 apart (layer 0, a BITMAP layer, TURNED AND SIZED)
;   VRAM $100000  the half size copy, 512 x 351, rows 512 apart (zoom 1.4 to 2)
;   VRAM $140000  the 11/32 size copy, 352 x 241, rows 512 apart (zoom 2 up; at the whole-print zoom, 32/11, it is shown 1:1)
;   VRAM $200000  the copper lists of the wipes (the copper's own animation plays them: a band of colour bars)
; The camera (centre, zoom) is worked out here every frame: straight steps between the short rows of ROWS (gen.py, which
; does the easing and the curved pan: rows.inc), the maths unit for the interpolation and the registers. Zoomed out, a smaller
; copy is used (an averaged picture, no speckle).
; The VIC text, in front (KEY = black is see-through), carries the captions, faded with the VIC palette.
; SPACE pauses, D shows the debug line (LATE and friends), F7 quits to BASIC.
!cpu 6502
BUILD   = 4
!src "data.inc"

OV      = $D600
VADDR   = $D600
VINC    = $D603
VDATA   = $D604
OCTRL   = $D605
OKEY    = $D606
OSTATUS = $D608
COPCTL  = $D60E
SPRCNT  = $D60F
COPBASE = $D610
PALSEL  = $D619
PALIDX  = $D61A
PALR    = $D61B
PALG    = $D61C
PALB    = $D61D
OID     = $D61E
OVER    = $D61F
L0      = $D620
COPSTEP = $D640
COPSTEPS = $D643
COPDIV  = $D645
MULA    = $D650
MULB    = $D652
MULR    = $D654
DIVN    = $D659
DIVD    = $D65D
DIVQ    = $D660
BDST    = $D673
BW      = $D676
BH      = $D678
BDSTR   = $D67C
BFILL   = $D67E
BCTRL   = $D67F
U0      = $D688
LATE    = $D6A0
LATETOT = $D6A6
REU     = $DF00
SCREEN  = $0400
COLRAM  = $D800
CHROUT  = $FFD2
PALBUF  = $C000
SATBASE = $D613
SPRGFX  = $D616
V_SAT   = $300000       ; the caption's dark band: 5 sprites, 64 x 16, taken-away mode (palette entry 255)
V_SPR   = $301000

!macro asr32 .a {
        lda .a+3
        cmp #$80
        ror .a+3
        ror .a+2
        ror .a+1
        ror .a
}

; zero page
tick    = $3A
row     = $3B           ; the timeline row
rowoff  = $3C           ; (not used)
rt      = $3D           ; 2: frames left in the row
sstep   = $3F           ; 2: 65536 / the row's frames
sacc    = $41           ; 2: the row's progress, 0-65535
paused  = $43
ksp     = $44
kd      = $45
dbg     = $46
lon     = $47           ; layer 0 on
mip     = $48           ; 1: the half size copy is in use
wf      = $49           ; 2: the wipe's frame
wmode   = $4B           ; 0 none, 1 wipe in, 2 wipe out
capmode = $4C           ; 0 none, 1 title, 2 credit
capt    = $4D
capb    = $4E           ; the caption's brightness 0-255
capdirty = $4F
ovr     = $50           ; frames the 6502 was late for (the IRQ ticked twice)
lmax    = $51
gt      = $52           ; 2: frames since start
ee      = $54           ; 2: the eased progress
amp     = $56
la      = $57           ; 3
lb      = $5A           ; 3
lr      = $5D           ; 3
dd      = $60           ; 3
sg      = $63
mm      = $64           ; 3
tp      = $67           ; 8 temporaries
up_r    = $70           ; 3: REU address
up_n    = $73           ; 3: bytes left
ptr     = $76
ptr2    = $78
dbgv    = $7A           ; 2
dg      = $7C
tx      = $7D
late    = $7E
rp      = $80           ; 2: the next row of ROWS

; RAM, not zero page
CA      = $9000         ; the camera: 3 x 24 bits (x, y, zoom), the row's start (A), its target (B), now (CUR)
CB      = $9009
CUR     = $9012
REGS    = $9020         ; U0 V0 DUX DVX DUY DVY, as OctoVIC has them ($D688-$D69F)

        * = $0801
        !byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00
        jmp start
; the music: Soran Bushi for 8 SIDs, a register stream from the REU (music.py makes it): every frame 256 bytes (8 SIDs x 32) at
; R_MUS + frame * 256, 4 DMA transfers of 64 bytes into the SIDs' windows (SID 0,1 at $D400/$D420, 4,5 at $D480/$D4A0,
; 2,3 at $D500/$D520, 6,7 at $D580/$D5A0). 2550 frames, the length of the camera's loop; the camera's wrap restarts it.
        * = $1000
MFR     = $9F00         ; 2: the music's frame
NMUS    = 2550
!zone music
music_init
        lda #0
        sta MFR
        sta MFR+1
        rts
        !byte 0
music_play
        lda MFR+1               ; past the last frame (the camera has not wrapped yet): hold
        cmp #>NMUS
        bcc .go
        bne .x
        lda MFR
        cmp #<NMUS
        bcs .x
.go     ldx #3
.l      lda .dst,x
        sta REU+2
        lda .dsth,x
        sta REU+3
        lda .off,x
        sta REU+4
        clc
        lda MFR
        adc #>R_MUS
        sta REU+5
        lda MFR+1
        adc #^R_MUS
        sta REU+6
        lda #64
        sta REU+7
        lda #0
        sta REU+8
        sta REU+10
        lda #$91                ; now, REU to C64
        sta REU+1
        dex
        bpl .l
        inc MFR
        bne .x
        inc MFR+1
.x      rts
.dst    !byte $00, $80, $00, $80
.dsth   !byte $d4, $d4, $d5, $d5
.off    !byte $00, $40, $80, $c0
; silence: music_mute = volume 0 on all 8 SIDs (the pause; the next frame's registers bring it back), music_off = every register 0 (F7)
music_mute
        lda #$18
        bne +
music_off
        lda #0
+       sta tp+2                ; the first register to clear
        ldx #7
.s      lda .dst4,x
        sta ptr
        lda .dsth4,x
        sta ptr+1
        ldy #$18
        lda #0
.z      sta (ptr),y
        cpy tp+2
        beq .zd
        dey
        bne .z
.zd     dex
        bpl .s
        rts
        !byte 0
.dst4   !byte $00, $20, $00, $20, $80, $a0, $80, $a0
.dsth4  !byte $d4, $d4, $d5, $d5, $d4, $d4, $d5, $d5

        * = $4000
start   cld
        sei
        lda #$4f                ; OctoVIC on
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

m_need  !byte 13
        !pet "GREAT WAVE NEEDS THE OCTOPHONIC 64 (OCTOVIC 2+)", 13, 0

; ======================================================================================================== init
!zone init
init    lda #$7f                ; no CIA interrupts: the keys are read from the matrix, the frame is the raster IRQ
        sta $dc0d
        lda $dc0d
        lda #0
        sta $d01a
        lda #$ff
        sta $d019
        ldx #$9a                ; OctoVIC: everything zero (off), then what is needed
        lda #0
.z      sta OCTRL,x
        dex
        cpx #$ff
        bne .z
        sta paused
        sta ksp
        sta kd
        sta dbg
        sta lon
        sta mip
        sta wmode
        sta capmode
        sta capb
        sta ovr
        sta lmax
        sta gt
        sta gt+1
        sta tick
        sta row
        sta rowoff
        sta rt
        sta rt+1
        lda #<rows
        sta rp
        lda #>rows
        sta rp+1
        lda #<nmi
        sta $0318
        lda #>nmi
        sta $0319
        lda #0                  ; the VIC: black, the upper case set, white text colour, no sprites
        sta $d020
        sta $d021
        sta $d015
        lda #$15
        sta $d018
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
.pl     lda PALBUF,x
        sta PALR
        lda PALBUF+256,x
        sta PALG
        lda PALBUF+512,x
        sta PALB
        inx
        bne .pl
        lda #1                  ; the VIC's 16 colours: black (the text colour, 1, is faded by the captions)
        sta PALSEL
        lda #0
        sta PALIDX
        ldx #16
.vp     lda #0
        sta PALR
        sta PALG
        sta PALB
        dex
        bne .vp
        lda #2                  ; the backdrop: black
        sta PALSEL
        lda #0
        sta PALIDX
        sta PALR
        sta PALG
        sta PALB
        ; the VRAM: both bitmaps cleared (the blitter), so the rows below the pictures are see-through
        lda #1
        sta VINC
        lda #0
        sta BDST
        sta BDST+1
        sta BFILL
        sta BW
        sta BH
        sta BDSTR
        ldx #4                  ; 1024 x 1024 at 0
        ldy #0
        jsr bfill
        ldx #2                  ; 512 x 512 at V_PIC1
        ldy #^V_PIC1
        jsr bfill
        ldx #2                  ; 512 x 512 at V_PIC2
        ldy #^V_PIC2
        jsr bfill
        ; the pictures and the copper lists, from the REU into the VRAM
        lda #<V_PIC0
        ldx #>V_PIC0
        ldy #^V_PIC0
        jsr vset
        lda #<R_PIC0
        sta up_r
        lda #>R_PIC0
        sta up_r+1
        lda #^R_PIC0
        sta up_r+2
        lda #<LEN_PIC0
        sta up_n
        lda #>LEN_PIC0
        sta up_n+1
        lda #^LEN_PIC0
        sta up_n+2
        jsr reuvram
        lda #<V_PIC1
        ldx #>V_PIC1
        ldy #^V_PIC1
        jsr vset
        lda #<R_PIC1
        sta up_r
        lda #>R_PIC1
        sta up_r+1
        lda #^R_PIC1
        sta up_r+2
        lda #<LEN_PIC1
        sta up_n
        lda #>LEN_PIC1
        sta up_n+1
        lda #^LEN_PIC1
        sta up_n+2
        jsr reuvram
        lda #<V_PIC2
        ldx #>V_PIC2
        ldy #^V_PIC2
        jsr vset
        lda #<R_PIC2
        sta up_r
        lda #>R_PIC2
        sta up_r+1
        lda #^R_PIC2
        sta up_r+2
        lda #<LEN_PIC2
        sta up_n
        lda #>LEN_PIC2
        sta up_n+1
        lda #^LEN_PIC2
        sta up_n+2
        jsr reuvram
        lda #<V_COP
        ldx #>V_COP
        ldy #^V_COP
        jsr vset
        lda #<R_COP
        sta up_r
        lda #>R_COP
        sta up_r+1
        lda #^R_COP
        sta up_r+2
        lda #<LEN_COP
        sta up_n
        lda #>LEN_COP
        sta up_n+1
        lda #^LEN_COP
        sta up_n+2
        jsr reuvram
        ; the dark band behind the captions: 5 sprites of 64 x 16, colour 255, "taken away" (a shadow); off until a caption shows
        lda #<V_SPR
        ldx #>V_SPR
        ldy #^V_SPR
        jsr vset
        ldx #4
        ldy #0
        lda #255
.sg     sta VDATA
        iny
        bne .sg
        dex
        bne .sg
        lda #<V_SAT
        ldx #>V_SAT
        ldy #^V_SAT
        jsr vset
        ldx #0
.ss     txa                     ; X: 64 * n (16 bits)
        lsr
        lsr
        sta tp                  ; (the high byte)
        txa
        asl
        asl
        asl
        asl
        asl
        asl
        sta VDATA
        lda tp
        sta VDATA
        lda #184                ; Y: the VIC's text rows 23 and 24
        sta VDATA
        lda #0
        sta VDATA
        sta VDATA               ; graphics 0
        sta VDATA
        lda #$c7                ; 64 wide, 16 high, 256 colours, on
        sta VDATA
        lda #$c0                ; in front, taken away
        sta VDATA
        inx
        cpx #5
        bne .ss
        lda #<V_SAT
        sta SATBASE
        lda #>V_SAT
        sta SATBASE+1
        lda #^V_SAT
        sta SATBASE+2
        lda #<V_SPR
        sta SPRGFX
        lda #>V_SPR
        sta SPRGFX+1
        lda #^V_SPR
        sta SPRGFX+2
        ; the camera starts on the whole painting
        ldx #8
.cb     lda keyfit,x
        sta CB,x
        dex
        bpl .cb
        ldx #23
        lda #0
.rg     sta REGS,x
        dex
        bpl .rg
        ; the layer: a BITMAP, turned and sized, nothing drawn outside the picture
        lda #$0c
        sta L0+$f
        ; the copper: the empty list (the wipes are played from the copper's own animation)
        jsr cop_static
        lda #1
        sta COPCTL
        lda #0                  ; the VIC's black is see-through, the VIC in front; its palette is OctoVIC's
        sta OKEY
        lda #$0b
        sta OCTRL
        ; the frame: a raster interrupt at line 300, below the picture
        lda #<irq
        sta $0314
        lda #>irq
        sta $0315
        lda #<300
        sta $d012
        lda $d011
        ora #$80
        sta $d011
        lda #1
        sta $d01a
        lda #$ff
        sta $d019
        lda #1
        sta $d030               ; turbo
        jsr music_init
        cli
        rts

!zone nmi
nmi     rti

!zone irq
irq     lda $d019
        sta $d019
        inc tick
        jmp $ea81

; fill a square of X * 256 bytes at VRAM Y * 65536 with 0 (the blitter)
!zone bfill
bfill   jsr bwait
        sty BDST+2
        stx BW+1
        stx BH+1
        stx BDSTR+1
        lda #3                  ; go, FILL
        sta BCTRL
        jmp bwait

!zone bwait
bwait   lda OSTATUS
        and #4
        bne bwait
        rts

; VADDR = A, X, Y (24 bits)
vset    sta VADDR
        stx VADDR+1
        sty VADDR+2
        rts

; up_n bytes from the REU at up_r into VDATA (VADDR counts up by itself: VINC = 1), 64 KB at a time
!zone reuvram
reuvram lda up_n+2
        bne .big
        lda up_n
        ora up_n+1
        beq .done
        ldx up_n
        ldy up_n+1
        lda #0
        sta up_n
        sta up_n+1
        jsr .fire
.done   rts
.big    dec up_n+2
        ldx #0
        ldy #0
        jsr .fire
        inc up_r+2
        jmp reuvram
.fire   stx REU+7
        sty REU+8
        lda #<VDATA
        sta REU+2
        lda #>VDATA
        sta REU+3
        lda up_r
        sta REU+4
        lda up_r+1
        sta REU+5
        lda up_r+2
        sta REU+6
        lda #$80                ; the C64 address stays (VDATA)
        sta REU+10
        lda #$91
        sta REU+1
        rts

; ======================================================================================================== the frame
!zone main
main    jsr waittick
        jsr vblank              ; this frame's numbers into OctoVIC (the beam is below the picture)
        jsr keys
        lda paused
        bne .p
        jsr advance             ; the next frame's numbers
        jsr music_play
.p      jsr debug
        jmp main

!zone waittick
waittick
.w      lda tick
        beq .w
        cmp #2
        bcc .ok
        inc ovr                 ; the IRQ ticked twice: the 6502 took more than a frame
        bne .ok
        dec ovr
.ok     lda #0
        sta tick
        rts

; what OctoVIC needs this frame (written in the vertical blank, before line 13)
!zone vblank
vblank  ldx #23
.r      lda REGS,x
        sta U0,x
        dex
        bpl .r
        lda mip
        beq .m0
        ldy #$10                ; mip 1: the half size copy
        cmp #2
        bne .m5
        ldy #$14                ; mip 2: the 11/32 size copy
.m5     lda #$5a
        bne .m
.m0     lda #$aa
        ldy #0
.m      ora lon
        sta L0
        lda #0
        sta L0+4
        sta L0+5
        sty L0+6
        lda LATE                ; last frame's late lines
        sta late
        cmp lmax
        bcc .nl
        sta lmax
.nl     lda capdirty
        beq .nc
        lda #0
        sta capdirty
        jsr setcapcol
.nc     rts

; VIC palette entry 1 (the text) from capb (and the debug line: white)
!zone setcapcol
setcapcol
        lda #1
        sta PALSEL
        sta PALIDX
        lda capb
        ldx dbg
        beq .a
        lda #255
.a      sta tp
        sta PALR
        lsr
        lsr
        lsr
        lsr
        sta tp+1
        lda tp
        sec
        sbc tp+1
        sta PALG
        lda tp
        lsr
        lsr
        sta tp+1
        lda tp
        sec
        sbc tp+1
        sta PALB
        lda capb                ; the shadow behind the text: palette entry 255, 1/4 of the brightness
        lsr
        lsr
        sta tp+1
        lda #0
        sta PALSEL
        lda #255
        sta PALIDX
        lda tp+1
        sta PALR
        sta PALG
        sta PALB
        rts

; ======================================================================================================== keys
!zone keys
keys    lda #$fe
        sta $dc00
        lda $dc01
        and #$08                ; F7
        bne .nf7
        jmp quit
.nf7    lda #$7f
        sta $dc00
        lda $dc01
        and #$10                ; SPACE
        bne .sp0
        lda ksp
        bne .d
        lda #1
        sta ksp
        jsr pause
        jmp .d
.sp0    lda #0
        sta ksp
.d      lda #$fb
        sta $dc00
        lda $dc01
        and #$04                ; D
        bne .d0
        lda kd
        bne .e
        lda #1
        sta kd
        lda dbg
        eor #1
        sta dbg
        jsr dbgtoggle
        jmp .e
.d0     lda #0
        sta kd
.e      lda #$ff
        sta $dc00
        rts

!zone pause
pause   lda paused
        eor #1
        sta paused
        beq +
        jsr music_mute
+
        lda wmode
        beq .x
        jmp cop_run             ; the copper's animation stops / goes on at the frame it is at
.x      rts

; ======================================================================================================== the copper
; the wipe's list for frame wf: base + wf * COPSTRIDE, the animation (a list a frame) from there to the last
!zone cop_run
cop_run lda wf
        sta MULA
        lda wf+1
        sta MULA+1
        lda #<COPSTRIDE
        sta MULB
        lda #>COPSTRIDE
        sta MULB+1
        lda wmode
        cmp #1
        bne .o
        clc
        lda MULR
        adc #<L_IN
        sta tp
        lda MULR+1
        adc #>L_IN
        sta tp+1
        lda MULR+2
        adc #^L_IN
        sta tp+2
        sec
        lda #<NLISTIN
        sbc wf
        sta tp+3
        lda #>NLISTIN
        sbc wf+1
        sta tp+4
        jmp .set
.o      clc
        lda MULR
        adc #<L_OUT
        sta tp
        lda MULR+1
        adc #>L_OUT
        sta tp+1
        lda MULR+2
        adc #^L_OUT
        sta tp+2
        sec
        lda #<NLISTOUT
        sbc wf
        sta tp+3
        lda #>NLISTOUT
        sbc wf+1
        sta tp+4
.set    lda #<COPSTRIDE
        sta COPSTEP
        lda #>COPSTRIDE
        sta COPSTEP+1
        lda #0
        sta COPSTEP+2
        lda tp+3
        sta COPSTEPS
        lda tp+4
        sta COPSTEPS+1
        lda #1
        ldx paused
        beq .d
        lda #0
.d      sta COPDIV
        lda tp
        sta COPBASE
        lda tp+1
        sta COPBASE+1
        lda tp+2
        sta COPBASE+2
        rts

; the empty list, no animation
!zone cop_static
cop_static
        lda #0
        sta COPDIV
        lda #<L_EMPTY
        sta COPBASE
        lda #>L_EMPTY
        sta COPBASE+1
        lda #^L_EMPTY
        sta COPBASE+2
        rts

; A = 1 wipe in, 2 wipe out
!zone wipe_start
wipe_start
        sta wmode
        lda #0
        sta wf
        sta wf+1
        jmp cop_run

!zone wipe_step
wipe_step
        lda wmode
        beq .x
        inc wf
        bne +
        inc wf+1
+       lda wf+1
        bne .x
        lda wf
        ldx wmode
        cpx #2
        beq .o
        cmp #NIN
        bne .x
        lda #1                  ; the picture is all there: the empty list, the layer on
        sta lon
        bne .end
.o      cmp #NOUT
        bne .x
        lda #0                  ; black: the layer off
        sta lon
.end    lda #0
        sta wmode
        jmp cop_static
.x      rts

; ======================================================================================================== the show
; ROWS (rows.inc, made by gen.py): frames (16), x (8.8), y (8.8), zoom (8.16), event; each row goes in a straight line from the
; last row's target to its own over its frames. gen.py cuts the eased moves and the curved pan into short rows. Frames 0 ends the list.
; events: 1 the wipe in, 2 the title, 3 the credit, 4 the wipe out
!src "rows.inc"

!zone advance
advance inc gt
        bne +
        inc gt+1
+       lda rt
        ora rt+1
        bne .go
        jsr nextrow
.go     jsr camera
        lda rt
        bne +
        dec rt+1
+       dec rt
        jsr wipe_step
        jmp capstep

!zone nextrow
nextrow ldx #8                  ; the last target is where this row starts
.a      lda CB,x
        sta CA,x
        dex
        bpl .a
        ldy #0
        lda (rp),y
        iny
        ora (rp),y
        bne .rd
.wrap   jsr music_init          ; the end of the list: round again, and the music with it
        lda #<rows
        sta rp
        lda #>rows
        sta rp+1
.rd     ldy #0
        lda (rp),y
        sta rt
        sta tp
        iny
        lda (rp),y
        sta rt+1
        sta tp+1
        ldy #2                  ; x, y, zoom: 3 bytes each, as they are
.t      lda (rp),y
        sta CB-2,y
        iny
        cpy #11
        bne .t
        lda (rp),y              ; the event
        pha
        ; sstep = 65536 / frames (the divide unit)
        lda #0
        sta DIVN
        sta DIVN+1
        lda #1
        sta DIVN+2
        lda #0
        sta DIVN+3
        lda tp
        sta DIVD
        lda tp+1
        sta DIVD+1
        lda DIVQ
        sta sstep
        lda DIVQ+1
        sta sstep+1
        lda #0
        sta sacc
        sta sacc+1
        ; the next row
        clc
        lda rp
        adc #12
        sta rp
        bcc +
        inc rp+1
+       pla
        beq .none
        cmp #1
        bne .e2
        lda #0
        sta lon
        lda #1
        jmp wipe_start
.e2     cmp #2
        bne .e3
        lda #1
        jmp capstart
.e3     cmp #3
        bne .e4
        lda #2
        jmp capstart
.e4     lda #1                  ; wipe out: the layer is on, the copper takes it off at line 0 of each frame
        sta lon
        lda #2
        jmp wipe_start
.none   rts

; the camera for this frame: the eased progress, the three values, the registers
!zone camera
camera  clc                     ; the row's progress
        lda sacc
        adc sstep
        sta sacc
        lda sacc+1
        adc sstep+1
        sta sacc+1
        bcc +
        lda #$ff
        sta sacc
        sta sacc+1
+       lda rt+1
        bne .s
        lda rt
        cmp #1
        bne .s
        lda #$ff                ; the last frame: exactly there
        sta sacc
        sta sacc+1
.s      lda sacc                ; e = s: gen.py's rows are short, the easing is in them
        sta ee
        lda sacc+1
        sta ee+1
        ; x, y, zoom
        ldx #0
.ch     lda CA,x
        sta la
        lda CA+1,x
        sta la+1
        lda CA+2,x
        sta la+2
        lda CB,x
        sta lb
        lda CB+1,x
        sta lb+1
        lda CB+2,x
        sta lb+2
        txa
        pha
        jsr lerp
        pla
        tax
        lda lr
        sta CUR,x
        lda lr+1
        sta CUR+1,x
        lda lr+2
        sta CUR+2,x
        inx
        inx
        inx
        cpx #9
        bne .ch
        ; which picture: the half size copy from zoom 1.4, the 11/32 copy from 2.0
        lda CUR+8
        cmp #2
        bcs .m2
        cmp #1
        bne .m0
        lda CUR+7
        cmp #$66
        bcc .m0
        lda #1
        bne +
.m2     lda #2
        bne +
.m0     lda #0
+       sta mip
        ; U0 = x - 198 * zoom, V0 = y - 158 * zoom (16.16), DUX = DVY = zoom
        ldx #0                  ; x
        ldy #198
        jsr .uv
        lda tp
        sta REGS
        lda tp+1
        sta REGS+1
        lda tp+2
        sta REGS+2
        lda tp+3
        sta REGS+3
        ldx #3                  ; y
        ldy #158
        jsr .uv
        lda tp
        sta REGS+4
        lda tp+1
        sta REGS+5
        lda tp+2
        sta REGS+6
        lda tp+3
        sta REGS+7
        lda CUR+6
        sta REGS+8
        sta REGS+20
        lda CUR+7
        sta REGS+9
        sta REGS+21
        lda CUR+8
        sta REGS+10
        sta REGS+22
        lda #0
        sta REGS+11
        sta REGS+23
        sta REGS+12
        sta REGS+13
        sta REGS+14
        sta REGS+15
        sta REGS+16
        sta REGS+17
        sta REGS+18
        sta REGS+19
        lda mip                 ; a smaller copy: everything smaller
        beq .done
        cmp #2
        beq .s11
        +asr32 REGS             ; mip 1: half
        +asr32 REGS+4
        +asr32 REGS+8
        +asr32 REGS+20
.done   rts
.s11    ldx #0                  ; mip 2: 11/32 = 1/4 + 1/16 + 1/32
        jsr scale11
        ldx #4
        jsr scale11
        ldx #8
        jsr scale11
        ldx #20
scale11 lda REGS,x
        sta tp+4
        lda REGS+1,x
        sta tp+5
        lda REGS+2,x
        sta tp+6
        lda REGS+3,x
        sta tp+7
        +asr32 tp+4             ; v / 2
        +asr32 tp+4             ; v / 4
        ldy #0
        sty tp+3                ; (the sum starts as v / 4: copied below)
        lda tp+4
        sta tp
        lda tp+5
        sta tp+1
        lda tp+6
        sta tp+2
        lda tp+7
        sta tp+3
        +asr32 tp+4
        +asr32 tp+4             ; v / 16
        jsr .add
        +asr32 tp+4             ; v / 32
        jsr .add
        lda tp
        sta REGS,x
        lda tp+1
        sta REGS+1,x
        lda tp+2
        sta REGS+2,x
        lda tp+3
        sta REGS+3,x
        rts
.add    clc
        lda tp
        adc tp+4
        sta tp
        lda tp+1
        adc tp+5
        sta tp+1
        lda tp+2
        adc tp+6
        sta tp+2
        lda tp+3
        adc tp+7
        sta tp+3
        rts
; tp..tp+3 = (CUR[x] << 8) - Y * zoom   (X = 0 or 3, Y = 198 or 158)
.uv     sty MULA
        lda #0
        sta MULA+1
        lda CUR+6
        sta MULB
        lda CUR+7
        sta MULB+1
        lda MULR
        sta tp+4
        lda MULR+1
        sta tp+5
        lda MULR+2
        sta tp+6
        lda MULR+3
        sta tp+7
        lda CUR+8               ; the zoom's whole part
        sta MULB
        lda #0
        sta MULB+1
        clc
        lda tp+6
        adc MULR
        sta tp+6
        lda tp+7
        adc MULR+1
        sta tp+7
        sec
        lda #0
        sbc tp+4
        sta tp
        lda CUR,x
        sbc tp+5
        sta tp+1
        lda CUR+1,x
        sbc tp+6
        sta tp+2
        lda CUR+2,x
        sbc tp+7
        sta tp+3
        rts

; lr = la + (lb - la) * ee / 65536      (24 bits; la, lb as numbers; the difference signed)
!zone lerp
lerp    sec
        lda lb
        sbc la
        sta dd
        lda lb+1
        sbc la+1
        sta dd+1
        lda lb+2
        sbc la+2
        sta dd+2
        sta sg
        bpl .p
        sec
        lda #0
        sbc dd
        sta dd
        lda #0
        sbc dd+1
        sta dd+1
        lda #0
        sbc dd+2
        sta dd+2
.p      lda ee
        sta MULB
        lda ee+1
        sta MULB+1
        lda dd
        sta MULA
        lda dd+1
        sta MULA+1
        lda MULR+2
        sta mm
        lda MULR+3
        sta mm+1
        lda dd+2
        sta MULA
        lda #0
        sta MULA+1
        clc
        lda MULR
        adc mm
        sta mm
        lda MULR+1
        adc mm+1
        sta mm+1
        lda MULR+2
        adc #0
        sta mm+2
        lda sg
        bmi .m
        clc
        lda la
        adc mm
        sta lr
        lda la+1
        adc mm+1
        sta lr+1
        lda la+2
        adc mm+2
        sta lr+2
        rts
.m      sec
        lda la
        sbc mm
        sta lr
        lda la+1
        sbc mm+1
        sta lr+1
        lda la+2
        sbc mm+2
        sta lr+2
        rts

; ======================================================================================================== captions
!zone captions
; A = 1 title, 2 credit
capstart
        sta capmode
        lda #5
        sta SPRCNT
        lda #0
        sta capt
        sta capb
        lda #<SCREEN+23*40
        sta ptr
        lda #>SCREEN+23*40
        sta ptr+1
        lda capmode
        cmp #1
        bne .c2
        ldy #6
        ldx #<t_title
        stx ptr2
        ldx #>t_title
        stx ptr2+1
        jsr puttext
        lda #<SCREEN+24*40
        sta ptr
        lda #>SCREEN+24*40
        sta ptr+1
        ldy #6
        lda #<t_name
        sta ptr2
        lda #>t_name
        sta ptr2+1
        jmp puttext
.c2     lda #<SCREEN+24*40
        sta ptr
        lda #>SCREEN+24*40
        sta ptr+1
        ldy #6
        lda #<t_credit
        sta ptr2
        lda #>t_credit
        sta ptr2+1
        jmp puttext

; the text at ptr2 (ends $ff) to ptr + Y
puttext lda #0
        sta tx
.l      ldx tx
        lda (ptr2,x)
        cmp #$ff
        beq .e
        sta (ptr),y
        iny
        inc ptr2
        bne .l
        inc ptr2+1
        bne .l
.e      rts

capstep lda capmode
        beq .x
        inc capt
        lda capt
        cmp #150
        bcs .end
        cmp #75
        bcc .a
        lda #150
        sec
        sbc capt
.a      cmp #31                 ; 30 frames to fade in, 30 to fade out
        bcc +
        lda #31
+       asl                     ; x 8: 248 at most
        asl
        asl
        cmp capb
        beq .x
        sta capb
        lda #1
        sta capdirty
.x      rts
.end    lda #0
        sta capmode
        sta capb
        sta SPRCNT
        lda #1
        sta capdirty
        ldx #39
        lda #$20
.c      sta SCREEN+23*40,x
        sta SCREEN+24*40,x
        dex
        bpl .c
        rts

t_title !scr "the great wave off kanagawa", $ff
t_name  !scr "katsushika hokusai, c. 1831", $ff
t_credit !scr "octovic 256 - octophonic 64", $ff

; ======================================================================================================== the debug line
!zone debug
dbgtoggle
        lda #1
        sta capdirty
        lda dbg
        bne .on
        ldx #39
        lda #$20
.c      sta SCREEN,x
        dex
        bpl .c
        rts
.on     ldx #39
.t      lda t_dbg,x
        sta SCREEN,x
        dex
        bpl .t
        rts
debug   lda dbg
        beq .x
        lda late
        sta dbgv
        lda #0
        sta dbgv+1
        ldx #5
        jsr pr5
        lda lmax
        sta dbgv
        lda #0
        sta dbgv+1
        ldx #15
        jsr pr5
        lda LATETOT
        sta dbgv
        lda LATETOT+1
        sta dbgv+1
        ldx #25
        jsr pr5
        lda ovr
        sta dbgv
        lda #0
        sta dbgv+1
        ldx #35
        jsr pr5
.x      rts

; dbgv as 5 digits at SCREEN + X
pr5     stx tx
        ldy #0
.nd     lda #$30
        sta dg
.sub    lda dbgv
        sec
        sbc pw_lo,y
        tax
        lda dbgv+1
        sbc pw_hi,y
        bcc .done
        sta dbgv+1
        stx dbgv
        inc dg
        bne .sub
.done   lda dg
        ldx tx
        sta SCREEN,x
        inc tx
        iny
        cpy #5
        bne .nd
        rts
pw_lo   !byte <10000, <1000, <100, <10, <1
pw_hi   !byte >10000, >1000, >100, >10, >1
t_dbg   !scr "late 00000 max 00000 tot 00000 ovr 00000"

; ======================================================================================================== quit
!zone quit
quit    sei
        jsr music_off
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
        lda $d011
        and #$7f
        sta $d011
        lda #$37
        sta $01
        jsr $e544               ; clear the screen
        lda #$0e
        sta 646                 ; light blue text, as BASIC starts
        jmp ($a002)             ; BASIC warm start: READY

