; OCTO KARATE build 2 - the first slice of a one-on-one fighting game engine for the Octophonic 64 (OctoVIC 2+). By Mong00se.
; Everything runs as 6502 (ACME, -f cbm, $0801, 10 SYS2061). export.py prepares the DATA only (sprite frames, palettes, frame-data
; tables, hit / hurt boxes, text, the character set) in "Octo Karate.reu" and data.inc.
;
; The stage is Eclipse Beach: a bitmap layer picture + palette ticks + sun / moon / corona / stars / foam sprites, 25 ticks a second,
; 1500 ticks = the 60 s round. The fighters are 12 sprites (6 each, 256 colours) whose graphics pointers change every frame; their
; colours are part of the tick's palette, so the eclipse light fades them with no pixel written. The HUD is VIC text (own character
; set, see-through key colour) in front of everything.
;
; The game is a fixed-step loop at the display rate (50 Hz): every frame reads input, runs both fighters' state machines, tests
; HIT boxes against HURT boxes (active frames only, one hit per move), applies hitstop, hitstun / blockstun, pushback, pushboxes, then
; builds the next sprite table in the INACTIVE one of two tables in VRAM and, at the top of the next frame, points SATBASE at it (so
; the picture never sees a half written table).
;
; Keys: 1-8 layers off/on (1 picture, 2 glow, 3 sun, 4 corona/ring, 5 stars, 6 foam, 7 fighters, 8 HUD), L layer names (gold on, grey
; off), D debug line (LATE MAX TOT OVR), SPACE pause, F7 quit. Clean (no debug text) by default.
!cpu 6502
BUILD   = 2

VADDR   = $D600
VINC    = $D603
VDATA   = $D604
OCTRL   = $D605
OKEY    = $D606
OSTATUS = $D608
XADJ    = $D60C
YADJ    = $D60D
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
SID6    = $D580
SID7    = $D5A0

V_PIC   = $000000
V_SAT0  = $020000
V_SAT1  = $020400
V_SPR   = $030000
ROW24   = SCREEN + 960
ROW23   = SCREEN + 920

; ---- the rules (all in frames / pixels)
XMIN    = 2             ; positions are screen x - 32 (so the stage fits in a byte): 34 .. 286
XMAX    = 254
HPMAX   = 96            ; 16 segments of 6
START0  = 68
START1  = 188
BUFFER  = 6             ; input buffer, frames
INTRO1  = 50            ; "ROUND 1"
INTRO2  = 100           ; + "FIGHT!"
KOTIME  = 100
RESTIME = 170
ST_STAND = 0
ST_ATK  = 1
ST_HURT = 2
ST_BLK  = 3
ST_FALL = 4
ST_LIE  = 5
J_UP    = 1
J_DN    = 2
J_BK    = 4
J_FW    = 8
J_FI    = 16
PH_INTRO = 0
PH_FIGHT = 1
PH_KO   = 2
PH_RES  = 3

; zero page
tick    = $3A           ; frames the IRQ has counted
fpar    = $3B           ; frame parity: the palette tick is every second frame
paused  = $3C
lmask   = $3D           ; layer on/off bits 0-7
lab     = $3E
dbg     = $3F
kx      = $40
ovr     = $41
lmax    = $42
late    = $43
tk      = $44           ; 2: the next tick
cur     = $46           ; 2: the tick on screen
rmid    = $48
rhi     = $49
tp      = $4A
ptr     = $4C           ; 2
sd      = $4E           ; 2: screen pointer
cd      = $50           ; 2: colour pointer
t0      = $52
t1      = $53
t2      = $54
t3      = $55
t4      = $56
t5      = $57
t6      = $58
t7      = $59
rng     = $5A
fc      = $5B           ; the fighter being worked on
si      = $5C
di      = $5D
mclr    = $5E
mcol    = $5F
up_r    = $70           ; 3: REU address
up_n    = $73           ; 3: bytes left
dbgv    = $7A           ; 2
dg      = $7C
tx      = $7D
gs      = $7E
gn      = $7F
sfp     = $80           ; 2: sound script pointer
sfw     = $82           ; frames to wait in the script
tl      = $83
th      = $84
bxl     = $85
bxh     = $86

; game variables (two bytes each: fighter 0 = VIC, fighter 1 = SID)
V       = $C300
px_lo   = V+0
px_hi   = V+2
st      = V+4
mv      = V+6
fr      = V+8
tm      = V+10
hp      = V+12
hitdone = V+14
pushv   = V+16
wph     = V+18
wdir    = V+20
ibuf    = V+22
ibt     = V+24
pfire   = V+26
dr      = V+28
jin     = V+30
stot    = V+32
crch    = V+34
aitm    = V+36
aijin   = V+38
aifc    = V+40
bcr     = V+42
hrt     = V+44          ; hit results this frame: 0 none, 1 hit, 2 blocked
hxl     = V+46          ; hit box centre x (biased) lo/hi, y
hxh     = V+48
hyy     = V+50
; single bytes
mode    = V+52          ; 0 attract, 1 game
humans  = V+53          ; bit 0: fighter 0 on port 2, bit 1: fighter 1 on port 1
phase   = V+54
ptm     = V+55
ptmh    = V+56
hstop   = V+57
shkt    = V+58
sparkt  = V+59
sparkk  = V+60          ; 0 hit, 1 block
spxl    = V+61
spxh    = V+62
spy     = V+63
secs    = V+64
tsub    = V+65
winner  = V+66
kokind  = V+67
hpold0  = V+68
hpold1  = V+69
secold  = V+70
bobc    = V+71
ftop    = V+72          ; which fighter is drawn on top
satb    = V+73          ; the buffer being shown (0/1)
satpend = V+74          ; the buffer to show from the next frame
raw0    = V+75
raw1    = V+76
hudon   = V+77
hudredo = V+78
blink   = V+79
xshk    = V+80
yshk    = V+81
sfxreq  = V+82
fcnt    = V+83
cpuf    = V+84          ; raster lines used by the frame's logic (debug)
lgmax   = V+85
dis     = V+86          ; scratch

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
        !pet "OCTO KARATE NEEDS THE OCTOPHONIC 64 (OCTOVIC 2+)", 13, 0

; ======================================================================================================== init
!zone init
init    lda #$ff                ; the joystick ports: port A out (keyboard columns), port B in
        sta $dc02
        lda #0
        sta $dc03
        lda #$7f                ; no CIA interrupts: keys and joysticks from the matrix, the frame is the raster IRQ
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
        sta satb
        sta satpend
        sta lgmax
        lda #$ff
        sta lmask
        lda #$a7
        sta rng
        lda #<nmi
        sta $0318
        lda #>nmi
        sta $0319
        lda #0                  ; the VIC: black (see-through), our own character set at $3800, screen at $0400, no sprites
        sta $d020
        sta $d021
        sta $d015
        lda #$1e
        sta $d018
        ldx #0
.cl     lda #0
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
        lda #1                  ; the VIC's 16 colours (OctoVIC's)
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
        ; the picture and the sprite graphics: REU into VRAM
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
        lda #<V_SAT0
        sta SATBASE
        lda #>V_SAT0
        sta SATBASE+1
        lda #^V_SAT0
        sta SATBASE+2
        lda #<V_SPR
        sta SPRGFX
        lda #>V_SPR
        sta SPRGFX+1
        lda #^V_SPR
        sta SPRGFX+2
        lda #NG+NSPR
        sta SPRCNT
        jsr setlayer            ; layer 0: the bitmap, 512 wide (64 tiles), 256 high (32 tiles), 256 colours
        ; the SIDs for sound effects: 6 and 7 (the spare ones), full volume
        lda #$0f
        sta SID6+$18
        sta SID7+$18
        lda #0
        sta sfp
        sta sfp+1
        sta sfxreq
        lda #1
        sta hudon
        jsr newgame             ; attract mode first
        jsr dotick              ; tick 0: palette
        jsr buildsat
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

vpal_r  !byte 0,255,255,70,120,175,225,245,245,235,225,140,80,96,240,40
vpal_g  !byte 0,255,200,225,225,225,220,180,135,85,45,140,70,150,240,32
vpal_b  !byte 0,255,64,90,70,60,50,45,40,40,45,150,92,255,255,44

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
        ; --- the top of the frame (vertical blank): show the sprite table built last frame, the screen shake
        lda satpend
        sta satb
        beq .s0
        lda #<V_SAT1
        sta SATBASE
        lda #>V_SAT1
        sta SATBASE+1
        lda #^V_SAT1
        sta SATBASE+2
        jmp .sd
.s0     lda #<V_SAT0
        sta SATBASE
        lda #>V_SAT0
        sta SATBASE+1
        lda #^V_SAT0
        sta SATBASE+2
.sd     lda xshk
        sta XADJ
        lda yshk
        sta YADJ
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
        bne .nt
        jsr dotick
.nt     jsr gamelogic
        jsr buildsat
!ifdef TRACE {
        lda $d012               ; how far down the frame the work got (the IRQ is at line 300): line / 2, bit 7 = line >= 256
        lsr
        sta t0
        lda $d011
        and #$80
        ora t0
        sta $d6ef
}
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

; ======================================================================================================== the stage tick: the palette
; (the sprite table of the stage is copied by buildsat, every frame, into the table that is not being shown)
!zone dotick
dotick  lda tk
        sta cur
        lda tk+1
        sta cur+1
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
        lda phase               ; the stage stands still during the intro
        beq .x
        lda phase
        cmp #PH_FIGHT
        bne .adv
        inc tsub                ; the round timer: 25 ticks a second
        lda tsub
        cmp #25
        bcc .adv
        lda #0
        sta tsub
        lda secs
        beq .adv
        dec secs
.adv    lda tk+1                ; on to the next tick; the last one is held
        cmp #>(NTICK-1)
        bne .inc
        lda tk
        cmp #<(NTICK-1)
        beq .x
.inc    inc tk
        bne .x
        inc tk+1
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

; ======================================================================================================== keys
!zone keys
NKEYS   = 12
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
; F7  SPACE  1 2 3 4 5 6 7 8  L  D
kcol    !byte $fe,$7f,$7f,$7f,$fd,$fd,$fb,$fb,$f7,$f7,$df,$fb
krow    !byte $08,$10,$01,$08,$01,$08,$01,$08,$01,$08,$04,$04
kst     !byte 0,0,0,0,0,0,0,0,0,0,0,0

kact    cpx #0
        bne .a1
        jmp quit
.a1     cpx #1
        bne .a2
        lda paused
        eor #1
        sta paused
        rts
.a2     cpx #10
        bcs .a3
        lda lbit-2,x            ; keys 1-8: layer 0-7
        eor lmask
        sta lmask
        jsr setlayer
        lda #1
        sta hudredo
        jmp drawlabels
.a3     cpx #10
        bne .a4
        lda lab
        eor #1
        sta lab
        jmp drawlabels
.a4     lda dbg
        eor #1
        sta dbg
        jmp dbgtoggle

lbit    !byte 1,2,4,8,16,32,64,128

; ======================================================================================================== the layer names
!zone labels
drawlabels
        ldx #39
        lda lab
        bne .on
        lda #$20
        lda #0
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
        lda #2
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
        cpy #8
        bne .w
        rts

; ======================================================================================================== debug
!zone debug
dbgtoggle
        ldx #39
        lda dbg
        bne .on
.c      lda #0
        sta ROW23,x
        dex
        bpl .c
        rts
.on     lda t_dbg,x
        sta ROW23,x
        lda #1
        sta COLRAM+920,x
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

; dbgv as 5 digits at ROW23 + X (our digits are codes 28-37: "0" is the glyph after Z)
pr5     stx tx
        ldy #0
.nd     lda #0
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
        clc
        adc #DIG0
        ldx tx
        sta ROW23,x
        inc tx
        iny
        cpy #5
        bne .nd
        rts
pw_lo   !byte <10000, <1000, <100, <10, <1
pw_hi   !byte >10000, >1000, >100, >10, >1

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

; ======================================================================================================== messages (the HUD's text)
; a message is blocks [col, row, colour, codes..., $FF] ended by $FE; code 0 is blank
!zone msg
drawmsg ldy #0
.blk    lda (ptr),y
        cmp #$fe
        beq .done
        sta mcol
        iny
        lda (ptr),y
        tax
        iny
        lda (ptr),y
        sta mclr
        iny
        sty si
        lda rowlo,x
        clc
        adc mcol
        sta sd
        sta cd
        lda rowhi,x
        adc #0
        sta sd+1
        clc
        adc #$d4                ; colour RAM = screen + $D400
        sta cd+1
        lda #0
        sta di
.ch     ldy si
        lda (ptr),y
        inc si
        cmp #$ff
        beq .eob
        ldy di
        sta (sd),y
        lda mclr
        sta (cd),y
        inc di
        jmp .ch
.eob    lda si                  ; the next block: move the pointer on (a message can be longer than 256 bytes)
        clc
        adc ptr
        sta ptr
        bcc .nb
        inc ptr+1
.nb     ldy #0
        jmp .blk
.done   rts

; message A/X = address lo/hi
showmsg sta ptr
        stx ptr+1
        jmp drawmsg

!macro MSG .m {
        lda #<.m
        ldx #>.m
        jsr showmsg
}

; ======================================================================================================== random numbers
!zone rnd
rnd     lda rng
        lsr
        bcc .a
        eor #$b8
.a      lsr
        bcc .b
        eor #$b8
.b      sta rng
        eor fcnt
        rts

; ======================================================================================================== a new round
!zone newround
; new game: attract mode (CPU against CPU)
newgame lda #0
        sta mode
        sta humans
        jmp newround

newround
        lda #0                  ; fighters
        ldx #1
.f      sta st,x
        sta mv,x
        sta fr,x
        sta tm,x
        sta hitdone,x
        sta pushv,x
        sta wph,x
        sta wdir,x
        sta ibt,x
        sta pfire,x
        sta crch,x
        sta aitm,x
        sta aijin,x
        sta aifc,x
        sta jin,x
        sta hrt,x
        lda #HPMAX
        sta hp,x
        lda #$ff
        sta ibuf,x
        lda #D_GUARD
        sta dr,x
        lda #0
        dex
        bpl .f
        lda #<START0
        sta px_lo
        lda #START1
        sta px_lo+1
        lda #0
        sta px_hi
        sta px_hi+1
        lda #PH_INTRO
        sta phase
        lda #0
        sta ptm
        sta ptmh
        sta hstop
        sta shkt
        sta sparkt
        sta winner
        sta kokind
        sta xshk
        sta yshk
        sta tk
        sta tk+1
        sta tsub
        sta bobc
        sta ftop
        lda #60
        sta secs
        lda #$ff
        sta secold
        sta hpold0
        sta hpold1
        lda #1
        sta hudredo
        rts

; ======================================================================================================== the game logic, once a frame
!zone logic
gamelogic
        inc fcnt
        jsr readinput
!ifdef TRACE { lda #6:sta $d6e0 }
        jsr phaseupd
!ifdef TRACE { lda #7:sta $d6e0 }
        lda hstop
        beq .run
        dec hstop
        jmp .after
.run    ldx #0
        jsr fupdate
        ldx #1
        jsr fupdate
        ldx #0
        jsr choosedr
        ldx #1
        jsr choosedr
        jsr hits
        jsr pushes
.after  ldx #0
        jsr inbuf
        ldx #1
        jsr inbuf
        ldx #0
        jsr choosedr
        ldx #1
        jsr choosedr
        ; who is drawn on top: the one attacking
        lda st
        cmp #ST_ATK
        beq .t0
        lda st+1
        cmp #ST_ATK
        bne .tx
        lda #1
        sta ftop
        jmp .tx
.t0     lda #0
        sta ftop
.tx     jsr shake
        jsr sfxstep
        jsr hud
        inc bobc
!ifdef TRACE {
        lda px_lo
        sta $d6e2
        lda px_lo+1
        sta $d6e3
        lda hp
        sta $d6e4
        lda hp+1
        sta $d6e5
        lda st
        asl
        asl
        asl
        asl
        ora mv
        sta $d6e6
        lda st+1
        asl
        asl
        asl
        asl
        ora mv+1
        sta $d6e7
        lda hstop
        sta $d6e8
        lda px_hi+1
        asl
        asl
        asl
        asl
        ora px_hi
        sta $d6e9
        lda phase
        asl
        asl
        asl
        asl
        ora mode
        sta $d6ea
        lda late
        sta $d6e1
        lda dr+1
        sta $d6ec
        lda secs
        sta $d6ed
        lda hrt
        ora hrt+1
        sta $d6ee
}
        rts

; ---------------------------------------------------------------------------------------- input
; joystick bits: 1 up, 2 down, 4 left, 8 right, 16 fire (active low on the CIAs)
!zone input
!zone z1
readinput
        lda $dc00               ; control port 2
        eor #$ff
        and #$1f
        sta raw0
        lda $dc01               ; control port 1
        eor #$ff
        and #$1f
        sta raw1
!ifdef TRACE {
        lda fcnt                ; test build: a scripted stick stands in for the player on port 2
        lsr
        lsr
        lsr
        and #15
        tax
        lda fakejoy,x
        sta raw0
        lda raw0
        sta $d6eb
}
        lda mode                ; attract: a fire button starts a game
        bne .game
        lda ptm
        cmp #20
        bcc .game
        lda raw0
        and #16
        beq .p1
        lda #1
        bne .go
.p1     lda raw1
        and #16
        beq .game
        lda #3
.go     pha
        lda #1
        sta mode
!ifdef TRACE { sta $d6e0 }
        jsr newround
!ifdef TRACE { lda #2:sta $d6e0 }
        pla
        sta humans
.game   ; canonical bits: up, down, back, forward, fire
!ifdef TRACE { lda #5:sta $d6e0 }
        lda #0
        sta jin
        sta jin+1
        lda phase
        cmp #PH_FIGHT
        bne .done               ; nobody steers outside the fight
        lda humans
        and #1
        beq .cpu0
        lda raw0                ; fighter 0 faces right: right = forward
        ldx #0
        jsr canon
        sta jin
        jmp .f1
.cpu0   ldx #0
        jsr ai
.f1     lda humans
        and #2
        beq .cpu1
        lda raw1                ; fighter 1 faces left: left = forward
        ldx #1
        jsr canon
        sta jin+1
        rts
.cpu1   ldx #1
        jmp ai
.done   rts

!ifdef TRACE {
fakejoy !byte 8,8,24,16,4,20,2,18,6,17,8,8,25,4,22,16
}
; A = raw joystick, X = fighter -> canonical in A
!zone z2
canon   sta t0
        lda #0
        sta t1
        lda t0
        and #1
        beq .a
        lda #J_UP
        ora t1
        sta t1
.a      lda t0
        and #2
        beq .b
        lda #J_DN
        ora t1
        sta t1
.b      lda t0
        and #4                  ; left
        beq .c
        lda t1
        cpx #0
        bne .l1
        ora #J_BK
        sta t1
        jmp .c
.l1     ora #J_FW
        sta t1
.c      lda t0
        and #8                  ; right
        beq .d
        lda t1
        cpx #0
        bne .r1
        ora #J_FW
        sta t1
        jmp .d
.r1     ora #J_BK
        sta t1
.d      lda t0
        and #16
        beq .e
        lda t1
        ora #J_FI
        sta t1
.e      lda t1
        rts

; the move a fire press means (A = canonical bits): up head kick, down shin, forward body kick, back front kick, else punch
!zone z3
pickmove
        and #(J_UP|J_DN|J_BK|J_FW)
        sta t0
        and #J_UP
        beq .m1
        lda #1
        rts
.m1      lda t0
        and #J_DN
        beq .m2
        lda #4
        rts
.m2      lda t0
        and #J_FW
        beq .m3
        lda #2
        rts
.m3      lda t0
        and #J_BK
        beq .m4
        lda #3
        rts
.m4      lda #0
        rts

; the input buffer: a fire press (an edge) is kept for BUFFER frames, with the move it meant
!zone z4
inbuf   lda jin,x
        and #J_FI
        beq .rel
        lda pfire,x
        bne .x
        lda #1
        sta pfire,x
        lda jin,x
        jsr pickmove
        sta ibuf,x
        lda #BUFFER
        sta ibt,x
.x      rts
.rel    lda #0
        sta pfire,x
        rts

; ---------------------------------------------------------------------------------------- the fighters
!zone fighter
!zone z5
fdir    !byte 1,$ff             ; forward direction on screen

!zone z6
fupdate stx fc
        lda ibt,x
        beq .nb
        lda st,x
        cmp #ST_STAND           ; a buffered press is used when the fighter can act
        beq .nb
        dec ibt,x               ; (it runs out while the fighter is busy)
.nb     lda st,x
        bne .n1
        jmp f_stand
.n1     cmp #ST_ATK
        bne .n2
        jmp f_atk
.n2     cmp #ST_FALL
        bne .n3
        jmp f_fall
.n3     cmp #ST_LIE
        beq .r
        ; hurt or blocking: count the stun down
        dec tm,x
        bne .r
        lda #ST_STAND
        sta st,x
        lda #0
        sta wdir,x
        sta wph,x
.r      rts

!zone z7
f_stand lda ibt,x
        beq .nobuf
        lda #0
        sta ibt,x
        lda ibuf,x
        jmp startmove
.nobuf  lda jin,x
        and #J_DN
        beq .up
        lda #1                  ; crouching
        sta crch,x
        lda #0
        sta wdir,x
        sta wph,x
        rts
.up     lda #0
        sta crch,x
        lda wdir,x
        bne .walking
        lda jin,x
        and #J_FW
        beq .nofw
        ; start a step forward if there is room
        jsr gapof               ; A = gap between the fighters
        sec
        sbc #STRIDE
        bcc .idle
        cmp #PUSHGAP
        bcc .idle
        lda #1
        sta wdir,x
        lda #0
        sta wph,x
        jmp .walking
.nofw   lda jin,x
        and #J_BK
        beq .idle
        ; a step back: the body moves at once, the legs play the cycle backwards
        lda #STRIDE
        jsr backstep
        bcs .idle
        lda #2
        sta wdir,x
        lda #0
        sta wph,x
        rts
.idle   rts
.walking
        inc wph,x
        lda wph,x
        cmp #12
        bcc .more
        lda #0
        sta wph,x
        lda wdir,x
        sta t7
        lda #0
        sta wdir,x
        lda t7
        cmp #1
        bne .more
        lda #STRIDE             ; the forward step lands: the body moves on
        jsr fwdstep
.more   rts

; the gap between the fighters (px1 - px0), clamped to 255
!zone z8
gapof   sec
        lda px_lo+1
        sbc px_lo
        sta t0
        lda px_hi+1
        sbc px_hi
        beq .ok
        lda #255
        rts
.ok     lda t0
        rts

; X = fighter, A = pixels: move forward (towards the other), stopped by the pushbox
!zone z9
fwdstep sta t5
        cpx #0
        bne .f1
        clc
        lda px_lo
        adc t5
        sta px_lo
        bcc .c0
        inc px_hi
.c0     jmp clampf
.f1     sec
        lda px_lo+1
        sbc t5
        sta px_lo+1
        bcs .c1
        dec px_hi+1
.c1     jmp clampf

; X = fighter, A = pixels: step back (away); carry set when the wall is in the way
!zone z10
backstep
        sta t5
        cpx #0
        bne .b1
        lda px_hi
        bne .ok0
        lda px_lo
        sec
        sbc t5
        bcc .wall
        cmp #XMIN
        bcc .wall
.ok0    sec
        lda px_lo
        sbc t5
        sta px_lo
        bcs .d0
        dec px_hi
.d0     clc
        rts
.b1     clc
        lda px_lo+1
        adc t5
        tay
        lda px_hi+1
        adc #0
        bne .wall
        cpy #XMAX+1
        bcs .wall
        sty px_lo+1
        clc
        rts
.wall   sec
        rts

; keep fighter X inside the stage and out of the other's pushbox (the mover is stopped)
!zone z11
clampf  lda px_hi
        bne .c1
        lda px_lo
        cmp #XMIN
        bcs .c1
        lda #XMIN
        sta px_lo
.c1     lda px_hi+1
        bne .hi
        lda px_lo+1
        cmp #XMAX+1
        bcc .g
.hi     lda #XMAX
        sta px_lo+1
        lda #0
        sta px_hi+1
.g      jsr gapof
        cmp #PUSHGAP
        bcs .ok
        cpx #0
        bne .m1
        lda px_lo+1             ; fighter 0: px0 = px1 - PUSHGAP
        sec
        sbc #PUSHGAP
        sta px_lo
        lda px_hi+1
        sbc #0
        sta px_hi
        rts
.m1     lda px_lo               ; fighter 1: px1 = px0 + PUSHGAP
        clc
        adc #PUSHGAP
        sta px_lo+1
        lda px_hi
        adc #0
        sta px_hi+1
.ok     rts

; A = move, X = fighter
!zone z12
startmove
        sta mv,x
        lda #ST_ATK
        sta st,x
        lda #0
        sta fr,x
        sta hitdone,x
        sta wdir,x
        sta wph,x
        lda #1                  ; a whoosh
        sta sfxreq
        rts

!zone z13
f_atk   inc fr,x
        lda fr,x
        ldy mv,x
        cmp mv_len,y
        bcc .r
        lda #ST_STAND
        sta st,x
        lda #0
        sta wdir,x
        sta wph,x
.r      rts

!zone z14
f_fall  inc fr,x
        lda fr,x
        cmp #FALL3_T
        bcc .r
        lda #ST_LIE
        sta st,x
.r      rts

; the drawing of fighter X for this frame, from its state
!zone z15
choosedr
        lda st,x
        beq .stand
        cmp #ST_ATK
        beq .atk
        cmp #ST_HURT
        beq .hurt
        cmp #ST_BLK
        bne .c1
        jmp .blk
.c1     cmp #ST_FALL
        bne .c2
        jmp .fall
.c2     lda #D_LIE
        sta dr,x
        rts
.stand  lda crch,x
        beq .nc
        lda jin,x
        and #J_BK
        bne .cb
        lda #D_CROUCH
        sta dr,x
        rts
.cb     lda #D_CBLOCK
        sta dr,x
        rts
.nc     lda wdir,x
        beq .bob
        lda wph,x
        lsr
        cmp #6
        bcc .w1
        lda #5
.w1     tay
        lda wdir,x
        cmp #2
        bne .fw
        sty t0
        lda #5
        sec
        sbc t0
        tay
.fw     lda walk_ids,y
        sta dr,x
        rts
.bob    lda bobc
        lsr
        lsr
        lsr
        lsr
        and #3
        tay
        lda bob_ids,y
        sta dr,x
        rts
.atk    lda mv,x
        tay
        lda mv_seq_lo,y
        sta ptr
        lda mv_seq_hi,y
        sta ptr+1
        ldy fr,x
        lda (ptr),y
        sta dr,x
        rts
.hurt   lda stot,x              ; elapsed = stot - tm
        sec
        sbc tm,x
        cmp #6
        bcc .h1
        lda tm,x
        cmp #4
        bcc .h3
        lda #D_HIT2
        sta dr,x
        rts
.h1     lda #D_HIT1
        sta dr,x
        rts
.h3     lda #D_HIT3
        sta dr,x
        rts
.blk    lda bcr,x
        beq .sb
        lda #D_CBLOCK
        sta dr,x
        rts
.sb     lda #D_BLOCK
        sta dr,x
        rts
.fall   lda fr,x
        cmp #6
        bcc .h1
        cmp #12
        bcc .f1
        lda #D_FALL2
        sta dr,x
        rts
.f1     lda #D_FALL1
        sta dr,x
        rts

!zone z16
bob_ids !byte D_GUARD,D_BOB1,D_GUARD,D_BOB2
; ---------------------------------------------------------------------------------------- the drawing record of fighter X -> ptr
!zone z17
dbase_lo !byte <dtab_vic,<dtab_sid
!zone z18
dbase_hi !byte >dtab_vic,>dtab_sid
!zone z19
drec    lda dr,x
        sta ptr
        lda #0
        sta ptr+1
        asl ptr
        rol ptr+1
        asl ptr
        rol ptr+1
        asl ptr
        rol ptr+1
        asl ptr
        rol ptr+1
        asl ptr
        rol ptr+1
        lda ptr
        clc
        adc dbase_lo,x
        sta ptr
        lda ptr+1
        adc dbase_hi,x
        sta ptr+1
        rts

; px[X] + sext(A) + 256 -> tl, th
!zone z20
absx    sta t0
        clc
        lda px_lo,x
        adc t0
        sta tl
        lda px_hi,x
        adc #0
        sta th
        lda t0
        bmi .n
        inc th
.n      rts

; ---------------------------------------------------------------------------------------- hits
!zone hits
; test fighter X's HIT box against the other's HURT boxes: hrt,x = 0 none, 1 hit, 2 blocked
HAX0L = V+90
HAX0H = V+91
HAX1L = V+92
HAX1H = V+93
HAY0  = V+94
HAY1  = V+95
!zone z21
hits    lda #0
        sta hrt
        sta hrt+1
        ldx #0
        jsr testhit
        ldx #1
        jsr testhit
        ldx #0
        lda hrt
        beq .n0
        jsr applyhit
.n0     ldx #1
        lda hrt+1
        beq .n1
        jsr applyhit
.n1     rts

!zone z22
testhit stx fc
        jmp .start
.no     ldx fc
        rts
.start  lda st,x
        cmp #ST_ATK
        bne .no
        lda hitdone,x
        bne .no
        ldy mv,x
        lda fr,x
        cmp mv_act0,y
        bcc .no
        cmp mv_act1,y
        beq .act
        bcs .no
.act    txa                     ; the defender must be on his feet or in the air: not falling / lying
        eor #1
        tay
        lda st,y
        cmp #ST_FALL
        bcs .no
        jsr drec                ; the attacker's drawing record
        ldy #14
        lda (ptr),y
        beq .no
        ldy #28
        lda (ptr),y
        jsr absx
        lda tl
        sta HAX0L
        lda th
        sta HAX0H
        ldy #29
        lda (ptr),y
        ldx fc
        jsr absx
        lda tl
        sta HAX1L
        lda th
        sta HAX1H
        ldy #30
        lda (ptr),y
        sta HAY0
        iny
        lda (ptr),y
        sta HAY1
        ; the defender's three hurt boxes
        ldx fc
        txa
        eor #1
        tax                     ; X = defender
        jsr drec
        lda #0
        sta t6                  ; box counter
        lda #16
        sta t7                  ; offset
.box    ldy t7
        lda (ptr),y             ; bx0
        jsr absx
        lda tl
        sta t1                  ; b.x0 lo
        lda th
        sta t2
        ldy t7
        iny
        lda (ptr),y
        jsr absx
        lda tl
        sta t3                  ; b.x1
        lda th
        sta t4
        ; a.x0 <= b.x1 ?
        sec
        lda t3
        sbc HAX0L
        lda t4
        sbc HAX0H
        bcc .next
        ; b.x0 <= a.x1 ?
        sec
        lda HAX1L
        sbc t1
        lda HAX1H
        sbc t2
        bcc .next
        ; y: a.y0 <= b.y1, b.y0 <= a.y1
        ldy t7
        iny
        iny
        iny
        lda (ptr),y             ; b.y1
        cmp HAY0
        bcc .next
        dey
        lda (ptr),y             ; b.y0
        cmp HAY1
        beq .y1
        bcs .next
.y1     jmp .connect
.next   lda t7
        clc
        adc #4
        sta t7
        inc t6
        lda t6
        cmp #3
        bcc .more
        jmp .no
.more   jmp .box
.connect
        ldx fc
        ; hit or block?
        txa
        eor #1
        tay                     ; Y = defender
        lda st,y
        cmp #ST_STAND
        beq .elig
        cmp #ST_BLK
        bne .hitit
.elig   lda jin,y
        and #J_BK
        beq .hitit
        ldy mv,x
        lda mv_level,y
        cmp #2
        beq .low
        cmp #0
        beq .high
        lda #2                  ; mid: blocked standing or crouching
        sta hrt,x
        jmp .pos
.low    txa
        eor #1
        tay
        lda jin,y
        and #J_DN
        beq .hitit
        lda #2
        sta hrt,x
        jmp .pos
.high   txa
        eor #1
        tay
        lda jin,y
        and #J_DN
        bne .hitit
        lda #2
        sta hrt,x
        jmp .pos
.hitit  lda #1
        sta hrt,x
.pos    ; the spark: the centre of the attacker's hit box
        lda HAX0L
        clc
        adc HAX1L
        sta t0
        lda HAX0H
        adc HAX1H
        lsr
        sta hxh,x
        lda t0
        ror
        sta hxl,x
        lda HAY0
        clc
        adc HAY1
        ror
        sta hyy,x
        rts

; apply the result for attacker X (hrt,x)
!zone z23
applyhit
        stx fc
        txa
        eor #1
        tay                     ; Y = defender
        lda #1
        sta hitdone,x
        lda hrt,x
        cmp #2
        bne .ishit
        jmp .block
.ishit  ; ---- a hit
        sty t5
        ldy mv,x
        lda mv_dmg,y
        sta t0
        lda mv_hs,y
        sta hstop
        lda mv_hstun,y
        sta t1
        lda mv_pushh,y
        sta t2
        ldy t5
        lda hp,y
        sec
        sbc t0
        bcs .hp
        lda #0
.hp     sta hp,y
        lda #ST_HURT
        sta st,y
        lda t1
        sta tm,y
        sta stot,y
        lda #0
        sta wdir,y
        sta wph,y
        sta ibt,y
        lda t2
        sta pushv,y
        lda #0
        sta sparkk
        lda #2                  ; the thud
        sta sfxreq
        lda hp,y
        bne .shk
        ; ---- K.O.
        lda #ST_FALL
        sta st,y
        lda #0
        sta fr,y
        lda #16
        sta pushv,y
        lda #18
        sta hstop
        lda #PH_KO
        sta phase
        lda #0
        sta ptm
        sta ptmh
        sta kokind
        stx winner
        +MSG msg_title_off
        +MSG msg_banner_off
        +MSG msg_ko
.shk    lda #14
        sta shkt
        jmp .spark
.block  sty t5
        ldy mv,x
        lda mv_hs,y
        sec
        sbc #2
        sta hstop
        lda mv_bstun,y
        sta t1
        lda mv_pushb,y
        sta t2
        ldy t5
        lda #ST_BLK
        sta st,y
        lda t1
        sta tm,y
        lda #0
        sta wdir,y
        sta wph,y
        lda t2
        sta pushv,y
        lda jin,y
        and #J_DN
        sta bcr,y
        lda #1
        sta sparkk
        lda #3                  ; the clack
        sta sfxreq
        lda #6
        sta shkt
.spark  ldx fc
        lda #12
        sta sparkt
        lda hxl,x
        sta spxl
        lda hxh,x
        sta spxh
        lda hyy,x
        sta spy
        rts

; the knock back: each frame up to 3 pixels away from the other; a fighter against the wall pushes the attacker back instead
!zone pushes
!zone z24
pushes  ldx #0
        jsr .one
        ldx #1
        jsr .one
        jsr separate
        rts
.one    lda pushv,x
        beq .r
        cmp #3
        bcc .s
        lda #3
.s      sta t4
        lda pushv,x
        sec
        sbc t4
        sta pushv,x
        lda t4
        sta t5
        cpx #0
        bne .p1
        lda px_hi               ; fighter 0 goes left
        bne .ok0
        lda px_lo
        sec
        sbc t5
        bcc .wl
        cmp #XMIN
        bcs .ok0
.wl     lda px_lo               ; the wall takes part of it
        sec
        sbc #XMIN
        bcs .part
        lda #0
.part   sta t6
        lda t5
        sec
        sbc t6
        sta t5                  ; what the wall refused: the other fighter goes right by it
        lda t6
        sta t4
        lda #0
        beq .mv0
.ok0    lda t5
        sta t4
        lda #0
        sta t5
.mv0    lda px_lo
        sec
        sbc t4
        sta px_lo
        bcs .e0
        dec px_hi
.e0     lda t5
        beq .r
        clc
        lda px_lo+1
        adc t5
        sta px_lo+1
        bcc .r
        inc px_hi+1
.r      rts
.p1     lda px_lo+1             ; fighter 1 goes right
        clc
        adc t5
        tay
        lda px_hi+1
        adc #0
        bne .wr
        cpy #XMAX+1
        bcc .ok1
.wr     lda #XMAX
        sec
        sbc px_lo+1
        bcs .part1
        lda #0
.part1  sta t6
        lda t5
        sec
        sbc t6
        sta t5
        lda t6
        sta t4
        jmp .mv1
.ok1    lda t5
        sta t4
        lda #0
        sta t5
.mv1    clc
        lda px_lo+1
        adc t4
        sta px_lo+1
        bcc .e1
        inc px_hi+1
.e1     lda t5
        beq .r
        sec
        lda px_lo
        sbc t5
        sta px_lo
        bcs .r
        dec px_hi
        rts

; pushboxes: fighters cannot stand inside each other (equal share), walls first
!zone z25
separate
        jsr gapof
        cmp #PUSHGAP
        bcs .ok
        sta t0
        lda #PUSHGAP
        sec
        sbc t0
        lsr
        adc #0                  ; need / 2 rounded up
        sta t1
        sec
        lda px_lo
        sbc t1
        sta px_lo
        bcs .a
        dec px_hi
.a      clc
        lda px_lo+1
        adc t1
        sta px_lo+1
        bcc .b
        inc px_hi+1
.b      ldx #0
        jsr clampf
        ldx #1
        jsr clampf
.ok     rts

; ======================================================================================================== the CPU opponent
!zone ai
; X = fighter: sets jin,x. Decides every few frames: close in, attack with a move that reaches, block, back off, wait.
!zone z26
ai      lda st,x
        beq .stand
        lda #0                  ; busy (hurt, attacking...): no stick
        sta jin,x
        sta aitm,x
        rts
.stand  lda aitm,x
        beq .decide
        dec aitm,x
        lda aijin,x
        ldy aifc,x
        beq .nofire
        dec aifc,x
        bne .out
.nofire and #(J_UP|J_DN|J_BK|J_FW)
.out    sta jin,x
        rts
.decide stx fc
        jsr rnd
        sta t6
        jsr gapof
        sta t5                  ; gap
        ldx fc
        txa
        eor #1
        tay                     ; Y = opponent
        lda st,y
        cmp #ST_ATK
        bne .noblk
        lda t5
        cmp #110
        bcs .noblk
        lda t6
        and #1
        beq .noblk              ; half the time it does not react
        lda #J_BK
        sta aijin,x
        lda mv,y                ; low attacks need a crouching guard
        tay
        lda mv_level,y
        cmp #2
        bne .hb
        lda aijin,x
        ora #J_DN
        sta aijin,x
.hb     lda t6
        lsr
        lsr
        lsr
        and #7
        clc
        adc #10
        sta aitm,x
        lda #0
        sta aifc,x
        jmp .stick
.noblk  lda t5
        cmp #92
        bcc .near
        lda #J_FW               ; too far: walk in
        sta aijin,x
        lda t6
        and #15
        clc
        adc #8
        sta aitm,x
        lda #0
        sta aifc,x
        jmp .stick
.near   jsr rnd
        and #7
        cmp #5
        bcs .other
        ; attack: a random move that reaches
        jsr rnd
        and #7
        cmp #5
        bcc .m
        sec
        sbc #5
.m      tay                     ; Y = move 0-4
        cpx #0
        bne .rs
        lda mv_reachv,y
        jmp .rc
.rs     lda mv_reachs,y
.rc     cmp t5
        bcc .toofar
        lda mvdir,y
        sta aijin,x
        lda #2
        sta aifc,x
        lda #5
        sta aitm,x
        jmp .stick
.toofar lda #J_FW
        sta aijin,x
        lda #6
        sta aitm,x
        lda #0
        sta aifc,x
        jmp .stick
.other  cmp #6
        bne .o5
        lda #J_BK               ; back off
        sta aijin,x
        lda #14
        sta aitm,x
        lda #0
        sta aifc,x
        jmp .stick
.o5     cmp #5
        bne .o6
        lda #J_BK               ; guard
        sta aijin,x
        lda #9
        sta aitm,x
        lda #0
        sta aifc,x
        jmp .stick
.o6     lda #0                  ; wait / creep
        sta aijin,x
        lda t5
        cmp #52
        bcc .w
        lda #J_FW
        sta aijin,x
.w      lda #8
        sta aitm,x
        lda #0
        sta aifc,x
.stick  lda aijin,x
        and #(J_UP|J_DN|J_BK|J_FW)
        sta jin,x
        rts
!zone z27
mvdir   !byte J_FI,J_UP|J_FI,J_FW|J_FI,J_BK|J_FI,J_DN|J_FI

; ======================================================================================================== the round: intro, fight, K.O., result
!zone phase
!zone z28
phaseupd
        inc ptm
        bne .nt
        inc ptmh
.nt     lda mode
!ifdef TRACE { lda #8:sta $d6e0 }
        lda mode
        bne .go
        lda #0                  ; attract: the title and the blinking "press fire"
        ; title is drawn once per round, below
.go     lda phase
        cmp #PH_INTRO
        bne .p1
        jmp .intro
.p1     cmp #PH_FIGHT
        bne .p2
        jmp .fight
.p2     cmp #PH_KO
        bne .p3
        jmp .ko
.p3     jmp .res
.intro  lda ptm
        cmp #1
        bne .i1
        lda mode
        bne .i0
        +MSG msg_title
        +MSG msg_press
        +MSG msg_ports
        +MSG msg_ctl
        jmp .i1
.i0     +MSG msg_title_off
!ifdef TRACE { lda #3:sta $d6e0 }
        +MSG msg_round
!ifdef TRACE { lda #4:sta $d6e0 }
.i1     lda mode
        beq .ia
        lda ptm
        cmp #INTRO1
        bne .i2
        +MSG msg_banner_off
        +MSG msg_fight
.i2     lda ptm
        cmp #INTRO2
        bcc .ir
        +MSG msg_banner_off
        lda #PH_FIGHT
        sta phase
        lda #0
        sta ptm
        sta ptmh
.ir     rts
.ia     lda ptm                 ; attract: a short intro, then the fight
        cmp #40
        bcc .ir
        lda #PH_FIGHT
        sta phase
        lda #0
        sta ptm
        sta ptmh
        rts
.fight  lda mode
        bne .f2
        lda ptm                 ; "press fire" blinks
        and #31
        bne .f2
        lda ptm
        and #32
        beq .on
        +MSG msg_press_off
        jmp .f2
.on     +MSG msg_press
.f2     lda secs
        bne .fr
        ; time is up: the one with more health wins
        lda #1
        sta kokind
        lda hp
        cmp hp+1
        beq .draw
        bcc .w1
        lda #0
        beq .sw
.w1     lda #1
        bne .sw
.draw   lda #2
.sw     sta winner
        lda #PH_KO
        sta phase
        lda #0
        sta ptm
        sta ptmh
        +MSG msg_title_off
        +MSG msg_banner_off
        +MSG msg_timeup
.fr     rts
.ko     lda ptm
        cmp #KOTIME
        bcc .kr
        +MSG msg_banner_off
        lda winner
        beq .v
        cmp #1
        beq .s
        +MSG msg_draw
        jmp .rs
.v      +MSG msg_vicwins
        jmp .rs
.s      +MSG msg_sidwins
.rs     lda #PH_RES
        sta phase
        lda #0
        sta ptm
        sta ptmh
.kr     rts
.res    lda ptm
        cmp #RESTIME
        bcc .rr
        jsr newgame             ; back to the attract mode
.rr     rts

; ======================================================================================================== the HUD
!zone hud
!zone z29
hud     lda lmask
        bmi .vis
        lda hudon               ; key 8 turned it off: clear its rows once
        beq .x
        lda #0
        sta hudon
        ldx #0
.c      sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        inx
        bne .c
.x      rts
.vis    lda hudon
        bne .upd
        lda #1
        sta hudon
        sta hudredo
.upd    lda hudredo
        beq .go
        lda #0
        sta hudredo
        lda #$ff
        sta hpold0
        sta hpold1
        sta secold
        +MSG msg_names
.go     lda hp
        cmp hpold0
        beq .h1
        sta hpold0
        ldx #0
        jsr bar
.h1     lda hp+1
        cmp hpold1
        beq .t
        sta hpold1
        ldx #1
        jsr bar
.t      lda secs
        cmp secold
        beq .xx
        sta secold
        ldx #0                  ; two big digits at columns 18-21, rows 0-1
        sec
.tens   sbc #10
        bcc .u
        inx
        bcs .tens
.u      adc #10
        sta t1
        txa
        jsr .dig
        ldx #18
        jsr .put
        lda t1
        jsr .dig
        ldx #20
        jsr .put
.xx     rts
.dig    asl
        asl
        tay
        lda bigdig,y
        sta t3
        lda bigdig+1,y
        sta t4
        lda bigdig+2,y
        sta t5
        lda bigdig+3,y
        sta t6
        rts
.put    lda t3
        sta SCREEN,x
        lda t4
        sta SCREEN+1,x
        lda t5
        sta SCREEN+40,x
        lda t6
        sta SCREEN+41,x
        lda #1
        sta COLRAM,x
        sta COLRAM+1,x
        sta COLRAM+40,x
        sta COLRAM+41,x
        rts

; the health bar of fighter X: 16 segments of 6, lit from the outer edge; green to red by what is left
!zone z30
bar     stx t7
        lda hp,x
        ldy #0
.cnt    cmp #1
        bcc .cd
        sec
        sbc #6
        bcc .part
        iny
        jmp .cnt
.part   iny
.cd     sty t0                  ; lit segments
        lda barcol,y
        sta t1
        ldy #0
.seg    ldx t7
        bne .right
        tya
        clc
        adc #1                  ; fighter 0: columns 1..16 (left to right)
        jmp .col
.right  sty t2
        lda #38                 ; fighter 1: columns 38..23
        sec
        sbc t2
.col    tax
        cpy t0
        bcs .empty
        lda t1
        jmp .set
.empty  lda #15
.set    sta COLRAM+40,x
        lda #SEGCH
        sta SCREEN+40,x
        iny
        cpy #16
        bne .seg
        ldx t7
        rts

; ======================================================================================================== shake, spark, sound
!zone fx
!zone z31
shake   lda sparkt
        beq .s
        dec sparkt
.s      lda shkt
        beq .z
        dec shkt
        tax
        lda shk_x,x
        sta xshk
        lda shk_y,x
        sta yshk
        rts
.z      lda #0
        sta xshk
        sta yshk
        rts
!zone z32
shk_x   !byte 0,1,$ff,2,$fe,2,$fe,2,$fe,1,$ff,1,$ff,1,$ff,0
!zone z33
shk_y   !byte 0,0,1,$ff,1,$fe,1,$ff,0,1,0,$ff,0,1,0,0
!zone z34
spk_idx !byte 0,0,0,1,1,1,2,2,2,3,3,3, 4,4,4,4,5,5,5,5,6,6,6,6

!zone z35
sfxstep lda sfxreq
        beq .run
        tax
        lda sf_lo-1,x
        sta sfp
        lda sf_hi-1,x
        sta sfp+1
        lda #0
        sta sfxreq
.run    lda sfp+1
        beq .r
        ldy #0
        lda (sfp),y
        cmp #$ff
        beq .end
        sta t0
        iny
        beq .adv
.w      lda (sfp),y
        sta t2
        iny
        lda (sfp),y
        sta t3
        iny
        sty t1
        lda t2
        bmi .s7
        tax
        lda t3
        sta SID6,x
        jmp .nx
.s7     and #$7f
        tax
        lda t3
        sta SID7,x
.nx     ldy t1
        dec t0
        bne .w
.adv    tya
        clc
        adc sfp
        sta sfp
        bcc .r
        inc sfp+1
.r      rts
.end    lda #0
        sta sfp
        sta sfp+1
        rts
!zone z36
sf_lo   !byte <sf_whoosh,<sf_thud,<sf_clack
!zone z37
sf_hi   !byte >sf_whoosh,>sf_thud,>sf_clack
; each script frame: n, then n x (register, value); register bit 7 = SID 7 (else SID 6); $FF ends
!zone z38
sf_whoosh
        !byte 5, $8e,$00, $8f,$08, $93,$38, $94,$00, $92,$81
        !byte 1, $8f,$0c
        !byte 1, $8f,$12
        !byte 1, $8f,$18
        !byte 1, $8f,$14
        !byte 1, $8f,$0e
        !byte 1, $8f,$08
        !byte 1, $92,$80
        !byte $ff
!zone z39
sf_thud
        !byte 10, $00,$00, $01,$20, $05,$06, $06,$00, $04,$81, $07,$00, $08,$0a, $0c,$07, $0d,$00, $0b,$11
        !byte 2, $08,$08, $01,$18
        !byte 2, $08,$06, $01,$10
        !byte 2, $08,$05, $01,$0a
        !byte 2, $08,$04, $01,$06
        !byte 1, $08,$03
        !byte 1, $08,$03
        !byte 2, $04,$80, $0b,$10
        !byte $ff
!zone z40
sf_clack
        !byte 10, $80,$00, $81,$50, $82,$00, $83,$08, $85,$00, $86,$f0, $84,$41, $8b,$81, $87,$00, $88,$e0
        !byte 3, $84,$40, $8b,$80, $94,$00
        !byte $ff

; ======================================================================================================== sprite table
!zone sat
; sprites 0-15 are the game's: 0 spark, 1-6 and 7-12 the two fighters (the attacker on top), 13-14 shadows, 15 spare;
; then the stage's NSPR sprites. The table is built in the buffer that is NOT shown.
!zone z41
buildsat
        lda satb
        eor #1
        sta satpend
        bne .b1
        lda #<V_SAT0
        ldx #>V_SAT0
        ldy #^V_SAT0
        jmp .set
.b1     lda #<V_SAT1
        ldx #>V_SAT1
        ldy #^V_SAT1
.set    jsr vset
        ; 0: the spark
        lda sparkt
        beq .nospark
        lda #12
        sec
        sbc sparkt
        ldy sparkk
        beq .k0
        clc
        adc #12
.k0     tay
        lda spk_idx,y
        tay
        lda spxl
        sec
        sbc #<240               ; (px + offset + 256) -> screen x - 16 = that - 240
        sta VDATA
        lda spxh
        sbc #0
        sta VDATA
        lda spy
        clc
        adc #BOXY-16
        sta VDATA
        lda #0
        sta VDATA
        lda spark_lo,y
        sta VDATA
        lda spark_hi,y
        sta VDATA
        lda #$8a                ; on, 32 x 32, 16 colours
        sta VDATA
        lda #0
        sta VDATA
        jmp .fighters
.nospark
        ldx #8
        lda #0
.z8     sta VDATA
        dex
        bne .z8
.fighters
        ldx ftop                ; sprite 0 is drawn on top, so the fighter on top goes first
        jsr emitf
        txa
        eor #1
        tax
        jsr emitf
        ; 13, 14: shadows (taken away, 64 x 16, 16 colours)
        ldx #0
.sh     lda px_lo,x             ; (screen x = px + 32; the shadow is 64 wide: its left = px)
        sta VDATA
        lda px_hi,x
        sta VDATA
        lda #BOXY+100
        sta VDATA
        lda #0
        sta VDATA
        lda #<G_SHADOW
        sta VDATA
        lda #>G_SHADOW
        sta VDATA
        lda #$87
        sta VDATA
        lda #$c0
        sta VDATA
        inx
        cpx #2
        bne .sh
        ldx #8                  ; 15: spare (off)
        lda #0
.sp     sta VDATA
        dex
        bne .sp
        ; the stage's sprite table of this tick: REU -> VRAM (VADDR is just after the game's sprites)
        jsr recaddr
        lda rmid
        clc
        adc #3                  ; the table follows the 768 bytes of palette
        sta up_r+1
        lda rhi
        adc #0
        sta up_r+2
        lda #0
        sta up_r
        lda #<SATLEN
        sta up_n
        lda #>SATLEN
        sta up_n+1
        lda #0
        sta up_n+2
        jsr reuvram
        ; the layers that are switched off have their sprites turned off
        ldx #1                  ; groups 1-5: bit of lmask, first sprite, count
.g      lda lmask
        and lbit,x
        bne .on
        lda gfirst,x
        clc
        adc #NG
        sta gs
        lda gcount,x
        sta gn
.s      jsr flagoff
        inc gs
        dec gn
        bne .s
.on     inx
        cpx #6
        bne .g
        lda lmask               ; key 7: the fighters, spark and shadows
        and #64
        bne .done
        lda #0
        sta gs
.f      jsr flagoff
        inc gs
        lda gs
        cmp #NG
        bne .f
.done   rts

; sprite gs of the table being built: its flags byte = 0
!zone z42
flagoff lda gs
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
        sta tp+1
        lda satpend
        beq .a
        lda #4                  ; the second buffer is $400 on
        clc
        adc tp+1
        sta tp+1
.a      lda tp+1
        sta VADDR+1
        lda #^V_SAT0
        sta VADDR+2
        lda #0
        sta VDATA
        rts
!zone z43
gfirst  !byte 0,5,4,0,19,9      ; (index 0 is the picture)
!zone z44
gcount  !byte 0,4,1,4,90,10

; fighter X: 6 sprite entries
!zone z45
emitf   stx fc
        jsr drec
        ldy #1
        lda px_lo,x
        sec
        sbc (ptr),y
        sta bxl
        lda px_hi,x
        sbc #0
        sta bxh
        lda bxl                 ; + 32: screen x
        clc
        adc #32
        sta bxl
        lda bxh
        adc #0
        sta bxh
        ldy #0
        lda (ptr),y
        sta t7                  ; mask
        lda #0
        sta t5                  ; slot 0-5
        lda fc
        beq .v
        lda #6
.v      sta t6                  ; table base
.slot   lda t6
        clc
        adc t5
        tax
        lda slotdx,x
        clc
        adc bxl
        sta VDATA
        lda bxh
        adc #0
        sta VDATA
        lda slotdy,x
        clc
        adc #BOXY
        sta VDATA
        lda #0
        sta VDATA
        lda t5
        asl
        clc
        adc #2
        tay
        lda (ptr),y
        sta VDATA
        iny
        lda (ptr),y
        sta VDATA
        lsr t7
        bcs .on
        lda #0
        beq .fl
.on     lda slotfl,x
.fl     sta VDATA
        lda #0
        sta VDATA
        inc t5
        lda t5
        cmp #6
        bne .slot
        ldx fc
        rts

; ======================================================================================================== data
* = $3800
        !binary "charset.bin"
* = $4000
!src "data.inc"
