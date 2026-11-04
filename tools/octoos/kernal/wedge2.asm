; OCTOPHONIC OS 1 - more of the READY-prompt commands, in the rest of the tape room $FB97-$FCD0
; (the tape's write and IRQ code; nothing else in the KERNAL calls in here). By Mong00se.
;   F1 at READY: the browser (types @@ on a clear screen, for the wedge to pick up); C=+F1 on a
;   MiSTer: @! (the MiSTer's own menu)
;   the no-reply message: ?NO REPLY FROM OCTOPHONIC MAIN (CMD nn)
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

; every key the KERNAL decodes comes through here (in the IRQ). F1, newly pressed, with the editor
; waiting at a direct-mode line: unshifted - clear the screen and type @@ RETURN (the browser); with
; C= on a MiSTer (Main sets NET b5) - clear the screen and type @! RETURN (the MiSTer's own menu)
keyhk   lda $CC                 ; the cursor flashing: the editor is waiting for a line
        bne out
        lda $9D                 ; direct mode, not a running program
        bpl out
        lda $CB                 ; the key: F1 is 4
        cmp #4
        bne out
        cmp $C5                 ; held down since last time: once only
        beq out
        ldx #3
        lda $028D               ; no SHIFT, C= or CTRL: the browser
        beq kf1
        cmp #2                  ; C= alone: the MiSTer's menu, only on a MiSTer
        bne out
        lda $D6FF
        and #$20
        beq out
        ldx #7
kf1     ldy #3
-       lda inject,x
        sta KEYD,y
        dex
        dey
        bpl -
        lda #4
        sta NDX
out     jmp $EB48               ; on to the KERNAL's own decoding
inject  !byte $93, $40, $40, $0D, $93, $40, $21, $0D

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
hex     cmp #10
        bcc +
        adc #6
+       adc #$30
        jmp CHROUT

nrmsg   !pet 13, "?no reply from octophonic main (cmd ", 0

; RUN after SHIFT+RUN/STOP's load, spelt out in full
runkeys lda #0
        sta AUTORUN
        ldx #3
-       lda runtxt,x
        sta KEYD,x
        dex
        bpl -
        lda #4
        sta NDX
        rts
runtxt  !byte $52, $55, $4E, $0D        ; RUN RETURN
wedge2end
!if wedge2end > $FCCE { !error "past the tape room" }
        * = $FCCE
        jmp runkeys             ; RUNKEYS (octo.asm's w_load): fixed
