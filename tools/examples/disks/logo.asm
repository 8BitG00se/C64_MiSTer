; LOGO.ASM - a colour-cycling logo on
; a STOCK C64. The big letters are
; made from the C64's own font: every
; lit pixel of a letter is a solid
; block in the text screen, and the
; cycling is only the colour memory,
; stepped round a table every few frames.
; target stock
; RUN/STOP+RESTORE: back to READY.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

speed   = 2     ; frames a colour step (1-5)

; the letters: C64 screen codes (A=1 ... Z=26,
; 0-9 = 48-57), 4 on the first line, 2 on the
; second. Try your own!
line1   !byte 15,3,20,15        ; O C T O
line2   !byte 54,52             ; 6 4

; 32 colours, round and round
cols    !byte 6,6,14,14,3,3,1,1
        !byte 3,3,14,14,6,6,2,2
        !byte 8,8,10,10,7,7,1,1
        !byte 7,7,10,10,8,8,2,2

; ======== the program ================

p       = $fb
q       = $fd

start   sei             ; (the ROM goes out of sight
        lda #0          ; while we read the font)
        sta $d020
        sta $d021
        ldx #0
-       lda #32         ; an empty screen
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        inx
        bne -
        lda #<($0400+4*40+4)    ; "OCTO": row 4
        sta q
        lda #>($0400+4*40+4)
        sta q+1
        ldx #0
        ldy #4
        jsr word
        lda #<($0400+14*40+12)  ; "64": row 14
        sta q
        lda #>($0400+14*40+12)
        sta q+1
        ldx #4
        ldy #2
        jsr word
main    lda #251        ; wait for the bottom
-       cmp $d012
        bne -
        dec wait
        bne main
        lda #speed
        sta wait
        inc phase
        lda #<$d800     ; colour memory, row by
        sta p           ; row: one colour a row,
        lda #>$d800     ; stepped round the table
        sta p+1         ; as the phase moves on
        ldx #0
rows    txa
        asl
        clc
        adc phase
        and #31
        tay
        lda cols,y
        ldy #39
-       sta (p),y
        dey
        bpl -
        clc
        lda p
        adc #40
        sta p
        bcc +
        inc p+1
+       inx
        cpx #25
        bne rows
        jmp main

; one word: Y letters, the screen codes
; from the list at X (4 = line 2), the
; first letter's top left at q
word    stx wx
        sty wn
        lda #0
        sta wi
letter  ldx wx
        lda line1,x
        ldx #0
        stx p+1
        asl             ; the letter's font
        rol p+1         ; address: $d000 +
        asl             ; code*8
        rol p+1
        asl
        rol p+1
        sta p
        lda p+1
        clc
        adc #>$d000
        sta p+1
        lda #$33        ; the character ROM
        sta $01         ; in view
        ldy #7
-       lda (p),y       ; its 8 rows
        sta bitrow,y
        dey
        bpl -
        lda #$37        ; back as it was
        sta $01
        ldx #0          ; draw the 8 rows
rowl    lda bitrow,x
        ldy #0
pix     asl
        pha
        lda #32
        bcc +
        lda #160        ; a solid block
+       sta (q),y
        pla
        iny
        cpy #8
        bne pix
        clc             ; down a row
        lda q
        adc #40
        sta q
        bcc +
        inc q+1
+       inx
        cpx #8
        bne rowl
        sec             ; back up 8 rows and
        lda q           ; on 9 columns
        sbc #<(8*40-9)
        sta q
        lda q+1
        sbc #>(8*40-9)
        sta q+1
        inc wx
        inc wi
        lda wi
        cmp wn
        bne letter
        rts

wait    !byte 1
phase   !byte 0
wx      !byte 0
wn      !byte 0
wi      !byte 0
bitrow  !byte 0,0,0,0,0,0,0,0
