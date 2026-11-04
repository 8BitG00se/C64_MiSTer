; OCTOCODE - the Octophonic 64's own code editor (OCTOCODE.PRG). By Mong00se.
; Original project by Mong00se - Octophonic 64 and OctoVIC by Mong00se (github.com/8BitG00se). GPL v3 or later.
;
; Write ACME source on the C64, press F1: Octophonic Main saves it, assembles it with ACME and runs
; it. RUN/STOP+RESTORE brings you back with your code as you left it.
;
;   F1 COMPILE (and run)   F3 LOAD   F5 SAVE   F7 EXIT (to READY; RUN comes back)
;   F2 delete the line     F4 a new line above the cursor     F6 / F8 page up / down
;   cursor keys; RETURN splits the line (the new one keeps the indent); DEL (at a line's start:
;   joins it to the one above); INST a space; HOME the top; CLR (SHIFT+HOME) the end
;
; The source is plain PETSCII text at TXT (lines end with RETURN, at most 79 characters each, up
; to $CDFF), the line being edited in LBUF. The mailbox ($D6F0, docs/OCTOOS.md):
;   $13 COMPILE  ADDR/LEN the source, NAME the file name, ARG b0: a copy is also in VRAM $FE0000
;   $14 COMPLOG  the log, a line at a time     $15 GO  the program into RAM (the 6502 starts it)
; Before GO the editor and its source ($0801 to the end of the text) go into OctoVIC's VRAM at
; $FF0000; the RUN/STOP+RESTORE handler (in the tape buffer, $0334) copies them back.
!to "octocode.prg", cbm
!cpu 6502

BUILD   = 1
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
MB_SEQ  = MB+$D
MB_RSEQ = MB+$E
VADDR   = $D600
VINC    = $D603
VDATA   = $D604
OCTRL   = $D605
SCR     = $0400
COL     = $D800
seq     = $02AB         ; the request number, shared with the ROM's commands and the browser
GETIN   = $FFE4
CHROUT  = $FFD2
CHRIN   = $FFCF
SETLFS  = $FFBA
SETNAM  = $FFBD
OPEN    = $FFC0
CLOSE   = $FFC3
CHKIN   = $FFC6
CHKOUT  = $FFC9
CLRCHN  = $FFCC
READYV  = $A474
TXT     = $2400         ; the source
TXTMAX  = $CE00         ; (its end, exclusive)
LOGBUF  = $CE00         ; Main's log lines come here
ROWS    = 20            ; the code: rows 2-21
TOPROW  = 2
MAXLEN  = 79
STUB    = $0334         ; the RUN/STOP+RESTORE handler
LAUNCH  = $0100         ; the launcher (GO)
VSTASH  = $FF           ; VRAM $FF0000: the editor and its source while a program runs
VSRC    = $FE           ; VRAM $FE0000: the source for Main (the MiSTer's Main reads it there)

; zero page (BASIC's, unused while the editor runs)
SRC     = $57
DST     = $59
CNT     = $5B
T0      = $5D
SP      = $5F
CP      = $61
T1      = $63
P       = $FB
Q       = $FD

; colours
C_CODE  = 1
C_LABEL = 3
C_STR   = 7
C_REM   = 13
C_RULE  = 14
C_HELP  = 15
C_STAT  = 7
C_ERR   = 10
C_OK    = 13

        * = $0801
        !byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00      ; 10 SYS2061
        jmp cold                ; $080D
        jmp resume              ; $0810: back from a program (the stub jumps here)

; ============================================================================ start
cold    cld
        lda #$36                ; BASIC off: $A000-$BFFF holds source too
        sta $01
        jsr scrinit
        lda alive
        cmp #$A5
        bne +
        jmp resume2             ; RUN after F7: everything is still here
+       jsr stashok             ; a program ran and the machine was reset: the copy in VRAM
        bcs fresh
        jsr unstash             ; (this same build: its code lands on itself)
        jmp resume
fresh   lda #$A5
        sta alive
        ldx #fdefl-1
-       lda fdef,x
        sta fname,x
        dex
        bpl -
        lda #fdefl
        sta fnlen
        jsr empty
        jsr drawall
        jsr loadfile
        jmp edit

; back from a program (RUN/STOP+RESTORE): the code as it was
resume  cld
        lda #$36
        sta $01
        jsr scrinit
        ldx #<m_back
        ldy #>m_back
        jsr status
        jmp edit
resume2 ldx #<m_hello
        ldy #>m_hello
        jsr status
edit    jsr fixline
        jsr drawall

; ============================================================================ the keys
loop    lda topy                ; (where the screen was, for vredraw)
        sta otop
        lda topy+1
        sta otop+1
        jsr getkey
        cmp #133                ; F1
        bne +
        jmp compile
+       cmp #134                ; F3
        bne +
        jmp k_load
+       cmp #135                ; F5
        bne +
        jmp k_save
+       cmp #136                ; F7
        bne +
        jmp k_exit
+       cmp #137                ; F2
        bne +
        jmp k_delln
+       cmp #138                ; F4
        bne +
        jmp k_insln
+       cmp #139                ; F6
        bne +
        jmp k_pgup
+       cmp #140                ; F8
        bne +
        jmp k_pgdn
+       cmp #17
        bne +
        jsr down
        jmp vredraw
+       cmp #145
        bne +
        jsr up
        jmp vredraw
+       cmp #29
        bne +
        jmp k_right
+       cmp #157
        bne +
        jmp k_left
+       cmp #13
        bne +
        jmp k_return
+       cmp #141
        bne +
        jmp k_return
+       cmp #20
        bne +
        jmp k_del
+       cmp #148
        bne +
        jmp k_ins
+       cmp #19
        bne +
        jmp k_home
+       cmp #147
        bne +
        jmp k_end
+       cmp #$A0                ; SHIFT+SPACE: a space
        bne +
        lda #' '
+       cmp #$20
        bcc tolp
        cmp #$60
        bcc k_char
        cmp #$C1
        bcc tolp
        cmp #$E0
        bcc k_char
tolp    jmp loop
k_char  jsr putch
        jmp rowdraw

redraw  lda cx                  ; (a move across: the column to keep going up and down)
        sta wantx
vredraw jsr fixh                ; up and down: the screen moved by a line at most?
        bcs +
        jsr title
        sec
        lda topy
        sbc otop
        tax
        lda topy+1
        sbc otop+1
        bne ++
        txa
        bne +++
        jmp loop                ; it didn't: the rows are as they were
+++     cpx #1
        bne +
        jsr shup                ; one down: the rows up, the cursor's line at the bottom
        jsr drawcur
        jmp loop
++      cmp #$FF
        bne +
        cpx #$FF
        bne +
        jsr shdn                ; one up: the rows down, the cursor's line at the top
        jsr drawcur
        jmp loop
+
vfull   jsr drawall
        jmp loop

; the code rows up one (row 2 goes, the bottom row is drawn after)
shup    ldx #TOPROW
-       jsr rowpair
        inx
        cpx #TOPROW+ROWS-1
        bcc -
        rts
; ... and down one (the top row is drawn after)
shdn    ldx #TOPROW+ROWS-1
-       dex
        jsr rowpair2
        cpx #TOPROW
        bne -
        rts
; row X+1 into row X (screen and colour)
rowpair lda rowlo,x
        sta SP
        sta CP
        lda rowhi,x
        sta SP+1
        clc
        adc #>(COL-SCR)
        sta CP+1
        lda rowlo+1,x
        sta Q
        sta P
        lda rowhi+1,x
        sta Q+1
        clc
        adc #>(COL-SCR)
        sta P+1
        ldy #39
-       lda (Q),y
        sta (SP),y
        lda (P),y
        sta (CP),y
        dey
        bpl -
        rts
; row X into row X+1
rowpair2
        lda rowlo+1,x
        sta SP
        sta CP
        lda rowhi+1,x
        sta SP+1
        clc
        adc #>(COL-SCR)
        sta CP+1
        lda rowlo,x
        sta Q
        sta P
        lda rowhi,x
        sta Q+1
        clc
        adc #>(COL-SCR)
        sta P+1
        ldy #39
-       lda (Q),y
        sta (SP),y
        lda (P),y
        sta (CP),y
        dey
        bpl -
        rts
rowdraw lda cx
        sta wantx
        jsr fixh                ; the cursor went past the screen's edge: everything moves
        bcc +
        jmp vfull
+       jsr drawcur
        jsr title
        jmp loop

; a key, the cursor blinking meanwhile
getkey  lda $A2
        and #$10
        sta blink
        jsr curon
-       jsr GETIN
        bne +
        lda $A2
        and #$10
        cmp blink
        beq -
        sta blink
        jsr curflip
        jmp -
+       pha
        jsr curoff
        pla
        rts

; ============================================================================ editing a line
; A into the line at the cursor
putch   ldx llen
        cpx #MAXLEN
        bcs full
        pha
        jsr roomck
        pla
        bcs full
        sta ch
        ldx llen
-       cpx cx
        beq +
        dex
        lda LBUF,x
        sta LBUF+1,x
        jmp -
+       lda ch
        sta LBUF,x
        inc llen
        inc cx
        lda #1
        sta dirty
        rts
full    ldx #<m_full
        ldy #>m_full
        jmp status

; room for one more byte in the text? C set: no
roomck  lda tend+1
        cmp #>(TXTMAX-1)
        rts

k_ins   lda #' '                ; INST: a space, the cursor stays
        jsr putch
        lda cx
        beq +
        dec cx
+       jmp rowdraw

k_del   lda cx
        beq join
        ldx cx                  ; the character before the cursor out
        dex
-       lda LBUF+1,x
        sta LBUF,x
        inx
        cpx llen
        bcc -
        dec llen
        dec cx
        lda #1
        sta dirty
        jmp rowdraw
; DEL at the start of a line: onto the end of the line above
join    lda cy
        ora cy+1
        bne +
        jmp loop
+       jsr commit
        jsr prevst              ; T0: the line above, T1 its length
        clc
        lda T1
        adc llen
        cmp #MAXLEN+1
        bcc +
        ldx #<m_long
        ldy #>m_long
        jsr status
        jmp loop
+       lda T1
        pha
        lda lptr                ; the RETURN between them out
        sec
        sbc #1
        sta DST
        lda lptr+1
        sbc #0
        sta DST+1
        lda #1
        jsr delbytes
        jsr declines
        jsr up0                 ; up a line: the joined line
        pla
        sta cx
        jsr fixline
        jmp redraw

k_left  lda cx
        beq +
        dec cx
        jmp rowdraw
+       lda cy
        ora cy+1
        bne +
        jmp loop
+       jsr up
        lda llen
        sta cx
        jmp redraw
k_right lda cx
        cmp llen
        bcs +
        inc cx
        jmp rowdraw
+       jsr lastck
        bcc +
        jmp loop
+       jsr down
        lda #0
        sta cx
        jmp redraw

k_home  lda #0
        sta wantx
        sta gline
        sta gline+1
        jsr gotoln
        jmp redraw
k_end   lda #$FF                ; (gotoln stops at the last line)
        sta gline
        sta gline+1
        jsr gotoln
        lda llen
        sta cx
        jmp redraw

k_pgup  lda #ROWS-1
        sta pgn
-       jsr up
        dec pgn
        bne -
        jmp vredraw
k_pgdn  lda #ROWS-1
        sta pgn
-       jsr down
        dec pgn
        bne -
        jmp vredraw

; RETURN: the line split at the cursor; the new line gets the old one's indent
k_return
        jsr commit
        ldx #0                  ; the indent (the spaces at the start, up to the cursor)
-       cpx cx
        beq +
        lda LBUF,x
        cmp #' '
        bne +
        inx
        bne -
+       stx indent
        lda llen                ; the new line too long with its indent? then no indent
        sec
        sbc cx
        clc
        adc indent
        cmp #MAXLEN+1
        bcc +
        lda #0
        sta indent
+       lda tend+1              ; room?
        cmp #>(TXTMAX-$100)
        bcc +
        jmp full2
+       clc                     ; DST = the cursor's place in the text
        lda lptr
        adc cx
        sta DST
        lda lptr+1
        adc #0
        sta DST+1
        lda indent
        clc
        adc #1
        jsr insbytes
        ldy #0
        lda #13
        sta (DST),y
        ldx indent
        beq +
-       iny
        lda #' '
        sta (DST),y
        dex
        bne -
+       jsr inclines
        lda cx                  ; the cursor's line is shorter now
        sta llen
        sta lold
        jsr down0
        lda indent
        sta cx
        jmp redraw
full2   ldx #<m_full
        ldy #>m_full
        jsr status
        jmp loop

; F2: the line out
k_delln jsr commit
        lda nlines+1
        bne +
        lda nlines
        cmp #2
        bcs +
        lda #0                  ; the only line: just empty it
        sta llen
        sta cx
        lda #1
        sta dirty
        jsr commit
        jmp redraw
+       lda lptr
        sta DST
        lda lptr+1
        sta DST+1
        lda lold
        clc
        adc #1
        jsr delbytes
        jsr declines
        lda cy                  ; it was the last line: the cursor up one
        cmp nlines
        lda cy+1
        sbc nlines+1
        bcc +
        jsr prevst
        lda T0
        sta lptr
        lda T0+1
        sta lptr+1
        jsr decy
+       jsr loadln
        jsr fixtop
        jmp redraw

; F4: an empty line above the cursor
k_insln jsr commit
        jsr roomck
        bcc +
        jmp full2
+       lda lptr
        sta DST
        lda lptr+1
        sta DST+1
        lda #1
        jsr insbytes
        ldy #0
        lda #13
        sta (DST),y
        jsr inclines
        lda #0
        sta cx
        jsr loadln
        jmp redraw

; ============================================================================ lines
; the edited line back into the text
commit  lda dirty
        bne +
        rts
+       lda llen
        sec
        sbc lold
        beq ++
        bcc +
        pha                     ; longer: room at lptr+lold
        clc
        lda lptr
        adc lold
        sta DST
        lda lptr+1
        adc #0
        sta DST+1
        pla
        jsr insbytes
        jmp ++
+       eor #$FF                ; shorter: lold-llen bytes out at lptr+llen
        clc
        adc #1
        pha
        clc
        lda lptr
        adc llen
        sta DST
        lda lptr+1
        adc #0
        sta DST+1
        pla
        jsr delbytes
++      lda lptr
        sta DST
        lda lptr+1
        sta DST+1
        ldy #0
-       cpy llen
        beq +
        lda LBUF,y
        sta (DST),y
        iny
        bne -
+       lda llen
        sta lold
        lda #0
        sta dirty
        lda #1
        sta dirty2
        rts

; the line at lptr into LBUF
loadln  lda lptr
        sta T0
        lda lptr+1
        sta T0+1
        ldy #0
-       lda (T0),y
        cmp #13
        beq +
        sta LBUF,y
        iny
        cpy #MAXLEN
        bcc -
+       sty llen
        sty lold
        lda #0
        sta dirty
        lda wantx               ; the column wanted, if the line is that long
        cmp llen
        bcc +
        lda llen
+       sta cx
        rts

; A bytes of room at DST (everything from DST on moves up); DST stays
insbytes
        sta T1
        lda DST                 ; SRC = DST, DST += n, CNT = tend - SRC
        sta SRC
        pha
        lda DST+1
        sta SRC+1
        pha
        clc
        lda DST
        adc T1
        sta DST
        lda DST+1
        adc #0
        sta DST+1
        sec
        lda tend
        sbc SRC
        sta CNT
        lda tend+1
        sbc SRC+1
        sta CNT+1
        clc
        lda tend
        adc T1
        sta tend
        bcc +
        inc tend+1
+       jsr mbwd
        pla
        sta DST+1
        pla
        sta DST
        lda #1
        sta dirty2
        rts

; A bytes out at DST
delbytes
        sta T1
        clc
        lda DST
        adc T1
        sta SRC
        lda DST+1
        adc #0
        sta SRC+1
        sec
        lda tend
        sbc SRC
        sta CNT
        lda tend+1
        sbc SRC+1
        sta CNT+1
        sec
        lda tend
        sbc T1
        sta tend
        bcs +
        dec tend+1
+       lda #1
        sta dirty2
        ; (on into mfwd)

; CNT bytes from SRC to DST, upwards (DST < SRC)
mfwd    ldy #0
        ldx CNT+1
        beq +
-       lda (SRC),y
        sta (DST),y
        iny
        bne -
        inc SRC+1
        inc DST+1
        dex
        bne -
+       ldx CNT
        beq +
-       lda (SRC),y
        sta (DST),y
        iny
        dex
        bne -
+       rts

; CNT bytes from SRC to DST, from the top down (DST > SRC)
mbwd    lda CNT
        ora CNT+1
        beq ++
        clc
        lda SRC+1
        adc CNT+1
        sta SRC+1
        clc
        lda DST+1
        adc CNT+1
        sta DST+1
        ldy CNT
        beq +
-       dey
        lda (SRC),y
        sta (DST),y
        cpy #0
        bne -
+       ldx CNT+1
        beq ++
--      dec SRC+1
        dec DST+1
        ldy #$FF
-       lda (SRC),y
        sta (DST),y
        dey
        bne -
        lda (SRC),y
        sta (DST),y
        dex
        bne --
++      rts

inclines
        inc nlines
        bne +
        inc nlines+1
+       rts
declines
        lda nlines
        bne +
        dec nlines+1
+       dec nlines
        rts
incy    inc cy
        bne +
        inc cy+1
+       rts
decy    lda cy
        bne +
        dec cy+1
+       dec cy
        rts

; C clear: there is a line below the cursor's
lastck  jsr commit
        clc
        lda cy
        adc #1
        tax
        lda cy+1
        adc #0
        cmp nlines+1
        bcc +
        bne ++
        cpx nlines
        bcc +
++      sec
        rts
+       clc
        rts

; down a line (if there is one)
down    jsr lastck
        bcs +
down0   clc                     ; lptr += lold + 1
        lda lptr
        adc lold
        sta lptr
        bcc ++
        inc lptr+1
++      inc lptr
        bne ++
        inc lptr+1
++      jsr incy
        jsr loadln
        jsr fixtop
+       rts

; up a line (if there is one)
up      jsr commit
        lda cy
        ora cy+1
        beq +
up0     jsr prevst
        lda T0
        sta lptr
        lda T0+1
        sta lptr+1
        jsr decy
        jsr loadln
        jsr fixtop
+       rts

; T0 = the start of the line above lptr's, T1 its length
prevst  lda lptr
        sec
        sbc #1
        sta T0
        lda lptr+1
        sbc #0
        sta T0+1
        lda #0
        sta T1
-       lda T0+1                ; back to the text's start or a RETURN
        cmp #>TXT
        bne +
        lda T0
        cmp #<TXT
        beq ++
+       lda T0
        bne +
        dec T0+1
+       dec T0
        inc T1
        ldy #0
        lda (T0),y
        cmp #13
        bne -
        inc T0                  ; (that RETURN ends the line before)
        bne +
        inc T0+1
+       dec T1
++      rts

; the top line follows the cursor: cy within topy .. topy+ROWS-1
fixtop  lda cy+1                ; cy < topy: the top is the cursor's line
        cmp topy+1
        bcc ++
        bne +
        lda cy
        cmp topy
        bcs +
++      lda cy
        sta topy
        lda cy+1
        sta topy+1
        lda lptr
        sta topptr
        lda lptr+1
        sta topptr+1
        rts
+       sec                     ; cy - topy >= ROWS: the top down a line, again
        lda cy
        sbc topy
        tax
        lda cy+1
        sbc topy+1
        bne +
        cpx #ROWS
        bcc ++
+       lda topptr
        sta T0
        lda topptr+1
        sta T0+1
        jsr skipln
        lda T0
        sta topptr
        lda T0+1
        sta topptr+1
        inc topy
        bne fixtop
        inc topy+1
        jmp fixtop
++      rts

; T0 past its line's RETURN
skipln  ldy #0
-       lda (T0),y
        inc T0
        bne +
        inc T0+1
+       cmp #13
        bne -
        rts

; to line gline (0 = the first; past the end: the last), the top 6 lines above it
gotoln  jsr commit
        lda gline
        cmp nlines
        lda gline+1
        sbc nlines+1
        bcc +
        lda nlines
        sec
        sbc #1
        sta gline
        lda nlines+1
        sbc #0
        sta gline+1
+       lda gline
        sec
        sbc #6
        sta gtop
        lda gline+1
        sbc #0
        sta gtop+1
        bcs +
        lda #0
        sta gtop
        sta gtop+1
+       lda #<TXT
        sta T0
        lda #>TXT
        sta T0+1
        lda #0
        sta cy
        sta cy+1
-       lda cy                  ; the top line?
        cmp gtop
        bne +
        lda cy+1
        cmp gtop+1
        bne +
        lda T0
        sta topptr
        lda T0+1
        sta topptr+1
        lda cy
        sta topy
        lda cy+1
        sta topy+1
+       lda cy                  ; the line?
        cmp gline
        bne +
        lda cy+1
        cmp gline+1
        beq ++
+       jsr skipln
        jsr incy
        jmp -
++      lda T0
        sta lptr
        lda T0+1
        sta lptr+1
        jsr loadln
        jmp fixtop

; an empty text: one empty line
empty   lda #13
        sta TXT
        lda #<(TXT+1)
        sta tend
        lda #>(TXT+1)
        sta tend+1
        lda #1
        sta nlines
        lda #0
        sta nlines+1
home0   lda #0
        sta cx
        sta wantx
        sta hx
        sta cy
        sta cy+1
        sta topy
        sta topy+1
        lda #<TXT
        sta lptr
        sta topptr
        lda #>TXT
        sta lptr+1
        sta topptr+1
        jmp loadln

; the cursor inside its line; C set if the screen's left edge had to move
fixline lda cx
        cmp llen
        bcc fixh
        lda llen
        sta cx
fixh    lda cx                  ; hx: 0 while the cursor is in the first 40 columns
        sec
        sbc #39
        bcs +
        lda #0
+       cmp hx
        beq +
        sta hx
        sec
        rts
+       clc
        rts

; ============================================================================ the screen
scrinit lda #$4F                ; OctoVIC's page (the mailbox is in it)
        sta $D03F
        lda #$38
        sta $D03F
        lda #0
        sta octo
        lda $D61E
        cmp #$8C
        bne +
        inc octo
        lda #0
        sta OCTRL               ; nothing of OctoVIC's on the screen; the VIC's palette with
        sta $D60E               ; the start screen's navy and cyan
        sta $D60F
        lda #1
        sta $D619
        lda #6
        sta $D61A
        lda #28
        sta $D61B
        lda #32
        sta $D61C
        lda #92
        sta $D61D
        lda #3
        sta $D61A
        lda #120
        sta $D61B
        lda #220
        sta $D61C
        lda #255
        sta $D61D
        lda #$02
        sta OCTRL
+       lda #6
        sta $D020
        sta $D021
        lda #$17                ; upper and lower case
        sta $D018
        lda #$1B
        sta $D011
        lda #$C8
        sta $D016
        lda #$80                ; no SHIFT+C= case switching
        sta $0291
        lda #0
        sta $D015
        ldx #0                  ; a clear screen
-       lda #$20
        sta SCR,x
        sta SCR+$100,x
        sta SCR+$200,x
        sta SCR+$2E8,x
        lda #C_CODE
        sta COL,x
        sta COL+$100,x
        sta COL+$200,x
        sta COL+$2E8,x
        inx
        bne -
        ldx #39                 ; the rules and the key bar
-       lda #$40
        sta SCR+40,x
        sta SCR+22*40,x
        lda #C_RULE
        sta COL+40,x
        sta COL+22*40,x
        lda keybar,x
        sta SCR+24*40,x
        lda keycol,x
        sta COL+24*40,x
        dex
        bpl -
        ldx #7
-       lda ttl,x
        sta SCR+1,x
        lda #1
        sta COL+1,x
        dex
        bpl -
        rts

; the title row: the file's name (* when changed) and the cursor's line
title   ldx #0
-       cpx fnlen
        bcs +
        lda fname,x
        jsr p2s
        sta SCR+11,x
        lda #C_LABEL
        sta COL+11,x
        inx
        cpx #16
        bcc -
+       lda #' '
        ldy dirty
        bne +
        ldy dirty2
        beq ++
+       lda #'*'
++      sta SCR+11,x
        lda #1
        sta COL+11,x
-       inx
        cpx #18
        bcs +
        lda #' '
        sta SCR+11,x
        bne -
+       ldx #4
-       lda lntx,x
        sta SCR+29,x
        lda #C_HELP
        sta COL+29,x
        dex
        bpl -
        clc
        lda cy
        adc #1
        sta num
        lda cy+1
        adc #0
        sta num+1
        ldx #34
        ; (on into putnum)

; num as a decimal number on row 0 from column X, spaces after it
putnum  stx pcol
        lda #0
        sta pany
        ldx #0
pn_dig  ldy #0
-       lda num
        sec
        sbc p10l,x
        sta T1
        lda num+1
        sbc p10h,x
        bcc +
        sta num+1
        lda T1
        sta num
        iny
        bne -
+       tya
        bne pn_out
        lda pany
        bne pn_out
        cpx #4
        bne pn_skip
pn_out  tya
        ora #$30
        ldy pcol
        sta SCR,y
        lda #1
        sta COL,y
        sta pany
        inc pcol
pn_skip inx
        cpx #5
        bne pn_dig
        ldy pcol
        lda #' '
-       cpy #40
        bcs +
        sta SCR,y
        iny
        bne -
+       rts
p10l    !byte <10000, <1000, <100, <10, <1
p10h    !byte >10000, >1000, >100, >10, >1

; every code row
drawall jsr fixh
        jsr title
        lda topptr
        sta T0
        lda topptr+1
        sta T0+1
        lda topy
        sta lnum
        lda topy+1
        sta lnum+1
        lda #0
        sta row
dr_row  lda lnum                ; past the last line: empty rows
        cmp nlines
        lda lnum+1
        sbc nlines+1
        bcc +
        lda #0
        sta dlen
        jsr rowline
        jmp dr_next
+       lda lnum
        cmp cy
        bne dr_text
        lda lnum+1
        cmp cy+1
        bne dr_text
        lda #<LBUF              ; the cursor's line: from LBUF
        sta SRC
        lda #>LBUF
        sta SRC+1
        lda llen
        sta dlen
        jsr rowline
        lda lptr                ; on past it in the text
        sta T0
        lda lptr+1
        sta T0+1
        jsr skipln
        jmp dr_next
dr_text lda T0
        sta SRC
        lda T0+1
        sta SRC+1
        ldy #0
-       lda (T0),y
        cmp #13
        beq +
        iny
        cpy #MAXLEN
        bcc -
+       sty dlen
        jsr rowline
        jsr skipln
dr_next inc lnum
        bne +
        inc lnum+1
+       inc row
        lda row
        cmp #ROWS
        bcs +
        jmp dr_row
+       jmp curon0

; the cursor's row again
drawcur lda #<LBUF
        sta SRC
        lda #>LBUF
        sta SRC+1
        lda llen
        sta dlen
        sec
        lda cy
        sbc topy
        sta row
        jsr rowline
        jmp curon0

; row `row`: dlen characters at SRC from column hx on, coloured: labels, strings, comments
rowline lda row
        clc
        adc #TOPROW
        tax
        lda rowlo,x
        sta SP
        sta CP
        lda rowhi,x
        sta SP+1
        clc
        adc #>(COL-SCR)
        sta CP+1
        ldy #0                  ; a label: something in column 0 that isn't a comment
        sty cst
        lda dlen
        beq +
        lda (SRC),y
        cmp #' '
        beq +
        cmp #';'
        beq +
        lda #1
        sta cst
+       ldx #0                  ; X: the screen column, Y: the character
rl_next cpy dlen
        bcc +
        jmp blnk
+
        lda (SRC),y
        sta ch
        lda cst
        cmp #3
        beq c_rem
        cmp #2
        beq c_str
        lda ch
        cmp #';'
        bne +
        lda #3
        sta cst
        bne c_rem
+       cmp #$22
        bne +
        lda #2
        sta cst
        lda #C_STR
        bne c_put
+       cmp #' '
        bne +
        lda cst
        cmp #1
        bne +
        lda #0
        sta cst
+       lda cst
        beq +
        lda #C_LABEL
        bne c_put
+       lda #C_CODE
        bne c_put
c_rem   lda #C_REM
        bne c_put
c_str   lda ch
        cmp #$22
        bne +
        lda #0
        sta cst
+       lda #C_STR
c_put   sta ccol
        cpy hx                  ; on the screen?
        bcc +
        lda ch
        jsr p2s
        sty T1+7
        txa
        tay
        lda ch2
        sta (SP),y
        lda ccol
        sta (CP),y
        ldy T1+7
        inx
        cpx #40
        bcs ++
+       iny
        jmp rl_next
blnk    txa
        tay
        lda #' '
-       cpy #40
        bcs ++
        sta (SP),y
        iny
        bne -
++      rts

; the cursor: the character under it reversed
curpos  sec
        lda cy
        sbc topy
        clc
        adc #TOPROW
        tax
        lda rowlo,x
        sta SP
        lda rowhi,x
        sta SP+1
        lda cx
        sec
        sbc hx
        tay
        rts
curon0  lda #0
        sta curst
        rts
curon   lda curst
        bne +
curflip jsr curpos
        lda (SP),y
        eor #$80
        sta (SP),y
        lda curst
        eor #1
        sta curst
+       rts
curoff  lda curst
        beq +
        jmp curflip
+       rts

; PETSCII to a screen code (A, and ch2)
p2s     cmp #$20
        bcc ++
        cmp #$40
        bcc +
        cmp #$60
        bcc s40
        cmp #$80
        bcc s20
        cmp #$A0
        bcc ++
        cmp #$C0
        bcc s40
        cmp #$FF
        bcc s80
++      lda #$3F
+       sta ch2
        rts
s40     sec
        sbc #$40
        sta ch2
        rts
s20     sec
        sbc #$20
        sta ch2
        rts
s80     and #$7F
        sta ch2
        rts

; the message at X (low) Y (high) on the status row - screen codes, 0 at the end. Y: its length
status  lda #C_STAT
        sta stcol
status2 stx Q
        sty Q+1
        ldy #0
-       lda (Q),y
        beq +
        sta SCR+23*40,y
        lda stcol
        sta COL+23*40,y
        iny
        bne -
+       sty stlen
        lda #' '
-       cpy #40
        bcs +
        sta SCR+23*40,y
        iny
        bne -
+       ldy stlen
        rts

; ============================================================================ COMPILE
compile jsr commit
        lda octo
        bne +
        ldx #<m_nomain
        ldy #>m_nomain
        jsr status
        jmp loop
+       jsr vsrc                ; the source into VRAM too (for the MiSTer's Main)
        jsr boxopen
        jsr setname
        lda #<TXT
        sta MB_AL
        lda #>TXT
        sta MB_AH
        sec
        lda tend
        sbc #<TXT
        sta MB_LL
        lda tend+1
        sbc #>TXT
        sta MB_LH
        lda #1
        sta MB_ARG
        lda #0
        sta MB_VAL
        lda #$13
        jsr call
        beq +
        jmp mainerr
+       lda #0
        sta shown
        sta shown+1
        sta errlen
cl_next lda #<LOGBUF            ; the log, a line at a time: the box fills as Main goes
        sta MB_AL
        lda #>LOGBUF
        sta MB_AH
        lda shown
        sta MB_LL
        lda shown+1
        sta MB_LH
        lda #1
        sta MB_VAL
        lda #$14
        jsr call
        beq +
        jmp mainerr
+       lda MB_VAL
        sta cstate
        lda MB_RL
        sta errln
        lda MB_RH
        sta errln+1
        lda MB_LL
        sta total
        lda MB_LH
        sta total+1
        lda LOGBUF              ; a line came: into the box
        beq +
        jsr boxline
        inc shown
        bne ++
        inc shown+1
++      ldx #4                  ; (a moment, so the box can be read as it fills)
        jsr waitj
+       lda shown
        cmp total
        lda shown+1
        sbc total+1
        bcc cl_next             ; more lines to come
        lda cstate
        bne +
        ldx #5                  ; still compiling (on the MiSTer): ask again
        jsr waitj
        jmp cl_next
+       cmp #1
        bne c_bad
        ldx #<f_run             ; good: run it
        ldy #>f_run
        jsr boxfoot
        ldx #40
        jsr waitj
        jmp golaunch
c_bad   ldx #<f_key             ; errors: the box until a key (or 6 seconds), then the line
        ldy #>f_key
        jsr boxfoot
        lda #0
        sta $C6
        sta pgn
-       jsr GETIN
        bne +
        ldx #2
        jsr waitj
        inc pgn
        lda pgn
        cmp #150
        bcc -
+       lda errln
        ora errln+1
        beq c_noj
        lda errln               ; ACME counts lines from 1
        sec
        sbc #1
        sta gline
        lda errln+1
        sbc #0
        sta gline+1
        lda #0
        sta wantx
        jsr gotoln
        ldx #0                  ; the cursor on the line's first word
-       cpx llen
        bcs +
        lda LBUF,x
        cmp #' '
        bne +
        inx
        bne -
+       stx cx
        stx wantx
c_noj   jsr scrinit
        jsr drawall
        lda errlen
        bne +
        ldx #<m_nocomp
        ldy #>m_nocomp
        jsr status
        jmp loop
+       ldy #0                  ; the first error, in red, on the status row
-       cpy errlen
        bcs +
        lda errmsg,y
        jsr p2s
        sta SCR+23*40,y
        lda #C_ERR
        sta COL+23*40,y
        iny
        cpy #40
        bcc -
+       lda #' '
-       cpy #40
        bcs +
        sta SCR+23*40,y
        iny
        bne -
+       jmp loop

mainerr pha                     ; Main said no (or didn't answer)
        jsr scrinit
        jsr drawall
        pla
        ldx #<m_noreply
        ldy #>m_noreply
        cmp #$FE
        beq +
        ldx #<m_mainno
        ldy #>m_mainno
+       jsr status
        jmp loop

; X jiffies
waitj   lda $A2
-       cmp $A2
        beq -
        dex
        bne waitj
        rts

; the file's name into the mailbox
setname lda #0
        sta MB_NCLR
        ldx #0
-       cpx fnlen
        bcs +
        lda fname,x
        sta MB_NAME
        inx
        bne -
+       rts

; the request in A, numbered; wait for Main (20 s). Z set if done; A the status ($FE no answer)
call    sta lastcmd
        lda #$4F
        sta $D03F
        lda #$38
        sta $D03F
        lda #20
        sta secs
        lda #50
        sta jifs
        inc seq
        lda seq
        sta MB_SEQ
        lda lastcmd
        sta MB_CMD
        lda $A2
        sta lastj
-       lda MB_ST
        cmp #$01
        beq +
        ldx MB_RSEQ
        cpx seq
        beq ++
+       lda $A2
        cmp lastj
        beq -
        sta lastj
        dec jifs
        bne -
        lda #50
        sta jifs
        dec secs
        bne -
        lda #$FE
++      cmp #$02
        rts

; the source into VRAM at $FE0000
vsrc    lda #0
        sta VADDR
        sta VADDR+1
        lda #VSRC
        sta VADDR+2
        lda #1
        sta VINC
        lda #<TXT
        sta P
        lda #>TXT
        sta P+1
        ldy #0
-       lda P
        cmp tend
        bne +
        lda P+1
        cmp tend+1
        beq ++
+       lda (P),y
        sta VDATA
        inc P
        bne -
        inc P+1
        bne -
++
vs_wait lda $D608               ; until OctoVIC's write queue is empty (Main reads VRAM)
        and #1
        bne vs_wait
        rts

; --- the box: rows 5-18, columns 1-38; the log in rows 6-17, columns 2-37
BOXT    = 5
BOXB    = 18
boxopen ldx #BOXT
--      lda rowlo,x
        sta SP
        sta CP
        lda rowhi,x
        sta SP+1
        clc
        adc #>(COL-SCR)
        sta CP+1
        ldy #1
-       lda #' '
        cpx #BOXT
        bne +
        lda #$40
+       cpx #BOXB
        bne +
        lda #$40
+       cpy #1
        bne +
        lda #$5D
+       cpy #38
        bne +
        lda #$5D
+       sta (SP),y
        lda #C_LABEL
        sta (CP),y
        iny
        cpy #39
        bcc -
        inx
        cpx #BOXB+1
        bcc --
        lda #$70                ; the corners
        sta SCR+BOXT*40+1
        lda #$6E
        sta SCR+BOXT*40+38
        lda #$6D
        sta SCR+BOXB*40+1
        lda #$7D
        sta SCR+BOXB*40+38
        ldy #0                  ; the title: Compiling, the name
-       lda boxttl,y
        beq +
        sta SCR+BOXT*40+3,y
        lda #1
        sta COL+BOXT*40+3,y
        iny
        bne -
+       ldx #0
-       cpx fnlen
        bcs +
        lda fname,x
        jsr p2s
        sta SCR+BOXT*40+3,y
        lda #C_STR
        sta COL+BOXT*40+3,y
        iny
        inx
        cpx #20
        bcc -
+       lda #' '
        sta SCR+BOXT*40+3,y
        lda #0
        sta boxrow
        lda #C_CODE
        sta lcol
        ldx #<m_comp
        ldy #>m_comp
        jmp status

; a line of the log (LOGBUF, ends with RETURN) into the box, which scrolls when full
boxline lda boxrow
        cmp #12
        bcc +
        jsr boxscrl
        lda #11
        sta boxrow
+       clc
        adc #BOXT+1
        tax
        lda rowlo,x
        sta SP
        sta CP
        lda rowhi,x
        sta SP+1
        clc
        adc #>(COL-SCR)
        sta CP+1
        lda LOGBUF              ; its colour from how it starts
        cmp #' '
        beq bl_draw             ; (a line carried on: as the one before)
        ldx #C_CODE
        cmp #$C5                ; Error
        beq bl_err
        cmp #$CE                ; Not compiled
        beq bl_err
        cmp #$D7                ; Warning
        bne +
        ldx #C_STAT
+       cmp #$CF                ; OK
        bne +
        ldx #C_OK
+       stx lcol
        jmp bl_draw
bl_err  lda #C_ERR
        sta lcol
        lda errlen              ; the first error kept for the status row
        bne bl_draw
        ldy #0
-       lda LOGBUF,y
        cmp #13
        beq +
        sta errmsg,y
        iny
        cpy #40
        bcc -
+       sty errlen
bl_draw ldy #0
-       lda LOGBUF,y
        cmp #13
        beq +
        jsr p2s
        sty T1+7
        tya
        clc
        adc #2
        tay
        lda ch2
        sta (SP),y
        lda lcol
        sta (CP),y
        ldy T1+7
        iny
        cpy #36
        bcc -
+       tya                     ; the rest of the row empty
        clc
        adc #2
        tay
        lda #' '
-       cpy #38
        bcs +
        sta (SP),y
        iny
        bne -
+       inc boxrow
        rts

boxscrl ldx #BOXT+1             ; the box's rows up one
--      lda rowlo,x
        sta SP
        sta CP
        lda rowhi,x
        sta SP+1
        clc
        adc #>(COL-SCR)
        sta CP+1
        lda rowlo+1,x
        sta Q
        sta P
        lda rowhi+1,x
        sta Q+1
        clc
        adc #>(COL-SCR)
        sta P+1
        ldy #2
-       lda (Q),y
        sta (SP),y
        lda (P),y
        sta (CP),y
        iny
        cpy #38
        bcc -
        inx
        cpx #BOXB-1
        bcc --
        rts

; the box's bottom line: the message at X/Y
boxfoot stx Q
        sty Q+1
        ldy #0
-       lda (Q),y
        beq +
        sta SCR+BOXB*40+3,y
        lda #1
        sta COL+BOXB*40+3,y
        iny
        bne -
+       rts

; ============================================================================ running it
; the editor and its source into VRAM $FF0000, the launcher into the tape buffer, then GO
golaunch
        jsr stash
        ldx #stubend-stubsrc-1
-       lda stubsrc,x
        sta STUB,x
        dex
        cpx #$FF
        bne -
        ldx #goend-gosrc-1
-       lda gosrc,x
        sta LAUNCH,x
        dex
        cpx #$FF
        bne -
        jmp s_go

stash   lda #0                  ; the header: 'O', the build, the pages from $0801
        sta VADDR
        sta VADDR+1
        lda #VSTASH
        sta VADDR+2
        lda #1
        sta VINC
        lda #'O'
        sta VDATA
        lda #BUILD
        sta VDATA
        sec
        lda tend+1
        sbc #>$0801
        clc
        adc #1
        sta VDATA
        lda #<$0801
        sta P
        lda #>$0801
        sta P+1
        ldy #0
-       lda P
        cmp tend
        bne +
        lda P+1
        cmp tend+1
        beq ++
+       lda (P),y
        sta VDATA
        inc P
        bne -
        inc P+1
        bne -
++      rts

; C clear if VRAM $FF0000 holds this build's copy (VDATA then at its page count)
stashok lda octo
        beq ++
        lda #0
        sta VADDR
        sta VADDR+1
        lda #VSTASH
        sta VADDR+2
        lda #1
        sta VINC
        lda VDATA
        cmp #'O'
        bne ++
        lda VDATA
        cmp #BUILD
        bne ++
        clc
        rts
++      sec
        rts

; the copy back (after stashok): the code is this very build's, so it lands on itself
unstash ldx VDATA
        lda #<$0801
        sta P
        lda #>$0801
        sta P+1
        ldy #0
-       lda VDATA
        sta (P),y
        iny
        bne -
        inc P+1
        dex
        bne -
        rts

; the launcher, run at $0100 (the bottom of the stack page: Main's load can't reach it)
gosrc
!pseudopc LAUNCH {
s_go    inc seq                 ; GO: Main puts the program into RAM, over the editor
        lda seq                 ; (the name is still in the mailbox from COMPILE)
        sta MB_SEQ
        lda #$15
        sta MB_CMD
        ldx #0
        ldy #0
-       lda MB_ST
        cmp #$01
        beq +
        lda MB_RSEQ
        cmp seq
        beq ++
+       dex
        bne -
        dey
        bne -
        lda #$FE
        bne s_fail
++      lda MB_ST
        cmp #$02
        bne s_fail
        ldx #4                  ; BASIC's program end, its variables after it
-       lda MB_LL
        sta $2D,x
        lda MB_LH
        sta $2E,x
        dex
        dex
        bpl -
        lda MB_RL
        sta s_at
        lda MB_RH
        sta s_at+1
        sei
        ldx #$FF
        txs
        jsr s_reset
        sta $D03F               ; (A = 0: OctoVIC's page shut, as for any program)
        sta $C6
        lda #<s_nmi
        sta $0318
        lda #>s_nmi
        sta $0319
        cli
        lda s_at                ; at $0801: RUN it, as BASIC would
        cmp #$01
        bne +
        lda s_at+1
        cmp #$08
        bne +
        jsr $A533
        jsr $A659
        jmp $A7AE
+       jmp (s_at)
s_fail  sta failst              ; (the editor is still there: Main put nothing in)
        jmp gofail
s_at    !word 0
}
goend
!if goend - gosrc > $A0 { !error "the launcher is too long" }

; the RUN/STOP+RESTORE handler, kept in the tape buffer at $0334 (no tape here) while a program runs
stubsrc
!pseudopc STUB {

; RUN/STOP+RESTORE: the editor back from VRAM $FF0000
s_nmi   pha
        lda #$7F
        sta $DC00
        lda $DC01
        bpl +
        pla
        jmp $FE47               ; RESTORE alone: as always
+       sei
        ldx #$FF
        txs
        jsr s_reset
        lda VDATA               ; this build's copy there?
        cmp #'O'
        bne s_ready
        lda VDATA
        cmp #BUILD
        bne s_ready
        ldx VDATA               ; its pages
        lda #$01
        sta $FB
        lda #$08
        sta $FC
        ldy #0
-       lda VDATA
        sta ($FB),y
        iny
        bne -
        inc $FC
        dex
        bne -
        cli
        jmp $0810
s_ready cli
        jmp ($A002)             ; no copy (a program used the top of VRAM): READY

; the machine as after RUN/STOP+RESTORE, OctoVIC off, the SIDs quiet, VRAM at the copy
s_reset cld
        jsr $FDA3
        jsr $FD15
        jsr $E518
        lda #$4F
        sta $D03F
        lda #$38
        sta $D03F
        lda #1
        sta VINC
        lda #VSTASH
        sta VADDR+2
        lda #0
        sta VADDR
        sta VADDR+1
        sta $D605
        sta $D60E
        sta $D60F
        ldx #3                  ; the eight SIDs' volume
-       ldy s_sids,x
        sta $D418,y
        sta $D518,y
        dex
        bpl -
        rts
s_sids  !byte $00,$20,$80,$A0
}
stubend
!if stubend - stubsrc > $0400 - STUB { !error "the stub is too long for the tape buffer" }

; GO failed: the editor carries on
gofail  cld
        lda #$36
        sta $01
        jsr scrinit
        jsr drawall
        ldx #<m_gofail
        ldy #>m_gofail
        jsr status
        jmp loop

; ============================================================================ F3 F5 F7
k_load  jsr commit
        ldx #<m_lname
        ldy #>m_lname
        jsr askname
        bcs +
        jsr loadfile
+       jsr drawall
        jmp loop

k_save  jsr commit
        ldx #<m_sname
        ldy #>m_sname
        jsr askname
        bcs +
        jsr savefile
        jsr title
        jmp loop
+       jsr drawall
        jmp loop

k_exit  jsr commit
        lda octo                ; a copy in VRAM, for LOAD and RUN later
        beq +
        jsr stash
+       lda #0
        sta OCTRL
        sta $D03F
        lda #$37
        sta $01
        lda #0                  ; the screen as BASIC's (the KERNAL's own set-up)
        sta $0291
        jsr $E518
        lda #<pend              ; BASIC's variables after the editor (RUN starts it again)
        sta $2D
        sta $2F
        sta $31
        lda #>pend
        sta $2E
        sta $30
        sta $32
        lda #$93
        jsr CHROUT
        ldx #0
-       lda m_bye,x
        beq +
        jsr CHROUT
        inx
        bne -
+       jmp READYV

; a file name on the status row after the prompt at X/Y (fname, changed by typing).
; RETURN: C clear; RUN/STOP: C set
askname stx apl
        sty aph
an_draw lda #1
        sta stcol
        ldx apl
        ldy aph
        jsr status2             ; the prompt (Y: its length)
        ldx #0                  ; the name after it
-       cpx fnlen
        bcs +
        lda fname,x
        jsr p2s
        sta SCR+23*40,y
        lda #C_LABEL
        sta COL+23*40,y
        iny
        inx
        bne -
+       lda #$A0                ; the cursor
        sta SCR+23*40,y
        lda #1
        sta COL+23*40,y
an_key  jsr GETIN
        beq an_key
        cmp #13
        bne +
        lda fnlen
        beq an_key
        clc
        rts
+       cmp #3
        bne +
        sec
        rts
+       cmp #20
        bne +
        lda fnlen
        beq an_key
        dec fnlen
        jmp an_draw
+       cmp #$20
        bcc an_key
        cmp #$60
        bcc +
        cmp #$C1
        bcc an_key
        cmp #$DB
        bcs an_key
+       ldx fnlen
        cpx #16
        bcs an_key
        sta fname,x
        inc fnlen
        jmp an_draw

; the disk's command channel: its message into dskmsg (screen codes); C set unless 00
dskerr  ldx #15
        jsr CHKIN
        ldy #0
-       jsr CHRIN
        cmp #13
        beq +
        jsr p2s
        cpy #38
        bcs ++
        sta dskmsg,y
        iny
++      lda $90
        beq -
+       sty dsklen
        jsr CLRCHN
        lda dsklen
        beq +
        lda dskmsg
        cmp #$30
        bne +
        lda dskmsg+1
        cmp #$30
        bne +
        clc
        rts
+       sec
        rts

dskshow ldy #0                  ; Disk: and the drive's message, in red
-       lda m_disk,y
        beq +
        sta SCR+23*40,y
        lda #C_ERR
        sta COL+23*40,y
        iny
        bne -
+       ldx #0
-       cpx dsklen
        bcs +
        lda dskmsg,x
        sta SCR+23*40,y
        lda #C_ERR
        sta COL+23*40,y
        inx
        iny
        cpy #40
        bcc -
+       lda #' '
-       cpy #40
        bcs +
        sta SCR+23*40,y
        iny
        bne -
+       rts

; the name with ",S,R" (A = 'R') or "@0:" and ",S,W" (A = 'W') into fbuf; X its length
mkname  sta T1+4
        ldx #0
        cmp #'W'
        bne +
        lda #'@'
        sta fbuf
        lda #'0'
        sta fbuf+1
        lda #':'
        sta fbuf+2
        ldx #3
+       ldy #0
-       cpy fnlen
        bcs +
        lda fname,y
        sta fbuf,x
        inx
        iny
        bne -
+       lda #','
        sta fbuf,x
        inx
        lda #'S'
        sta fbuf,x
        inx
        lda #','
        sta fbuf,x
        inx
        lda T1+4
        sta fbuf,x
        inx
        rts

; channel 15 to drive 8 open; C set: no drive
open15  lda #0
        jsr SETNAM
        lda #15
        ldx #8
        ldy #15
        jsr SETLFS
        jsr OPEN
        rts
; file 2 with the name in fbuf (X long)
open2   txa
        ldx #<fbuf
        ldy #>fbuf
        jsr SETNAM
        lda #2
        ldx #8
        ldy #2
        jsr SETLFS
        jmp OPEN
close2  lda #2
        jsr CLOSE
        lda #15
        jmp CLOSE

; fname from drive 8 into the text
loadfile
        ldx #<m_loading
        ldy #>m_loading
        jsr status
        jsr open15
        bcc +
        jmp nodrive
+       lda #'R'
        jsr mkname
        jsr open2
        jsr dskerr
        bcc +
        jsr dskshow
        jmp close2
+       ldx #2
        jsr CHKIN
        lda #<TXT
        sta P
        lda #>TXT
        sta P+1
        lda #0
        sta nlines
        sta nlines+1
        sta lcount
        sta cutx
ld_next jsr CHRIN
        sta ch
        lda $90
        sta dstat
        lda ch
        cmp #$0A
        beq ld_st
        cmp #13
        beq ld_cr
        cmp #9
        bne +
        lda #' '
        sta ch
+       cmp #$20
        bcc ld_st
        lda lcount              ; a line too long: cut there
        cmp #MAXLEN
        bcc +
        lda #1
        sta cutx
        lda #13
        jsr ld_put
        lda #0
        sta lcount
+       lda ch
        jsr ld_put
        inc lcount
        jmp ld_st
ld_cr   lda #13
        jsr ld_put
        lda #0
        sta lcount
ld_st   lda dstat
        bne ld_end
        lda P+1                 ; full?
        cmp #>(TXTMAX-$100)
        bcc ld_next
        lda #1
        sta cutx
ld_end  jsr CLRCHN
        jsr close2
        lda P                   ; the last line ends with RETURN too
        cmp #<TXT
        bne +
        lda P+1
        cmp #>TXT
        beq ++
+       lda lcount
        beq +++
++      lda #13
        jsr ld_put
+++     lda P
        sta tend
        lda P+1
        sta tend+1
        lda #0
        sta dirty2
        jsr home0
        jsr drawall
        ldx #<m_loaded
        ldy #>m_loaded
        lda cutx
        beq +
        ldx #<m_cut
        ldy #>m_cut
+       jmp status
ld_put  ldy #0
        sta (P),y
        cmp #13
        bne +
        inc nlines
        bne +
        inc nlines+1
+       inc P
        bne +
        inc P+1
+       rts
nodrive ldx #<m_nodrive
        ldy #>m_nodrive
        jmp status

; the text to drive 8 as fname (a SEQ file, replacing one of that name)
savefile
        ldx #<m_saving
        ldy #>m_saving
        jsr status
        jsr open15
        bcc +
        jmp nodrive
+       lda #'W'
        jsr mkname
        jsr open2
        jsr dskerr
        bcc +
        jsr dskshow
        jmp close2
+       ldx #2
        jsr CHKOUT
        lda #<TXT
        sta P
        lda #>TXT
        sta P+1
        ldy #0
-       lda P
        cmp tend
        bne +
        lda P+1
        cmp tend+1
        beq ++
+       lda (P),y
        jsr CHROUT
        ldy #0
        inc P
        bne -
        inc P+1
        bne -
++      jsr CLRCHN
        lda #2
        jsr CLOSE
        jsr dskerr
        bcc +
        jsr dskshow
        lda #15
        jmp CLOSE
+       lda #15
        jsr CLOSE
        lda #0
        sta dirty2
        ldx #<m_saved
        ldy #>m_saved
        jmp status

; ============================================================================ data
rowlo
!for r, 0, 24 { !byte <(SCR + r*40) }
rowhi
!for r, 0, 24 { !byte >(SCR + r*40) }

ttl     !scr "OCTOCODE"
lntx    !scr "Line "
boxttl  !scr " Compiling ", 0
fdef    !pet "hello.asm"
fdefl   = * - fdef
keybar  !scr "F1 Compile  F3 Load  F5 Save  F7 Exit   "
keycol  !byte 1,1,15,15,15,15,15,15,15,15,15,15,1,1,15,15,15,15,15,15,15,1,1,15,15,15,15,15,15,15,1,1,15,15,15,15,15,15,15,15
m_bye   !pet "octocode: your code is kept.", 13, "run takes you back to it.", 13, 0
m_hello !scr "Welcome back. F1 compiles and runs it.", 0
m_back  !scr "Back! Change something, then F1 again.", 0
m_loading !scr "Loading from the disk...", 0
m_loaded !scr "Change something, then F1 to run it!", 0
m_cut   !scr "Loaded - some long lines were cut.", 0
m_full  !scr "No room for more.", 0
m_long  !scr "That line would be too long.", 0
m_nomain !scr "No Octophonic Main here: can't compile.", 0
m_noreply !scr "Octophonic Main didn't answer.", 0
m_mainno !scr "Octophonic Main couldn't compile it.", 0
m_nocomp !scr "Not compiled - see the box.", 0
m_gofail !scr "Couldn't start the program.", 0
m_comp  !scr "Compiling...", 0
m_lname !scr "Load: ", 0
m_sname !scr "Save as: ", 0
m_saving !scr "Saving to the disk...", 0
m_saved !scr "Saved.", 0
m_nodrive !scr "No disk drive 8.", 0
f_run   !scr " Running it... ", 0
f_key   !scr " Any key: to the line ", 0
m_disk  !scr "Disk: ", 0

; ---- variables (0 in the PRG; alive is $A5 once the editor has run)
alive   !byte 0
octo    !byte 0
tend    !word 0
nlines  !word 0
cy      !word 0
cx      !byte 0
wantx   !byte 0
hx      !byte 0
lptr    !word 0
lold    !byte 0
llen    !byte 0
dirty   !byte 0
dirty2  !byte 0
topy    !word 0
otop    !word 0
topptr  !word 0
gtop    !word 0
gline   !word 0
indent  !byte 0
pgn     !byte 0
fname   !fill 17, 0
fnlen   !byte 0
fbuf    !fill 26, 0
errmsg  !fill 40, 0
errlen  !byte 0
errln   !word 0
shown   !word 0
total   !word 0
cstate  !byte 0
boxrow  !byte 0
lcol    !byte 0
row     !byte 0
lnum    !word 0
dlen    !byte 0
ch      !byte 0
ch2     !byte 0
cst     !byte 0
ccol    !byte 0
curst   !byte 0
blink   !byte 0
stcol   !byte 0
stlen   !byte 0
num     !word 0
pcol    !byte 0
pany    !byte 0
apl     !byte 0
aph     !byte 0
lastcmd !byte 0
secs    !byte 0
jifs    !byte 0
lastj   !byte 0
failst  !byte 0
lcount  !byte 0
cutx    !byte 0
dstat   !byte 0
dskmsg  !fill 40, 0
dsklen  !byte 0
LBUF    !fill 82, 0
pend
!if pend > TXT { !error "the editor runs into the source" }
