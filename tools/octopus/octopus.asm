; OCTOPUS build 1 - a demo for the Octophonic 64 (OctoVIC 2+). By Mong00se.
; The Octophonic octopus, turning and breathing in technicolour. The octopus is ONE still 256 x 256 picture (a BITMAP layer,
; TURNED AND SIZED by OctoVIC), its body drawn in palette "bands" (swirls by distance and angle); all its colour is the copper
; rewriting 249 palette entries a frame in the vertical blank (the way of the Black Hole demo), so the rainbow flows round and
; through it. The same list changes the backdrop's colour on every line (slow bands) and twinkles 40 stars (sprites behind the
; layer). The turn and the zoom come from a table in the REU (one row of 24 bytes a frame, gen.py makes it) that the 6502
; hands to OctoVIC every frame, as Great Wave does. 1800 frames (36 s): 4 turns, 2 zoom breaths, 15 colour cycles.
; The VIC text in front (KEY = black is see-through) carries the caption; a dark band behind it is 3 sprites in "half and half" mode (over the octopus it halves the light).
; SPACE pauses (the copper's animation stops too), F7 quits to BASIC (all 8 SIDs silent). Silent: a music hook at $1003 is
; called every frame (JSR MUSIC_PLAY), $1000 once at the start; both are just RTS - put a tune there.
; 6502, ACME (-f cbm), loads at $0801 (10 SYS2061).
!cpu 6502
BUILD   = 1
!src "data.inc"

OVER    = $D61F
OID     = $D61E
OCTRL   = $D605
OKEY    = $D606
OSTATUS = $D608
COPCTL  = $D60E
SPRCNT  = $D60F
COPBASE = $D610
SATBASE = $D613
SPRGFX  = $D616
PALSEL  = $D619
PALIDX  = $D61A
PALR    = $D61B
PALG    = $D61C
PALB    = $D61D
VADDR   = $D600
VINC    = $D603
VDATA   = $D604
L0      = $D620
COPSTEP = $D640
COPSTEPS = $D643
COPDIV  = $D645
U0      = $D688
REU     = $DF00
SCREEN  = $0400
COLRAM  = $D800
CHROUT  = $FFD2
PALBUF  = $C000
REGS    = $9020         ; the camera's 24 bytes for the next frame
MUSIC_INIT = $1000
MUSIC_PLAY = $1003

tick    = $3A
paused  = $43
ksp     = $44
fr      = $52           ; 2: frames shown (0 - NFR-1)
cp      = $54           ; 2: the camera's REU address, low 16 bits, 32 a frame
up_r    = $70           ; 3: REU address
up_n    = $73           ; 3: bytes left
ptr     = $76
tp      = $67

        * = $0801
        !byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00
        jmp start

; the music hook (replace these two RTS with a player; $1000 once at the start, $1003 every frame)
        * = $1000
        rts
        !byte 0, 0
        rts

; silence: every register of all 8 SIDs 0 (F7)
!zone music_off
music_off
        ldx #7
.s      lda .dst,x
        sta ptr
        lda .dsth,x
        sta ptr+1
        ldy #$18
        lda #0
.z      sta (ptr),y
        dey
        bpl .z
        dex
        bpl .s
        rts
.dst    !byte $00, $20, $00, $20, $80, $a0, $80, $a0
.dsth   !byte $d4, $d4, $d5, $d5, $d4, $d4, $d5, $d5

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
        !pet "OCTOPUS NEEDS THE OCTOPHONIC 64 (OCTOVIC 2+)", 13, 0

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
        sta tick
        sta fr
        sta fr+1
        sta cp
        sta cp+1
        lda #<nmi
        sta $0318
        lda #>nmi
        sta $0319
        lda #0                  ; the VIC: black (see-through), the upper case set, white text, no sprites
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
        ldx #12                 ; the caption, rows 23 and 24, centred
.t1     lda t_c1,x
        sta SCREEN+23*40+13,x
        dex
        bpl .t1
        ldx #19
.t2     lda t_c2,x
        sta SCREEN+24*40+10,x
        dex
        bpl .t2
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
        lda #1                  ; the VIC's 16 colours: all black (0, the KEY, see-through) but colour 1, the text: white
        sta PALSEL
        lda #0
        sta PALIDX
        ldx #0
.vp     lda #0
        cpx #1
        bne +
        lda #255
+       sta PALR
        sta PALG
        sta PALB
        inx
        cpx #16
        bne .vp
        lda #2                  ; the backdrop: black until the copper starts
        sta PALSEL
        lda #0
        sta PALIDX
        sta PALR
        sta PALG
        sta PALB
        ; the picture, the sprites and the copper lists, from the REU into the VRAM (64 KB runs from 64 KB boundaries)
        lda #1
        sta VINC
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
        lda #<V_SPR
        ldx #>V_SPR
        ldy #^V_SPR
        jsr vset
        lda #<R_SPR
        sta up_r
        lda #>R_SPR
        sta up_r+1
        lda #^R_SPR
        sta up_r+2
        lda #<LEN_SPR
        sta up_n
        lda #>LEN_SPR
        sta up_n+1
        lda #^LEN_SPR
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
        lda #<V_SAT             ; the sprites
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
        lda #NSPR
        sta SPRCNT
        ; the layer: a 256 x 256 BITMAP (map 32 x 32 tiles), turned and sized, nothing drawn outside the picture
        lda #<V_PIC0
        sta L0+4
        lda #>V_PIC0
        sta L0+5
        lda #^V_PIC0
        sta L0+6
        lda #$0c
        sta L0+$f
        jsr camfetch            ; frame 0's numbers, and applied
        jsr vblank
        lda #$0b                ; on, 256 colours, BITMAP, 256 x 256
        sta L0
        ; the copper: a list a frame by itself (COPDIV 1), NLIST lists, then round again
        lda #<FB
        sta COPSTEP
        lda #>FB
        sta COPSTEP+1
        lda #^FB
        sta COPSTEP+2
        lda #<NLIST
        sta COPSTEPS
        lda #>NLIST
        sta COPSTEPS+1
        lda #1
        sta COPDIV
        lda #<V_COP
        sta COPBASE
        lda #>V_COP
        sta COPBASE+1
        lda #^V_COP
        sta COPBASE+2
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
        jsr MUSIC_INIT
        cli
        rts

t_c1    !scr "octophonic 64"
t_c2    !scr "8 sids - octovic 256"

!zone nmi
nmi     rti

!zone irq
irq     lda $d019
        sta $d019
        inc tick
        jmp $ea81

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
        jsr advance             ; the next frame's numbers (the copper moves on by itself)
        jsr MUSIC_PLAY
.p      jmp main

!zone waittick
waittick
.w      lda tick
        beq .w
        lda #0
        sta tick
        rts

; the camera: U0 V0 DUX DVX DUY DVY into OctoVIC
!zone vblank
vblank  ldx #23
.r      lda REGS,x
        sta U0,x
        dex
        bpl .r
        rts

; the next frame's 24 bytes from the REU (R_CAM + 32 a frame) into REGS; round again after NFR frames
!zone advance
advance jsr camfetch
        rts

!zone camfetch
camfetch
        lda #<REGS
        sta REU+2
        lda #>REGS
        sta REU+3
        lda cp
        sta REU+4
        lda cp+1
        clc
        adc #>R_CAM
        sta REU+5
        lda #^R_CAM
        adc #0
        sta REU+6
        lda #24
        sta REU+7
        lda #0
        sta REU+8
        sta REU+10
        lda #$91
        sta REU+1
        lda cp                  ; the next row
        clc
        adc #32
        sta cp
        bcc +
        inc cp+1
+       inc fr
        bne +
        inc fr+1
+       lda fr+1
        cmp #>NFR
        bne .x
        lda fr
        cmp #<NFR
        bne .x
        lda #0
        sta fr
        sta fr+1
        sta cp
        sta cp+1
.x      rts

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
        bne .e
        lda #1
        sta ksp
        lda paused
        eor #1
        sta paused
        sta tp
        lda #1                  ; the copper's animation stops with it
        sec
        sbc tp
        sta COPDIV
        jmp .e
.sp0    lda #0
        sta ksp
.e      lda #$ff
        sta $dc00
        rts

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
