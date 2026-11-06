; SPLIT.ASM - split screens: three
; bands, each set up differently by
; OctoVIC's copper as the beam gets
; there. Each band says what it shows.
; Band 1: the VIC's text on a dark sky.
; Band 2: a layer scrolling left, in
; FRONT of the text (a fence: you see
; the text through its gaps). Band 3:
; the same layer scrolling right, 3
; times faster, behind the text.
; RUN/STOP+RESTORE: back to the editor.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

; the splits sit BETWEEN text rows:
; the first row starts on line 51 and
; a row is 8 lines, so 51 + 8 * row
split1  = 115   ; band 2 starts: row 8
split2  = 187   ; band 3 starts: row 17
speed1  = 1     ; band 2 speed (left)
speed2  = 3     ; band 3 speed (right)

; the colours 1-8: red, green, blue
; 1-2 the fence, 3-8 the soft bars
cols    !byte 255,170,60, 200,90,30
        !byte 140,230,235, 100,200,225
        !byte 70,160,210, 50,120,190
        !byte 35,85,160, 25,55,125

; ======== the program ================

list    = $020000       ; copper list
p       = $fb           ; a pointer
q       = $fd           ; another

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

; ---- white text, and a label for each band
screen  lda #0
        sta $d020
        sta $d021
        ldx #0
-       lda #1
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        lda #32         ; a blank screen
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        inx
        bne -
        lda #<labels    ; the labels: an
        sta q           ; address, then
        lda #>labels    ; the text up to
        sta q+1         ; a 0
--      ldy #0
        lda (q),y
        sta p
        iny
        lda (q),y
        beq ++          ; address 0: done
        sta p+1
        lda q           ; past the address
        clc
        adc #2
        sta q
        bcc +
        inc q+1
+       ldy #0
-       lda (q),y       ; the text
        beq +
        sta (p),y
        iny
        bne -
+       iny             ; past the 0
        tya
        clc
        adc q
        sta q
        bcc --
        inc q+1
        bne --
++      rts
; row r starts at $0400 + 40 * r
labels  !word $0400+40*1+2
        !scr "band 1: the vic's own text",0
        !word $0400+40*2+2
        !scr "the copper has the layer off here",0
        !word $0400+40*3+2
        !scr "just a dark blue sky behind",0
        !word $0400+40*5+2
        !scr "change split1 and split2 to",0
        !word $0400+40*6+2
        !scr "move the bands (51 + 8 * row)",0
        !word $0400+40*9+2
        !scr "band 2: a layer in front of text",0
        !word $0400+40*10+2
        !scr "a fence scrolling left, 1 pixel",0
        !word $0400+40*11+2
        !scr "a frame. the text is behind it",0
        !word $0400+40*18+2
        !scr "band 3: the same layer behind",0
        !word $0400+40*19+2
        !scr "the text, as soft bars scrolling",0
        !word $0400+40*20+2
        !scr "right, three times faster",0
        !word 0

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
        lda #0          ; palette 1-8
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
        cpx #24
        bne -
        lda #2          ; the copper sets
        sta $d619       ; the backdrop
        lda #1
        sta $d603
        rts

; ---- five 16-colour tiles at VRAM
; $040020 (tile 0 is blank): tile 1
; the fence, tiles 2-5 one soft bar
; (colours 3 bright to 8 dark)
tiles   lda #$20
        sta $d600
        lda #0
        sta $d601
        lda #4
        sta $d602
        ldx #0          ; 160 bytes:
-       lda stripes,x   ; five tiles
        sta $d604
        inx
        cpx #160
        bne -
        rts
; tile 1: the fence - two bars in eight
; pixels, the rest colour 0 (see-through)
stripes !byte $12,$00,$00,$00
        !byte $12,$00,$00,$00
        !byte $12,$00,$00,$00
        !byte $12,$00,$00,$00
        !byte $12,$00,$00,$00
        !byte $12,$00,$00,$00
        !byte $12,$00,$00,$00
        !byte $12,$00,$00,$00
        ; tile 2: soft bar, columns 0-7 of 32
        !byte $87,$77,$66,$65
        !byte $87,$77,$66,$65
        !byte $87,$77,$66,$65
        !byte $87,$77,$66,$65
        !byte $87,$77,$66,$65
        !byte $87,$77,$66,$65
        !byte $87,$77,$66,$65
        !byte $87,$77,$66,$65
        ; tile 3: soft bar, columns 8-15 of 32
        !byte $55,$44,$43,$33
        !byte $55,$44,$43,$33
        !byte $55,$44,$43,$33
        !byte $55,$44,$43,$33
        !byte $55,$44,$43,$33
        !byte $55,$44,$43,$33
        !byte $55,$44,$43,$33
        !byte $55,$44,$43,$33
        ; tile 4: soft bar, columns 16-23 of 32
        !byte $33,$34,$44,$55
        !byte $33,$34,$44,$55
        !byte $33,$34,$44,$55
        !byte $33,$34,$44,$55
        !byte $33,$34,$44,$55
        !byte $33,$34,$44,$55
        !byte $33,$34,$44,$55
        !byte $33,$34,$44,$55
        ; tile 5: soft bar, columns 24-31 of 32
        !byte $56,$66,$77,$78
        !byte $56,$66,$77,$78
        !byte $56,$66,$77,$78
        !byte $56,$66,$77,$78
        !byte $56,$66,$77,$78
        !byte $56,$66,$77,$78
        !byte $56,$66,$77,$78
        !byte $56,$66,$77,$78

; ---- the map: rows 0-15 the fence
; (tile 1 every other tile), rows 16-31 the soft bar
; (tiles 2-5 side by side), 64 wide
map     lda #0
        sta $d600
        sta $d601
        lda #3          ; $030000
        sta $d602
        ldy #0          ; row
--      ldx #0          ; column
-       txa
        cpy #16
        bcs +
        and #1          ; the fence: tile 1
        jmp ++          ; and a blank tile
+       and #3          ; tile 2 + column
        clc             ; mod 4
        adc #2
++      sta $d604
        lda #0
        sta $d604
        inx
        cpx #64
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
