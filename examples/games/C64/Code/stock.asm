; STOCK.ASM - a program for a STOCK
; C64 (one SID, no OctoVIC, no REU).
;
; The line below makes it one: F2
; warns if the code names anything
; only an Octophonic 64 has, and runs
; it on a stock machine.
; target stock
;
; Rainbow raster bars in the border
; and a slow arpeggio on the one SID.
; RUN/STOP+RESTORE comes back here.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

speed   = 12    ; frames a note (1-50)
wave    = $21   ; $11 triangle, $21 saw,
                ; $41 pulse

; the notes (SID frequencies, PAL)
notes   !word 4455, 5613, 6675, 8910
        !word 6675, 5613
nnotes  = 6

; ======== the program ================

start   sei
        lda #0
        sta $d020
        sta $d021
        ldx #$18        ; the SID clear
-       sta $d400,x
        dex
        bpl -
        lda #$0f
        sta $d418       ; volume
        lda #$09
        sta $d405       ; attack 0, decay 9
        lda #$00
        sta $d406       ; sustain 0
        lda #$08
        sta $d403       ; pulse width
        lda #1
        sta wait
        lda #0
        sta pos
frame   lda #251        ; the bottom of the screen
-       cmp $d012
        bne -
        dec wait
        bne bars
        lda #speed
        sta wait
        lda pos         ; the next note
        asl
        tax
        lda notes,x
        sta $d400
        lda notes+1,x
        sta $d401
        lda #wave-1     ; gate off, then on
        sta $d404
        lda #wave
        sta $d404
        inc pos
        lda pos
        cmp #nnotes
        bne bars
        lda #0
        sta pos
bars    ldx #0          ; a colour every line
-       lda $d012
        cmp $d012
        beq *-3
        txa
        lsr
        lsr
        lsr
        and #15
        sta $d020
        inx
        cpx #200
        bne -
        lda #0
        sta $d020
        jmp frame

wait    !byte 0
pos     !byte 0
