; OCTOPHONIC OS 1 - the READY-prompt commands, in the tape room $F72C-$F92B (the core has no tape;
; LOAD, SAVE and OPEN on device 1 now give ?ILLEGAL DEVICE NUMBER instead of running into here).
; By Mong00se.
;   @            the current SD folder, paged like a disk directory
;   @NAME  @/NAME   into a folder (".." up, @/ back to the start folder), then its directory
;   /NAME        load and run it (.prg, .crt); a disk image goes into drive 8
;   @@           the browser (F1 at READY types it: wedge2.asm)
; The work is done by Main on the MiSTer; the 6502 talks to it through the mailbox at $D6F0.
; Every request gives up after 20 seconds (the border flickers while Main works) with
; ?NO REPLY FROM OCTOPHONIC MAIN (CMD nn). Each carries a number, so a late answer is never taken.
MB      = $D6F0
MB_CMD  = MB
MB_ST   = MB+1
MB_AL   = MB+2
MB_AH   = MB+3
MB_LL   = MB+4
MB_LH   = MB+5
MB_VAL  = MB+7
MB_NAME = MB+8
MB_NCLR = MB+9
MB_VER  = MB+$C
OCTST   = $02A7
PTR     = $FB
BUF     = $0200
CHROUT  = $FFD2
GETIN   = $FFE4
STOP    = $FFE1
DIRTXT  = $A000         ; Main writes the directory text into the RAM under BASIC
LASTCMD = $02A9         ; the last request, for the no-reply message
TIMEOUT = $02AA         ; the jiffy that request gives up at
SETKEY  = $FB97         ; wedge2.asm: F1 at READY, the no-reply message
NOREPLY = $FB9A
CALL2   = $FB9D
SHELLAT = $C000         ; where SHELL.PRG goes
AUTORUN = $02A8

        * = $F72C
osinit  lda #<wedge             ; BASIC's main loop comes through here (IMAIN)
        sta $0302
        lda #>wedge
        sta $0303
        jmp SETKEY

wedge   jsr SETKEY              ; F1 again after RUN/STOP+RESTORE (CINT put $028F back)
        jsr $A560               ; read the line, as BASIC does
        lda BUF
        cmp #$40                ; @
        beq ours
        cmp #$2F                ; /
        beq ours
back    ldx #$FF                ; not ours: on into BASIC, as if nothing happened
        ldy #$01
        jmp $A486

ours    jsr open
        bcc +
        ldx #msg_nobox-msgs
        jsr print
        jmp ready
+       ldx #1
        jsr skipsp
        lda BUF
        cmp #$2F
        beq dorun
        lda BUF+1
        cmp #$40                ; @@: the browser
        beq doshell
        lda BUF,x               ; @ alone: the directory
        beq dodir
        jsr name                ; (a leading / means from the start folder: Main does that)
        lda #$02                ; CHDIR
        jsr call
        beq dodir
        jmp error
dodir   lda #0
        sta MB_LL
        sta MB_LH
page    lda #<DIRTXT
        sta MB_AL
        sta PTR
        lda #>DIRTXT
        sta MB_AH
        sta PTR+1
        lda #20
        sta MB_VAL
        lda #$01                ; DIR: a page of text
        jsr call
        bne error
        ldy #0
-       lda $01                 ; the text is under the BASIC ROM: bank it out for one read
        pha
        and #$FE
        sta $01
        lda (PTR),y
        tax
        pla
        sta $01
        txa
        beq +
        jsr CHROUT
        inc PTR
        bne -
        inc PTR+1
        bne -
+       lda MB_VAL              ; more to come?
        beq ready
        ldx #msg_more-msgs
        jsr print
-       jsr GETIN
        beq -
        cmp #$03                ; RUN/STOP ends it
        beq ready
        lda #$0D
        jsr CHROUT
        jmp page                ; LEN already holds where the next page starts

doshell lda #$0F                ; SHELL: the browser into RAM
        jsr call
        bne error
        jmp SHELLAT

dorun   jsr name
        lda #$04                ; RUN
        jsr call
        bne error
        ldx #msg_load-msgs
        lda MB_VAL
        cmp #8
        bne +
        ldx #msg_disk-msgs
+       jsr print
ready   jsr close
        jmp $A474               ; READY.

error   cmp #$FE                ; no reply in 3 seconds
        bne +
        jmp NOREPLY
+       ldx #msg_err-msgs       ; A = the status
        cmp #$81
        bne +
        ldx #msg_nf-msgs
+       cmp #$82
        bne +
        ldx #msg_nd-msgs
+       cmp #$83
        bne +
        ldx #msg_big-msgs
+       cmp #$85
        bne +
        ldx #msg_cr-msgs
+       jsr print
        jmp ready

; the command in A: wait for Main (RUN/STOP gives up, 20 s at most); Z set when it's done
call    jmp CALL2               ; wedge2.asm: the sequence number, the wait, the border

; the name from BUF,x to the end of the line, without quotes
name    sta MB_NCLR
-       lda BUF,x
        beq +
        inx
        cmp #$22
        beq -
        sta MB_NAME
        bne -
+       rts

skipsp  lda BUF,x
        cmp #$20
        bne +
        inx
        bne skipsp
+       rts

; OctoVIC's page open, and the mailbox there? carry clear if so
open    lda #$4F
        sta $D03F
        lda #$38
        sta $D03F
        lda MB_VER
        cmp #$02
        bne +
        clc
        rts
+       jsr close
        sec
        rts
close   lda OCTST               ; the start screen keeps the page open
        bne +
        lda #$00
        sta $D03F
+       rts

print   lda msgs,x
        beq +
        jsr CHROUT
        inx
        bne print
+       rts

msgs
msg_nobox !pet 13, "?no os", 13, 0
msg_more  !pet 18, "more", 146, " (stop ends)", 0
msg_load  !pet 13, "loading", 13, 0
msg_disk  !pet 13, "in drive 8", 13, 0
msg_err   !pet 13, "?os error", 13, 0
msg_nf    !pet 13, "?not found", 13, 0
msg_nd    !pet 13, "?not a folder", 13, 0
msg_big   !pet 13, "?too big", 13, 0
msg_cr    !pet 13, "?can't run that", 13, 0
; SHIFT+RUN/STOP types LOAD"*",8 spelt out in full (an abbreviated keyword shows as a graphics
; character). X back as 1, so the KERNAL's own copy that follows puts its 'L' over our 'L' and stops
shiftr2 sei
        ldx #9
-       lda ldtxt,x
        sta $0277,x
        dex
        bpl -
        lda #10
        sta $C6
        lda #$01
        sta AUTORUN
        ldx #1
        rts
ldtxt   !byte $4C, $4F, $41, $44, $22, $2A, $22, $2C, $38, $0D   ; LOAD"*",8 RETURN
wedgeend
!if wedgeend > $F929 { !error "past the tape room" }
        * = $F929
        jmp shiftr2             ; SHIFTR2 (octo.asm's shiftrun): fixed
