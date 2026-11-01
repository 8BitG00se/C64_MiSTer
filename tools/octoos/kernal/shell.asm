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
SCR     = $0400
COL     = $D800
FRAME   = $F92F         ; the V1.1 start screen, without NEW (octo.asm)
READY   = $A474
GETIN   = $FFE4
STOP    = $FFE1
CHROUT  = $FFD2
AUTORUN = $02A8
ROWS    = 17
TOP     = 6             ; the first list row
LBUF    = $CA00         ; Main writes the path (40) and the records (32 each) here
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
        cmp #$01
        beq +
        jmp READY
+       jsr FRAME               ; the navy screen, the band, the title
        ldx #8                  ; the start screen's F1 BROWSE hint: not in here
        lda #$20
-       sta SCR + 3*40 + 31,x
        dex
        bpl -
        jsr fixed
reload  jsr dolist
        jsr drawall
        jsr hilite
loop    jsr getkey
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
        ldx #m_load-msgs        ; a program or a cartridge: Main loads it and the C64 restarts
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
        ldx #7                  ; LOAD"*",8 then RUN, as SHIFT+RUN/STOP does
-       lda autold,x
        sta $0277,x
        dex
        bpl -
        lda #8
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

; the request in A; wait for Main, 3 seconds at most. Z set when it is done
call    sta MB_CMD
        sta lastcmd
        lda $A2
        clc
        adc #150
        sta tmo
-       lda MB_ST
        cmp #$01
        bne +
        lda $A2
        cmp tmo
        bne -
        lda #$FE
        rts
+       cmp #$02
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
        sta SCR + 23*40 + 36
        lda lastcmd
        and #$0F
        jsr hexd
        sta SCR + 23*40 + 37
        lda #$29
        sta SCR + 23*40 + 38
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
        sta SCR + 23*40,y
        lda #7
        sta COL + 23*40,y
        inx
        iny
        bne -
+       lda #$20
-       cpy #40
        beq +
        sta SCR + 23*40,y
        iny
        bne -
+       rts

; the header line and the key help
fixed   ldx #39
-       lda hdr,x
        sta SCR + 5*40,x
        lda #15
        sta COL + 5*40,x
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
        sta SCR + 4*40,x
        lda #3
        sta COL + 4*40,x
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
drawrec lda row                 ; R = REC + row*32
        asl
        asl
        asl
        asl
        asl
        sta rp
        lda row
        lsr
        lsr
        lsr
        clc
        adc #>REC
        sta rp+1
        lda rp
        clc
        adc #<REC
        sta rp
        bcc +
        inc rp+1
+       lda rp
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
        ldx #6                  ; the name: columns 1-26
        ldy #1
-       jsr recb
        jsr scr
        sta (Q),y
        inx
        iny
        cpy #27
        bne -
        lda rtype               ; the type: columns 30-32
        beq +
        cmp #5
        bne ++
+       ldy #30
        lda #4                  ; DIR
        sta (Q),y
        iny
        lda #9
        sta (Q),y
        iny
        lda #18
        sta (Q),y
        rts
++      ldx #3
        ldy #30
-       jsr recb
        jsr scr
        sta (Q),y
        inx
        iny
        cpy #33
        bne -
        ldx #1                  ; the blocks, right-aligned in columns 34-38
        jsr recb
        sta num
        inx
        jsr recb
        sta num+1
        ldy #34
        ldx #0
        stx lead
--      lda #0
        sta dig
-       lda num
        sec
        sbc tenlo,x
        pha
        lda num+1
        sbc tenhi,x
        bcc +
        sta num+1
        pla
        sta num
        inc dig
        bne -
+       pla
        lda dig
        bne +
        lda lead
        bne +
        cpx #4
        beq +
        lda #$20
        bne ++
+       lda #1
        sta lead
        lda dig
        ora #$30
++      sta (Q),y
        iny
        inx
        cpx #5
        bne --
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
        sta SCR + 4*40,x
        lda #3
        sta COL + 4*40,x
        lda #$20
        sta SCR + 5*40,x
        lda shelp,x
        sta SCR + 24*40,x
        lda #15
        sta COL + 24*40,x
        dex
        bpl -
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

rowlo   !for i, 0, 24 { !byte <(SCR + i*40) }
rowhi   !for i, 0, 24 { !byte >(SCR + i*40) }
tenlo   !byte <10000, <1000, <100, <10, <1
tenhi   !byte >10000, >1000, >100, >10, >1
colours !byte 7, 1, 13, 8, 12, 7, 12, 12
autold  !byte $4C, $CF, $22, $2A, $22, $2C, $38, $0D     ; lO"*",8 RETURN
stitle  !scr "settings                                "
shelp   !scr "up/down pick  left/right change  f7 back"
hdr     !scr " name                         type blks "
help    !scr "ret run f1/f5 page f3 up f7 ready f8 set"

msgs
m_none    !scr 0
m_load    !scr "loading...", 0
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
num     !word 0
dig     !byte 0
lead    !byte 0
tmp     !byte 0
tmo     !byte 0
lastcmd !byte 0
mountonly !byte 0
sline   !byte 0
joyold  !byte 0
joyt    !byte 0
shellend
!if shellend > LBUF { !error "the browser is too big" }
