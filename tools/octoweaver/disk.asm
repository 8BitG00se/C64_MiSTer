; disk.asm - text entry, save / load (.OWS) and export (NAME.OWP, NAME PLAY) with the OctoPaint disk guard.  ACME.
; The KERNAL is switched in ($01 = $36) only while the disk is busy, the raster interrupt is off, and the bytes go one at a time.
!zone disk
SETLFS  = $FFBA
SETNAM  = $FFBD
OPEN    = $FFC0
CLOSE   = $FFC3
CHKIN   = $FFC6
CHKOUT  = $FFC9
CLRCHN  = $FFCC
CHRIN   = $FFCF
CHROUT  = $FFD2

; ---- text entry on row 21 after the prompt at X:Y; ip is free.  Result in tbuf / tn; carry set = RETURN, clear = RUN/STOP
textin  jsr msgp
        lda #0
        sta msgt
        sta tn
@show   ldx #22
        ldy #21
        jsr txtpos
        lda #1
        sta tcol
        ldx #0
@c      cpx tn
        beq @cur
        stx t7
        lda tbuf,x
        and #$3f
        jsr putc
        ldx t7
        inx
        bne @c
@cur    lda #$e0                ; the cursor: a reversed space... drawn as a block
        jsr putc
        lda #$20
        jsr putc
@k      jsr waitkey
        cmp #$0d
        beq @ret
        cmp #$03
        beq @esc
        cmp #$14
        beq @del
        cmp #$20
        bcc @k
        cmp #$5b
        bcs @k
        ldx tn
        cpx tmax
        bcs @k
        sta tbuf,x
        inc tn
        jmp @show
@del    lda tn
        beq @k
        dec tn
        jmp @show
@ret    jsr clr_msg
        sec
        rts
@esc    jsr clr_msg
        clc
        rts

; N: the song's name
l_sname ldx #<m_sname
        ldy #>m_sname
        lda #11
        sta tmax
        jsr textin
        bcc @r
        ldx #0
@c      cpx tn
        bcs @p
        lda tbuf,x
        bne @s
@p      lda #$20
@s      sta SONG+H_SNAME,x
        inx
        cpx #16
        bne @c
        lda #1
        sta dirty
@r      rts
m_sname !scr "song name: ", 0

; R: the current track's job name
l_tname ldx #<m_tname
        ldy #>m_tname
        lda #6
        sta tmax
        jsr textin
        bcc @r
        ldx ctrk
        lda jnoff,x
        tax
        ldy #0
@c      cpy tn
        bcs @p
        lda tbuf,y
        jmp @s
@p      lda #$20
@s      sta SONG+H_NAMES,x
        inx
        iny
        cpy #6
        bne @c
        lda #1
        sta dirty
@r      rts
m_tname !scr "job name: ", 0

; ---- the file names: the song's name (11 letters at most, no trailing spaces) and a ending
; A = 0 ".OWS", 1 ".OWP", 2 " PLAY" -> fname / fnlen
mkname  pha
        ldx #0
@c      cpx #11
        beq @e
        lda SONG+H_SNAME,x
        sta fname,x
        inx
        bne @c
@e      dex                     ; trim trailing spaces
@t      bmi @empty
        lda fname,x
        cmp #$20
        bne @got
        dex
        bpl @t
@empty  ldx #3
        ldy #3
@sg     lda sgname,y
        sta fname,y
        dey
        bpl @sg
        jmp @suf
@got
@suf    inx                     ; X = the next free place
        pla
        tay
        lda sufoff,y
        sta t0
        lda suflen,y
        sta t1
        ldy t0
@sc     lda sufs,y
        sta fname,x
        inx
        iny
        dec t1
        bne @sc
        stx fnlen
        rts
sgname  !text "SONG"
sufs    !text ".OWS", ".OWP", " PLAY"
sufoff  !byte 0, 4, 8
suflen  !byte 4, 4, 5

; the command buffer: cb_clear, cb_str X:Y (zero terminated), cb_name
cb_clear
        lda #0
        sta clen
        rts
cb_str  stx jp
        sty jp+1
        ldy #0
@l      lda (jp),y
        beq @r
        ldx clen
        sta cbuf,x
        inc clen
        iny
        bne @l
@r      rts
cb_name ldy #0
@l      cpy fnlen
        beq @r
        lda fname,y
        ldx clen
        sta cbuf,x
        inc clen
        iny
        bne @l
@r      rts
setnm_cb
        lda clen
        ldx #<cbuf
        ldy #>cbuf
        jmp SETNAM

; ---- the drive's message into ebuf: carry clear if it starts "00"
rderr   ldx #15
        jsr CHKIN
        bcc @ok
        lda #0
        sta elen
        sec
        rts
@ok     lda #0
        sta elen
        sta ni
@l      inc ni
        beq @e
        jsr CHRIN
        cmp #13
        beq @e
        ldy elen
        cpy #30
        bcs @l
        sta ebuf,y
        inc elen
        jmp @l
@e      jsr CLRCHN
        lda elen
        cmp #2
        bcc @bad
        lda ebuf
        cmp #'0'
        bne @bad
        lda ebuf+1
        cmp #'0'
        bne @bad
        clc
        rts
@bad    sec
        rts

io_begin
        sei
        lda #0
        sta $d01a
        lda #$ff
        sta $d019
        lda #$36
        sta $01
        lda #0
        sta ioerr
        sta bcnt
        sta bcnt+1
        sta elen
        rts
io_end  lda #$35
        sta $01
        lda #$ff
        sta $dc00
        jsr irq_on
        jsr eq_reset
        ldx #0                  ; the progress row off
        ldy #22
        jsr txtpos
        ldx #40
        lda #1
        sta tcol
        jmp pspaces

; both channels closed, the interrupt back, the result on the message row
io_finish
        jsr CLRCHN
        lda #2
        jsr CLOSE
        lda #15
        jsr CLOSE
        jsr io_end
        lda #1
        sta dirty
        jsr clr_msg
        lda ioerr
        beq @ok
        cmp #1
        beq @kern
        cmp #2
        beq @drv
        cmp #4
        beq @bad
        jsr msg
        !scr "the file ends too soon", 0
        rts
@bad    jsr msg
        !scr "that is not an ows1 song", 0
        rts
@kern   jsr msg
        !scr "disk error ", 0
        lda ioacc
        jmp pdec3
@drv    jsr msg
        !scr "drive: ", 0
        ldx #0
@d      cpx elen
        beq @r
        lda ebuf,x
        and #$3f
        stx t7
        jsr putc
        ldx t7
        inx
        bne @d
@ok     ldx #<m_done
        ldy #>m_done
        lda okmsg
        beq @s1
        cmp #1
        beq @s2
        ldx #<m_expd
        ldy #>m_expd
        jmp msgp
@s1     ldx #<m_saved
        ldy #>m_saved
        jmp msgp
@s2     ldx #<m_loaded
        ldy #>m_loaded
        jmp msgp
@r      rts
m_done   !scr "done", 0
m_saved  !scr "song saved", 0
m_loaded !scr "song loaded", 0
m_expd   !scr "exported .owp and play files", 0
m_disk   !scr "disk in drive 8? y/n", 0

io_fail ldx iosp
        txs
        jmp io_finish

; one byte out / in with the status checked and the progress drawn
outb    jsr CHROUT
        lda $90
        beq bump
        lda #3                  ; the drive says no
        sta ioacc
        lda #1
        sta ioerr
        jmp io_fail
bump    inc bcnt
        bne @r
        inc bcnt+1
@r      lda bcnt
        bne @d
        lda bcnt+1
        and #1
        bne @d
        lda bcnt+1              ; a cell for every 512 bytes
        lsr
        tax
        lda #160
        sta SCREEN+22*40,x
        lda #7
        sta COLRAM+22*40,x
@d      rts
inb     lda $90
        bne @end
        jsr CHRIN
        pha
        jsr bump
        pla
        rts
@end    lda #6
        sta ioerr
        jmp io_fail

; open channel 15 (the drive's messages) and the file with the name in cbuf (the caller built it): X = channel type given
; ok_open: the name is in cbuf, clen set
openfile
        lda #0
        jsr SETNAM
        lda #15
        ldx #8
        ldy #15
        jsr SETLFS
        jsr OPEN
        bcc @a
        jmp opener
@a      jsr setnm_cb
        lda #2
        ldx #8
        ldy #2
        jsr SETLFS
        jsr OPEN
        bcc @b
        jmp opener
@b      jsr rderr
        bcc @c
        lda #2
        sta ioerr
        jmp io_fail
@c      rts
opener  sta ioacc
        lda #1
        sta ioerr
        jmp io_fail

; scratch the old file, open NAME,x,W
openw   jsr cb_clear
        ldx #<s_scr
        ldy #>s_scr
        jsr cb_str
        jsr cb_name
        jsr setnm_cb
        lda #15
        ldx #8
        ldy #15
        jsr SETLFS
        jsr OPEN
        bcc @a
        jmp opener
@a      jsr rderr               ; (the answer, files scratched or not found, is not needed)
        jsr cb_clear
        jsr cb_name
        ldx #<s_w
        ldy #>s_w
        lda ftype
        beq @s
        ldx #<s_pw
        ldy #>s_pw
@s      jsr cb_str
        jsr setnm_cb
        lda #2
        ldx #8
        ldy #2
        jsr SETLFS
        jsr OPEN
        bcc @b
        jmp opener
@b      jsr rderr
        bcc @c
        lda #2
        sta ioerr
        jmp io_fail
@c      ldx #2
        jsr CHKOUT
        bcc @d
        jmp opener
@d      rts
s_scr   !text "S0:", 0
s_w     !text ",S,W", 0
s_pw    !text ",P,W", 0
s_sr    !text ",S,R", 0

; the file is complete: its close tells whether the disk took it
closew  jsr CLRCHN
        lda #2
        jsr CLOSE
        jsr rderr
        bcc @r
        lda #2
        sta ioerr
        jmp io_fail
@r      rts

; ---- W: save the song
l_save  ldx #<m_disk
        ldy #>m_disk
        jsr askyn
        bcc @r
        tsx
        stx iosp
        lda #0
        sta okmsg
        sta ftype
        jsr prep
        lda #0
        jsr mkname
        jsr io_begin
        jsr openw
        ldx #0
@h      lda s_ows,x
        stx t7
        jsr outb
        ldx t7
        inx
        cpx #4
        bne @h
        lda #<SONG
        sta ip
        lda #>SONG
        sta ip+1
        lda #<SONGEND
        sta jp
        lda #>SONGEND
        sta jp+1
        jsr plain_out
        jsr closew
        jmp io_finish
@r      rts
s_ows   !text "OWS1"

; the player stops and the SIDs are quiet before the disk is used
prep    sei
        jsr pl_stop
        cli
        rts

; ip .. jp (exclusive) as they are
plain_out
        ldy #0
@l      lda ip
        cmp jp
        bne @b
        lda ip+1
        cmp jp+1
        beq @d
@b      lda (ip),y
        jsr outb
        inc ip
        bne @l
        inc ip+1
        bne @l
@d      rts

; ---- L: load a song: first into the stage
l_load  ldx #<m_disk
        ldy #>m_disk
        jsr askyn
        bcs @go
        rts
@go     tsx
        stx iosp
        lda #1
        sta okmsg
        jsr prep
        lda #0
        jsr mkname
        jsr io_begin
        jsr cb_clear
        jsr cb_name
        ldx #<s_sr
        ldy #>s_sr
        jsr cb_str
        jsr openfile
        ldx #2
        jsr CHKIN
        bcc @h
        jmp opener
@h      ldx #0                  ; OWS1
@v      stx t7
        jsr inb
        ldx t7
        cmp s_ows,x
        bne @bad
        inx
        cpx #4
        bne @v
        lda #<STAGE
        sta ip
        lda #>STAGE
        sta ip+1
        lda #55
        sta t6
@pg     ldy #0
@b      sty t7
        jsr inb
        ldy t7
        sta (ip),y
        iny
        bne @b
        inc ip+1
        dec t6
        bne @pg
        lda #<STAGE             ; whole: now into the song
        sta ip
        lda #>STAGE
        sta ip+1
        lda #<SONG
        sta jp
        lda #>SONG
        sta jp+1
        lda #55
        sta t6
@cp     ldy #0
@c      lda (ip),y
        sta (jp),y
        iny
        bne @c
        inc ip+1
        inc jp+1
        dec t6
        bne @cp
        sei
        jsr pl_inval
        cli
        lda #0
        sta ctrk
        sta cbar
        sta cstep
        sta mode
        inc clrf
        ldx #7
@m      sta mstate,x
        sta tmute,x
        dex
        bpl @m
        jsr load_csnd
        jmp io_finish
@bad    lda #4
        sta ioerr
        jmp io_fail
@r      rts

; ---- X: export  NAME.OWP (the player and the song: $1000 .. SONGEND) and  NAME PLAY (the whole program, a memory image from $0801)
l_export
        ldx #<m_disk
        ldy #>m_disk
        jsr askyn
        bcc @r
        tsx
        stx iosp
        lda #2
        sta okmsg
        lda #1
        sta ftype
        jsr prep
        lda #1
        jsr mkname
        jsr io_begin
        jsr openw
        lda #<PLAYER
        sta ip
        lda #>PLAYER
        sta ip+1
        lda #<SONGEND
        sta jp
        lda #>SONGEND
        sta jp+1
        jsr image_out
        jsr closew
        jsr CLRCHN
        lda #2
        jsr CLOSE
        lda #15
        jsr CLOSE
        lda #0
        sta bcnt
        sta bcnt+1
        lda #2
        jsr mkname
        jsr openw
        lda #<$0801
        sta ip
        lda #>$0801
        sta ip+1
        lda #<front_end
        sta jp
        lda #>front_end
        sta jp+1
        jsr image_out
        jsr closew
        jmp io_finish
@r      rts

; a PRG: the load address (the first byte), then the memory image ip .. jp with the song's live state left out
image_out
        lda ip
        jsr outb
        lda ip+1
        jsr outb
@l      lda ip
        cmp jp
        bne @b
        lda ip+1
        cmp jp+1
        beq @d
@b      jsr imgbyte
        jsr outb
        inc ip
        bne @l
        inc ip+1
        jmp @l
@d      rts

; the byte at ip for the image: zeros for the gaps and the live variables, the entry word set to the PLAY program
imgbyte lda ip
        cmp #<entry
        bne @n1
        lda ip+1
        cmp #>entry
        bne @n1
        lda #<play_start
        rts
@n1     lda ip
        cmp #<(entry+1)
        bne @z
        lda ip+1
        cmp #>(entry+1)
        bne @z
        lda #>play_start
        rts
@z      ldx #0
@r      lda ip+1                ; ip >= zs[x] ?
        cmp zsh,x
        bcc @nx
        bne @hi
        lda ip
        cmp zsl,x
        bcc @nx
@hi     lda ip+1                ; ip < ze[x] ?
        cmp zeh,x
        bcc @zero
        bne @nx
        lda ip
        cmp zel,x
        bcs @nx
@zero   lda #0
        rts
@nx     inx
        cpx #5
        bne @r
        ldy #0
        lda (ip),y
        rts
; the ranges that are zero in an image
zsl     !byte <($0812), <VARS, <tmute, <frame, <PLAYER_END
zsh     !byte >($0812), >VARS, >tmute, >frame, >PLAYER_END
zel     !byte <PLAYER, <VARS_END, <(tmute+8), <play_start, <SONG
zeh     !byte >PLAYER, >VARS_END, >(tmute+8), >play_start, >SONG

; ---- variables
tbuf    !fill 16, 0
tn      !byte 0
tmax    !byte 0
fname   !fill 24, 0
fnlen   !byte 0
cbuf    !fill 40, 0
clen    !byte 0
ebuf    !fill 32, 0
elen    !byte 0
ni      !byte 0
ioerr   !byte 0
ioacc   !byte 0
iosp    !byte 0
bcnt    !word 0
okmsg   !byte 0
ftype   !byte 0
