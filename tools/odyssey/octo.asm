; (C) 2026 Mong00se
; OCTO.ASM - the Octophonic show of ODYSSEY.ASM, by Mong00se.
; The Webb "Cosmic Cliffs" (NASA, ESA, CSA, STScI) as one picture of
; 2048 x 1186 in 256 colours on OctoVIC's turned-and-sized bitmap
; layer (the camera as in Mona Lisa and Starry Night): it starts on
; a star, pulls back to the whole picture, then glides to the western
; peak, along the ridge, up to the stars, to the eastern cliffs, down
; into the dust and back out - in time with the waltz, all 8 SIDs.
; Stars twinkle (8 palette entries the picture's stars use, set every
; frame), sparkles glow on the brightest ones
; (OctoVIC sprites, "added" light), 8 equaliser bars (a SID each),
; the scroll text on the VIC in front.
; Everything big is in the .reu: its first bytes list the parts, so
; this needs no numbers from the PC.
!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }
!if odyp = 0 {
        !src "odyssey.asm"
} else {

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
L0      = $D620
MULA    = $D650
MULB    = $D652
MULR    = $D654
DIVN    = $D659
DIVD    = $D65D
DIVQ    = $D660
U0      = $D688

V_PIC0  = $000000       ; VRAM: the picture, 2048 wide
V_PIC1  = $260000       ; the half size (1024)
V_PIC2  = $300000       ; the quarter size (512)
V_SPR   = $340000       ; the sprites' graphics
V_SAT   = $350000       ; two sprite tables (one shown, one built)
NSPR    = 13            ; 0-3 sparkles, 4 off (was the comet), 5-12 the bars

HDR     = $c000         ; the .reu's list of parts (128 bytes)
STARS   = $c100         ; the sparkle stars: n, then x, y (16 bits)
PALBUF  = $c200         ; the palette: R x 256, G x 256, B x 256
MBUF    = $c500         ; this frame's registers for SIDs 3-8
CA      = $c600         ; the camera: x, y, zoom (24 bits each):
CB      = $c609         ; the row's start, its target, now
CUR     = $c612
REGS    = $c620         ; U0 V0 DUX DVX DUY DVY as OctoVIC has them
TW      = $c640         ; the 8 twinkle groups: brightness, target
SPS     = $c660         ; the sparkles: frames left, wait, star
EQL     = $c680         ; the 8 bars' levels (0-16)
GPREV   = $c690         ; SIDs 3-8: last frame's gates
PATH    = $4000         ; the camera's rows (from the .reu)

; zero page (the Octophonic show's)
tick    = $60
rt      = $61           ; 2: frames left in the row
sstep   = $63           ; 2: 65536 / the row's frames
sacc    = $65           ; 2: the row's progress
mip     = $67           ; 0, 1 or 2: which copy is shown
ee      = $68           ; 2
la      = $6a           ; 3
lb      = $6d           ; 3
lr      = $70           ; 3
dd      = $73           ; 3
sg      = $76
mm      = $77           ; 3
tq      = $7a           ; 8 temporaries
up_r    = $82           ; 3: REU address
up_n    = $85           ; 3: bytes left
rp      = $88           ; 2: the next row
fade    = $8a           ; the palette's fade in, 0-64
sat     = $8b           ; which sprite table is being built
oxs     = $8c           ; the scroll text's fine scroll
optr    = $8d           ; 2: the scroll text
oshift  = $8f           ; 1: the scroll text moves a letter at the next frame's top

!macro asr32 .a {
        lda .a+3
        cmp #$80
        ror .a+3
        ror .a+2
        ror .a+1
        ror .a
}

; ======================================================= the start
!zone octo
octo    sei
        lda #1
        sta $d030       ; turbo
        ldx #<t_octo
        ldy #>t_octo
        lda #13
        jsr print
        ldx #$9a        ; OctoVIC: everything 0 (off)
        lda #0
-       sta OCTRL,x
        dex
        cpx #$ff
        bne -
        lda #<HDR       ; the .reu's list of parts
        ldx #>HDR
        ldy #0
        jsr r_setc
        lda #0
        sta up_r
        sta up_r+1
        sta up_r+2
        lda #128
        ldx #0
        jsr r_get
        ldx #3*6        ; the palette into RAM
        lda #<PALBUF
        ldy #>PALBUF
        jsr part2ram
        ldx #5*6        ; the camera's rows
        lda #<PATH
        ldy #>PATH
        jsr part2ram
        ldx #6*6        ; the sparkle stars
        lda #<STARS
        ldy #>STARS
        jsr part2ram
        lda #0          ; the palette black (it fades up), the VIC's
        sta PALSEL      ; 16 colours the C64's, the backdrop black
        sta PALIDX
        tax
-       sta PALR
        sta PALG
        sta PALB
        inx
        bne -
        ldx #240        ; (the sprites' colours now)
        jsr palfrom
        lda #1
        sta PALSEL
        lda #0
        sta PALIDX
        tax
-       lda vicpal,x
        sta PALR
        lda vicpal+16,x
        sta PALG
        lda vicpal+32,x
        sta PALB
        inx
        cpx #16
        bne -
        lda #2
        sta PALSEL
        lda #0
        sta PALIDX
        sta PALR
        sta PALG
        sta PALB
        lda #1          ; the pictures and the sprites into VRAM
        sta VINC
        lda #<V_PIC0
        ldx #>V_PIC0
        ldy #^V_PIC0
        jsr vset
        ldx #0*6
        jsr part2vram
        lda #<V_PIC1
        ldx #>V_PIC1
        ldy #^V_PIC1
        jsr vset
        ldx #1*6
        jsr part2vram
        lda #<V_PIC2
        ldx #>V_PIC2
        ldy #^V_PIC2
        jsr vset
        ldx #2*6
        jsr part2vram
        lda #<V_SPR
        ldx #>V_SPR
        ldy #^V_SPR
        jsr vset
        ldx #4*6
        jsr part2vram
        jsr oinit
        jmp omain

; the part at X (6 x its number) of the list to C64 RAM at A/Y
part2ram
        sta REU+2
        sty REU+3
        jsr r_part
        lda up_n
        ldx up_n+1
        jmp r_get
; up_r / up_n from the list's entry X
r_part  lda HDR+64,x
        sta up_r
        lda HDR+65,x
        sta up_r+1
        lda HDR+66,x
        sta up_r+2
        lda HDR+67,x
        sta up_n
        lda HDR+68,x
        sta up_n+1
        lda HDR+69,x
        sta up_n+2
        rts
r_setc  sta REU+2
        stx REU+3
        rts
; A/X bytes from the REU at up_r to the C64 address set
r_get   sta REU+7
        stx REU+8
        lda up_r
        sta REU+4
        lda up_r+1
        sta REU+5
        lda up_r+2
        sta REU+6
        lda #0
        sta REU+10
        lda #$91
        sta REU+1
        rts
; the part X/6 into VRAM at VADDR, 64 KB at a time
part2vram
        jsr r_part
.l      lda up_n+2
        bne .big
        lda up_n
        ora up_n+1
        beq .x
        ldx up_n
        ldy up_n+1
        jmp .fire
.big    dec up_n+2
        ldx #0
        ldy #0
        jsr .fire
        inc up_r+2
        jmp .l
.x      rts
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
        lda #$80        ; the C64 address stays (VDATA)
        sta REU+10
        lda #$91
        sta REU+1
        rts
vset    sta VADDR
        stx VADDR+1
        sty VADDR+2
        rts

; ======================================================== the frame
!zone omain
omain   lda tick
        beq omain
        lda #0
        sta tick
        jsr ovblank     ; the camera's numbers into OctoVIC
        jsr omusic      ; all 8 SIDs
        jsr advance     ; the camera's next frame
        jsr twinkle8    ; the stars' palette entries
        jsr ofade
        jsr levels8     ; the equaliser
        jsr sparkle8
        jsr satbuild    ; the sprite table for the next frame
        jsr oscroll
        jmp omain

!zone ovblank
ovblank ldx #23
-       lda REGS,x
        sta U0,x
        dex
        bpl -
        ldx mip
        lda mipctl,x
        sta L0
        lda #0
        sta L0+4
        sta L0+5
        lda miphi,x
        sta L0+6
        lda sat         ; the table just built: shown from now
        asl
        asl
        sta SATBASE+1
        lda #^V_SAT
        sta SATBASE+2
        lda oxs         ; the scroll text's fine scroll (38 columns)
        sta $d016
        lda oshift      ; and its letters, in the same frame
        beq +
        jsr oshiftrow
+       rts
mipctl  !byte $fb, $ab, $5b     ; on, 256 colours, bitmap, its size
miphi   !byte ^V_PIC0, ^V_PIC1, ^V_PIC2

; ------------------------------------------------ the music
; SIDs 1-2: the player (PLAYER.ASM); SIDs 3-8: this frame's 192
; bytes from the REU (music list entry 7: 256 a frame) into RAM,
; then into the SIDs, and the equaliser looks at their gates
!zone omusic
omusic  jsr pl_play
        lda #<MBUF
        sta REU+2
        lda #>MBUF
        sta REU+3
        lda HDR+64+7*6
        sta REU+4
        clc
        lda mfr
        adc HDR+64+7*6+1
        sta REU+5
        lda mfr+1
        adc HDR+64+7*6+2
        sta REU+6
        lda #192
        sta REU+7
        lda #0
        sta REU+8
        sta REU+10
        lda #$91
        sta REU+1
        ldx #5          ; SID by SID: 25 registers
.s      lda osidlo,x
        sta tq
        lda osidhi,x
        sta tq+1
        txa
        asl
        asl
        asl
        asl
        asl
        sta tq+2        ; its 32 bytes in MBUF
        ldy #0
-       sty tq+4
        tya
        clc
        adc tq+2
        tay
        lda MBUF,y
        ldy tq+4
        sta (tq),y
        iny
        cpy #25
        bne -
        dex
        bpl .s
        rts
; SIDs 3-8 on the Octophonic: $D500, $D520, $D480, $D4A0, $D580, $D5A0
osidlo  !byte $00, $20, $80, $a0, $80, $a0
osidhi  !byte $d5, $d5, $d4, $d4, $d5, $d5

; ------------------------------------------------ the equaliser
; SIDs 1-2: the player's levels; SIDs 3-8: a gate coming on fills
; the bar, a gate held keeps it at half, else it falls
!zone levels8
levels8 ldx #0
        jsr .pl
        ldx #3
        jsr .pl
        ldx #5
.sid    txa             ; SID x (0-5) of the stream: its 3 gates
        asl
        asl
        asl
        asl
        asl
        tay
        lda MBUF+4,y
        and #1
        sta tq
        lda MBUF+11,y
        and #1
        asl
        ora tq
        sta tq
        lda MBUF+18,y
        and #1
        asl
        asl
        ora tq
        sta tq          ; gates now
        lda GPREV,x
        eor #$ff
        and tq          ; gates that came on
        beq +
        lda #15
        sta EQL+2,x
        jmp .n
+       lda tq
        beq +
        lda EQL+2,x
        cmp #9
        bcc .n
+       lda EQL+2,x
        beq .n
        dec EQL+2,x
.n      lda tq
        sta GPREV,x
        dex
        bpl .sid
        rts
.pl     lda pv_eq,x     ; the loudest of the player's 3 voices
        cmp pv_eq+1,x
        bcs +
        lda pv_eq+1,x
+       cmp pv_eq+2,x
        bcs +
        lda pv_eq+2,x
+       lsr             ; 0-20 to 0-15 (3/4)
        sta tq
        lsr
        clc
        adc tq
        cpx #3
        beq +
        sta EQL
        rts
+       sta EQL+1
        rts

; ================================================== texts, colours
t_octo  !byte 15, 3
        !scr "octophonic 64: 8 sids, octovic, reu", 0
; the VIC's 16 colours (R, G, B) for the scroll text
vicpal  !byte $00,$ff,$81,$75,$8e,$56,$2e,$ed,$8e,$55,$c4,$4a,$7b,$a9,$70,$b2
        !byte $00,$ff,$33,$ce,$3c,$ac,$2c,$f1,$50,$38,$6c,$4a,$7b,$ff,$6d,$b2
        !byte $00,$ff,$38,$c8,$97,$4d,$9b,$71,$29,$00,$71,$4a,$7b,$9f,$eb,$b2
omsg    !scr "      2026: an octophonic odyssey  -  (c) 2026 mong00se"
        !scr "    ...    the cosmic cliffs of the carina nebula, seen "
        !scr "by the james webb space telescope, 2048 x 1186 in 256 "
        !scr "colours on octovic    ...    image: nasa, esa, csa, "
        !scr "stsci    ...    music: the blue danube, johann strauss "
        !scr "ii (1866), arranged by mong00se for all 8 sids - strings,"
        !scr " harp, horns, flute, bells, cellos and timpani    ...    "
        !scr "every star, sparkle and note is done by the 6502    "
        !scr "...    ", 0
}
