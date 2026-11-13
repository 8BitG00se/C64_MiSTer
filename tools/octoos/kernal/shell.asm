; OCTOPHONIC OS 1 - the browser (SHELL.PRG). The F keys at READY load it to $C000 and run it: the
; ROM types @@ and a letter (wedge2.asm), still in the input buffer at $0202 when we start, and the
; letter says what for:
;   F1 "B" BROWSE  the drives (SD CARD / NETWORK), then run anything: its own titled page
;   F3 "C" LOAD    the disk in drive 8: LOAD"*",8,1 typed for you and RUN after it (build 4)
;   F5 "D" SIDS    a page of its own: SID CHIPS (preset, my chips, 6581/8580, 8 SIDS, FX)
;   F7 "A" DUAL    a page of its own: DUAL SCREEN (the split-screen setting)
;   F8 "E" SET     a page of its own: SETTINGS (everything)   (F2/F4/F6 as F1/F3/F5; @@ typed: as F1)
; By Mong00se.
;   cursor up/down (or joystick port 2)  move          RETURN (or fire)  run / into a folder
;   F5 / F6   page down / up                            M (or SHIFT+RETURN) a disk: just put it in
;                                                       (build 5: the bar on a disk says so below)
;   F3, DEL or left arrow (joystick left)  up a folder  F2                the start folder
;   F1        the drives (SD CARD / NETWORK)            F7 or RUN/STOP    back to READY
;   HOME      the top
;   F8        settings: chip preset, my chips, SID models, Octophonic, FX, split screens, turbo
;             (cursor up/down to pick, left/right to change, RETURN starts a chip preset)
; The 6502 is only the front end: the list, the folders and every load are Octophonic Main's,
; the same code the MiSTer menu uses (LIST, OPEN, CHDIR through the mailbox at $D6F0).
;
; BATCH 1 (build 9, (c) 2026 Mong00se):
;   Fix 76  F1 opens the DISKS page: the Disks folder of the start drive (F1 there: the drives). Row 23
;           always shows the keys - R/RETURN run, M mount, O source, N new - dimmed when they do nothing
;           for the entry under the bar: O only lights on a disk with source on it (Main marks it, b3 of
;           the record's type); O mounts the disk and opens its source in OCTOCODE (SRCOPEN, $19)
;   Fix 46  N: a new blank disk - type its name, Main makes NAME.d64 here and puts it in drive 8 ($1B)
;   Fix 38  F8: VIDEO OUT and SCALING (sharp pixels) - Main writes MiSTer.ini; the page scrolls now
;   Fix 54  F7: the DUAL SCREEN set-up page - your screens (VIDEO OUT), the split, what each means,
;           RETURN a test picture; the first time it asks you to pick (the 31 kHz split needs a core)
;   To do 77 the slogan, one line (s_slogan) on the settings pages' row 23 - easy to move
;   The browser's $C000-$CFFF was full: new code lives at $B000-$B7FF (RAM under BASIC's ROM), run
;   with BASIC switched out through a small stub each; SHELL.PRG loads at $B000 now.
!to "shell.prg", cbm

MB      = $D6F0
MB_CMD  = MB
MB_ST   = MB+1
MB_AL   = MB+2
MB_AH   = MB+3
MB_LL   = MB+4
MB_LH   = MB+5
MB_ARG  = MB+6
MB_VAL  = MB+7
MB_NAME = MB+8
MB_NCLR = MB+9
MB_RL   = MB+$A
MB_RH   = MB+$B
MB_VER  = MB+$C
MB_SEQ  = MB+$D
MB_RSEQ = MB+$E
MB_NET  = MB+$F         ; the network share: 0 none set up, 1 waiting for it, 2 there, 3 not there
SCR     = $0400
COL     = $D800
FRAME   = $F92F         ; the V1.1 start screen, without NEW (octo.asm)
READY   = $A474
GETIN   = $FFE4
STOP    = $FFE1
CHROUT  = $FFD2
AUTORUN = $02A8
STROUT  = $AB1E         ; BASIC: print the 0-terminated string at A/Y
seq     = $02AB         ; the request number, shared with the ROM's commands
ROWS    = 13
TOP     = 9             ; the first list row (5 the path, 7 the column names, 8 left blank)
LBUF    = $BA00         ; Main writes the path (40) and the records (40 each) here (to $BC30; the settings, 15 lines, to $BC58)
                        ; (batch 1: $BA00 - it was $B800 - so the far code has $B000-$B9FF)
                        ; (build 5: in the RAM under BASIC's ROM, read with BASIC switched out for the moment of
                        ; each read - recb, compact - so $C000-$CFFF is all the browser's code; it was $CDC0)
REC     = LBUF + 40
P       = $FB
Q       = $FD

;------------------------------------------------------------- (batch 1) $B000-$B9FF: far code
; In the RAM under BASIC's ROM, so run with BASIC switched out ($01 = $36) by its stub in the browser
; (FAR below). It may call the browser's routines that don't switch $01 (status, scr, recat, call,
; putrow...) but never recb, seltype or anything of BASIC's (STROUT): it reads LBUF directly.
        * = $B000
; the key strip (Fix 76) on row 23 for the entry under the bar; CURTYPE its type byte ($FF none)
fkeys_b ldx #5                  ; N: anywhere but the drives level
-       lda LBUF,x
        cmp drvtxt,x
        bne kn1
        dex
        bpl -
        lda #0
        beq kn2
kn1     lda #$10
kn2     sta lit
        lda #$FF
        sta curtype
        lda count
        beq kdraw
        lda sel
        jsr recat               ; rp: the record under the bar
        lda rp
        sta P
        lda rp+1
        sta P+1
        ldy #0
        lda (P),y
        sta curtype
        and #7
        cmp #2                  ; a disk: M, and O when it has source (b3)
        bne +
        lda #4
        ora lit
        sta lit
        lda curtype
        and #8
        beq +
        lda #8
        ora lit
        sta lit
+       lda #2                  ; R/RETURN: always, on an entry
        ora lit
        sta lit
kdraw   ldx #39
-       lda kstrip,x
        sta SCR + 23*40,x
        lda kseg,x
        beq ++
        and lit
        bne +
        lda #11                 ; dimmed: does nothing here
        bne +++
+       lda kkey,x              ; lit: the key yellow, its word grey
        bne +++
++      lda #15
+++     sta COL + 23*40,x
        dex
        bpl -
        ldx #0
        rts
drvtxt  !pet "drives"
lit     !byte 0
; the strip (40 columns), each column's key bit (0 none) and colour when lit
kstrip  !scr "r/return run  m mount  o source  n new  "
kseg    !byte 2,2,2,2,2,2,2,2,2,2,2,2, 0,0, 4,4,4,4,4,4,4, 0,0, 8,8,8,8,8,8,8,8, 0,0, $10,$10,$10,$10,$10, 0,0
kkey    !byte 7,15,7,7,7,7,7,7,15,15,15,15, 0,0, 7,15,15,15,15,15,15, 0,0, 7,15,15,15,15,15,15,15, 0,0, 7,15,15,15,15, 0,0

; N (Fix 46): the new disk's name typed on the status row, then NEWDISK. X 1: made (LEN its place
; in the list), 0: not (RUN/STOP, no name, or Main said no - its error is on the status row)
fnewd_b lda lit                 ; (not at the drives level: N is dimmed there)
        and #$10
        bne +
        tax
        rts
+       ldx #fm_newd-fmsgs
        jsr fstatus
        lda #0
        sta nlen
nd_draw ldy #0                  ; the name after the prompt, the cursor a reversed space
-       cpy nlen
        bcs +
        lda nbuf,y
        jsr scr
        sta SCR + 22*40 + 17,y
        iny
        bne -
+       lda #$A0
        sta SCR + 22*40 + 17,y
        lda #7
        sta COL + 22*40 + 17,y
        iny
        cpy #18
        bcs nd_key
        lda #$20
        sta SCR + 22*40 + 17,y
nd_key  jsr GETIN
        beq nd_key
        cmp #13
        beq nd_go
        cmp #3                  ; RUN/STOP: not now
        bne +
        ldx #fm_none-fmsgs
        jsr fstatus
        ldx #0
        rts
+       cmp #20                 ; DEL
        bne +
        lda nlen
        beq nd_key
        dec nlen
        jmp nd_draw
+       ldx nlen                ; letters, digits, space, - . ! ( ) +
        cpx #16
        bcs nd_key
        cmp #$20
        bcc nd_key
        cmp #$5B
        bcs nd_key
        cmp #$22                ; (no quotes, no commas, no colons, no wildcards)
        beq nd_key
        cmp #$2C
        beq nd_key
        cmp #$3A
        beq nd_key
        cmp #$2A
        beq nd_key
        cmp #$3F
        beq nd_key
        sta nbuf,x
        inc nlen
        jmp nd_draw
nd_go   lda nlen
        beq nd_key
        sta MB_NCLR
        ldx #0
-       lda nbuf,x
        sta MB_NAME
        inx
        cpx nlen
        bne -
        lda #$1B                ; NEWDISK
        jsr call
        beq +
        jsr err
        ldx #0
        rts
+       ldx #1
        rts
nlen    !byte 0
nbuf    !fill 16, 0

; the settings pages, after each drawing: F7's set-up help (and the first-time line), F8's "more",
; the slogan row
fset_b  lda view
        cmp #2
        bne fs_more
        ldx #0                  ; F7: what each choice means, rows 12-21 - names yellow, the rest grey
-       lda dhelp,x
        sta SCR + 12*40,x
        lda dhelp+200,x
        sta SCR + 12*40+200,x
        txa
        ldy #0
--      cmp #40
        bcc +
        sbc #40
        iny
        bne --
+       cmp #13
        lda #15
        bcs +
        lda #7
+       sta COL + 12*40,x
        sta COL + 12*40+200,x
        inx
        cpx #200
        bne -
        lda LBUF + 20           ; VIDEO OUT still "NOT SET": the first time - say so
        cmp #$4E
        bne fs_slog
        ldx #fm_first-fmsgs
        jsr fstatus
        jmp fs_slog
fs_more ldx #39                 ; F8: more lines than rows - which way
        lda #$20
-       sta SCR + 8*40,x
        dex
        bpl -
        lda count
        cmp #ROWS+1
        bcc fs_slog
        ldy #0
        lda stop
        bne +
        ldx #fm_below-fmsgs
        bne fsm
+       ldx #fm_above-fmsgs
fsm     lda fmsgs,x
        beq fs_slog
        sta SCR + 8*40 + 16,y
        lda #12
        sta COL + 8*40 + 16,y
        inx
        iny
        bne fsm
fs_slog ldx #39                 ; row 23: the slogan (To do 77) and the credit, mid grey
-       lda s_slogan,x
        sta SCR + 23*40,x
        lda #12                 ; (mid grey: readable, not loud)
        sta COL + 23*40,x
        dex
        bpl -
        ldx #0
        rts

; RETURN on VIDEO OUT (Fix 54): a test picture on the VIC - with the split off every screen shows it.
; Any key: back
ftest_b ldx #0
-       lda #$20
        sta SCR,x
        sta SCR+250,x
        sta SCR+500,x
        sta SCR+750,x
        lda #1
        sta COL,x
        sta COL+250,x
        sta COL+500,x
        sta COL+750,x
        inx
        cpx #250
        bne -
        ldx #39                 ; the bars: rows 4-13 eight colours (5 columns each), rows 14-15 five greys
-       txa
        ldy #0
--      cmp #5
        bcc +
        sbc #5
        iny
        bne --
+       lda tbars,y
        sta tmp
        txa
        ldy #0
--      cmp #8
        bcc +
        sbc #8
        iny
        bne --
+       lda tgrey,y
        sta tmp+1
        lda #$A0
        sta SCR + 4*40,x
        sta SCR + 5*40,x
        sta SCR + 6*40,x
        sta SCR + 7*40,x
        sta SCR + 8*40,x
        sta SCR + 9*40,x
        sta SCR + 10*40,x
        sta SCR + 11*40,x
        sta SCR + 12*40,x
        sta SCR + 13*40,x
        sta SCR + 14*40,x
        sta SCR + 15*40,x
        lda tmp
        sta COL + 4*40,x
        sta COL + 5*40,x
        sta COL + 6*40,x
        sta COL + 7*40,x
        sta COL + 8*40,x
        sta COL + 9*40,x
        sta COL + 10*40,x
        sta COL + 11*40,x
        sta COL + 12*40,x
        sta COL + 13*40,x
        lda tmp+1
        sta COL + 14*40,x
        sta COL + 15*40,x
        dex
        bpl -
        ldx #0                  ; the words
-       lda ttext,x
        sta SCR + 1*40,x
        lda ttext+80,x
        sta SCR + 17*40,x
        lda ttext+160,x
        sta SCR + 19*40,x
        lda ttext+240,x
        sta SCR + 21*40,x
        lda #7
        sta COL + 17*40,x
        sta COL + 18*40,x
        inx
        cpx #80
        bne -
        lda #0
        sta $C6
-       jsr GETIN
        beq -
        ldx #0
        rts
tbars   !byte 1, 7, 3, 5, 4, 2, 6, 0
tgrey   !byte 0, 11, 12, 15, 1
ttext   !scr "      octophonic 64 - screen test       "
        !scr "                                        "
        !scr "you should see this on every screen you "
        !scr "have plugged in.                        "
        !scr "split screens on: this is the c64 side  "
        !scr "(vga/crt); hdmi shows octovic.          "
        !scr "any key: back to the set-up page        "
        !scr "(c) 2026 mong00se                       "

; (moved here from the browser for room) REU ATTACHED (nnM), or (nnnK) under 1 MB
reumsg_b
        ldx #m_reu-msgs
        jsr status
        ldy #14
        lda reuu+1              ; 256 units and up: 16M and more
        bne rmbig
        lda reuu
        cmp #16
        bcs rmmeg
        asl                     ; under 1 MB: units x 64 = K (64..960)
        asl
        asl
        asl
        asl
        asl
        sta tmp                 ; low byte of units x 64
        lda reuu
        lsr
        lsr
        sta tmp+1               ; high byte
        jsr dec16
        lda #$0B                ; K
        bne rmend
rmbig   lda #16                 ; 256 units: 16M (the largest REU there is)
        sta tmp
        lda #0
        sta tmp+1
        jsr dec16
        lda #$0D
        bne rmend
rmmeg   lsr                     ; 1-15 MB: units / 16
        lsr
        lsr
        lsr
        sta tmp
        lda #0
        sta tmp+1
        jsr dec16
        lda #$0D                ; M
rmend   sta SCR + 22*40,y
        iny
        lda #$29                ; )
        sta SCR + 22*40,y
        lda #0
        sta reumb
        ldx #0
        rts

; tmp/tmp+1 (0-999) in decimal at SCR + 22*40 + Y, no leading zeros; Y moves on
dec16   ldx #0
        stx dflag
        ldx #2
-       lda #$30
        sta dch
--      lda tmp
        sec
        sbc dlo,x
        pha
        lda tmp+1
        sbc dhi,x
        bcc +
        sta tmp+1
        pla
        sta tmp
        inc dch
        bne --
+       pla
        lda dch
        cpx #0
        beq ++
        cmp #$30
        bne ++
        bit dflag
        bpl +++
++      sta SCR + 22*40,y
        iny
        lda #$80
        sta dflag
+++     dex
        bpl -
        rts
dlo     !byte 1, 10, 100
dhi     !byte 0, 0, 0
dch     !byte 0
dflag   !byte 0

; (moved here for room) the core's name ($D6B8-$D6BF) and build date ($D6B4-$D6B6, BCD) on the
; settings title row: "core mem3     01.11.26" - from OctoVIC itself, so it is always the core really running
corenm_b
        ldx #4
-       lda t_core,x
        sta SCR + 5*40 + 18,x
        dex
        bpl -
        ldx #7
-       lda $D6B8,x
        and #$3F                ; ASCII to screen codes
        sta SCR + 5*40 + 23,x
        dex
        bpl -
        ldx #2                  ; day, month, year at 32, 35, 38
        ldy #6
-       lda $D6B4,x
        pha
        lsr
        lsr
        lsr
        lsr
        ora #$30
        sta SCR + 5*40 + 32,y
        pla
        and #$0F
        ora #$30
        sta SCR + 5*40 + 33,y
        cpx #0
        beq +
        lda #$2E
        sta SCR + 5*40 + 31,y
+       tya
        sec
        sbc #3
        tay
        dex
        bpl -
        ldx #0
        rts
t_core  !scr "core "

; (batch 1) moved to the far code - and not called since F1 stopped waiting for the share (build 4);
; kept for when it is wanted again (call it through a +far stub)
; the share is set up but still connecting (Main is waiting to open it): PLEASE WAIT, until it is
; there (Main has the folder on it by then), a key is pressed, or 60 seconds - then the SD card
netwait lda MB_NET
        and #3
        cmp #1
        bne nwdone
        ldx #m_wait-msgs
        jsr status
        lda #60
        sta secs
        lda #50
        sta jifs
        lda $A2
        sta lastj
nwloop  jsr netlite
        lda MB_NET
        and #3
        cmp #1
        bne nwdone              ; there (or Main stopped waiting)
        jsr GETIN
        bne nwsd                ; a key: the SD card now
        lda $A2
        cmp lastj
        beq nwloop
        sta lastj
        dec jifs
        bne nwloop
        lda #50
        sta jifs
        dec secs
        bne nwloop
        lda #1                  ; 60 seconds: the SD card, and say so
        sta nonet
nwsd    lda #$0B                ; NOSHARE: Main stops waiting, the SD card's folder
        jsr call
nwdone  ldx #0
        rts

; a far message (X in fmsgs) on the status line, yellow - as status does with msgs
fmsg_b
fstatus ldy #0
-       lda fmsgs,x
        beq +
        sta SCR + 22*40,y
        lda #7
        sta COL + 22*40,y
        inx
        iny
        bne -
+       lda #$20
-       cpy #40
        bcs +
        sta SCR + 22*40,y
        iny
        bne -
+       ldx #0
        rts
fmsgs
fm_none   !scr 0
fm_newd   !scr "new disk - name: ", 0
fm_there  !scr "?a disk of that name is there already", 0
fm_newok  !scr "new disk made - it is in drive 8 now", 0
fm_osrc   !scr "opening its source in octocode...", 0
fm_rs     !scr "saved - switch the mister off and on", 0
fm_first  !scr "first time: pick your screens <- ->", 0
fm_below  !scr "more below - cursor down", 0
fm_above  !scr "more above - cursor up", 0
!if * - fmsgs > 255 { !error "the far messages are over 255 bytes" }
; F7's help, rows 12-21 (40 columns each)
dhelp   !scr "hdmi only    one screen - no split      "
        !scr "hdmi+vga 31k a pc monitor on vga. its   "
        !scr "             c64 side needs a new core  "
        !scr "hdmi+crt 15k a crt on vga/bnc, and hdmi "
        !scr "crt only 15k one crt - no split         "
        !scr "                                        "
        !scr "split        c64 on the crt, octovic on "
        !scr "             hdmi (hdmi+crt 15k only)   "
        !scr "return       a test picture             "
        !scr "saved to mister.ini: switch off and on  "
; To do 77: the slogan - ONE line, here; to move it, move this string and its fset_b lines
s_slogan !scr "the future is the past  (c)2026 mong00se"
!if * > LBUF { !error "the far code runs into LBUF" }
        !fill $BE00 - *, 0      ; LBUF (batch 1: $BA00-$BDFF), Main's list (zeros in the file)

; ------------------------------------------------------------- (build 5) $BE00-$BFFF: the jingle
; In the RAM under BASIC's ROM: SHELL.PRG starts here now (its $C000-$CFFF is all the browser's).
        * = $BE00
; ------------------------------------------------------------------------- the start jingle
; Called by the ROM at a cold start, once the screen is up (Main loads SHELL.PRG for it). About 2 s:
; C major pentatonic up an octave and back down (C D E G A C, A G E D C), a third above it in the key
; on the next SID each time, a soft C-G pad under it (SID 1 and 2, voice 1), ending on the C chord.
; The scale moves over voice 3 of the 8 SIDs (melody left 1 3 5 7, its third right 2 4 6 8), so the
; start screen's eq shows it. Every note has sustain 0: it dies away by itself whatever happens.
; The player runs from the IRQ and lives in the tape buffer ($033C, unused on the core), where no
; program loads: it stops at once (leaving the SIDs alone) when RUN, SYS or LOAD shut the start screen
; (OCTST 0) or the IRQ vector is no longer its own.
OCTSTA  = $02A7
JP      = $033C
JVOL    = 15            ; the SIDs' volume (build 5: 11, -15.2 dBFS; build 6: 15 and every note
                        ; on two voices in phase - about -6 dBFS, the eq and the tune as before)
jingle  sei
        ldx #0
-       lda jsrc,x
        sta JP,x
        inx
        cpx #jend-jsrc
        bne -
        ldx #7
-       lda jlo,x               ; each SID: voice 3 triangle, soft attack, decay 750 ms
        sta jp1+1
        lda jhi,x
        sta jp1+2
        ldy #$13
        lda #$39
        jsr jp1
        ldy #$0C                ; voice 2 the same: it doubles voice 3 (build 6: louder, in phase)
        jsr jp1
        iny
        lda #$09                ; sustain 0, release 9 = the decay (the end lets go of the gates)
        jsr jp1
        ldy #$14
        jsr jp1
        ldy #$12
        lda #$10
        jsr jp1
        ldy #$0B
        jsr jp1
        dex
        bpl -
        sei
        ldx #5                  ; the pad: SID 1-6 voice 1 (1 3 5 C3, 2 4 6 G3: three of each, in
                                ; phase - build 6, louder), slow attack, long decay
-       lda jlo,x
        sta jp1+1
        lda jhi,x
        sta jp1+2
        ldy #0
        lda padlo,x
        jsr jp1
        iny
        lda padhi,x
        jsr jp1
        ldy #5
        lda #$9B
        jsr jp1
        iny
        lda #$0B                ; sustain 0, release B = the decay
        jsr jp1
        ldy #4
        lda #$08                ; TEST: the two copies' oscillators start together
        jsr jp1
        lda #$11
        jsr jp1
        dex
        bpl -
        lda #<JP
        sta $0314
        lda #>JP
        sta $0315
        cli
; build 8: the volume ramp moved here, after the first notes are set going - it was before them, and
; on its own the SIDs' DC step at each volume step was half a second of low thump before the tune.
; Now it is the tune's 0.3 s fade-in and the steps are under the notes.
        lda #1                  ; then the volume up a step a frame (a 6581 clicks at a jump in volume,
                                ; and at a waveform chosen at full volume: chosen above, at 0)
        sta jvol
--      ldx #7
---     lda jlo,x
        sta jp1+1
        lda jhi,x
        sta jp1+2
        ldy #$18
        lda jvol
        jsr jp1
        ldy #0                  ; (the SIDs a step each 1.3 ms apart: eight small steps, not one)
-       dey
        bne -
        dex
        bpl ---
        lda $A2
-       cmp $A2
        beq -
        inc jvol
        lda jvol
        cmp #JVOL+1
        bne --
        rts
jp1     sta $FFFF,y
        rts
jvol    !byte 0
jlo     !byte $00, $20, $00, $20, $80, $A0, $80, $A0
jhi     !byte $D4, $D4, $D5, $D5, $D4, $D4, $D5, $D5
padlo   !byte <2227, <3338, <2227, <3338, <2227, <3338
padhi   !byte >2227, >3338, >2227, >3338, >2227, >3338

jsrc
!pseudopc JP {
jirq    lda OCTSTA              ; the start screen shut (a program): stop, the SIDs left alone
        beq jout
        dec jwait
        bne jx
        lda #7                  ; a step every 7 frames (0.14 s)
        sta jwait
        ldy jpos
        lda jtab,y              ; a step: its third (high nibble) and the melody's note (low)
        cmp #$FF                ; the end: every gate off - so a POKE that gates a voice at READY
        beq jfin                ; sounds (build 6; the release rates are the decay rates, so the
                                ; last notes and the pad still die away as before)
        inc jpos
        pha
        and #$0F
        ldx jsid
        jsr jnote
        pla
        lsr
        lsr
        lsr
        lsr
        inx
        jsr jnote
        inx
        txa
        and #7
        sta jsid
jx      jmp $EA31
jfin    ldx #7                  ; voices 1-3 of the 8 SIDs: triangle, gate off
-       jsr jaddr
        lda #$10
        ldy #$04
        jsr jw
        ldy #$0B
        jsr jw
        ldy #$12
        jsr jw
        dex
        bpl -
jout    lda $0315               ; the IRQ back to the KERNAL - only if it is still ours
        cmp #>JP
        bne jx
        lda $0314
        cmp #<JP
        bne jx
        lda #$31
        sta $0314
        lda #$EA
        sta $0315
        bne jx
jnote   pha                     ; note A (jfreq) on voices 3 and 2 of SID X: the frequency, both
        jsr jaddr               ; oscillators reset together (TEST) so they stay in phase - twice
        pla                     ; the level with no beating - then a new gate.
        asl
        tay
        lda jfreq,y
        pha
        lda jfreq+1,y
        ldy #$0F
        jsr jw
        ldy #$08
        jsr jw
        pla
        ldy #$0E
        jsr jw
        ldy #$07
        jsr jw
        lda #$18                ; TEST + triangle, gate off
        ldy #$12
        jsr jw
        ldy #$0B
        jsr jw
        lda #$11                ; triangle, gate on
        jsr jw
        ldy #$12
jw      sta $FFFF,y
        rts
jaddr   txa                     ; jw at SID X: $D400 + (X&1)*$20 + (X&4)*$20 + (X&2)*$80
        and #5
        asl
        asl
        asl
        asl
        asl
        sta jw+1
        txa
        lsr
        and #1
        ora #$D4
        sta jw+2
        rts
jwait   !byte 1
jpos    !byte 0
jsid    !byte 0
}
jend
!if jend - jsrc > 192 { !error "the jingle's player is bigger than the tape buffer" }
!if jend > $C000 { !error "the jingle is too big for $BE00-$BFFF" }
        !fill $C000 - *, 0

        * = $C000
        jmp start               ; $C000: the browser (the ROM's @@, F1)
        jmp jstub               ; $C003: the start jingle (the ROM's cold start)
start   lda $0202               ; the letter after @@: what the browser is opened for (0: @@ alone)
        sta mode
        jsr jstop               ; the jingle, if still playing, stopped (its player is in the tape buffer)
        lda #0
        sta $C6                 ; the F1 that brought us here, and anything else typed
        sta first
        sta first+1
        sta sel
        sta joyold
        lda #$4F                ; OctoVIC's page: the mailbox is in it
        sta $D03F
        lda #$38
        sta $D03F
        lda MB_VER
        cmp #$02
        beq +
        jmp READY
+       jsr FRAME               ; the start screen's top box (the eq, the title, the network light)
        jsr fixed
        jsr netlite
        lda mode                ; what for: F1 the drives, F3 the last folder, F5/F7/F8 the settings
        beq mbrowse
        sec
        sbc #$41
        cmp #4
        beq mset                ; "E" F8
        and #3
        beq mdual               ; "A" F7
        cmp #2
        beq mload               ; "C" F3
        bcs msids               ; "D" F5
mbrowse jmp disks               ; "B" F1: the Disks page (batch 1, Fix 76)
mdual   lda #2                  ; its own page: DUAL SCREEN
        !byte $2C
msids   lda #1                  ; its own page: SID CHIPS
        !byte $2C
mset    lda #0                  ; SETTINGS, everything
        sta view
        lda #1                  ; F7 there goes back to READY, not to the files
        sta setonly
        jmp settings
mload   jmp f3load              ; (build 4) F3: the disk in drive 8, not the browser
reload  lda #$FF                 ; (build 5) the key strip under the list: drawn again for the bar
        sta hsel
        jsr dolist
        jsr drawall
        jsr hilite
        lda reumb               ; a .reu just attached: say so once the list is up
        beq +
        jsr reumsg
+       lda newmb               ; (batch 1) a new disk just made: say so
        beq +
        lda #0
        sta newmb
        ldx #fm_newok-fmsgs
        jsr fmsg
+       lda nonet               ; "no network" from the wait: say so once the list is up
        beq loop
        lda #0
        sta nonet
        ldx #m_nonet-msgs
        jsr status
loop    jsr netlite             ; when the share comes or goes, list again
        bcs reload
        jsr hint                ; (batch 1) the key strip on row 23 for the entry under the bar
        jsr cpage               ; on a MiSTer: C= held shows the help's second page
        jsr getkey
        beq loop
        cmp #17
        bne +
        jsr down
        jmp loop
+       cmp #145
        bne +
        jsr up
        jmp loop
+       cmp #133                ; F1: the drives
        bne +
        jmp drives
+       cmp #139                ; F6: page up
        bne +
        jmp pageup
+       cmp #135                ; F5
        bne +
        jmp pagedn
+       cmp #134                ; F3
        beq upf
        cmp #20                 ; DEL
        beq upf
        cmp #95                 ; left arrow
        beq upf
        cmp #157                ; cursor left (joystick left)
        bne +
upf     jmp upfold
+       cmp #140                ; F8: settings
        bne +
        jmp settings
+
        cmp #137                ; F2 - or C=+F1 (the C= key's table makes F1 137 too): on a MiSTer
        bne +                   ; the MiSTer's own menu
        lda $028D
        and #2
        beq gostf
        lda MB_NET
        and #$20
        beq gostf
        lda #$12                ; MENU: Main loads the MiSTer's menu core
        jsr call
        jmp loop
gostf   jmp startf
+
        cmp #19                 ; HOME
        beq home
        cmp #13
        bne +
        lda #0
        jmp open
+       cmp #141                ; SHIFT+RETURN
        bne +
        lda #1
        jmp open
+       cmp #$4D                ; (build 5) M: a disk into drive 8, not run
        bne +
        jsr seltype
        cmp #2
        bne +                   ; (not a disk: nothing)
        lda #1
        jmp open
+       cmp #$52                ; (batch 1) R: as RETURN
        bne +
        lda #0
        jmp open
+       cmp #$4F                ; (batch 1) O: the disk's source in OCTOCODE
        bne +
        jmp osrc
+       cmp #$4E                ; (batch 1) N: a new blank disk here
        bne +
        jmp newd
+       cmp #136                ; F7
        beq quit
        cmp #3                  ; RUN/STOP
        beq quit
        jmp loop

quit    jsr FRAME
        jmp READY

home    lda #0
        sta first
        sta first+1
        sta sel
        lda #1                  ; a fresh folder: the bar on its first entry, not on ".."
        sta skipup
        jmp reload

drives  lda #'*'                 ; the drives (SD CARD / NETWORK): CHDIR "*"
        sta MB_NCLR
        sta MB_NAME
        bne chdir
upfold  lda #'.'
        sta MB_NCLR
        sta MB_NAME
        sta MB_NAME
        jmp chdir
startf  lda #'/'
        sta MB_NCLR
        sta MB_NAME
chdir   lda #$02
        jsr call
        bne +
        jmp home
+       jsr err
        jmp loop

pagedn  clc                     ; first + ROWS < total?
        lda first
        adc #ROWS
        tax
        lda first+1
        adc #0
        tay
        cmp total+1
        bcc +
        bne nopage
        cpx total
        bcs nopage
+       stx first
        sty first+1
        lda #0
        sta sel
        jmp reload
nopage  jmp loop

pageup  lda first
        ora first+1
        beq nopage
        jsr back
        lda #0
        sta sel
        jmp reload

; first back by a page, not below 0
back    sec
        lda first
        sbc #ROWS
        sta first
        lda first+1
        sbc #0
        sta first+1
        bcs +
        lda #0
        sta first
        sta first+1
+       rts

down    ldx sel
        inx
        cpx count
        bcs +
        jsr hilite
        inc sel
        jmp hilite
+       pla                     ; the bottom of the page: the next page
        pla
        jmp pagedn

up      lda sel
        beq +
        jsr hilite
        dec sel
        jmp hilite
+       lda first
        ora first+1
        bne +
        rts
+       pla
        pla
        jsr back
        lda #ROWS-1
        sta sel
        jmp reload

; RETURN: entry first+sel - into a folder, a disk into drive 8 (and loaded, unless A=1), a
; program or a cartridge run by Main (the core resets)
open    sta mountonly
        clc
        lda first
        adc sel
        sta MB_LL
        lda first+1
        adc #0
        sta MB_LH
        lda #$07
        jsr call
        beq +
        jsr err
        jmp loop
+       lda MB_VAL
        cmp #$10
        bne +
        jmp home                ; a folder: its list
+       cmp #8
        beq disk
        cmp #2
        bne +
        jmp reuin               ; a .reu on its own: attached, still in the browser
+       ldx #m_load-msgs        ; a program or a cartridge: Main loads it and the C64 restarts
        jsr status
-       jsr STOP
        bne -
        jmp quit

f3load  lda #0                  ; F3 LOAD: LOAD"*",8,1 and RUN, a title first
        sta mountonly
        jsr FRAME
        jsr d8ask               ; (build 5) which disk: its name in the title, or "empty"
        bne f3old               ; (an older Main doesn't know DRIVE8: as before)
        lda d8len
        beq f3none
        lda #<m_f3n
        ldy #>m_f3n
        jsr STROUT
        lda #<d8buf
        ldy #>d8buf
        jsr STROUT
        lda #13
        jsr CHROUT
        jmp dtype
f3none  lda #<m_f3e             ; nothing in drive 8: say how to put one in, no LOAD
        ldy #>m_f3e
        jsr STROUT
        jmp READY
f3old   lda #<m_f3n             ; (no name to show)
        ldy #>m_f3n
        jsr STROUT
        lda #13
        jsr CHROUT
        jmp dtype
disk    jsr FRAME
        lda mountonly
        beq +
        lda #<m_mnt             ; (build 5) M: DISK IN DRIVE 8: NAME, and how to run it
        ldy #>m_mnt
        jsr STROUT
        jsr d8ask
        bne ++
        lda #<d8buf
        ldy #>d8buf
        jsr STROUT
++      lda #<m_mnt2
        ldy #>m_mnt2
        jsr STROUT
        jmp READY
+       ldx #0
dmsg    lda m_disk,x
        beq dtype
        jsr CHROUT
        inx
        bne dmsg
dtype   lda mountonly
        bne +
        ldx #0                  ; LOAD"*",8,1 typed on the screen (too long for the keyboard buffer),
-       lda autold,x            ; then RETURN on it, and RUN after the load (AUTORUN, as SHIFT+RUN/STOP)
        beq ++
        jsr CHROUT
        inx
        bne -
++      lda #$0D                ; a new line, then the keys: cursor up onto it, RETURN
        jsr CHROUT
        sta $0278
        lda #$91
        sta $0277
        lda #2
        sta $C6
        lda #1
        sta AUTORUN
        jmp $A480               ; BASIC's main loop, without READY. (the line is read at once)
+       jmp READY

; LIST: a page of the folder into LBUF
dolist  lda #<LBUF
        sta MB_AL
        lda #>LBUF
        sta MB_AH
        lda first
        sta MB_LL
        lda first+1
        sta MB_LH
        lda #ROWS
        sta MB_VAL
        lda #$06
        jsr call
        beq +
        pha
        lda #0
        sta count
        sta total
        sta total+1
        pla
        jmp err
+       lda MB_VAL
        sta count
        lda MB_RL
        sta total
        lda MB_RH
        sta total+1
        lda count               ; the folder got shorter: back to its top
        bne +
        lda first
        ora first+1
        beq +
        lda #0
        sta first
        sta first+1
        jmp dolist
+       lda skipup
        beq +
        lda #0
        sta skipup
        lda #0                  ; ".." first and more after it: start below it
        jsr recat
        ldx #0
        jsr recb
        cmp #5
        bne +
        lda count
        cmp #2
        bcc +
        lda #1
        sta sel
+       lda sel                 ; the bar stays on the list
        cmp count
        bcc +
        ldx count
        dex
        stx sel
        bpl +
        lda #0
        sta sel
+       ldx #m_none-msgs
        jmp status

; the request in A, numbered (SEQ); wait for Main. Folders, loads and presets (LIST, CHDIR,
; OPEN, SETAPPLY) may take a while on a network share: 20 seconds, with SCANNING... or
; LOADING... on the status line and the border flickering. The rest: 3 seconds. Only an answer
; carrying our own number counts. Z set when it is done; A = the status ($FE: no answer)
call    sta lastcmd
        ldy #3
        sty secs
        cmp #$06
        beq long
        cmp #$02
        beq long
        cmp #$07
        beq longl
        cmp #$0A
        bne +
longl   lda #0                  ; (OPEN takes no VALUE: from Main, VALUE 3 means a .reu is going in)
        sta MB_VAL
        lda #$FF
        sta rbdone              ; (the bar is drawn the first time Main says how far it is)
        sta rbdone+1
        ldx #m_load-msgs    ; (a 16 MB .reu over the network can take a while)
        ldy #60
        bne long3
long    ldx #m_scan-msgs
        ldy #20
long3   sty secs
        jsr status              ; (status uses Y: secs is set first)
+        lda #50
        sta jifs
        lda $D020
        sta bsave
        inc seq
        lda seq
        sta MB_SEQ
        lda lastcmd
        sta MB_CMD
        lda $A2
        sta lastj
-       lda MB_ST
        cmp #$01
        beq tick
        ldx MB_RSEQ             ; the answer's number: ours?
        cpx seq
        beq fin
tick    lda MB_VAL              ; still busy, VALUE 3: Main is putting a .reu in the REU - the bar
        cmp #3
        bne +
        jsr reubar
+       jsr bars                ; (build 4) gentle raster bars in the border while we wait
        lda $A2
        cmp lastj
        beq -
        sta lastj
        lsr                     ; the bars slide down the border: one step every two jiffies
        sta phase
        dec jifs
        bne -
        lda #50
        sta jifs
        dec secs
        bne -
        lda #$FE
fin     pha
        lda bsave
        sta $D020
        pla
        cmp #$02
        rts

; the waiting border (build 4; it used to flash): soft dark-blue raster bars, the border colour
; chosen by the raster line (8 lines a step) and slid down the screen by PHASE. Neighbouring
; colours are close, so the ragged edge of a poll loop can't be seen.
bars    lda $D012
        lsr
        lsr
        lsr
        clc
        adc phase
        and #$1F
        tax
        lda bartab,x
        sta $D020
        rts
bartab  !byte 0,0,0,6,6,6,14,14,6,6,6,0,0,0,0,0
        !byte 0,11,11,11,12,12,11,11,11,0,0,0,0,0,0,0
phase   !byte 0

; an error (A) on the status line
err     cmp #$FE
        bne +
        ldx #m_noreply-msgs
        jsr status
        lda lastcmd             ; the request's number in the brackets
        lsr
        lsr
        lsr
        lsr
        jsr hexd
        sta SCR + 22*40 + 36
        lda lastcmd
        and #$0F
        jsr hexd
        sta SCR + 22*40 + 37
        lda #$29
        sta SCR + 22*40 + 38
        rts
+       ldx #m_err-msgs
        cmp #$81
        bne +
        ldx #m_nf-msgs
+       cmp #$82
        bne +
        ldx #m_nd-msgs
+       cmp #$85
        bne +
        ldx #m_cant-msgs
+       cmp #$86
        bne +
        ldx #m_nonc-msgs
+       cmp #$87                ; (batch 1) NEWDISK: that name is there already
        bne +
        ldx #fm_there-fmsgs
        jmp fmsg
+       jmp status
hexd    cmp #10                 ; a hex digit as a screen code
        bcc +
        sbc #9
        rts
+       ora #$30
        rts

; OPEN of a .reu, or of a demo that has one: Octophonic Main puts it in the REU itself, with no
; MiSTer OSD bar, and while it does (STATUS still 1) keeps VALUE 3, RESULT the 64 KB blocks in so
; far and LEN the blocks in all up to date. The bar goes on the status line in the start screen's
; colours, and while it moves the wait starts again (60 s from the last block).
reubar  lda lastcmd
        cmp #$07
        bne rbx
        lda MB_RL
        cmp rbdone
        bne +
        lda MB_RH
        cmp rbdone+1
        beq rbx                 ; no further on: nothing to draw
+       lda MB_RL
        sta rbdone
        sta rbn
        lda MB_RH
        sta rbdone+1
        sta rbn+1
        lda #60
        sta secs
        ldx #5                  ; the cells: done*32/all (done <= all <= 256 blocks, 16 MB)
-       asl rbn
        rol rbn+1
        dex
        bne -
        stx rbq                 ; (X is 0)
rbdiv   lda rbq
        cmp #32
        bcs rbdraw
        lda rbn
        sec
        sbc MB_LL
        tax
        lda rbn+1
        sbc MB_LH
        bcc rbdraw
        sta rbn+1
        stx rbn
        inc rbq
        bne rbdiv
rbdraw  ldx #m_rin-msgs
        jsr status              ; "reu" on the status line, yellow, and the rest of it blank
        ldy #0
-       lda #$A0                ; a solid cell
        sta SCR + 22*40 + 6,y
        lda #14                 ; still to come: light blue
        cpy rbq
        bcs +
        lda #1                  ; in: white
+       sta COL + 22*40 + 6,y
        iny
        cpy #32
        bne -
rbx     rts
rbdone  !word $FFFF
rbn     !word 0
rbq     !byte 0

; the message at msgs+X on the status line (row 23), in yellow
status  ldy #0
-       lda msgs,x
        beq +
        sta SCR + 22*40,y
        lda #7
        sta COL + 22*40,y
        inx
        iny
        bne -
+       lda #$20
-       cpy #40
        bcs +
        sta SCR + 22*40,y
        iny
        bne -
+       rts

; the header line and the key help
fixed   lda #0                  ; (the help's first page)
        sta hpage
        ldx #39
-       lda hdr,x
        sta SCR + 7*40,x
        lda #15
        sta COL + 7*40,x
        lda help,x
        sta SCR + 24*40,x
        lda #15
        sta COL + 24*40,x
        dex
        bpl -
        rts

; the path and the page
drawall ldx #s_browse-strs      ; (build 4) the page's own title, F1
        lda #6
        jsr putrow
        lda #<LBUF
        sta recb+5
        lda #>LBUF
        sta recb+6
        ldx #39
-       jsr recb
        jsr scr
        sta SCR + 5*40,x
        lda #3
        sta COL + 5*40,x
        dex
        bpl -
        lda #0
        sta row
-       lda row
        jsr rowptr
        lda row
        cmp count
        bcs blank
        jsr drawrec
        jmp +
blank   ldy #39
        lda #$20
--      sta (Q),y
        dey
        bpl --
+       inc row
        lda row
        cmp #ROWS
        bne -
        rts

; Q = the screen at list row A, P = its colour
rowptr  clc
        adc #TOP
        tax
        lda rowlo,x
        sta Q
        sta P
        lda rowhi,x
        sta Q+1
        clc
        adc #>(COL-SCR)
        sta P+1
        rts

; record row (Q/P already at its line)
drawrec lda row
        jsr recat
        jmp drawr2
; recb at record A of the page: REC + A*40 (A*5*8; ROWS = 13, so A*5 < 256)
recat   sta rp
        asl
        asl
        clc
        adc rp                  ; row*5
        sta rp
        lda #0
        sta rp+1
        asl rp                  ; *8
        rol rp+1
        asl rp
        rol rp+1
        asl rp
        rol rp+1
        lda rp
        clc
        adc #<REC
        sta rp
        lda rp+1
        adc #>REC
        sta rp+1
        lda rp
        sta recb+5
        lda rp+1
        sta recb+6
        rts
drawr2  ldx #0                  ; the type
        jsr recb
        and #7
        sta rtype
        tax
        lda colours,x
        ldy #39
-       sta (P),y
        dey
        bpl -
        lda #$20                ; the line, blank
        ldy #39
-       sta (Q),y
        dey
        bpl -
        ldx #9                  ; the name: columns 1-28 (Main cuts a long one in the middle)
        ldy #1
-       jsr recb
        jsr scr
        sta (Q),y
        inx
        iny
        cpy #29
        bne -
        ldx #6                  ; the type: columns 30-32 (DIR for folders)
        ldy #30
-       jsr recb
        jsr scr
        sta (Q),y
        inx
        iny
        cpy #33
        bne -
        ldx #1                  ; the size (blocks, or K/M), as Main wrote it: columns 34-38
        ldy #34
-       jsr recb
        jsr scr
        sta (Q),y
        inx
        iny
        cpy #39
        bne -
        rts
recb    lda #$36                ; byte X of the record (the address is put in above): BASIC's ROM
        sta $01                 ; out for the read (the list is in the RAM under it), then in again
        lda $FFFF,x
        pha
        lda #$37
        sta $01
        pla
        rts

; (build 5) the type of the entry under the bar (2 a disk; $FF an empty list)
seltype lda count
        beq +
        lda sel
        jsr recat
        ldx #0
        jsr recb
        and #7
        rts
+       lda #$FF
        rts

; (build 5) the bar moved: on a disk, the status line says what RETURN and M do; off it, clear again
hint    lda sel
        cmp hsel
        bne +
        lda first
        cmp hfirst
        beq hx
+       lda sel
        sta hsel
        lda first
        sta hfirst
        jmp fkeys               ; (batch 1, Fix 76) the key strip, row 23
hx      rts

; (build 5) DRIVE8 ($17): the name of the disk in drive 8 into d8buf (PETSCII, 0 after it). Z set
; when Main answered, d8len its length (0: empty); Z clear: no answer, or a Main without DRIVE8 ($8F)
d8ask   lda #<d8buf
        sta MB_AL
        lda #>d8buf
        sta MB_AH
        lda #0
        sta d8buf
        sta d8len
        lda #$17
        jsr call
        bne +
        ldx MB_RL
        stx d8len
        cmp #2
+       rts

; (build 5) at a cold start (the ROM calls the jingle): DRIVE 8: NAME on row 23, over the F-key bar,
; when a disk is in (after CTRL+F12 or a preset the disk stays in). Nothing when the drive is empty.
d8row   jsr d8ask
        bne d8rx
        lda d8len
        beq d8rx
        ldx #0
-       lda m_d8r,x
        beq +
        sta SCR + 23*40,x
        lda #15
        sta COL + 23*40,x
        inx
        bne -
+       ldy #0
-       lda d8buf,y
        beq d8rx
        jsr scr
        sta SCR + 23*40,x
        lda #1
        sta COL + 23*40,x
        inx
        iny
        cpx #40
        bne -
d8rx    rts

; the bar on row sel: the line reversed
hilite  lda sel
        jsr rowptr
        ldy #39
-       lda (Q),y
        eor #$80
        sta (Q),y
        dey
        bpl -
        rts

; PETSCII to a screen code
scr     cmp #$20
        bcc ++
        cmp #$40
        bcc +
        cmp #$60
        bcc sub40
        cmp #$80
        bcc sub20
        cmp #$A0
        bcc ++
        cmp #$C0
        bcc sub40
        cmp #$E0
        bcc sub80
++      lda #$3F
+       rts
sub40   sec
        sbc #$40
        rts
sub20   sec
        sbc #$20
        rts
sub80   and #$7F
        rts

; a key: the keyboard, else joystick 2 (with repeat)
getkey  jsr GETIN
        bne +
        lda $DC00
        and #$1F
        eor #$1F
        bne joy
        sta joyold
+       rts
joy     cmp joyold
        beq held
        sta joyold
        lda $A2
        clc
        adc #18
        sta joyt
        jmp joymap
held    lda $A2
        cmp joyt
        beq +
        lda #0
        rts
+       clc
        adc #5
        sta joyt
joymap  lda joyold
        lsr
        bcc +
        lda #145                ; up
        rts
+       lsr
        bcc +
        lda #17                 ; down
        rts
+       lsr
        bcc +
        lda #157                ; left
        rts
+       lsr
        bcc +
        lda #29                 ; right
        rts
+       lsr
        bcc +
        lda #13                 ; fire
        rts
+       lda #0
        rts


; (batch 1, Fix 76) F1 at READY: the Disks folder of the start drive - CHDIR "/DISKS"; not there: the drives
disks   lda #'/'
        sta MB_NCLR
        sta MB_NAME
        ldx #0
-       lda dsname,x
        beq +
        sta MB_NAME
        inx
        bne -
+       lda #$02
        jsr call
        beq +
        jmp drives
+       jmp home
dsname  !pet "disks", 0

; (batch 1, Fix 76) O: a disk with source (type 2, b3) - Main puts it in drive 8 and starts OCTOCODE,
; which opens the source (SRCOPEN $19, then OCTOCODE's SRCNAME $1A). The core resets.
osrc    lda curtype
        and #$0F
        cmp #$0A
        beq +
        jmp loop                ; (not a disk with source: nothing - O is dimmed)
+       clc
        lda first
        adc sel
        sta MB_LL
        lda first+1
        adc #0
        sta MB_LH
        lda #$19
        jsr call
        beq +
        jsr err
        jmp loop
+       ldx #fm_osrc-fmsgs
        jsr fmsg
-       jsr STOP
        bne -
        jmp quit
; (batch 1, Fix 46) N: a new blank disk in this folder, put in drive 8, the bar on it
newd    jsr fnewd
        bne +
        jmp loop
+       lda #1
        sta newmb
        jmp place

; ------------------------------------------------------------------------------- the settings
settings
        lda #0
        sta sline
        sta stop                ; (batch 1) the first line shown (the F8 list scrolls)
        ldx #39
-       lda #$20                ; the help (row 7 blank)
        sta SCR + 7*40,x
        lda shelp,x
        sta SCR + 24*40,x
        lda #15
        sta COL + 24*40,x
        dex
        bpl -
        ldx view                ; this page's own title and its line under it
        lda vtitle,x
        tax
        lda #5
        jsr putrow
        ldx view
        lda vsub,x
        tax
        lda #6
        jsr putrow
        jsr corenm              ; the running core's name and build date, right of the title
sreload lda #<LBUF
        sta MB_AL
        lda #>LBUF
        sta MB_AH
        lda #$08                ; SETLIST
        jsr call
        beq +
        jsr err
        lda #0
        sta count
        beq sdraw
+       lda MB_RL
        sta count
        jsr compact             ; (build 4) F5 / F7: only their own lines
        lda #m_none-msgs
        tax
        jsr status
        lda rsmsg               ; (batch 1) a MiSTer.ini setting changed: switch off and on
        beq sdraw
        lda #0
        sta rsmsg
        ldx #fm_rs-fmsgs
        jsr fmsg
sdraw   lda #0
        sta row
-       lda row
        jsr rowptr
        ldy #39
        lda #$20
--      sta (Q),y
        dey
        bpl --
        lda row
        clc
        adc stop
        cmp count
        bcs +
        jsr sline40
+       inc row
        lda row
        cmp #ROWS
        bne -
        jsr fset                ; (batch 1) F7's help, F8's "more", the slogan row
        lda sline
        jsr hirow
sloop   jsr getkey
        beq sloop
        cmp #17
        bne +
        ldx sline
        inx
        cpx count
        bcs sloop
        txa                     ; (batch 1) off the bottom: the list moves up a line
        sec
        sbc stop
        cmp #ROWS
        bcc sdn1
        inc stop
        inc sline
        jmp sdraw
sdn1    lda sline
        jsr hirow
        inc sline
        lda sline
        jsr hirow
        jmp sloop
+       cmp #145
        bne +
        lda sline
        beq sloop
        cmp stop                ; (batch 1) off the top: the list moves down a line
        bne sup1
        dec stop
        dec sline
        jmp sdraw
sup1    jsr hirow
        dec sline
        lda sline
        jsr hirow
        jmp sloop
+       cmp #29                 ; right: the next choice
        bne +
        lda #1
        jmp sstep
+       cmp #157                ; left: the one before
        bne +
        lda #$FF
        jmp sstep
+       cmp #13
        bne +
        jsr actual
        cmp #13                 ; (batch 1, Fix 54) RETURN on VIDEO OUT: the test picture
        bne snotv
        jsr ftest
        jsr FRAME
        jmp settings
snotv   cmp #0
        bne ++
        lda #$0A                ; RETURN on the chip preset: start it
        jsr call
        beq sstart
        jsr err
        jmp sloop
++      lda #1
        jmp sstep
+       cmp #136                ; F7, F8 or RUN/STOP: back to the files
        beq sback
        cmp #140
        beq sback
        cmp #3
        beq sback
        jmp sloop
sback   lda setonly         ; opened from READY (F5, F7, F8): back to READY
        beq +
        jmp quit
+       jsr fixed
        jmp reload

sstep   sta MB_VAL
        jsr actual
        sta MB_ARG
        lda #$09                ; SETSTEP
        jsr call
        beq +
        jsr err
        jmp sloop
+       lda MB_VAL              ; (batch 1) VALUE 4: in MiSTer.ini - switch off and on
        cmp #4
        bne +
        sta rsmsg
+       jmp sreload

sstart  ldx #m_preset-msgs      ; Main starts the core again with the preset
        jsr status
-       jsr STOP
        bne -
        jmp quit

; settings line row: the label (grey) and the value (white), from LBUF + row*40
sline40 lda row
        clc
        adc stop                ; (batch 1) the line shown on this row
        asl                     ; row*40 = row*32 + row*8
        asl
        asl
        sta tmp
        lda #0
        sta rp+1
        lda tmp
        asl
        rol rp+1
        asl
        rol rp+1
        clc
        adc tmp
        sta rp
        lda rp+1
        adc #0
        sta rp+1
        lda rp
        clc
        adc #<LBUF
        sta recb+5
        lda rp+1
        adc #>LBUF
        sta recb+6
        ldx #0
        ldy #1
-       jsr recb
        jsr scr
        sta (Q),y
        lda #15
        cpx #20
        bcc +
        lda #1
+       sta (P),y
        inx
        iny
        cpx #39
        bne -
        rts

; (build 4) the settings pages: Main's list has 12 lines (0 CHIP PRESET, 1-2 MY CHIP LEFT/RIGHT, 3 START IN,
; 4-5 LEFT/RIGHT SIDS, 6 MY CHIPS, 7 OCTOPHONIC, 8 OCTOSID FX, 9 SPLIT SCREENS, 10-11 TURBO). The pages
; keep their own: view 1 (F5) SID CHIPS: 0 1 2 4 5 6 7 8   view 2 (F7) DUAL SCREEN: 9   view 0 (F8): all
compact ldx view
        beq cpdone
        lda vcnt,x
        sta count
        lda vbase,x
        sta cv
        lda #0
        sta ck
        lda #$36                ; (build 5) the list is in the RAM under BASIC's ROM
        sta $01
cploop  ldy cv
        lda vmap,y
        tax
        lda lbl,x
        sta P
        lda lbh,x
        sta P+1
        ldx ck
        lda lbl,x
        sta Q
        lda lbh,x
        sta Q+1
        ldy #39
-       lda (P),y
        sta (Q),y
        dey
        bpl -
        inc cv
        inc ck
        lda ck
        cmp count
        bcc cploop
        lda #$37
        sta $01
cpdone  rts
; the line (of Main's 12) the bar is on: A, Z set when it is line 0
actual  lda sline
        ldx view
        beq +
        clc
        adc vbase,x
        tay
        lda vmap,y
+       cmp #0
        rts
lbl     !for i, 0, 14 { !byte <(LBUF + i*40) }
lbh     !for i, 0, 14 { !byte >(LBUF + i*40) }
; (batch 1) Main's 15 lines: ... 12 SHOWCASE, 13 VIDEO OUT, 14 SCALING. F7 DUAL SCREEN: 13 VIDEO OUT, 9 SPLIT
vmap    !byte 0, 1, 2, 4, 5, 6, 7, 8, 13, 9
vbase   !byte 0, 0, 8
vcnt    !byte 15, 8, 2
vtitle  !byte s_set-strs, s_sids-strs, s_dual-strs
vsub    !byte s_setu-strs, s_sidsu-strs, s_dualu-strs
; a string (X in strs, 0 at its end) on screen row A, yellow, the rest of the row blank
putrow  tay
        lda rowlo,y
        sta Q
        lda rowhi,y
        sta Q+1
        sta P+1
        lda Q
        sta P
        lda P+1
        clc
        adc #>(COL-SCR)
        sta P+1
        ldy #0
-       lda strs,x
        beq +
        sta (Q),y
        lda #7
        sta (P),y
        inx
        iny
        bne -
+       lda #$20
-       cpy #40
        beq +
        sta (Q),y
        iny
        bne -
+       rts
strs
s_browse !scr "disks and files - f1: the drives", 0
s_set   !scr "settings", 0
s_sids  !scr "sid chips", 0
s_dual  !scr "dual screen", 0
s_setu  !scr "everything, in one list", 0
s_sidsu !scr "which sids play, and which chips", 0
s_dualu !scr "set-up: your screens, and the split", 0

hirow   sec                     ; the bar on settings line A (batch 1: on the screen at A - stop)
        sbc stop
        jsr rowptr
        ldy #39
-       lda (Q),y
        eor #$80
        sta (Q),y
        dey
        bpl -
        rts

; ------------------------------------------------------------------------------- the network
; the network share's state (the light itself is the start screen's, on the top box: the KERNAL's
; IRQ colours it from NET). Carry set when it changed since last time
netlite lda MB_NET
        and #3
        tax
        cpx lastnet
        stx lastnet
        clc
        beq +
        sec
+       rts

; on a MiSTer (NET b5), while C= is held: the help line's second page (C=+F1 the MiSTer's menu)
cpage   lda MB_NET
        and #$20
        beq +
        lda $028D
        and #2
        cmp hpage
        beq +
        sta hpage
        tay
        ldx #39
-       lda help,x
        cpy #0
        beq ++
        lda help2,x
++      sta SCR + 24*40,x
        lda #15
        sta COL + 24*40,x
        dex
        bpl -
+       rts


; a .reu attached on its own: the bar onto its .prg (Main says where: LEN), the list again, and
; REU ATTACHED (nnM) on the status line - RETURN then runs the demo without loading the .reu again
reuin   lda MB_RL               ; RESULT: its size in 64 KB units (kept for REU ATTACHED)
        sta reuu
        lda MB_RH
        sta reuu+1
        lda #1
        sta reumb
place   lda MB_LH               ; (batch 1: N comes in here too) LEN: the entry to put the bar on
        cmp #$FF
        beq ++
        sec                     ; on this page? then just the bar
        lda MB_LL
        sbc first
        tax
        lda MB_LH
        sbc first+1
        bne +
        cpx #ROWS
        bcs +
        stx sel
        jmp reload
+       lda MB_LL               ; else its page starts with it
        sta first
        lda MB_LH
        sta first+1
        lda #0
        sta sel
++      jmp reload

; (batch 1) reumsg and dec16 moved to the far code ($B000)
reuu    !word 0

rowlo   !for i, 0, 24 { !byte <(SCR + i*40) }
rowhi   !for i, 0, 24 { !byte >(SCR + i*40) }
colours !byte 7, 1, 13, 3, 12, 7, 12, 12   ; folders yellow, .prg white, disks light green, .crt sky blue, others grey
autold  !byte $4C, $4F, $41, $44, $22, $2A, $22, $2C, $38, $2C, $31, 0   ; LOAD"*",8,1 in full (build 6: ,1)
; (batch 1) corenm moved to the far code ($B000)
; the far code's stubs: BASIC switched out, the routine, BASIC back in; A = its X (flags set)
!macro far .r {
        lda #$36
        sta $01
        jsr .r
        lda #$37
        sta $01
        txa
        rts
}
fkeys   +far fkeys_b
fnewd   +far fnewd_b
fset    +far fset_b
ftest   +far ftest_b
reumsg  +far reumsg_b
corenm  +far corenm_b
fmsg    +far fmsg_b
shelp   !scr "up/down pick  left/right change  f7 back"
hdr     !scr " name                         type size "
help    !scr "f1 drives f3 up f5/6 page f7 back f8 set"
help2   !scr "c=+f1 mister menu (the mister's own)    "

msgs
m_none    !scr 0
m_load    !scr "loading...", 0
m_rin     !scr "reu", 0
m_wait    !scr "please wait - connecting to network...", 0
m_nonet   !scr "no network - using the sd card", 0
m_nonc    !scr "?the network is not connected", 0
m_reu     !scr "reu attached (", 0
m_scan    !scr "scanning...", 0
m_noreply !scr "?no reply from octophonic main (cmd   ", 0
m_err     !scr "?os error", 0
m_nf      !scr "?not found", 0
m_nd      !scr "?not a folder", 0
m_cant    !scr "?can't run that type of file", 0
m_preset  !scr "starting the chip preset...", 0
m_disk    !pet 13, "disk in drive 8", 13, 0
m_mnt     !pet 13, "disk in drive 8: ", 0
m_mnt2    !pet 13, "f3 loads and runs it", 13, 0
m_f3n     !pet 13, "f3 load - drive 8: ", 0
m_f3e     !pet 13, "f3 load: drive 8 is empty.", 13, "f1: put the bar on a disk, m mounts it", 13, 0
m_d8r     !scr "drive 8: ", 0
d8buf     !fill 34, 0
d8len     !byte 0
hsel      !byte $FF
hfirst    !byte 0
hwas      !byte 0

first   !word 0
total   !word 0
count   !byte 0
sel     !byte 0
row     !byte 0
rtype   !byte 0
rp      !word 0
tmp     !byte 0, 0
secs    !byte 0
jifs    !byte 0
bsave   !byte 0
lastj   !byte 0
lastcmd !byte 0
hpage   !byte 0
mountonly !byte 0
lastnet !byte $ff
nonet   !byte 0
reumb   !byte 0
skipup  !byte 1
sline   !byte 0
joyold  !byte 0
joyt    !byte 0
mode    !byte 0
view    !byte 0
cv      !byte 0
ck      !byte 0
setonly !byte 0
stop    !byte 0                 ; (batch 1) the settings list's first line on screen
rsmsg   !byte 0                 ; (batch 1) say "switch off and on" after the list is drawn
curtype !byte $FF               ; (batch 1) the type byte of the entry under the bar ($FF none)
newmb   !byte 0                 ; (batch 1) a new disk was made: say so
; the jingle's tune (read by its player from here: SHELL.PRG stays in RAM while it plays)
; C4 D4 E4 F4 G4 A4 B4 C5 E5 (PAL: Hz x 17.0284)
jfreq   !word 4455, 5001, 5613, 5947, 6675, 7493, 8410, 8910, 11226
; up C D E G A C (their thirds E F G B C E), down A G E D, home C E then G C; $FF the end
jtab    !byte $20, $31, $42, $64, $75, $87, $75, $64, $42, $31, $20, $74, $FF
; (build 5) the ROM's cold start calls $C003: the disk in drive 8 on row 23, then the jingle - its
; code is in the RAM under BASIC's ROM ($BE00, loaded with the rest of SHELL.PRG), run with BASIC out
jstub   jsr d8row
        lda #$36
        sta $01
        jsr jingle
        lda #$37
        sta $01
        rts
jstop   lda $0315               ; the browser starting: the jingle's IRQ out, if it is in
        cmp #>JP
        bne +
        lda $0314
        cmp #<JP
        bne +
        sei
        lda #$31
        sta $0314
        lda #$EA
        sta $0315
        cli
+       rts
shellend
!if shellend > $D000 { !error "the browser is too big" }
