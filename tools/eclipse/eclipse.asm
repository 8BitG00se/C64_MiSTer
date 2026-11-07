; ECLIPSE BEACH build 1 - a backdrop demo for the Octophonic 64 (OctoVIC 2+). By Mong00se.
; A beach at the end of an afternoon and a total solar eclipse, 60 seconds, looping. Cinematic hi-res gradient pixel art.
; 6502, ACME (-f cbm), loads at $0801 (10 SYS2061). gen.py prepares the data in "Eclipse Beach.reu"; this program copies it
; into OctoVIC's VRAM while the screen is black and then, every second frame (25 ticks a second), plays one record of it:
;   VRAM $000000  the picture: a BITMAP layer (layer 0), 512 x 256, 256 colours (the sky, the sea, the beach as palette classes)
;   VRAM $020000  the sprite table (NSPR sprites, 8 bytes each)
;   VRAM $030000  the sprite graphics (the sun, the moon's bite, the corona, the ring, stars, foam, the sun glow)
;   REU  R_TICK + tick * 2048: [palette: 256 R, 256 G, 256 B][sprite table, SATLEN bytes]
; Every tick the 6502 copies the sprite table of the tick into the VRAM (REU DMA) and the palette into OctoVIC: the eclipse
; (sky, sea and sand darkening), the travelling wave crests (palette cycling) and the stars all happen in the palette and the
; sprite table. Nothing else is drawn: no copper and no blitter.
; Keys: 1-6 layers off/on (1 picture, 2 sun glow, 3 sun and moon, 4 corona and ring, 5 stars, 6 foam), L shows the layer
; names (gold = on, grey = off), D the debug line (LATE MAX TOT OVR), SPACE pause, F7 quits to BASIC. Clean by default.
!cpu 6502
BUILD   = 1
!src "data.inc"

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
L0      = $D620
LATE    = $D6A0
LATETOT = $D6A6
REU     = $DF00
SCREEN  = $0400
COLRAM  = $D800
CHROUT  = $FFD2
PALBUF  = $C000

V_PIC   = $000000
V_SAT   = $020000
V_SPR   = $030000
ROW24   = SCREEN + 960
ROW23   = SCREEN + 920

; zero page
tick    = $3A           ; frames the IRQ has counted
fpar    = $3B           ; frame parity: the work is done every second frame
paused  = $3C
lmask   = $3D           ; layer on/off bits 0-5
lab     = $3E           ; layer names shown
dbg     = $3F           ; debug line shown
kx      = $40
ovr     = $41
lmax    = $42
late    = $43
tk      = $44           ; 2: the next tick
cur     = $46           ; 2: the tick on screen
rmid    = $48
rhi     = $49
tp      = $4A
up_r    = $70           ; 3: REU address
up_n    = $73           ; 3: bytes left
dbgv    = $7A           ; 2
dg      = $7C
tx      = $7D
gs      = $7E
gn      = $7F

        * = $0801
        !byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00
        jmp start

; ======================================================================================================== start
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
        !pet "ECLIPSE BEACH NEEDS THE OCTOPHONIC 64 (OCTOVIC 2+)", 13, 0

; ======================================================================================================== init
!zone init
init    lda #$7f                ; no CIA interrupts: keys from the matrix, the frame is the raster IRQ
        sta $dc0d
        lda $dc0d
        lda #0
        sta $d01a
        lda #$ff
        sta $d019
        ldx #$9a                ; OctoVIC: everything zero (off)
        lda #0
.z      sta OCTRL,x
        dex
        cpx #$ff
        bne .z
        sta paused
        sta lab
        sta dbg
        sta ovr
        sta lmax
        sta tick
        sta fpar
        sta tk
        sta tk+1
        lda #$3f
        sta lmask
        lda #<nmi
        sta $0318
        lda #>nmi
        sta $0319
        lda #0                  ; the VIC: black (see-through), upper case set, no sprites
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
        lda #1                  ; the VIC's 16 colours (OctoVIC's): 0 black, 1 gold (text on), 11 grey (text off)
        sta PALSEL
        lda #0
        sta PALIDX
        ldx #0
.vp     lda vpal_r,x
        sta PALR
        lda vpal_g,x
        sta PALG
        lda vpal_b,x
        sta PALB
        inx
        cpx #16
        bne .vp
        lda #2                  ; the backdrop: black
        sta PALSEL
        lda #0
        sta PALIDX
        sta PALR
        sta PALG
        sta PALB
        sta PALSEL
        lda #1
        sta VINC
        ; the picture, the sprite graphics: REU into VRAM
        lda #<V_PIC
        ldx #>V_PIC
        ldy #^V_PIC
        jsr vset
        lda #<R_PIC
        sta up_r
        lda #>R_PIC
        sta up_r+1
        lda #^R_PIC
        sta up_r+2
        lda #<LEN_PIC
        sta up_n
        lda #>LEN_PIC
        sta up_n+1
        lda #^LEN_PIC
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
        lda #NSPR
        sta SPRCNT
        jsr setlayer            ; layer 0: the bitmap, 512 wide (64 tiles), 256 high (32 tiles), 256 colours
        jsr dotick              ; tick 0: palette and sprite table
        lda #0                  ; the VIC's black is see-through, the VIC in front; its palette is OctoVIC's
        sta OKEY
        lda #$0b
        sta OCTRL
        lda #<irq               ; the frame: a raster interrupt at line 300, below the picture
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
        cli
        rts

vpal_r  !byte 0,255,0,0,0,0,0,0,0,0,0,110,0,0,0,0
vpal_g  !byte 0,200,0,0,0,0,0,0,0,0,0,110,0,0,0,0
vpal_b  !byte 0,64,0,0,0,0,0,0,0,0,0,120,0,0,0,0

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

; the picture layer on or off (layer 0, bitmap, 64 x 32 tiles, 256 colours)
setlayer
        lda lmask
        and #1
        ora #$1a
        sta L0
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
        lda LATE                ; last frame's late lines
        sta late
        cmp lmax
        bcc .nl
        sta lmax
.nl     jsr keys
        lda paused
        bne .p
        lda fpar
        eor #1
        sta fpar
        bne .p
        jsr dotick
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

; one tick: the sprite table and the palette of record tk
!zone dotick
dotick  lda tk
        sta cur
        lda tk+1
        sta cur+1
        jsr satload
        ; the palette: REU -> PALBUF -> OctoVIC
        jsr recaddr
        lda #<PALBUF
        sta REU+2
        lda #>PALBUF
        sta REU+3
        lda #0
        sta REU+4
        lda rmid
        sta REU+5
        lda rhi
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
        inc tk                  ; on to the next tick; after the last, round again
        bne .n1
        inc tk+1
.n1     lda tk
        cmp #<NTICK
        bne .x
        lda tk+1
        cmp #>NTICK
        bne .x
        lda #0
        sta tk
        sta tk+1
.x      rts

; rmid, rhi: the REU address of record "cur" (R_TICK + cur * 2048; the low byte is 0)
recaddr lda cur
        asl
        asl
        asl
        sta rmid
        lda cur+1
        asl
        asl
        asl
        sta tp
        lda cur
        lsr
        lsr
        lsr
        lsr
        lsr
        ora tp
        clc
        adc #^R_TICK
        sta rhi
        rts

; the sprite table of tick "cur" into the VRAM (REU DMA), then the layers that are switched off have their sprites turned off
!zone satload
satload jsr recaddr
        lda rmid
        clc
        adc #3                  ; the table follows the 768 bytes of palette
        sta up_r+1
        lda rhi
        adc #0
        sta up_r+2
        lda #0
        sta up_r
        lda #<V_SAT
        ldx #>V_SAT
        ldy #^V_SAT
        jsr vset
        lda #<SATLEN
        sta up_n
        lda #>SATLEN
        sta up_n+1
        lda #0
        sta up_n+2
        jsr reuvram
        ldx #1                  ; groups 1-5: bit of lmask, first sprite, count
.g      lda lmask
        and lbit,x
        bne .on
        lda gfirst,x
        sta gs
        lda gcount,x
        sta gn
.s      lda gs                  ; VADDR = V_SAT + gs * 8 + 6
        sta tp
        lda #0
        sta tp+1
        asl tp
        rol tp+1
        asl tp
        rol tp+1
        asl tp
        rol tp+1
        lda tp
        clc
        adc #6
        sta VADDR
        lda tp+1
        adc #0
        clc
        adc #>V_SAT
        sta VADDR+1
        lda #^V_SAT
        sta VADDR+2
        lda #0
        sta VDATA
        inc gs
        dec gn
        bne .s
.on     inx
        cpx #6
        bne .g
        rts
lbit    !byte 1,2,4,8,16,32
gfirst  !byte 0,5,4,0,19,9      ; (index 0 is the picture)
gcount  !byte 0,4,1,4,90,10

; ======================================================================================================== keys
!zone keys
NKEYS   = 10
keys    ldx #0
.k      lda kcol,x
        sta $dc00
        lda $dc01
        and krow,x
        bne .up
        lda kst,x
        bne .nx
        lda #1
        sta kst,x
        stx kx
        jsr kact
        ldx kx
        jmp .nx
.up     lda #0
        sta kst,x
.nx     inx
        cpx #NKEYS
        bne .k
        lda #$ff
        sta $dc00
        rts
; F7  SPACE  1 2 3 4 5 6  L  D
kcol    !byte $fe,$7f,$7f,$7f,$fd,$fd,$fb,$fb,$df,$fb
krow    !byte $08,$10,$01,$08,$01,$08,$01,$08,$04,$04
kst     !byte 0,0,0,0,0,0,0,0,0,0

kact    cpx #0
        bne .a1
        jmp quit
.a1     cpx #1
        bne .a2
        lda paused
        eor #1
        sta paused
        rts
.a2     cpx #8
        bcs .a3
        lda lbit-2,x             ; keys 1-6: layer 0-5
        eor lmask
        sta lmask
        jsr setlayer
        jsr satload2
        jmp drawlabels
.a3     cpx #8
        bne .a4
        lda lab
        eor #1
        sta lab
        jmp drawlabels
.a4     lda dbg
        eor #1
        sta dbg
        jmp dbgtoggle

; reload the sprite table of the tick on screen (the layers changed)
satload2
        lda cur
        pha
        lda cur+1
        pha
        jsr satload
        pla
        sta cur+1
        pla
        sta cur
        rts

; ======================================================================================================== the layer names
!zone labels
drawlabels
        ldx #39
        lda lab
        bne .on
        lda #$20
.c      sta ROW24,x
        dex
        bpl .c
        rts
.on     lda t_lab,x
        sta ROW24,x
        dex
        bpl .on
        ldy #0                  ; colours: gold when the layer is on, grey when off
.w      lda lmask
        and lbit,y
        beq .off
        lda #1
        bne .go
.off    lda #11
.go     sta tp
        ldx lstart,y
        lda lend,y
        sta tp+1
.f      lda tp
        sta COLRAM+960,x
        inx
        cpx tp+1
        bne .f
        iny
        cpy #6
        bne .w
        rts
t_lab   !scr "1 pic 2 glow 3 sun 4 ring 5 star 6 foam  "
lstart  !byte 0,6,13,19,26,33
lend    !byte 5,12,18,25,32,39

; ======================================================================================================== debug
!zone debug
dbgtoggle
        ldx #39
        lda dbg
        bne .on
        lda #$20
.c      sta ROW23,x
        dex
        bpl .c
        rts
.on     lda t_dbg,x
        sta ROW23,x
        dex
        bpl .on
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

; dbgv as 5 digits at ROW23 + X
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
        sta ROW23,x
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
