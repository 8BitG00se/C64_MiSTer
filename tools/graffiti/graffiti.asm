; GRAFFITI WALL build 1 - a demo for the Octophonic 64 (OctoVIC 2+). By Mong00se.
; A full-screen brick wall (Neal's own photo, made into a seamless 384 x 256 tile by gen.py) with a big graffiti scroller sprayed
; on it. The wall is 35 sprites of 64 x 64 in 256 colours, priority 2 (behind both layers): 6 x 4 graphics repeated 7 x 5.
; Layer 1 (in front) is the lettering: 8 x 8 tiles in 256 colours, a map 256 x 32 tiles; the lettering is 16 tile rows tall.
; Layer 0 is its shadow: the SAME map, a second tile set (grey levels), in "taken away" mode (LMODE 3), scrolled 7 pixels
; down and right, so the letters throw a soft shadow onto the wall. The text scrolls 2 pixels a frame (SCROLLX); every 4
; frames the 6502 writes the next map column (16 words) from the REU where the beam can not see it. The lettering bobs 3 pixels.
; SPACE pauses, F7 quits to BASIC (all 8 SIDs silent). Silent: a music hook at $1003 is called every frame (JSR MUSIC_PLAY),
; $1000 once at the start; both are just RTS - put a tune there.
; 6502, ACME (-f cbm), loads at $0801 (10 SYS2061).
!cpu 6502
BUILD   = 1
SPEED   = 2             ; pixels a frame (a divisor of 8)
SHDX    = 7             ; the shadow lies this far right and down

OVER    = $D61F
OID     = $D61E
OCTRL   = $D605
OKEY    = $D606
SPRCNT  = $D60F
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
L0      = $D620         ; layer 0: the shadow (taken away from the wall)
L1      = $D630         ; layer 1: the lettering
REU     = $DF00
SCREEN  = $0400
COLRAM  = $D800
CHROUT  = $FFD2
PALBUF  = $C000
COLBUF  = $9020         ; the next map column: 16 words
MUSIC_INIT = $1000
MUSIC_PLAY = $1003

tick    = $3A
paused  = $43
ksp     = $44
sx      = $54           ; 2: the scroll, 0-2047 (the map is 256 tiles of 8)
mc      = $56           ; the map column the next write goes to (0-255)
ti      = $57           ; 2: the text column that goes in it (0 to NCOL-1)
bi      = $59           ; the bob's place in bobtab (0-127)
cl      = $5A           ; the map column's VRAM address, low and high
ch      = $5B
sy      = $5C
up_r    = $70           ; 3: REU address
up_n    = $73           ; 3: bytes left
ptr     = $76
tp      = $67

!macro upload .v, .r, .n {
        lda #<.v
        ldx #>.v
        ldy #^.v
        jsr vset
        lda #<.r
        sta up_r
        lda #>.r
        sta up_r+1
        lda #^.r
        sta up_r+2
        lda #<.n
        sta up_n
        lda #>.n
        sta up_n+1
        lda #^.n
        sta up_n+2
        jsr reuvram
}

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
        !pet "GRAFFITI WALL NEEDS THE OCTOPHONIC 64 (OCTOVIC 2+)", 13, 0

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
        sta sx
        sta sx+1
        sta mc
        sta ti
        sta ti+1
        sta bi
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
        ; the wall's graphics + sprite table, the tiles (letters, shadow), the empty map: from the REU into the VRAM
        lda #1
        sta VINC
        +upload V_LT, V_LT, LEN_LT
        +upload V_ST, V_ST, LEN_ST
        +upload V_MAP, V_MAP, LEN_MAP
        +upload V_SPR, V_SPR, LEN_SPR
        lda #<V_SAT             ; the sprites: 35 of 64 x 64, priority 2 (behind both layers)
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
        ; the two tile layers: 256 colours, map 256 x 32 tiles, one map, two tile sets
        lda #$33
        sta L0                  ; (off until the map is filled: written again below with b0)
        sta L1
        lda #<V_MAP
        sta L0+1
        sta L1+1
        lda #>V_MAP
        sta L0+2
        sta L1+2
        lda #^V_MAP
        sta L0+3
        sta L1+3
        lda #<V_ST
        sta L0+4
        lda #>V_ST
        sta L0+5
        lda #^V_ST
        sta L0+6
        lda #<V_LT
        sta L1+4
        lda #>V_LT
        sta L1+5
        lda #^V_LT
        sta L1+6
        lda #3                  ; the shadow layer takes its colour away from the wall under it
        sta L0+$f
        lda #0
        sta L1+$f
        lda #$32                ; (both layers off while the map is filled)
        sta L0
        sta L1
        lda #0
        sta mc
        sta ti
        sta ti+1
.pre    jsr colupdate           ; the map's first 53 columns, from text column 0
        lda mc
        cmp #53
        bne .pre
        jsr setscroll
        jsr waittick_init
        lda #$33
        sta L0
        sta L1
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

; (nothing to wait for: the picture is not on yet) 
waittick_init
        rts


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
        jsr setscroll           ; this frame's scrolls into OctoVIC (the beam is below the picture)
        jsr keys
        lda paused
        bne .p
        jsr advance             ; the next frame's: 2 pixels along, and a new map column every 4th
        jsr MUSIC_PLAY
.p      jmp main

!zone waittick
waittick
.w      lda tick
        beq .w
        lda #0
        sta tick
        rts

!zone setscroll
setscroll
        lda sx                  ; the lettering: SCROLLX = sx, SCROLLY = 12 + bob
        sta L1+8
        lda sx+1
        sta L1+9
        ldx bi
        lda bobtab,x
        sta sy
        sta L1+$a
        lda #0
        sta L1+$b
        sta L0+$b
        lda sx                  ; its shadow: the same, SHDX further back (so SHDX right and down on the screen)
        sec
        sbc #SHDX
        sta L0+8
        lda sx+1
        sbc #0
        and #7
        sta L0+9
        lda sy
        sec
        sbc #SHDX
        sta L0+$a
        rts

!zone advance
advance lda sx
        clc
        adc #SPEED
        sta sx
        bcc .a
        inc sx+1
.a      lda sx+1
        and #7                  ; 8 x 256 = 2048 pixels = the map's width
        sta sx+1
        inc bi
        lda bi
        and #127
        sta bi
        lda sx
        and #7
        bne .x
        jsr colupdate           ; a tile column has gone by: the next one in at the far side
.x      rts

; the text column ti (32 bytes: 16 map words) from the REU into the map's column mc, rows ROW0 - ROW0+15
!zone colupdate
colupdate
        lda ti                  ; the REU address: R_TEXT + 32 * ti
        asl
        asl
        asl
        asl
        asl
        sta REU+4
        lda ti
        lsr
        lsr
        lsr
        sta tp
        lda ti+1
        asl
        asl
        asl
        asl
        asl
        clc
        adc tp
        sta REU+5
        lda #^R_TEXT
        sta REU+6
        lda #<COLBUF
        sta REU+2
        lda #>COLBUF
        sta REU+3
        lda #32
        sta REU+7
        lda #0
        sta REU+8
        sta REU+10
        lda #$91
        sta REU+1
        lda mc                  ; the map word of row r, column mc: V_MAP + (r * 256 + mc) * 2
        asl
        sta cl
        lda #0
        rol
        sta ch
        ldx #0
.row    txa
        asl
        clc
        adc #ROW0*2
        adc ch
        sta VADDR+1
        lda cl
        sta VADDR
        lda #^V_MAP
        sta VADDR+2
        txa
        asl
        tay
        lda COLBUF,y
        sta VDATA
        lda COLBUF+1,y
        sta VDATA
        inx
        cpx #16
        bne .row
        inc mc
        inc ti
        bne .n
        inc ti+1
.n      lda ti
        cmp #<NCOL
        bne .x
        lda ti+1
        cmp #>NCOL
        bne .x
        lda #0
        sta ti
        sta ti+1
.x      rts

!src "data.inc"

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
