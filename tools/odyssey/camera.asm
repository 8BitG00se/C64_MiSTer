; (C) 2026 Mong00se. All rights reserved.
; CAMERA.ASM - the Octophonic camera (as in Mona Lisa): the path's rows, the
; eased glide, the turned-and-sized layer's numbers (with OCTO.ASM)
; A part of ODYSSEY.ASM (2026: An Octophonic Odyssey), by Mong00se:
; F2 on it builds the whole demo.
!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }
!if odyp = 0 {
        !src "odyssey.asm"
} else {
; ======================================== the camera (Mona Lisa's)
; PATH: rows of frames (16), x (8.8), y (8.8), zoom (8.16), event;
; each row goes in a straight line from the last row's target to its
; own over its frames. Frames 0 ends the list: round again.
!zone advance
advance lda rt
        ora rt+1
        bne .go
        jsr nextrow
.go     jsr camera
        lda rt
        bne +
        dec rt+1
+       dec rt
        rts

!zone nextrow
nextrow ldx #8
-       lda CB,x
        sta CA,x
        dex
        bpl -
        ldy #0
        lda (rp),y
        iny
        ora (rp),y
        bne .rd
        lda #<PATH
        sta rp
        lda #>PATH
        sta rp+1
.rd     ldy #0
        lda (rp),y
        sta rt
        sta tq
        iny
        lda (rp),y
        sta rt+1
        sta tq+1
        ldy #2
-       lda (rp),y
        sta CB-2,y
        iny
        cpy #11
        bne -
        lda #0          ; sstep = 65536 / frames
        sta DIVN
        sta DIVN+1
        lda #1
        sta DIVN+2
        lda #0
        sta DIVN+3
        lda tq
        sta DIVD
        lda tq+1
        sta DIVD+1
-       lda OSTATUS
        and #2
        bne -
        lda DIVQ
        sta sstep
        lda DIVQ+1
        sta sstep+1
        lda #0
        sta sacc
        sta sacc+1
        clc
        lda rp
        adc #12
        sta rp
        bcc +
        inc rp+1
+       rts

!zone camera
camera  clc
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
        lda #$ff        ; the last frame: exactly there
        sta sacc
        sta sacc+1
.s      lda sacc
        sta ee
        lda sacc+1
        sta ee+1
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
        ; which copy: the half size from zoom 1.4, the quarter from 2.8
        lda CUR+8
        cmp #3
        bcs .m2
        cmp #2
        bne +
        lda CUR+7
        cmp #$cc
        bcs .m2
        lda #1
        bne .mm
+       cmp #1
        bne .m0
        lda CUR+7
        cmp #$66
        bcc .m0
        lda #1
        bne .mm
.m2     lda #2
        bne .mm
.m0     lda #0
.mm     sta mip
        ; U0 = x - 198 zoom, V0 = y - 158 zoom (16.16), DUX = DVY = zoom
        ldx #0
        ldy #198
        jsr .uv
        ldx #3
-       lda tq,x
        sta REGS,x
        dex
        bpl -
        ldx #3
        ldy #158
        jsr .uv
        ldx #3
-       lda tq,x
        sta REGS+4,x
        dex
        bpl -
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
        ldx #7
-       sta REGS+12,x
        dex
        bpl -
        lda mip         ; a smaller copy: all of it halved (twice)
        beq .done
        tax
-       +asr32 REGS
        +asr32 REGS+4
        +asr32 REGS+8
        +asr32 REGS+20
        dex
        bne -
.done   rts
; tq..tq+3 = (CUR[x] << 8) - Y x zoom
.uv     sty MULA
        lda #0
        sta MULA+1
        lda CUR+6
        sta MULB
        lda CUR+7
        sta MULB+1
        lda MULR
        sta tq+4
        lda MULR+1
        sta tq+5
        lda MULR+2
        sta tq+6
        lda MULR+3
        sta tq+7
        lda CUR+8
        sta MULB
        lda #0
        sta MULB+1
        clc
        lda tq+6
        adc MULR
        sta tq+6
        lda tq+7
        adc MULR+1
        sta tq+7
        sec
        lda #0
        sbc tq+4
        sta tq
        lda CUR,x
        sbc tq+5
        sta tq+1
        lda CUR+1,x
        sbc tq+6
        sta tq+2
        lda CUR+2,x
        sbc tq+7
        sta tq+3
        rts

; lr = la + (lb - la) x ee / 65536 (24 bits, the difference signed)
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
}
