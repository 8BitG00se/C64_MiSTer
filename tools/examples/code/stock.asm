; STOCK.ASM - a program for a STOCK
; C64 (one SID, no OctoVIC, no REU).
;
; The line below makes it one: F2
; warns if the code names anything
; only an Octophonic 64 has, and runs
; it on a stock machine.
; target stock
;
; Steady rainbow raster bars over the
; whole screen, and a slow arpeggio
; on the one SID. The trick: a raster
; interrupt twice (the second one
; fires inside a row of NOPs, so we
; know the exact cycle), then a loop
; of exactly 63 cycles - one PAL
; line - that changes the border
; colour. The screen is switched off
; so no line is a "bad line" that
; steals the CPU's cycles.
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
lines   = 296   ; lines of bars a frame

; the notes (SID frequencies, PAL)
notes   !word 4455, 5613, 6675, 8910
        !word 6675, 5613
nnotes  = 6

; 32 colours, four bars of 8 lines:
; blue, red, green, purple
colours !byte 0,6,14,3,1,3,14,6
        !byte 0,2,8,10,7,10,8,2
        !byte 0,5,13,7,1,7,13,5
        !byte 0,4,10,15,1,15,10,4

; ======== the program ================

tab     = $0c00         ; the colours, copied here
                        ; so a line never crosses
                        ; a page (that costs a cycle)
cnt     = $fb

start   sei
        lda #$7f
        sta $dc0d       ; no timer interrupts
        sta $dd0d
        lda $dc0d
        lda $dd0d
        ldx #31
-       lda colours,x
        sta tab,x
        dex
        bpl -
        lda $d020       ; to put back at the end
        sta oldb
        lda $d021
        sta oldg
        lda #0
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
        sta phase
        lda #<nmi       ; RUN/STOP+RESTORE
        sta $fffa       ; (the ROM is off,
        lda #>nmi       ; so the vectors are
        sta $fffb       ; in RAM now)
        lda #<irq1
        sta $fffe
        lda #>irq1
        sta $ffff
        lda #$0b        ; screen off
        sta $d011
        lda #0          ; raster line 0
        sta $d012
        lda #$ff
        sta $d019
        lda #1
        sta $d01a       ; raster interrupt on
        lda #$35        ; all RAM but the I/O
        sta $01
        cli
        jmp *           ; the rest is interrupts

; ---- the first interrupt, line 0: set up
; the second one for the next line and
; wait for it in a row of NOPs
irq1    lda #<irq2
        sta $fffe
        lda #>irq2
        sta $ffff
        inc $d012       ; the next line
        lda #$ff
        sta $d019       ; acknowledge
        tsx
        cli
        nop             ; (the interrupt
        nop             ; lands on one of
        nop             ; these: 0 or 1
        nop             ; cycles late)
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop

; ---- the second interrupt, line 1: now
; we know the cycle. Wait out the rest
; of the line, then one more cycle if the
; raster has not moved on yet.
irq2    txs
        ldx #$09
-       dex
        bne -
        bit $ea
        lda $d012
        cmp $d012
        beq +
+       ldx phase       ; the bars
        lda #lines/2    ; (two lines a turn)
        sta cnt
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        bit $ea
; ---- two lines, 63 cycles each
bars    lda tab,x       ; 4  the colour
        sta $d020       ; 4
        inx             ; 2
        txa             ; 2
        and #31         ; 2  (round and round)
        tax             ; 2
        ldy #8          ; 2
-       dey             ; 2 \ 5 cycles a turn
        bne -           ; 3 / (39 in all)
        nop             ; 2
        nop             ; 2
        nop             ; 2
        lda tab,x       ; 4  the next line
        sta $d020       ; 4
        inx             ; 2
        txa             ; 2
        and #31         ; 2
        tax             ; 2
        dec cnt         ; 5
        beq done        ; 2
        ldy #6          ; 2
-       dey             ; 2 \ 29 in all
        bne -           ; 3 /
        nop             ; 2
        nop             ; 2
        nop             ; 2
        jmp bars        ; 3

; ---- the end of the bars: the SID,
; the key, and the next frame
done    inc phase
        lda phase
        and #31
        sta phase
        dec wait
        bne next
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
        bne next
        lda #0
        sta pos
next    lda #<irq1
        sta $fffe
        lda #>irq1
        sta $ffff
        lda #0
        sta $d012
        lda #$ff
        sta $d019
        rti             ; (back to the jmp *)

; ---- RUN/STOP+RESTORE: put the screen
; back, then the ROM's own NMI
nmi     pha
        lda #$37
        sta $01
        lda #$1b
        sta $d011
        lda oldb
        sta $d020
        lda oldg
        sta $d021
        lda #0
        sta $d01a
        lda #$ff
        sta $d019
        lda #$0
        sta $d418
        lda #$81
        sta $dc0d       ; the ROM's timers
        pla
        jmp $fe43

wait    !byte 0
pos     !byte 0
phase   !byte 0
oldb    !byte 0
oldg    !byte 0
