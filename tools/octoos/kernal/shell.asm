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
;   F5 / F6   page down / up                            SHIFT+RETURN      a disk: just put it in
;   F3, DEL or left arrow (joystick left)  up a folder  F2                the start folder
;   F1        the drives (SD CARD / NETWORK)            F7 or RUN/STOP    back to READY
;   HOME      the top
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
LBUF    = $CDC0         ; Main writes the path (40) and the records (40 each) here (to $CFF0; the settings to $CF80)
REC     = LBUF + 40
P       = $FB
Q       = $FD

        * = $C000
        jmp start               ; $C000: the browser (the ROM's @@, F1)
        jmp jingle              ; $C003: the start jingle (the ROM's cold start)
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
mbrowse jmp drives              ; "B" F1
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
mbrows  jsr netwait             ; a share still connecting: wait for it (any key: the SD card)
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
loop    jsr netlite             ; when the share comes or goes, list again
        bcs reload
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
        cmp #137                ; F2 - or C=+F1 (the C= key's table makes F1 137 too): on a MiSTer
        bne +                   ; the MiSTer's own menu
        lda $028D
        and #2
        beq startf
        lda MB_NET
        and #$20
        beq startf
        lda #$12                ; MENU: Main loads the MiSTer's menu core
        jsr call
        jmp loop
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
        ldx #m_f3-m_disk
        bne dmsg
disk    jsr FRAME
        ldx #0
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
        beq +
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
        ldx #39
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
        jsr actual
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
lbl     !for i, 0, 11 { !byte <(LBUF + i*40) }
lbh     !for i, 0, 11 { !byte >(LBUF + i*40) }
vmap    !byte 0, 1, 2, 4, 5, 6, 7, 8, 9
vbase   !byte 0, 0, 8
vcnt    !byte 12, 8, 1
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
s_browse !scr "f1 browse - return runs anything here", 0
s_set   !scr "settings", 0
s_sids  !scr "sid chips", 0
s_dual  !scr "dual screen", 0
s_setu  !scr "everything, in one list", 0
s_sidsu !scr "which sids play, and which chips", 0
s_dualu !scr "c64 on the crt, octovic on hdmi", 0

hirow   jsr rowptr              ; the bar on settings line A
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
colours !byte 7, 1, 13, 3, 12, 7, 12, 12   ; folders yellow, .prg white, disks light green, .crt sky blue, others grey
autold  !byte $4C, $4F, $41, $44, $22, $2A, $22, $2C, $38, $2C, $31, 0   ; LOAD"*",8,1 in full (build 6: ,1)
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
m_f3      !pet 13, "f3 load - the disk in drive 8", 13, 0

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
; the jingle's tune (read by its player from here: SHELL.PRG stays in RAM while it plays)
; C4 D4 E4 F4 G4 A4 B4 C5 E5 (PAL: Hz x 17.0284)
jfreq   !word 4455, 5001, 5613, 5947, 6675, 7493, 8410, 8910, 11226
; up C D E G A C (their thirds E F G B C E), down A G E D, home C E then G C; $FF the end
jtab    !byte $20, $31, $42, $64, $75, $87, $75, $64, $42, $31, $20, $74, $FF
shellend
!if shellend > LBUF { !error "the browser is too big" }

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
