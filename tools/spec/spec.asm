; ================================================================ OCTOPHONIC 64
;  .----.
;  | 64 |   SPEC - what this machine has: the core, its build, OctoVIC,
;  '----'   the SIDs, the SDRAM board, the REU, PAL or NTSC (Fix 59).
;  Mong00se  Send a photo of this page with any bug report.
;
; (c) 2026 Mong00se
; Reads the core's spec register, $D6B3 (core 9 on): b7 SDRAM size known,
; b1-0 SDRAM (0 none, 1 32MB, 2 64MB, 3 128MB), b5-4 REU (0 off, 1 512K,
; 2 2MB, 3 16MB). Older cores and other machines get what can be found.
; Any key: back to the start screen. Text: OCTO-64, flat colours.

; build: tools/spec/build.sh (or: cd tools/spec && acme -f cbm -o SPEC.PRG spec.asm)
!cpu 6502

OV      = $d600         ; OctoVIC (open once $D03F has seen $4F, $38)
SCR     = $fb
SRC     = $fd
COLP    = $22
P0      = $24
TMP     = $26
TMP1    = $27
TMP4    = $28
CUR     = $29
COL     = $02

GREY    = 15
WHITE   = 1
BLUE    = 14
YELLOW  = 7
DGREY   = 11

!macro at .r, .c, .col {
        ldx #.r
        ldy #.c
        jsr pos
        lda #.col
        sta COL
}
!macro txt .r, .c, .col, .addr {
        +at .r, .c, .col
        lda #<.addr
        sta SRC
        lda #>.addr
        sta SRC+1
        jsr pstr
}

* = $0801
        !word l2, 2026
        !byte $9e
        !text "2112"
        !byte 0
l2      !word l3, 2027
        !byte $8f
        !text " (C) 2026 MONG00SE"
        !byte 0
l3      !word 0
!if * > 2112 { !error "the BASIC lines run into the code" }
        !fill 2112 - *, 0

; ---------------------------------------------------------------- start
start   lda #0
        sta $d020
        sta $d021
        ldx #0
cl1     lda #32
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        lda #WHITE
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne cl1
        lda #$1e        ; screen $0400, OCTO-64 at $3800
        sta $d018
        lda #$1b
        sta $d011
        lda #$08
        sta $d016
        jsr detect
        jsr palntsc

        +txt 1, 2, BLUE, s_title
        +txt 2, 2, DGREY, s_rule
        +txt 4, 2, GREY, s_core
        +txt 6, 2, GREY, s_built
        +txt 8, 2, GREY, s_ovic
        +txt 10, 2, GREY, s_sids
        +txt 12, 2, GREY, s_sdram
        +txt 14, 2, GREY, s_reu
        +txt 16, 2, GREY, s_video
        +txt 19, 2, DGREY, s_bug
        +txt 21, 2, GREY, s_key
        +txt 23, 2, DGREY, s_copy

        lda isov
        bne v_ov
        +txt 4, 13, YELLOW, s_notoct
        +txt 6, 13, WHITE, s_dash
        +txt 8, 13, WHITE, s_notfound
        +txt 12, 13, WHITE, s_dash
        +txt 14, 13, WHITE, s_dash
        jmp v_sids

v_ov    +at 4, 13, WHITE        ; the core's name: 8 ASCII letters
        ldx #0
vn1     lda OV+$b8,x
        cmp #$40
        bcc +
        and #$3f
+       stx TMP1
        jsr pch
        ldx TMP1
        inx
        cpx #8
        bne vn1
        +at 6, 13, WHITE        ; its build date: 20YY-MM-DD (BCD)
        lda #$32
        jsr pch
        lda #$30
        jsr pch
        lda OV+$b6
        jsr pbcd
        lda #$2d
        jsr pch
        lda OV+$b5
        jsr pbcd
        lda #$2d
        jsr pch
        lda OV+$b4
        jsr pbcd
        +txt 8, 13, WHITE, s_version
        lda OV+$1f
        jsr pdec
        lda OV+$1f              ; the spec register: core 9 (OctoVIC 4) and up
        cmp #4
        bcc v_old
        lda OV+$b3
        bmi +
        +txt 12, 13, WHITE, s_unknown
        jmp v_reu
+       and #3
        tax
        lda sdl,x
        ldy sdh,x
        jsr vstr8
v_reu   lda OV+$b3
        lsr
        lsr
        lsr
        lsr
        and #3
        tax
        lda rul,x
        ldy ruh,x
        jsr vstr9
        jmp v_sids
v_old   +txt 12, 13, WHITE, s_oldcore
        +txt 14, 13, WHITE, s_oldcore

v_sids  +at 10, 13, WHITE
        lda nsid
        jsr pdec
        +at 16, 13, WHITE
        lda ntsc
        beq +
        +txt 16, 13, WHITE, s_ntsc
        jmp wait
+       lda isov
        beq +
        lda OV+8                ; STATUS b5: the 60 Hz mode
        and #$20
        beq +
        +txt 16, 13, WHITE, s_pal60
        jmp wait
+       +txt 16, 13, WHITE, s_pal50

wait    jsr $ffe4
        beq wait
        lda #0
        sta $d03f
        jmp ($fffc)             ; back to the start screen

vstr8   ldx #12
        !byte $2c
vstr9   ldx #14
        sta SRC
        sty SRC+1
        ldy #13
        jsr pos
        lda #WHITE
        sta COL
        jmp pstr

; ---------------------------------------------------------------- printing
; X row, Y column
pos     lda rowl,x
        sta SCR
        sta COLP
        lda rowh,x
        sta SCR+1
        clc
        adc #$d4
        sta COLP+1
        sty CUR
        rts
; A (a screen code) at the cursor, in COL
pch     ldy CUR
        sta (SCR),y
        lda COL
        sta (COLP),y
        inc CUR
        rts
pstr    ldy #0
ps1     lda (SRC),y
        beq ps9
        sty TMP
        jsr pch
        ldy TMP
        iny
        bne ps1
ps9     rts
pdec    ldx #0
pd1     cmp #10
        bcc pd2
        sbc #10
        inx
        bne pd1
pd2     pha
        txa
        beq +
        ora #$30
        jsr pch
+       pla
        ora #$30
        jmp pch
pbcd    pha
        lsr
        lsr
        lsr
        lsr
        ora #$30
        jsr pch
        pla
        and #$0f
        ora #$30
        jmp pch
rowl    !for r, 0, 24 { !byte <($0400 + r * 40) }
rowh    !for r, 0, 24 { !byte >($0400 + r * 40) }

; ---------------------------------------------------------------- detect
; OctoVIC answers at $D61E (ID $8C). Then each SID address is tried in
; order; the first with no chip of its own ends the count. Otherwise the
; C64 way: a 2nd SID at $D420, $D500 or $DE00, or none.
detect  lda #0
        sta isov
        lda #1
        sta nsid
        lda #$4f
        sta $d03f
        lda #$38
        sta $d03f
        lda OV+$1e
        cmp #$8c
        bne dnoct
        lda OV+$1e
        cmp #$8c
        bne dnoct
        lda OV+$1f
        cmp #2
        bcc dnoct
        cmp #16
        bcs dnoct
        lda #1
        sta isov
        ldx #1
dos     lda sidtl,x
        sta P0
        lda sidth,x
        sta P0+1
        stx TMP4
        jsr sidtest
        ldx TMP4
        bcc dosend
        inx
        cpx #8
        bne dos
dosend  stx nsid
        rts
dnoct   lda #0
        sta $d03f
        ldx #0
dst     lda cand,x
        sta P0
        lda cand+3,x
        sta P0+1
        stx TMP4
        jsr sidtest
        ldx TMP4
        bcs +
        inx
        cpx #3
        bne dst
        rts
+       lda #2
        sta nsid
        rts
sidtl   !byte $0,$20,$0,$20,$80,$a0,$80,$a0
sidth   !byte $d4,$d4,$d5,$d5,$d4,$d4,$d5,$d5
cand    !byte $20,$0,$0
        !byte $d4,$d5,$de

; Is there a SID of its own at (P0)? SID 1's voice 3 is held (test bit);
; voice 3 there runs noise at full speed: its OSC3 must change all the time
; while SID 1's does not. A mirror or an empty address fails. C set = a SID.
sidtest ldy #$18
        lda #0
        sta (P0),y
        sta $d418
        ldy #$e
        lda #$ff
        sta (P0),y
        iny
        sta (P0),y
        lda #0
        sta $d40e
        sta $d40f
        lda #$8
        sta $d412
        ldy #$12
        sta (P0),y
        ldy #$1b
        lda (P0),y
        sta TMP
        ldx #4
st1     lda (P0),y
        cmp TMP
        bne stfail
        dex
        bne st1
        ldy #$12
        lda #$81
        sta (P0),y
        ldy #$1b
        ldx #16
        lda #0
        sta TMP1
st2     lda (P0),y
        cmp TMP
        beq st3
        inc TMP1
st3     nop
        nop
        dex
        bne st2
        ldx #6
st4     lda $d41b
        cmp TMP
        bne stfail
        dex
        bne st4
        lda TMP1
        cmp #3
        bcc stfail
        jsr stclr
        sec
        rts
stfail  jsr stclr
        clc
        rts
stclr   ldy #$12
        lda #0
        sta (P0),y
        sta $d412
        rts

; a PAL machine has raster lines past 263, an NTSC one does not
palntsc lda #1
        sta ntsc
        ldx #0
        ldy #0
pn1     lda $d011
        bpl pn2
        lda $d012
        cmp #8
        bcc pn2
        lda #0
        sta ntsc
        rts
pn2     inx
        bne pn1
        iny
        cpy #24
        bne pn1
        rts

isov    !byte 0
nsid    !byte 1
ntsc    !byte 0

; ---------------------------------------------------------------- words
s_title   !scr "octophonic 64  spec", 0
s_rule    !scr "-------------------", 0
s_core    !scr "core", 0
s_built   !scr "built", 0
s_ovic    !scr "octovic", 0
s_sids    !scr "sids", 0
s_sdram   !scr "sdram", 0
s_reu     !scr "reu", 0
s_video   !scr "video", 0
s_bug     !scr "send a photo of this with bug reports", 0
s_key     !scr "press any key for the start screen", 0
s_copy    !byte $1c
          !scr " 2026 mong00se", 0
s_notoct  !scr "not an octophonic 64", 0
s_notfound !scr "not found", 0
s_dash    !scr "-", 0
s_version !scr "version ", 0
s_unknown !scr "not reported", 0
s_oldcore !scr "needs core 9", 0
s_ntsc    !scr "ntsc 60hz", 0
s_pal50   !scr "pal 50hz", 0
s_pal60   !scr "pal 60hz", 0
sd0       !scr "none", 0
sd1       !scr "32mb", 0
sd2       !scr "64mb", 0
sd3       !scr "128mb", 0
ru0       !scr "off", 0
ru1       !scr "512kb", 0
ru2       !scr "2mb", 0
ru3       !scr "16mb", 0
sdl       !byte <sd0, <sd1, <sd2, <sd3
sdh       !byte >sd0, >sd1, >sd2, >sd3
rul       !byte <ru0, <ru1, <ru2, <ru3
ruh       !byte >ru0, >ru1, >ru2, >ru3
s_sign    !text "(C) 2026 MONG00SE"

!if * > $3800 { !error "the code runs into the charset" }
* = $3800
!binary "octo64.bin"
