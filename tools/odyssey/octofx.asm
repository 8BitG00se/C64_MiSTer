; (C) 2026 Mong00se
; OCTOFX.ASM - the Octophonic show's set-up and effects: the twinkles, the
; sparkles, the sprite table, the scroll text (with OCTO.ASM)
; A part of ODYSSEY.ASM (2026: An Octophonic Odyssey), by Mong00se:
; F2 on it builds the whole demo.
!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }
!if odyp = 0 {
        !src "odyssey.asm"
} else {
; ------------------------------------------------ the stars twinkle
; palette entries 232-239: the picture's stars, 8 groups; each one's
; brightness walks to a new random target
!zone twinkle8
twinkle8
        lda fade
        cmp #64
        bcc .x
        lda #0
        sta PALSEL
        lda #232
        sta PALIDX
        ldx #0
.l      lda TW,x
        cmp TW+8,x
        bne .mv
        jsr random      ; a new target: 120-255, mostly bright
        ora #$78
        sta TW+8,x
        jmp .w
.mv     bcc .up
        sec
        sbc #9
        bcc +
        cmp TW+8,x
        bcs .st
+       lda TW+8,x
        jmp .st
.up     adc #6
        bcs +
        cmp TW+8,x
        bcc .st
+       lda TW+8,x
.st     sta TW,x
.w      lda TW,x
        sta PALR
        sta PALG
        lsr
        lsr
        lsr
        lsr
        eor #$ff
        sec
        adc TW,x
        sta PALB
        inx
        cpx #8
        bne .l
.x      rts

; the fade in: the picture's colours (1-231) from black, 64 frames:
; 16 steps, each written a quarter at a time (58 entries a frame)
!zone ofade
ofade   lda fade
        cmp #64
        bcs .x
        inc fade
        lda fade
        cmp #64
        beq .all
        lda #0
        sta PALSEL
        sta MULB+1
        sta MULA+1
        lda fade        ; the step (fade AND $3C) x 4 / 256
        and #$3c
        asl
        asl
        sta MULB
        lda fade        ; the quarter: entries 1 + 58 q ...
        and #3
        tax
        lda q58,x
        sta PALIDX
        tax
        clc
        adc #58
        sta tq
-       lda PALBUF,x
        sta MULA
        lda MULR+1
        sta PALR
        lda PALBUF+256,x
        sta MULA
        lda MULR+1
        sta PALG
        lda PALBUF+512,x
        sta MULA
        lda MULR+1
        sta PALB
        inx
        cpx tq
        bne -
.x      rts
.all    ldx #1          ; the end: all of it as it is
        jmp palfrom
q58     !byte 1, 59, 117, 175   ; (175 + 58 = 233: 231, 232 too)
; palette entries X-255 from PALBUF
palfrom stx PALIDX
-       lda PALBUF,x
        sta PALR
        lda PALBUF+256,x
        sta PALG
        lda PALBUF+512,x
        sta PALB
        inx
        bne -
        rts

; ------------------------------------------------ the sparkles
; 4 sprites; each waits, then glows on a bright star in view for 32
; frames (sizes 0 1 2 3 3 2 1 0). The star's place on the screen is
; worked out every frame from the camera: (star - camera) / zoom.
!zone sparkle8
sparkle8
        lda fade
        cmp #64
        bcc .x
        ldx #3
.l      lda SPS,x
        bne .on
        lda SPS+4,x     ; waiting
        beq .new
        dec SPS+4,x
        jmp .nx
.new    jsr random
        and #31
        cmp STARS
        bcs .nx         ; (not a star: try again next frame)
        sta SPS+8,x
        jsr spos
        bcs .nx         ; not in view
        lda #32
        sta SPS,x
.on     dec SPS,x
        bne .nx
        jsr random
        and #63
        ora #16
        sta SPS+4,x
.nx     dex
        bpl .l
.x      rts

; carry clear: sparkle X's star is on the screen; tq..tq+3: its
; sprite X, Y (the sprite is 32 x 32, so 16 up and left)
spos    stx tq+6
        lda SPS+8,x
        asl
        asl
        tay             ; its entry: 1 + 4n
        ldx #0          ; across, then down
        jsr .ax
        bcs .out
        clc
        lda tq+4
        adc #<(198-32-16)
        sta tq
        lda tq+5
        adc #>(198-32-16)
        sta tq+1
        iny
        iny
        ldx #3
        jsr .ax
        bcs .out
        clc
        lda tq+4
        adc #<(158-51-16)
        sta tq+2
        lda tq+5
        adc #>(158-51-16)
        sta tq+3
        ldx tq+6
        clc
        rts
.out    ldx tq+6
        sec
        rts
; tq+4/5 = (star coordinate (STARS+1+y) x 256 - CUR,x) / zoom
.ax     sec
        lda #0
        sbc CUR,x
        sta DIVN
        lda STARS+1,y
        sbc CUR+1,x
        sta DIVN+1
        lda STARS+2,y
        sbc CUR+2,x
        sta DIVN+2
        lda #0
        sta DIVN+3
        sta sg
        lda DIVN+2      ; negative: divide the size, then turn it
        bpl +
        inc sg
        sec
        lda #0
        sbc DIVN
        sta DIVN
        lda #0
        sbc DIVN+1
        sta DIVN+1
        lda #0
        sbc DIVN+2
        sta DIVN+2
+       lda CUR+7       ; by the zoom (8.8)
        sta DIVD
        lda CUR+8
        sta DIVD+1
-       lda OSTATUS
        and #2
        bne -
        lda DIVQ+1      ; 220 or more pixels off: not in view
        bne .far
        lda DIVQ
        cmp #220
        bcs .far
        sta tq+4
        lda #0
        sta tq+5
        lda sg
        beq +
        sec
        lda #0
        sbc tq+4
        sta tq+4
        lda #0
        sbc #0
        sta tq+5
+       clc
        rts
.far    sec
        rts

; ------------------------------------------------ the sprite table
; built in the table not shown (VRAM V_SAT + sat x 1024), 8 bytes a
; sprite: x, y, graphics, size and on, how it mixes
!zone satbuild
satbuild
        lda sat         ; the other table
        eor #1
        sta sat
        asl
        asl
        tax             ; (V_SAT + sat x 1024)
        lda #0
        ldy #^V_SAT
        jsr vset
        ldx #0          ; the sparkles
.sp     lda SPS,x
        beq .off
        stx tq+7
        jsr spos
        bcs .off2
        lda tq
        sta VDATA
        lda tq+1
        sta VDATA
        lda tq+2
        sta VDATA
        lda tq+3
        sta VDATA
        ldx tq+7
        lda SPS,x       ; the size: 0 1 2 3 3 2 1 0
        lsr
        lsr
        tay
        lda osize,y
        asl
        asl
        asl
        asl
        asl
        clc
        adc HDR+64+8*6  ; (the first sparkle's graphics)
        sta VDATA
        lda #0
        sta VDATA
        lda #$ca        ; 32 x 32, 256 colours, on
        sta VDATA
        lda #$80        ; in front, added
        sta VDATA
        jmp .nx
.off2   ldx tq+7
.off    jsr soff
.nx     inx
        cpx #4
        bne .sp
        jsr soff        ; (the comet's sprite: no comet now)
        ldx #0          ; the bars: 8 x 64, the graphics of the level
-       txa
        asl
        asl
        asl
        clc
        adc #<284
        sta VDATA
        lda #>284
        adc #0
        sta VDATA
        lda #124
        sta VDATA
        lda #0
        sta VDATA
        lda EQL,x
        asl
        asl
        asl
        asl
        clc
        adc HDR+64+8*6+2
        sta VDATA
        lda #0
        adc #0
        sta VDATA
        lda #$cc        ; 8 x 64, 256 colours, on
        sta VDATA
        lda #$40        ; in front, half and half (glass)
        sta VDATA
        inx
        cpx #8
        bne -
        rts
soff    lda #0
        ldy #8
-       sta VDATA
        dey
        bne -
        rts
osize   !byte 0,1,2,3,3,2,1,0

; ------------------------------------------------ the scroll text
; 1 pixel a frame. The fine scroll steps here; when it wraps (7 again)
; the row moves a letter left in OVBLANK, at the top of the next frame,
; together with the new fine scroll - so the letters and $D016 always
; change in the same frame (before, the row moved at the end of this
; frame's work, one frame early: the text jumped back 8 pixels every
; 8 frames).
!zone oscroll
oscroll dec oxs
        bpl .x
        lda #7
        sta oxs
        lda #1
        sta oshift
.x      rts
; the row a letter left, the next letter in at the right (OVBLANK)
!zone oshiftrow
oshiftrow
        lda #0
        sta oshift
        ldx #0
-       lda $07c1,x
        sta $07c0,x
        inx
        cpx #39
        bne -
.g      ldy #0
        lda (optr),y
        bne +
        lda #<omsg
        sta optr
        lda #>omsg
        sta optr+1
        jmp .g
+       sta $07e7
        inc optr
        bne +
        inc optr+1
+       rts
; ------------------------------------------------ the show's set-up
!zone oinit
oinit   lda #0
        sta fade
        sta sat
        sta oxs
        sta tick
        sta rt
        sta rt+1
        sta oshift
        lda #<PATH
        sta rp
        lda #>PATH
        sta rp+1
        ldx #8          ; the camera starts on the path's first row
-       lda PATH+2,x
        sta CB,x
        dex
        bpl -
        ldx #$4f
        lda #0
-       sta TW,x
        dex
        bpl -
        ldx #31
-       sta EQL,x
        dex
        bpl -
        jsr cls         ; the VIC: the scroll text's row only
        ldx #39
        lda #1
-       sta $dbc0,x
        dex
        bpl -
        lda #<omsg
        sta optr
        lda #>omsg
        sta optr+1
        lda #0
        sta $d020
        sta $d021
        lda #$15
        sta $d018
        lda #<V_SAT     ; the sprites
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
        jsr satbuild
        jsr satbuild
        lda #NSPR
        sta SPRCNT
        lda #$0c        ; layer 0: a BITMAP, turned and sized, nothing
        sta L0+$f       ; outside the picture
        lda #0
        sta OKEY        ; the VIC's black is see-through, the VIC in
        lda #$0b        ; front, its colours OctoVIC's VIC palette
        sta OCTRL
        lda #<oirq
        sta $0314
        lda #>oirq
        sta $0315
        lda #<300       ; a frame: the raster interrupt at line 300
        sta $d012
        lda $d011
        ora #$80
        sta $d011
        lda #1
        sta $d01a
        sta $d019
        ldx #5          ; wake SIDs 3-8 (a control write, then the
-       lda osidlo,x    ; volume: until then the Octophonic gives
        sta tq          ; their writes to SID 1 too - their filter
        lda osidhi,x    ; settings would silence it)
        sta tq+1
        lda #0
        ldy #4
        sta (tq),y
        ldy #$18
        sta (tq),y
        dex
        bpl -
        lda #$20        ; the music: SIDs 1 and 2 by the player,
        sta sid2lo      ; 3-8 from the REU
        lda #$d4
        sta sid2hi
        lda #6
        jsr pl_init
        cli
        rts

!zone oirq
oirq    lda $d019
        sta $d019
        inc tick
        jmp $ea81

}
