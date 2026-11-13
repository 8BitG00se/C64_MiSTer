; TESTCARD.PRG - a CRT/HDMI test card for the Octophonic 64 (and any C64)
; (c) 2026 Mong00se
;  _____
; | OCT |  MONG00SE / OCTOPHONIC
; |_____|
; A white crosshatch on black filling the whole 320x200 screen, edge to edge, with a centre
; circle and corner circles, for setting a monitor's size, centre and geometry.
;   SPACE   - border colour: grey / white / black / blue (see where the picture ends)
;   I       - swap: black lines on white
;   RETURN  - back to the start screen (reset)

        * = $0801
        !word basend, 2026
        !byte $9e
        !text "2112"
        !byte $3a, $8f                          ; : REM
        !text " (C) 2026 MONG00SE TESTCARD"
        !byte 0
basend  !word 0

        * = $0840                               ; 2112
start   sei
        lda #$7f
        sta $dc0d                               ; no CIA interrupts while we set up
        lda #$36
        sta $01
        ; bitmap at $2000, screen (colours) at $0400
        lda #$3b                                ; bitmap mode, display on, 25 rows
        sta $d011
        lda #$08                                ; hires, 40 columns
        sta $d016
        lda #$18                                ; screen $0400, bitmap $2000
        sta $d018
        lda $dd00
        ora #$03                                ; VIC bank 0
        sta $dd00
        lda #$10                                ; white lines on black
        jsr setcol
        ldx #0
        stx bord
        lda borders
        sta $d020
        lda #0
        sta $d021
        cli

keys    jsr $ffe4                               ; GETIN
        beq keys
        cmp #$20
        bne +
        ldx bord
        inx
        cpx #4
        bne nb
        ldx #0
nb      stx bord
        lda borders,x
        sta $d020
        jmp keys
+       cmp #$49                                ; I
        bne +
        lda inv
        eor #1
        sta inv
        beq w
        lda #$01                                ; black lines on white
        !byte $2c
w       lda #$10
        jsr setcol
        jmp keys
+       cmp #$0d                                ; RETURN: back to the start screen
        bne keys
        jmp ($fffc)

setcol  ldx #0
-       sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        inx
        bne -
        rts

bord    !byte 0
inv     !byte 0
borders !byte 12, 1, 0, 6                       ; grey, white, black, blue
copyr   !text "(C) 2026 MONG00SE"

        * = $2000
        !binary "card.bin"
