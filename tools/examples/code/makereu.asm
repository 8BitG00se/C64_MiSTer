; MAKEREU.ASM - make a .reu file on
; the Octophonic 64 itself (Fix 56).
; (c) 2026 Mong00se
; Your program builds its data in the
; REU, then saves it as a .reu beside
; itself. Next time, the browser puts
; that .reu in before the .prg runs.
;   1 data into C64 RAM (here: a test
;     pattern - put your own there)
;   2 C64 RAM -> REU (STASH)
;   3 REU -> OctoVIC's VRAM (FETCH,
;     the C64 address fixed at VDATA)
;   4 SAVEREU: Main writes the VRAM
;     pages to the file
; RUN/STOP+RESTORE: back to the editor.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

name    !text "MADE"   ; the file: MADE.REU
namel   = 4
kb      = 16           ; how much (KB, 1-48)

; ======== the program ================

data    = $4000        ; the data in C64 RAM
vpage   = $F000        ; VRAM $F00000 (/256)
MB      = $D6F0        ; Main's mailbox
seq     = $02AB        ; its request number

start   lda #$4F       ; OctoVIC's page on
        sta $D03F
        lda #$38
        sta $D03F
        lda #<said     ; what it does
        ldy #>said
        jsr $AB1E
; 1 - the data: a pattern, A = lo + hi
        lda #<data
        sta $FB
        lda #>data
        sta $FC
        ldx #kb*4      ; pages
--      ldy #0
-       tya
        clc
        adc $FC
        sta ($FB),y
        iny
        bne -
        inc $FC
        dex
        bne --
; 2 - C64 -> REU, at REU address 0
        jsr regs
        lda #0
        sta $DF0A      ; both count up
        lda #$90       ; STASH, now
        sta $DF01
; 3 - REU -> VRAM: VDATA, fixed
        lda #0         ; VRAM address
        sta $D600
        lda #<vpage
        sta $D601
        lda #>vpage
        sta $D602
        lda #1
        sta $D603      ; +1 a byte
        jsr regs
        lda #<$D604    ; into VDATA
        sta $DF02
        lda #>$D604
        sta $DF03
        lda #$80       ; C64 side fixed
        sta $DF0A
        lda #$91       ; FETCH, now
        sta $DF01
        lda #0
        sta $DF0A
; 4 - SAVEREU ($1C)
        sta MB+9       ; the name, new
        ldx #0
-       lda name,x
        sta MB+8
        inx
        cpx #namel
        bne -
        lda #<vpage
        sta MB+2
        lda #>vpage
        sta MB+3
        lda #<(kb*4)
        sta MB+4
        lda #>(kb*4)
        sta MB+5
        lda #0         ; ARG 0: a new file
        sta MB+6
        inc seq
        lda seq
        sta MB+$D
        lda #$1C
        sta MB         ; ask Main
-       lda MB+1       ; wait: busy is 1
        cmp #1
        beq -
        lda MB+$E      ; our answer?
        cmp seq
        bne -
        lda MB+1
        cmp #2
        bne bad
        lda #<good
        ldy #>good
        jmp $AB1E
bad     lda #<nogood
        ldy #>nogood
        jmp $AB1E

; the REU's registers for kb KB
regs    lda #<data
        sta $DF02
        lda #>data
        sta $DF03
        lda #0
        sta $DF04
        sta $DF05
        sta $DF06
        lda #<(kb*1024)
        sta $DF07
        lda #>(kb*1024)
        sta $DF08
        rts

said    !pet 13, "makereu: data -> reu -> vram -> file", 13, 0
good    !pet "saved made.reu beside the program.", 13, 0
nogood  !pet "?not saved (an older main?)", 13, 0
