; OCTOPHONIC OS 1 - more of the READY-prompt commands, in the rest of the tape room $FB97-$FCD0
; (the tape's write and IRQ code; nothing else in the KERNAL calls in here). By Mong00se.
;   F1 F3 F5 F7 F8 at READY: the browser, for what the key says (types @@ and a letter on a clear
;   screen, for the wedge to pick up); C=+F1 on a MiSTer: @! (the MiSTer's own menu)
;   the no-reply message: ?NO MAIN REPLY (CMD nn)
;   call2: a request to Main, numbered (SEQ), waited on for up to 20 seconds with the border
;   flickering so it never looks hung; only an answer with our own number counts
!src "wedge.lbl"
KEYLOG  = $028F
NDX     = $C6
KEYD    = $0277
AUTORUN = $02A8
SEQV    = $02AB             ; the number of our last request
BSAVE   = $02AC             ; the border colour, put back after the wait
SECS    = $02AD             ; seconds left
JIFS    = $02AE             ; jiffies left in this second
LASTJ   = $02AF
RUNTXT  = $E4E6             ; octo.asm: R U N RETURN (fixed; moved there in build 6 for the room)

        * = $FB97
        jmp setkey
        jmp noreply
        jmp call2

; the request in A, numbered; wait for Main. Z set when it is done; A = the status,
; $FE no answer in 20 s, $FF RUN/STOP
call2   inc SEQV
        ldx SEQV
        stx MB+$D               ; SEQ first, then the bell
        sta MB_CMD
        sta LASTCMD
        lda $D020
        sta BSAVE
        lda #20
        sta SECS
        lda #50
        sta JIFS
        lda $A2
        sta LASTJ
wait    jsr STOP
        beq gaveup
        lda MB_ST
        cmp #$01
        beq tick
        ldx MB+$E               ; the answer's number: ours?
        cpx SEQV
        beq fin
tick    lda $A2
        cmp LASTJ
        beq wait
        sta LASTJ
        and #3
        bne +
        inc $D020               ; Main is working: the border says so
+       dec JIFS
        bne wait
        lda #50
        sta JIFS
        dec SECS
        bne wait
        lda #$FE
        bne fin
gaveup  lda #$FF
fin     pha
        lda BSAVE
        sta $D020
        pla
        cmp #$02
        rts

setkey  php                     ; the keyboard's decode vector: through keyhk first
        sei                     ; (both bytes before the next IRQ uses it)
        lda #<keyhk
        sta KEYLOG
        lda #>keyhk
        sta KEYLOG+1
        plp
        rts

; every key the KERNAL decodes comes through here (in the IRQ). An F key, newly pressed, with the
; editor waiting at a direct-mode line: clear the screen and type @@, a letter, RETURN - the browser
; (SHELL.PRG) opens, and the letter (still at $0202 when it starts) says what for:
;   F7 "A" DUAL, F1 "B" BROWSE, F3 "C" LOAD, F5 "D" SIDS; with SHIFT: F8 "E" SET, F2 F4 F6 "F" "G" "H"
; C=+F1 on a MiSTer (Main sets NET b5) types @! instead: the MiSTer's own menu. (Build 6: all the
; bar's keys; up to build 5 only F1.)
keyhk   lda $CC                 ; the cursor flashing: the editor is waiting for a line
        bne out
        lda $9D                 ; direct mode, not a running program
        bpl out
        lda $CB                 ; the key: F7 3, F1 4, F3 5, F5 6
        cmp $C5                 ; held down since last time: once only
        beq out
        sec
        sbc #3
        cmp #4
        bcs out                 ; (not an F key; carry clear from here)
        ldy #$40                ; @@ and the letter
        ldx $028D               ; SHIFT 1, C= 2 (nothing else)
        beq kgo
        dex
        bne kcbm
        adc #4                  ; SHIFT: F8 F2 F4 F6
        bne kgo
kcbm    dex
        bne out
        cmp #1                  ; C=: F1 only, and only on a MiSTer
        bne out
        lda $D6FF
        and #$20
        beq out
        ldy #$21                ; @! - its menu (and a space), on any screen
        lda #$20
        bne kok
kgo     adc #$41
        cmp #$42                ; F1 always; the other keys only while the start screen (and its
        beq kok                 ; bar) is up - after a program, READY's F keys are a stock C64's
        ldx OCTST
        beq out
kok     sta KEYD+3
        sty KEYD+2
        lda #$40
        sta KEYD+1
        lda #$93
        sta KEYD
        lda #$0D
        sta KEYD+4
        lda #5
        sta NDX
out     jmp $EB48               ; on to the KERNAL's own decoding

noreply ldx #0
-       lda nrmsg,x
        beq +
        jsr CHROUT
        inx
        bne -
+       lda LASTCMD
        lsr
        lsr
        lsr
        lsr
        jsr hex
        lda LASTCMD
        and #$0F
        jsr hex
        lda #$29                ; )
        jsr CHROUT
        lda #$0D
        jsr CHROUT
        jmp ready
; (hex: in wedge.asm)

nrmsg   !pet 13, "?no main reply (cmd ", 0

; RUN after SHIFT+RUN/STOP's load, spelt out in full
runkeys lda #0
        sta AUTORUN
        ldx #3
-       lda RUNTXT,x
        sta KEYD,x
        dex
        bpl -
        lda #4
        sta NDX
        rts
wedge2end
!if wedge2end > $FCCE { !error "past the tape room" }
        * = $FCCE
        jmp runkeys             ; RUNKEYS (octo.asm's w_load): fixed
