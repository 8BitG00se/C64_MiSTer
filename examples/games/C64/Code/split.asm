; SPLIT.ASM - split screens: three
; bands, each set up differently by
; OctoVIC's copper as the beam gets
; there. Top: the VIC's text on a
; dark sky. Middle: a layer scrolling
; left, in FRONT of the VIC. Bottom:
; the same layer scrolling right, two
; times faster, BEHIND the VIC's text.
; RUN/STOP+RESTORE: back to the editor.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

split1  = 110   ; raster line: band 2
split2  = 200   ; raster line: band 3
speed1  = 1     ; band 2 speed (left)
speed2  = 3     ; band 3 speed (right)

; the stripes' colours: red, green, blue
cols    !byte 255,80,60, 255,200,60
        !byte 60,140,255, 60,230,200

; ======== the program ================

list    = $020000       ; copper list
p       = $fb           ; a pointer

start   sei
        jsr screen
        jsr octoon
        jsr tiles
        jsr map
        jsr copper
main    lda #255        ; wait for the
-       cmp $d012       ; bottom
        bne -
        lda s1          ; band 2 left
        clc
        adc #speed1
        sta s1
        bcc +
        inc s1+1
+       lda s2          ; band 3 right
        sec
        sbc #speed2
        sta s2
        bcs +
        dec s2+1
+       ldx #6          ; into the list:
        lda s1          ; entries 6,7,12,13
        jsr poke
        ldx #7
        lda s1+1
        jsr poke
        ldx #12
        lda s2
        jsr poke
        ldx #13
        lda s2+1
        jsr poke
        jmp main

; list entry X's value = A
poke    pha
        txa
        asl
        asl
        ora #3
        sta $d600
        lda #>list
        sta $d601
        lda #^list
        sta $d602
        pla
        sta $d604
        rts

; ---- text on every row, white
screen  lda #0
        sta $d020
        sta $d021
        ldx #0
-       lda #1
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne -
        lda #<$0400
        sta p
        lda #>$0400
        sta p+1
        ldx #25
--      ldy #0
-       lda msg,y
        sta (p),y
        iny
        cpy #40
        bne -
        lda p
        clc
        adc #40
        sta p
        bcc +
        inc p+1
+       dex
        bne --
        rts
msg     !scr "  split screens with octovic's copper   "

; ---- OctoVIC on, everything off
octoon  lda #$4f
        sta $d03f
        lda #$38
        sta $d03f
        ldx #$4b
        lda #0
-       sta $d605,x
        dex
        bpl -
        lda #9
        sta $d605
        lda #0          ; palette 1-4
        sta $d619
        lda #1
        sta $d61a
        ldx #0
-       lda cols,x
        sta $d61b
        inx
        lda cols,x
        sta $d61c
        inx
        lda cols,x
        sta $d61d
        inx
        cpx #12
        bne -
        lda #2          ; the copper sets
        sta $d619       ; the backdrop
        lda #1
        sta $d603
        rts

; ---- two 16-colour tiles: stripes
; colour ((x+y)/4 and 1) + 1 (tile 1),
; the other way + 3 (tile 2), at
; VRAM $040020 (tile 0 is blank)
tiles   lda #$20
        sta $d600
        lda #0
        sta $d601
        lda #4
        sta $d602
        ldx #0          ; 64 bytes:
-       lda stripes,x   ; both tiles
        sta $d604
        inx
        cpx #64
        bne -
        rts
stripes !byte $11,$22,$22,$11, $12,$22,$21,$11
        !byte $22,$22,$11,$11, $22,$21,$11,$12
        !byte $22,$11,$11,$22, $21,$11,$12,$22
        !byte $11,$11,$22,$22, $11,$12,$22,$21
        !byte $33,$44,$44,$33, $34,$44,$43,$33
        !byte $44,$44,$33,$33, $44,$43,$33,$34
        !byte $44,$33,$33,$44, $43,$33,$34,$44
        !byte $33,$33,$44,$44, $33,$34,$44,$43

; ---- the map: rows 0-15 tile 1,
; rows 16-31 tile 2 (64 wide)
map     lda #0
        sta $d600
        sta $d601
        lda #3          ; $030000
        sta $d602
        ldy #0          ; row
--      ldx #64
-       lda #1          ; tile 1 or 2
        cpy #16
        bcc +
        lda #2
+       sta $d604
        lda #0
        sta $d604
        dex
        bne -
        iny
        cpy #32
        bne --
        lda #0          ; layer 0's map
        sta $d621       ; and tiles
        sta $d622
        lda #3
        sta $d623
        lda #0
        sta $d624
        sta $d625
        lda #4
        sta $d626
        rts

; ---- the list: line, register, value
copper  lda #<list
        sta $d600
        lda #>list
        sta $d601
        lda #^list
        sta $d602
        ldx #0
-       lda steps,x
        sta $d604
        inx
        cpx #stepsend-steps
        bne -
        lda #<list      ; COPBASE
        sta $d610
        lda #>list
        sta $d611
        lda #^list
        sta $d612
        lda #1
        sta $d60e       ; the copper on
        rts

; band 1 (line 16): layer off, the VIC
; in front, its black see-through
steps   !word 16
        !byte $20,0
        !word 16
        !byte $05,$09
        !word 16        ; the backdrop:
        !byte $1a,0     ; colour 0 =
        !word 16
        !byte $1b       ; sky1
        !byte 10
        !word 16
        !byte $1c,10
        !word 16
        !byte $1d,50
; band 2: the layer on, the VIC behind
        !word split1
        !byte $28,0     ; (entry 6)
        !word split1
        !byte $29,0     ; (entry 7)
        !word split1
        !byte $2a,0
        !word split1
        !byte $2b,0
        !word split1
        !byte $05,$05
        !word split1
        !byte $20,$11
; band 3: map rows 16-31, VIC in front
        !word split2
        !byte $28,0     ; (entry 12)
        !word split2
        !byte $29,0     ; (entry 13)
        !word split2
        !byte $2a,<(128-(split2-51))
        !word split2
        !byte $2b,>(128-(split2-51))
        !word split2
        !byte $05,$09
        !word split2    ; the backdrop
        !byte $1a,0     ; again: sky3
        !word split2
        !byte $1b,40
        !word split2
        !byte $1c,0
        !word split2
        !byte $1d,40
        !word $ffff,$ffff
stepsend

s1      !word 0
s2      !word 0
