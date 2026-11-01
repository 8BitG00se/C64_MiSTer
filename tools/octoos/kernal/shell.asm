; OCTOPHONIC OS 1 - the browser (SHELL.PRG). F1 at READY loads it to $C000 and runs it.
; By Mong00se.
;   cursor up/down (or joystick port 2)  move          RETURN (or fire)  run / into a folder
;   F1 / F5   page up / down                            SHIFT+RETURN      a disk: just put it in
;   F3, DEL or left arrow (joystick left)  up a folder  F2                the start folder
;   HOME      the top                                   F7 or RUN/STOP    back to READY
;   F8        settings: chip preset, my chips, SID models, Octophonic, FX, split screens, turbo
;             (cursor up/down to pick, left/right to change, RETURN starts a chip preset)
; The 6502 is only the front end: the list, the folders and every load are Octophonic Main's,
; the same code the MiSTer menu uses (LIST, OPEN, CHDIR through the mailbox at $D6F0).
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
seq     = $02AB         ; the request number, shared with the ROM's commands
ROWS    = 13
TOP     = 9             ; the first list row (5 the path, 7 the column names, 8 left blank)
LBUF    = $CB00         ; Main writes the path (40) and the records (40 each) here (to $CD58; the settings to $CD20)
REC     = LBUF + 40
P       = $FB
Q       = $FD

        * = $C000
start   lda #0
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
+       jsr FRAME               ; the navy screen, the band, the title
        ldx #8                  ; the start screen's F1 BROWSE hint: not in here
        lda #$20
-       sta SCR + 3*40 + 31,x
        dex
        bpl -
        jsr fixed
        jsr netwait             ; a share still connecting: wait for it (any key: the SD card)
        jsr netlite
reload  jsr dolist
        jsr drawall
        jsr hilite
        lda reumb               ; a .reu just attached: say so once the list is up
        beq +
        jsr reumsg
+       lda nonet               ; "no network" from the wait: say so once the list is up
        beq loop
        lda #0
        sta nonet
        ldx #m_nonet-msgs
        jsr status
loop    jsr netlite             ; the network light; when the share comes or goes, list again
        bcs reload
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
+       cmp #133                ; F1
        bne +
        jmp pageup
+       cmp #135                ; F5
        bne +
        jmp pagedn
+       cmp #134                ; F3
        beq upfold
        cmp #20                 ; DEL
        beq upfold
        cmp #95                 ; left arrow
        beq upfold
        cmp #157                ; cursor left (joystick left)
        beq upfold
        cmp #140                ; F8: settings
        bne +
        jmp settings
+
        cmp #137                ; F2
        beq startf
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

disk    jsr FRAME
        ldx #0
-       lda m_disk,x
        beq +
        jsr CHROUT
        inx
        bne -
+       lda mountonly
        bne +
        ldx #9                  ; LOAD"*",8 then RUN, as SHIFT+RUN/STOP does
-       lda autold,x
        sta $0277,x
        dex
        bpl -
        lda #10
        sta $C6
        lda #1
        sta AUTORUN
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
        lda REC                 ; ".." first and more after it: start below it
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
longl   ldx #m_load-msgs    ; (a 16 MB .reu over the network can take a while)
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
tick    lda $A2
        cmp lastj
        beq -
        sta lastj
        and #3
        bne +
        inc $D020
+       dec jifs
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
+       jmp status
hexd    cmp #10                 ; a hex digit as a screen code
        bcc +
        sbc #9
        rts
+       ora #$30
        rts

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
        beq +
        sta SCR + 22*40,y
        iny
        bne -
+       rts

; the header line and the key help
fixed   ldx #39
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
drawall ldx #39
-       lda LBUF,x
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
drawrec lda row                 ; R = REC + row*40 (row*5*8; ROWS = 14, so row*5 < 256)
        sta rp
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
        sta recb+1
        lda rp+1
        sta recb+2
        ldx #0                  ; the type
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
recb    lda $FFFF,x             ; byte X of the record (the address is put in above)
        rts

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


; ------------------------------------------------------------------------------- the settings
settings
        lda #0
        sta sline
        ldx #39
-       lda stitle,x            ; the title, the help
        sta SCR + 5*40,x
        lda #3
        sta COL + 5*40,x
        lda #$20
        sta SCR + 7*40,x
        lda shelp,x
        sta SCR + 24*40,x
        lda #15
        sta COL + 24*40,x
        dex
        bpl -
        jsr corenm              ; the running core's name and build date, right of SETTINGS
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
        lda #m_none-msgs
        tax
        jsr status
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
        cmp count
        bcs +
        jsr sline40
+       inc row
        lda row
        cmp #ROWS
        bne -
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
        lda sline
        jsr hirow
        inc sline
        lda sline
        jsr hirow
        jmp sloop
+       cmp #145
        bne +
        lda sline
        beq sloop
        jsr hirow
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
        lda sline
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
sback   jsr fixed
        jmp reload

sstep   sta MB_VAL
        lda sline
        sta MB_ARG
        lda #$09                ; SETSTEP
        jsr call
        beq +
        jsr err
        jmp sloop
+       jmp sreload

sstart  ldx #m_preset-msgs      ; Main starts the core again with the preset
        jsr status
-       jsr STOP
        bne -
        jmp quit

; settings line row: the label (grey) and the value (white), from LBUF + row*40
sline40 lda row
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
        sta recb+1
        lda rp+1
        adc #>LBUF
        sta recb+2
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

hirow   jsr rowptr              ; the bar on settings line A
        ldy #39
-       lda (Q),y
        eor #$80
        sta (Q),y
        dey
        bpl -
        rts

; ------------------------------------------------------------------------------- the network
; the light at the top right (row 3), as the start screen's: none set up - not shown, waiting or
; not there - red, there - green. Carry set when it changed since last time
netlite lda MB_NET
        and #3
        tax
        lda #$51
        sta SCR + 3*40 + 39
        lda litecol,x
        sta COL + 3*40 + 39
        cpx lastnet
        stx lastnet
        clc
        beq +
        sec
+       rts

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
nwdone  rts

; a .reu attached on its own: the bar onto its .prg (Main says where: LEN), the list again, and
; REU ATTACHED (nnM) on the status line - RETURN then runs the demo without loading the .reu again
reuin   lda MB_RL               ; RESULT: its size in 64 KB units (kept for REU ATTACHED)
        sta reuu
        lda MB_RH
        sta reuu+1
        lda #1
        sta reumb
        lda MB_LH
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

reumsg  ldx #m_reu-msgs         ; REU ATTACHED (nnM), or (nnnK) under 1 MB
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
reuu    !word 0

rowlo   !for i, 0, 24 { !byte <(SCR + i*40) }
rowhi   !for i, 0, 24 { !byte >(SCR + i*40) }
colours !byte 7, 1, 13, 8, 12, 7, 12, 12
autold  !byte $4C, $4F, $41, $44, $22, $2A, $22, $2C, $38, $0D   ; LOAD"*",8 RETURN, in full
; the core's name ($D6B8-$D6BF) and build date ($D6B4-$D6B6, BCD) on the settings title row:
; "core mem3     01.11.26" - from OctoVIC itself, so it is always the core really running
corenm  ldx #4
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
        rts
t_core  !scr "core "
stitle  !scr "settings                                "
shelp   !scr "up/down pick  left/right change  f7 back"
hdr     !scr " name                         type size "
help    !scr "ret run f1/f5 page f3 up f7 ready f8 set"

msgs
m_none    !scr 0
m_load    !scr "loading...", 0
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
mountonly !byte 0
lastnet !byte $ff
nonet   !byte 0
reumb   !byte 0
litecol !byte 6, 2, 5, 2
skipup  !byte 1
sline   !byte 0
joyold  !byte 0
joyt    !byte 0
shellend
!if shellend > LBUF { !error "the browser is too big" }
