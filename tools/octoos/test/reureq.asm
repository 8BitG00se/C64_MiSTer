; REU REQUEST - the os-fixes test of mailbox command $18 (REU) and NET b3 (SHOWCASE).
; A running program asks Octophonic Main for a .reu from its own folder by name, waits for the
; answer, then reads the REU's first 40 bytes onto the screen. It asks for PART A, then PART B,
; then PART B again (Main answers "in already", VALUE 4, and loads nothing). Last it shows NET b3.
; Run it from the browser in a folder holding Part A.reu and Part B.reu (mkreureq.sh makes them).
; By Mong00se. acme -f cbm -o "REU Request.prg" reureq.asm
!to "reureq.prg", cbm

MB_CMD  = $D6F0
MB_ST   = $D6F1
MB_ARG  = $D6F6
MB_VAL  = $D6F7
MB_NAME = $D6F8
MB_NCLR = $D6F9
MB_RL   = $D6FA
MB_RH   = $D6FB
MB_SEQ  = $D6FD
MB_RSEQ = $D6FE
MB_NET  = $D6FF
CHROUT  = $FFD2

        * = $0801
        !byte $0B, $08, $0A, $00, $9E, $32, $30, $36, $31, 0, 0, 0     ; 10 SYS2061

        lda #$4F                ; OctoVIC's page: the mailbox is in it
        sta $D03F
        lda #$38
        sta $D03F
        lda #<t_title
        ldy #>t_title
        jsr $AB1E
        ldx #0                  ; PART A
        jsr ask
        ldx #t_b-t_a            ; PART B
        jsr ask
        ldx #t_b-t_a            ; PART B again: in already
        jsr ask
        lda #<t_show            ; SHOWCASE, from NET b3
        ldy #>t_show
        jsr $AB1E
        lda MB_NET
        and #$08
        beq +
        lda #<t_on
        ldy #>t_on
        bne ++
+       lda #<t_off
        ldy #>t_off
++      jsr $AB1E
        rts

; ask Main for the .reu named at t_a+X; print the answer and the REU's first 40 bytes
ask     stx nm
        lda #<t_ask
        ldy #>t_ask
        jsr $AB1E
        sta MB_NCLR             ; the name: empty, then its letters
        ldx nm
-       lda t_a,x
        beq +
        sta MB_NAME
        jsr CHROUT
        inx
        bne -
+       lda #0
        sta MB_ARG              ; ARG b0 0: don't load it again if it is in already
        sta MB_VAL              ; (Main writes 3 while it puts the .reu in)
        lda MB_RSEQ             ; a number of our own, not the last one answered
        clc
        adc #1
        sta seq
        sta MB_SEQ
        lda #$18                ; REU
        sta MB_CMD
-       lda MB_ST               ; wait: STATUS no longer 1, with our number in RSEQ
        cmp #1
        beq -
        ldx MB_RSEQ
        cpx seq
        bne -
        sta st
        cmp #2
        bne fail
        lda #<t_val
        ldy #>t_val
        jsr $AB1E
        lda MB_VAL              ; 2: put in now, 4: it was in already
        jsr hex
        lda #<t_size
        ldy #>t_size
        jsr $AB1E
        lda MB_RL               ; its size in 64 KB
        jsr hex
        lda #13
        jsr CHROUT
        lda $D1                 ; the REU's first 40 bytes to the start of the next line
        clc
        adc #40
        sta $DF02
        lda $D2
        adc #0
        sta $DF03
        lda #0
        sta $DF04
        sta $DF05
        sta $DF06
        sta $DF08
        lda #40
        sta $DF07
        lda #$91                ; REU -> C64, now
        sta $DF01
        lda #13
        jsr CHROUT
        jsr CHROUT
        jmp CHROUT
fail    lda #<t_err
        ldy #>t_err
        jsr $AB1E
        lda st
        jsr hex
        lda #13
        jmp CHROUT

hex     pha
        lsr
        lsr
        lsr
        lsr
        jsr +
        pla
        and #$0F
+       cmp #10
        bcc +
        adc #6
+       adc #$30
        jmp CHROUT

nm      !byte 0
seq     !byte 0
st      !byte 0
t_a     !pet "part a", 0
t_b     !pet "part b", 0
t_title !pet 147, "reu request ($18) - a running program", 13, "asks main for a .reu by name", 13, 13, 0
t_ask   !pet "ask for ", 0
t_val   !pet 13, " status 02  value ", 0
t_size  !pet "  size (64k) ", 0
t_err   !pet " error ", 0
t_show  !pet 13, "showcase (net b3): ", 0
t_on    !pet "on", 13, 0
t_off   !pet "off", 13, 0
