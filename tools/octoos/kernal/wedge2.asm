; OCTOPHONIC OS 1 - more of the READY-prompt commands, in the rest of the tape room $FB97-$FCD0
; (the tape's write and IRQ code; nothing else in the KERNAL calls in here). By Mong00se.
;   F1 at READY: the browser (types @@ on a clear screen, for the wedge to pick up)
;   the no-reply message: ?NO REPLY FROM OCTOPHONIC MAIN (CMD nn)
!src "wedge.lbl"
KEYLOG  = $028F
NDX     = $C6
KEYD    = $0277

        * = $FB97
        jmp setkey
        jmp noreply

setkey  php                     ; the keyboard's decode vector: through keyhk first
        sei                     ; (both bytes before the next IRQ uses it)
        lda #<keyhk
        sta KEYLOG
        lda #>keyhk
        sta KEYLOG+1
        plp
        rts

; every key the KERNAL decodes comes through here (in the IRQ). F1, newly pressed, unshifted,
; with the editor waiting at a direct-mode line: clear the screen and type @@ RETURN
keyhk   lda $CC                 ; the cursor flashing: the editor is waiting for a line
        bne out
        lda $9D                 ; direct mode, not a running program
        bpl out
        lda $CB                 ; the key: F1 is 4
        cmp #4
        bne out
        cmp $C5                 ; held down since last time: once only
        beq out
        lda $028D               ; no SHIFT, C= or CTRL
        bne out
        ldx #3
-       lda inject,x
        sta KEYD,x
        dex
        bpl -
        lda #4
        sta NDX
out     jmp $EB48               ; on to the KERNAL's own decoding
inject  !byte $93, $40, $40, $0D

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
wedge2end
!if wedge2end > $FCD1 { !error "past the tape room" }
