; (C) 2026 Mong00se
; GALAXY.ASM - the stock C64 / 2-SID show's galaxy: the disk turned and
; drawn anew by the 6502, and the live stars in orbit (with SHOW.ASM)
; A part of ODYSSEY.ASM (2026: An Octophonic Odyssey), by Mong00se:
; F2 on it builds the whole demo.
!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }
!if odyp = 0 {
        !src "odyssey.asm"
} else {

; Two hires bitmaps ($6000 in bank 1, $A000 in bank 2): one is shown
; while the stars are moved in the other, then they swap (25 a second).
; THE TURN: the disk is a 64x64 texture of dither levels (0-16) in its
; own plane ($E000, made by GALAXY.PY). Every line of the disk is drawn
; anew, a byte at a time, from the texture turned by the galaxy's angle
; and tilted (two texture steps a byte, a nibble of a 16x16 dither from
; each): the lines 0,4,8.. then 1,5,9.., each quarter at the angle of
; the moment. This fills the time the stars leave free, into both
; bitmaps at once. THE STARS: on rings in the disk's plane, the inner
; ones faster (the same speed along the ring: an angle 1/r a frame), so
; the arms wind. A star that runs too far ahead of its arm starts again
; behind it. Each is 2 pixels in the bitmap not on show; what it covered
; is kept and put back first (in the reverse order, so stars on the same
; byte come off right).

; memory (GALAXY.PY writes the tables)
SOFF    = $4c00         ; a star: its angle in its ring (8 high bits)
EAL0    = $4d00         ; the bitmap $6000's stars: address lo, hi,
EAH0    = $4e00         ; the byte they covered
ES0     = $4f00
EAL1    = $5000         ; the same for $A000
EAH1    = $5100
ES1     = $5200
RR      = $5300         ; a ring: its radius (pixels)
RN      = $5330         ; its stars (0: no more rings)
RWL     = $5360         ; its turn a step (16 bits, 65536 a turn)
RWH     = $5390
RARM    = $53c0         ; the arm's angle at its radius
RTL     = $5400         ; its angle now (16 bits)
RTH     = $5430
ROWC0   = $5500         ; a line of the disk: its first byte column,
ROWNB   = $55c0         ; how many bytes, where it starts across and
ROWUQ   = $5680         ; down in the texture (quarter texels from
ROWVQ   = $5740         ; the middle)
SRING   = $4b00         ; a star's ring
SQL     = $8c00         ; n*n/4: lo (0-255)
SQH     = $8d00         ; hi (0-511)
NSQH    = $8f00         ; (n-255)^2/4 hi (0-511)
CQ      = $9100         ; cos, a quarter turn in 256 steps (x 255)
SQT     = $9200         ; sin x the tilt (x 255 x cos 60)
XLR     = $9300         ; right of the middle: the column's offset lo,
XHR     = $9400         ; hi, the star's 2 pixels
MR      = $9500
XLL     = $9600         ; left of it
XHL     = $9700
ML      = $9800
YLO     = $9900         ; a line (the star's middle + y, or - y at
YHA     = $9a00         ; +128): its address in the bitmap $6000 lo,
YHB     = $9b00         ; hi, and hi in $A000
DUL     = $9c00         ; the texture's step a nibble at each angle
DUH     = $9d00
SIN8    = $9e00         ; sin x 127
DITH    = $c000         ; the dither: 64 tables of 17 (16 lines x 4)
TEX     = $e000         ; the texture (64 x 64)
TWTAB   = $c440         ; the twinkles: n, then n x (screen offset, colour)
GLTAB   = $c4a0         ; the glints' stars: n, then n x (sprite x, y)

; (its zero page is in SHOW.ASM: front, flipped, alpha, ... $60-$8A)

WAHEAD  = 18            ; a star this far ahead of its arm (256 a turn) ...
WBACK   = 10            ; ... starts again this far behind it (+0-7)
DALPHA  = 32768 / songlen       ; the galaxy turns half a turn a song

; ============================================== the live stars
; plot all the stars into bitmap B (0 or 1)
!macro starplot .b {
        ldx #0
        stx ringk
.ring   ldy ringk
        lda RN,y
        bne +
        jmp .done
+       stx rend
        clc
        adc rend
        sta rend
        lda RR,y
        sta p1
        eor #$ff
        sta p3
        lda RTL,y
        rol
        rol
        rol
        and #3
        sta rlo2
        lda RTH,y
        sta rth
.star   lda SOFF,x
        clc
        adc rth
        sta th
        asl
        asl
        ora rlo2
        tay
        bit th
        bmi .q23
        bvs .q1
        ; 0-90: right, down
        lda CQ,y
        sta xm
        lda SQT,y
        tay
        lda (p1),y
        sec
        sbc (p3),y
        tay
        lda YLO,y
        sta pp
        !if .b = 0 { lda YHA,y } else { lda YHB,y }
        sta pp+1
        ldy xm
        lda (p1),y
        sec
        sbc (p3),y
        tay
        lda pp
        clc
        adc XLR,y
        sta pp
        lda pp+1
        adc XHR,y
        sta pp+1
        lda MR,y
        jmp .plot
.q1     ; 90-180: left, down
        tya
        eor #$ff
        tay
        lda CQ,y
        sta xm
        lda SQT,y
        tay
        lda (p1),y
        sec
        sbc (p3),y
        tay
        lda YLO,y
        sta pp
        !if .b = 0 { lda YHA,y } else { lda YHB,y }
        sta pp+1
        ldy xm
        lda (p1),y
        sec
        sbc (p3),y
        tay
        lda pp
        clc
        adc XLL,y
        sta pp
        lda pp+1
        adc XHL,y
        sta pp+1
        lda ML,y
        jmp .plot
.q23    bvs .q3
        ; 180-270: left, up
        lda CQ,y
        sta xm
        lda SQT,y
        tay
        lda (p1),y
        sec
        sbc (p3),y
        ora #$80
        tay
        lda YLO,y
        sta pp
        !if .b = 0 { lda YHA,y } else { lda YHB,y }
        sta pp+1
        ldy xm
        lda (p1),y
        sec
        sbc (p3),y
        tay
        lda pp
        clc
        adc XLL,y
        sta pp
        lda pp+1
        adc XHL,y
        sta pp+1
        lda ML,y
        jmp .plot
.q3     ; 270-360: right, up
        tya
        eor #$ff
        tay
        lda CQ,y
        sta xm
        lda SQT,y
        tay
        lda (p1),y
        sec
        sbc (p3),y
        ora #$80
        tay
        lda YLO,y
        sta pp
        !if .b = 0 { lda YHA,y } else { lda YHB,y }
        sta pp+1
        ldy xm
        lda (p1),y
        sec
        sbc (p3),y
        tay
        lda pp
        clc
        adc XLR,y
        sta pp
        lda pp+1
        adc XHR,y
        sta pp+1
        lda MR,y
.plot   sta mk
        ldy #0
        lda (pp),y
        !if .b = 0 { sta ES0,x } else { sta ES1,x }
        ora mk
        sta (pp),y
        lda pp
        !if .b = 0 { sta EAL0,x } else { sta EAL1,x }
        lda pp+1
        !if .b = 0 { sta EAH0,x } else { sta EAH1,x }
        inx
        cpx rend
        beq +
        jmp .star
+       inc ringk
        jmp .ring
.done   !if .b = 0 { stx nst0 } else { stx nst1 }
        rts
}

; take the stars off bitmap B: the bytes back, the last first
!macro starerase .b {
        !if .b = 0 { ldx nst0 } else { ldx nst1 }
        beq .x
        ldy #0
.l      dex
        !if .b = 0 { lda EAL0,x } else { lda EAL1,x }
        sta pp
        !if .b = 0 { lda EAH0,x } else { lda EAH1,x }
        sta pp+1
        !if .b = 0 { lda ES0,x } else { lda ES1,x }
        sta (pp),y
        txa
        bne .l
.x      rts
}

!zone splot0
splot0  +starplot 0
!zone splot1
splot1  +starplot 1
!zone serase0
serase0 +starerase 0
!zone serase1
serase1 +starerase 1

; the rings a step on (2 frames)
!zone rings
rings   ldy #0
.l      lda RN,y
        beq .x
        lda RTL,y
        clc
        adc RWL,y
        sta RTL,y
        lda RTH,y
        adc RWH,y
        sta RTH,y
        iny
        bne .l
.x      rts

; 6 stars checked against their arm: too far ahead, it starts again behind
!zone respawn
respawn lda #6
        sta xm
.l      ldx rr
        cpx nstars
        bcc +
        ldx #0
+       ldy SRING,x
        lda RTH,y
        clc
        adc SOFF,x
        sta th
        lda RARM,y
        clc
        adc alpha+1
        sec
        sbc th
        and #$7f
        cmp #WAHEAD
        bcc .nx
        cmp #64
        bcs .nx
        jsr random      ; behind the arm (either arm)
        sta th
        and #7
        clc
        adc #WBACK
        adc RARM,y
        adc alpha+1
        sec
        sbc RTH,y
        sta mk
        lda th
        and #$80
        eor mk
        sta SOFF,x
.nx     inx
        stx rr
        dec xm
        bne .l
        rts

; the stars on hand at the start: their rings, the count, the rings' angles 0
!zone starinit
starinit
        ldx #0
        ldy #0
.r      lda RN,y
        beq .x
        sta xm
        lda #0
        sta RTL,y
        sta RTH,y
-       tya
        sta SRING,x
        inx
        dec xm
        bne -
        iny
        bne .r
.x      stx nstars
        lda #0
        sta nst0
        sta nst1
        sta rr
        lda #>SQH
        sta p1+1
        lda #>NSQH
        sta p3+1
        rts
nstars  !byte 0

; ============================================== the turn
; m1 x m2 (signed bytes, -127..127) -> res (16 bits): (a+b)^2/4 - (a-b)^2/4
!zone smul
smul    lda m1
        eor m2
        sta sgn
        lda m1
        bpl +
        eor #$ff
        clc
        adc #1
        sta m1
+       lda m2
        bpl +
        eor #$ff
        clc
        adc #1
        sta m2
+       lda m1
        clc
        adc m2
        tax             ; |a|+|b|
        lda m1
        sec
        sbc m2
        bcs +
        eor #$ff
        adc #1
+       tay             ; ||a|-|b||
        lda SQL,x
        sec
        sbc SQL,y
        sta res
        lda SQH,x
        sbc SQH,y
        sta res+1
        bit sgn
        bpl +
        lda #0
        sec
        sbc res
        sta res
        lda #0
        sbc res+1
        sta res+1
+       rts

; draw (into both bitmaps) until the bitmaps swap (flipped); the init sets
; noyield to draw a whole turn's frame first
!zone render
render  lda rstate
        beq .quarter
        cmp #1
        bne +
        jmp .line
+       ldy ysave       ; on along the line
        jmp rbytes
.quarter                ; a new quarter: the lines k, k+4, ... at the angle now
        lda rk
        clc
        adc #1
        and #3
        sta rk
        sta ry
        inc nquar
        lda alpha+1
        sta ra
        tax
        lda SIN8,x
        sta rs8
        txa
        clc
        adc #64
        tay
        lda SIN8,y
        sta rc8
        lda DUL,x       ; the steps along a line: u + cos, v - sin
        sta rdul1+1
        sta rdul2+1
        sta rdul3+1
        sta rdul4+1
        lda DUH,x
        sta rduh1+1
        sta rduh2+1
        sta rduh3+1
        sta rduh4+1
        txa
        sec
        sbc #64
        tax
        lda #0          ; dv = -du(a - 64)
        sec
        sbc DUL,x
        sta rdvl1+1
        sta rdvl2+1
        sta rdvl3+1
        sta rdvl4+1
        lda #0
        sbc DUH,x
        bmi .neg
        ldx #0          ; dv >= 0: a carry steps down a texture line
        beq +
.neg    ldx #1          ; dv < 0: no carry steps up one
+       lda vbr,x
        sta rvb1
        sta rvb2
        sta rvb3
        sta rvb4
        sta rvc1
        sta rvc2
        sta rvc3
        sta rvc4
        lda vad,x
        sta rva1
        sta rva2
        sta rva3
        sta rva4
        lda vin,x
        sta rvi1
        sta rvi2
        sta rvi3
        sta rvi4
        lda #1
        sta rstate
.line   ldx ry          ; the next line of the disk in this quarter
-       cpx #192
        bcc +
        lda #0          ; the quarter is done
        sta rstate
        lda noyield
        beq .again
        lda nquar
        cmp #4
        bcs .whole
.again  jmp render
.whole  rts
+       lda ROWNB,x
        bne +
        inx
        inx
        inx
        inx
        jmp -
+       stx ry
        sta rcnt
        lda rc8         ; u = 32 + (c uq + s vq) / 2 texels (8.8)
        sta m1
        lda ROWUQ,x
        sta m2
        jsr smul
        lda res
        sta acc
        lda res+1
        sta acc+1
        lda rs8
        sta m1
        ldx ry
        lda ROWVQ,x
        sta m2
        jsr smul
        lda acc
        clc
        adc res
        sta acc
        lda acc+1
        adc res+1
        cmp #$80
        ror
        ror acc
        clc
        adc #$20
        sta ysave       ; the texture column (Y, once the sums are done)
        lda acc
        sta ufr
        lda #0          ; v = 32 + (c vq - s uq) / 2
        sec
        sbc rs8
        sta m1
        ldx ry
        lda ROWUQ,x
        sta m2
        jsr smul
        lda res
        sta acc
        lda res+1
        sta acc+1
        lda rc8
        sta m1
        ldx ry
        lda ROWVQ,x
        sta m2
        jsr smul
        lda acc
        clc
        adc res
        sta acc
        lda acc+1
        adc res+1
        cmp #$80
        ror
        ror acc
        clc
        adc #$20        ; the texture line: TEX + 64 x v
        sta tp+1
        lda acc
        sta vfr
        lda #0
        lsr tp+1
        ror
        lsr tp+1
        ror
        sta tp
        lda tp+1
        clc
        adc #>TEX
        sta tp+1
        ldx ry          ; the bitmap's line: $6000 + 320 (y / 8) + (y & 7) + 8 c0
        lda ROWC0,x
        sta c8x
        lda #0
        sta acc+1
        asl c8x
        asl c8x
        asl c8x
        rol acc+1       ; (c0 < 40: 8 c0 fits in 9 bits)
        txa
        and #7
        sta acc
        txa
        lsr
        lsr
        lsr
        tax
        lda acc
        clc
        adc bmrlo,x
        sta rsa+1
        sta rsb+1
        sta rsc+1
        sta rsd+1
        lda acc+1
        adc bmrhi,x
        sta rsa+2
        sta rsc+2
        clc
        adc #$40
        sta rsb+2
        sta rsd+2
        lda ry          ; the dither's 4 tables for this line
        and #15
        tax
        lda dtlo,x
        sta rdl0+1
        lda dthi,x
        sta rdl0+2
        lda rdl0+1
        clc
        adc #17
        sta rdl1+1
        lda rdl0+2
        adc #0
        sta rdl1+2
        lda rdl1+1
        clc
        adc #17
        sta rdr0+1
        lda rdl1+2
        adc #0
        sta rdr0+2
        lda rdr0+1
        clc
        adc #17
        sta rdr1+1
        lda rdr0+2
        adc #0
        sta rdr1+2
        lda #2
        sta rstate
        ldy ysave
        ldx ry
        lda ROWC0,x
        lsr
        bcc rbytes
        jmp rodd        ; an odd first byte
; the bytes: texture steps 2 a byte, a nibble from each
!zone rbytes
rbytes  lda flipped
        beq +
        jmp .yield
+
        ; an even byte: left nibble
        lda (tp),y
        tax
        lda ufr
        clc
rdul1   adc #0
        sta ufr
        tya
rduh1   adc #0
        tay
        lda vfr
        clc
rdvl1   adc #0
        sta vfr
rvb1    bcc +
        lda tp
rva1    adc #$3f
        sta tp
rvc1    bcc +
rvi1    inc tp+1
+
rdl0    lda DITH,x
        sta mk
        ; its right nibble
        lda (tp),y
        tax
        lda ufr
        clc
rdul2   adc #0
        sta ufr
        tya
rduh2   adc #0
        tay
        lda vfr
        clc
rdvl2   adc #0
        sta vfr
rvb2    bcc +
        lda tp
rva2    adc #$3f
        sta tp
rvc2    bcc +
rvi2    inc tp+1
+
rdr0    lda DITH,x
        ora mk
        ldx c8x
rsa     sta $6000,x
rsb     sta $a000,x
        txa
        clc
        adc #8
        sta c8x
        bcc +
        inc rsa+2
        inc rsb+2
        inc rsc+2
        inc rsd+2
+       dec rcnt
        beq .eol
rodd    ; an odd byte: left nibble
        lda (tp),y
        tax
        lda ufr
        clc
rdul3   adc #0
        sta ufr
        tya
rduh3   adc #0
        tay
        lda vfr
        clc
rdvl3   adc #0
        sta vfr
rvb3    bcc +
        lda tp
rva3    adc #$3f
        sta tp
rvc3    bcc +
rvi3    inc tp+1
+
rdl1    lda DITH,x
        sta mk
        lda (tp),y
        tax
        lda ufr
        clc
rdul4   adc #0
        sta ufr
        tya
rduh4   adc #0
        tay
        lda vfr
        clc
rdvl4   adc #0
        sta vfr
rvb4    bcc +
        lda tp
rva4    adc #$3f
        sta tp
rvc4    bcc +
rvi4    inc tp+1
+
rdr1    lda DITH,x
        ora mk
        ldx c8x
rsc     sta $6000,x
rsd     sta $a000,x
        txa
        clc
        adc #8
        sta c8x
        bcc +
        inc rsa+2
        inc rsb+2
        inc rsc+2
        inc rsd+2
+       dec rcnt
        beq .eol
        jmp rbytes
.eol    lda ry          ; the line is done
        clc
        adc #4
        sta ry
        lda #1
        sta rstate
        jmp render
.yield  sty ysave
        rts
noyield !byte 0
; the step's opcodes: dv >= 0 (bcc, adc, bcc, inc) or dv < 0 (bcs, sbc, bcs, dec)
vbr     !byte $90, $b0
vad     !byte $69, $e9
vin     !byte $e6, $c6
; the bitmap's cell rows ($6000 + 320 row)
bmrlo   !for k, 0, 23 { !byte <($6000 + 320 * k) }
bmrhi   !for k, 0, 23 { !byte >($6000 + 320 * k) }
; the dither's tables for a line (+0 left even, +17 left odd, +34 right even, +51 right odd)
dtlo    !for k, 0, 15 { !byte <(DITH + 68 * k) }
dthi    !for k, 0, 15 { !byte >(DITH + 68 * k) }
}
