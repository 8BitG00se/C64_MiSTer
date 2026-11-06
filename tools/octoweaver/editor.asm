; editor.asm - Octo Weaver Lite: the editor.  ACME.  By Mong00se (Octophonic 64).
; Three screens: the lanes (the 8 tracks and their bars), the pattern editor (16 steps), the sound editor (16 fields).
; The raster interrupt (front.asm) runs the player and the key scan; the main loop runs the eq, the keys and the drawing.
!zone editor
bp      = $13                   ; pointer to a bar list
pp      = $15                   ; pointer to a pattern
sp      = $17                   ; pointer to a sound

MODE_LANES = 0
MODE_PAT   = 1
MODE_SND   = 2

; ================================================================================================ start
editor_start
        jsr start
        jsr clrscr
        lda #8
        sta eq_rows
        lda #1
        sta eq_top
        lda #64
        sta eq_px
        lda #2
        sta eq_gs
        jsr octo_init
        jsr eq_reset
        lda #0
        jsr pl_init
        jsr pl_stop
        lda #0
        sta mode
        sta ctrk
        sta cbar
        sta cstep
        sta padon
        sta audt
        sta msgt
        ldx #7
@m      sta mstate,x
        sta tmute,x
        dex
        bpl @m
        lda #3
        sta coct
        lda #1
        sta ssel
        lda #49
        sta lastnote
        lda #$a5
        sta rnd
        lda #$3c
        sta rnd+1
        jsr load_csnd
        jsr draw_title
        lda #1
        sta dirty
        jsr irq_on
@loop   jsr frame_step
        jsr getkey
        beq @nk
        jsr dispatch
@nk     lda dirty
        beq @loop
        jsr redraw
        jmp @loop

; once a frame: wait for the interrupt, the eq, the small timers
frame_step
@w      lda frame
        beq @w
        lda #0
        sta frame
        jsr eq_frame
        lda audt                ; the audition note: gate off when its time is up
        beq @a
        dec audt
        bne @a
        ldx audtrk
        sei
        jsr pl_gate
        cli
@a      lda msgt
        beq @p
        dec msgt
        bne @p
        jsr clr_msg
@p      lda padon               ; a paddle on the first POT: it turns the cutoff of the current track
        beq @pl
        lda $d419
        ldx ctrk
        sta SONG+H_DCUT,x
        lda mode
        bne @pl
        lda #1
        sta dirty
@pl     lda playing             ; the position moved: draw it
        beq @r
        lda pos
        cmp lpos
        bne @mv
        lda step
        cmp lstep
        beq @r
@mv     lda pos
        sta lpos
        lda step
        sta lstep
        lda mode
        cmp #MODE_SND
        beq @r
        lda #1
        sta dirty
@r      rts

waitkey jsr frame_step
        jsr getkey
        beq waitkey
        rts

; ---- keys: global first, then the screen's own
dispatch
        sta t0
        ldx #<globtab
        ldy #>globtab
        jsr tabsearch
        bcs @go
        lda mode
        asl
        tax
        lda modetabs,x
        pha
        lda modetabs+1,x
        tay
        pla
        tax
        jsr tabsearch
        bcc @no
@go     jmp (jp)
@no     rts
; X:Y = a table of (key, handler) triples ending in 0: carry set and jp = the handler if the key (t0) is in it
tabsearch
        stx ip
        sty ip+1
        ldy #0
@l      lda (ip),y
        beq @none
        cmp t0
        beq @hit
        iny
        iny
        iny
        bne @l
@none   clc
        rts
@hit    iny
        lda (ip),y
        sta jp
        iny
        lda (ip),y
        sta jp+1
        sec
        rts

modetabs !word lanestab, pattab, sndtab
globtab !byte $85 : !word k_play
        !byte $88 : !word k_quit
        !byte 0
lanestab
        !byte $91 : !word l_up
        !byte $11 : !word l_down
        !byte $9d : !word l_left
        !byte $1d : !word l_right
        !byte '+' : !word l_plus
        !byte '-' : !word l_minus
        !byte $0d : !word l_open
        !byte $86 : !word l_open
        !byte $87 : !word l_snd
        !byte 'M' : !word l_mute
        !byte 'S' : !word l_solo
        !byte '1' : !word d_cutm
        !byte '2' : !word d_cutp
        !byte '3' : !word d_resm
        !byte '4' : !word d_resp
        !byte '5' : !word d_mode
        !byte '6' : !word d_lfo
        !byte '7' : !word d_volm
        !byte '8' : !word d_volp
        !byte 'P' : !word d_paddle
        !byte 'K' : !word l_key
        !byte 'T' : !word l_scale
        !byte 'C' : !word l_chords
        !byte 'J' : !word l_roll
        !byte 'B' : !word l_build
        !byte 'N' : !word l_sname
        !byte 'R' : !word l_tname
        !byte 'W' : !word l_save
        !byte 'L' : !word l_load
        !byte 'X' : !word l_export
        !byte 'G' : !word l_page
        !byte $13 : !word l_home
        !byte ',' : !word l_lenm
        !byte '.' : !word l_lenp
        !byte '/' : !word l_spdm
        !byte ';' : !word l_spdp
        !byte '9' : !word l_tsm
        !byte '0' : !word l_tsp
        !byte 'Q' : !word l_role
        !byte 'V' : !word l_new
        !byte 0
pattab
        !byte $91 : !word p_up
        !byte $11 : !word p_down
        !byte $9d : !word p_left
        !byte $1d : !word p_right
        !byte '+' : !word p_sndp
        !byte '-' : !word p_sndm
        !byte 'Z' : !word p_octm
        !byte 'X' : !word p_octp
        !byte 'O' : !word p_off
        !byte $14 : !word p_clear
        !byte $20 : !word p_hear
        !byte 'R' : !word p_roll
        !byte $0d : !word p_back
        !byte $86 : !word p_back
        !byte $03 : !word p_back
        !byte $87 : !word p_snd
        !byte 'A' : !word p_key
        !byte 'W' : !word p_key
        !byte 'S' : !word p_key
        !byte 'E' : !word p_key
        !byte 'D' : !word p_key
        !byte 'F' : !word p_key
        !byte 'T' : !word p_key
        !byte 'G' : !word p_key
        !byte 'Y' : !word p_key
        !byte 'H' : !word p_key
        !byte 'U' : !word p_key
        !byte 'J' : !word p_key
        !byte 'K' : !word p_key
        !byte 0
sndtab
        !byte $91 : !word s_up
        !byte $11 : !word s_down
        !byte $9d : !word s_prev
        !byte $1d : !word s_next
        !byte '+' : !word s_plus
        !byte '-' : !word s_minus
        !byte $20 : !word s_hear
        !byte 'Z' : !word p_octm
        !byte 'X' : !word p_octp
        !byte $0d : !word s_back
        !byte $87 : !word s_back
        !byte $03 : !word s_back
        !byte $86 : !word s_pat
        !byte 0

; ================================================================================================ messages
clr_msg ldx #0
        ldy #21
        jsr txtpos
        ldx #40
        lda #1
        sta tcol
        jmp pspaces

; a message on row 21: the text is the zero-terminated string after the call (like pstr)
msg     jsr msgpre
        jmp pstr
msgpre  jsr clr_msg
        ldx #0
        ldy #21
        jsr txtpos
        lda #7
        sta tcol
        lda #150
        sta msgt
        rts
; the same, the text at X (low) Y (high)
msgp    stx jp
        sty jp+1
        jsr msgpre
puts    ldy #0
@l      lda (jp),y
        beq @r
        sty t0
        jsr putc
        ldy t0
        iny
        bne @l
@r      rts

; a question X:Y on row 21, Y or N: carry set = yes
askyn   jsr msgp
        lda #0
        sta msgt
@w      jsr waitkey
        cmp #'Y'
        beq @y
        cmp #'N'
        beq @n
        cmp #$03
        bne @w
@n      jsr clr_msg
        clc
        rts
@y      jsr clr_msg
        sec
        rts

; ================================================================================================ the common keys
k_quit  ldx #<m_quit
        ldy #>m_quit
        jsr askyn
        bcc @r
        jmp quit
@r      rts
m_quit  !scr "quit octo weaver? y/n", 0

k_play  lda playing
        beq @go
        sei
        jsr pl_stop
        cli
        jsr eq_reset
        lda #1
        sta dirty
        rts
@go     lda mode
        lda cbar                ; (also from the pattern / sound editor: from the bar being edited)
        sei
        jsr pl_init
        cli
        lda #$ff
        sta lpos
        lda #1
        sta dirty
        rts

; ================================================================================================ drawing
draw_title
        ldx #0
        ldy #0
        jsr txtpos
        lda #7
        sta tcol
        jsr pstr
        !scr "octo weaver lite ", 0
        lda #3
        sta tcol
        jsr pstr
        !scr "build 1", 0
        ldx #26
        ldy #0
        jsr txtpos
        lda #1
        sta tcol
        ldx #0
@n      lda SONG+H_SNAME,x
        and #$3f
        stx t7
        jsr putc
        ldx t7
        inx
        cpx #12
        bne @n
        rts

redraw  lda #0
        sta dirty
        jsr draw_title
        lda clrf
        beq @nc
        lda #0
        sta clrf
        ldx #15
        ldy #9
        jsr clrrows
@nc
        lda mode
        beq @l
        cmp #MODE_PAT
        beq @p
        jmp draw_snd
@l      jmp draw_lanes
@p      jmp draw_pat

; rows Y .. Y+X-1 cleared
clrrows stx t5
        ldx #0
        jsr txtpos
@r      ldy #39
@c      lda #$20
        sta (tp),y
        lda #1
        sta (cp),y
        dey
        bpl @c
        lda tp
        clc
        adc #40
        sta tp
        sta cp
        bcc @n
        inc tp+1
        inc cp+1
@n      dec t5
        bne @r
        rts

; the key help bar (row 24) and a second line (row 23): X:Y = text, ends with 0
helpbar stx jp
        sty jp+1
        ldx #0
        ldy #24
        jsr txtpos
        lda #11
        sta tcol
        jmp puts

; ---- the lanes
draw_lanes
        ; the first bar shown: the playing bar's, or the cursor's, rounded down to 10
        lda playing
        beq @c
        lda pos
        jmp @w
@c      lda cbar
@w      sta t0
        lda #0
        sta ws
@d      lda t0
        cmp #10
        bcc @dd
        sbc #10
        sta t0
        lda ws
        clc
        adc #10
        sta ws
        jmp @d
@dd     ldx #9                  ; the ruler
        ldy #9
        jsr txtpos
        lda #11
        sta tcol
        lda #0
        sta li
@ru     lda ws
        clc
        adc li
        clc
        adc #1
@m100   cmp #100
        bcc @m
        sbc #100
        jmp @m100
@m      jsr pdec2
        lda #$20
        jsr putc
        inc li
        lda li
        cmp #10
        bne @ru
        lda #0
        sta lt
@row    lda lt
        clc
        adc #10
        tay
        ldx #0
        jsr txtpos
        lda #1
        sta tcol
        lda lt
        cmp ctrk
        bne @nc
        lda #62                 ; >
        bne @cc
@nc     lda #$20
@cc     jsr putc
        ldx lt
        lda mstate,x
        beq @ns
        cmp #1
        bne @sol
        lda #2
        sta tcol
        lda #13                 ; M
        bne @mm
@sol    lda #7
        sta tcol
        lda #19                 ; S
        bne @mm
@ns     lda #$20
@mm     jsr putc
        ldx lt
        lda vcol,x
        sta tcol
        lda jnoff,x
        tax
        lda #6
        sta t5
@nm     stx t6
        lda SONG+H_NAMES,x
        and #$3f
        jsr putc
        ldx t6
        inx
        dec t5
        bne @nm
        lda #$20
        jsr putc
        ; the bars
        ldx lt
        lda barlo,x
        sta bp
        lda barhi,x
        sta bp+1
        lda #0
        sta li
@cell   lda ws
        clc
        adc li
        sta t4                  ; the bar
        cmp SONG+H_LEN
        bcc @in
        ldx #3
        jsr pspaces
        jmp @nx
@in     lda #0
        sta rvf
        lda lt
        cmp ctrk
        bne @nr
        lda t4
        cmp cbar
        bne @nr
        lda #$80
        sta rvf
@nr     ldx lt
        lda vcol,x
        sta tcol
        lda playing
        beq @pc
        lda t4
        cmp pos
        bne @pc
        lda #1
        sta tcol
@pc     ldy t4
        lda (bp),y
        bne @num
        lda #11
        sta tcol
        lda #46                 ; ..
        jsr putc
        lda #46
        jsr putc
        jmp @sp
@num    jsr pdec2
@sp     lda #0
        sta rvf
        lda #$20
        jsr putc
@nx     inc li
        lda li
        cmp #10
        bne @cell
        inc lt
        lda lt
        cmp #8
        beq @info
        jmp @row
@info   ldx #0                  ; row 18: speed, key, scale, length, bar
        ldy #18
        jsr txtpos
        lda #1
        sta tcol
        jsr pstr
        !scr "spd ", 0
        lda SONG+H_SPEED
        jsr pdec2
        jsr pstr
        !scr " key ", 0
        jsr putkey
        jsr pstr
        !scr " ", 0
        jsr putscale
        jsr pstr
        !scr " len ", 0
        lda SONG+H_LEN
        jsr pdec3
        jsr pstr
        !scr " bar ", 0
        lda cbar
        clc
        adc #1
        jsr pdec3
        ldx #0                  ; row 19: chords
        ldy #19
        jsr txtpos
        jsr pstr
        !scr "chords ", 0
        lda #0
        sta li
@ch     ldx li
        lda SONG+H_CHORDS,x
        clc
        adc #1
        jsr pdig
        lda #$20
        jsr putc
        inc li
        lda li
        cmp #4
        bne @ch
        jsr pstr
        !scr " = ", 0
        lda #0
        sta li
@cn     ldx li
        lda SONG+H_CHORDS,x
        jsr degnote             ; A = pitch class 0-11
        jsr putpc
        lda #$20
        jsr putc
        inc li
        lda li
        cmp #4
        bne @cn
        jsr draw_dials
        lda #1
        sta tcol
        ldx #<h_lanes2
        ldy #>h_lanes2
        stx jp
        sty jp+1
        ldx #0
        ldy #23
        jsr txtpos
        lda #12
        sta tcol
        jsr puts
        ldx #<h_lanes
        ldy #>h_lanes
        jmp helpbar
h_lanes  !scr "f1 play  f3 bar  f5 sound  f7 quit", 0
h_lanes2 !scr "m s mute/solo j roll b build c chords", 0

putkey  ldx SONG+H_KEY
        lda keyname1,x
        jsr putc
        lda keyname2,x
        jmp putc
keyname1 !scr "ccddeffggaab"
keyname2 !scr " # #  # # # "
; (the spaces in the lists above line up with the sharps)

putscale
        lda SONG+H_SCALE
        asl
        asl
        asl
        tax
        lda #8
        sta t5
@l      stx t6
        lda scnames,x
        jsr putc
        ldx t6
        inx
        dec t5
        bne @l
        rts
scnames !scr "major   minor   min pentmaj pent"
        !scr "dorian  blues   "

; a pitch class (0-11) as two letters
putpc   tax
        lda keyname1,x
        jsr putc
        lda keyname2,x
        jmp putc

; the dials of the current track's SID: row 20
draw_dials
        ldx #0
        ldy #20
        jsr txtpos
        ldx ctrk
        lda vcol,x
        sta tcol
        jsr pstr
        !scr "sid ", 0
        lda ctrk
        clc
        adc #1
        jsr pdig
        lda #1
        sta tcol
        jsr pstr
        !scr " cut ", 0
        ldx ctrk
        lda SONG+H_DCUT,x
        jsr pdec3
        jsr pstr
        !scr " res ", 0
        ldx ctrk
        lda SONG+H_DRES,x
        lsr
        lsr
        lsr
        lsr
        jsr pdec2
        jsr pstr
        !scr " ", 0
        ldx ctrk
        lda SONG+H_DMV,x
        lsr
        lsr
        lsr
        lsr
        jsr modename
        jsr pstr
        !scr " vol ", 0
        ldx ctrk
        lda SONG+H_DMV,x
        and #15
        jsr pdec2
        jsr pstr
        !scr " lfo ", 0
        ldx ctrk
        lda SONG+H_LFO,x
        beq @l0
        ldy #1
@lf     cmp lfopre,y
        beq @lo
        iny
        cpy #4
        bcc @lf
@lo     tya
        jmp @lp
@l0     lda #0
@lp     jsr pdig
        lda padon
        beq @np
        jsr pstr
        !scr " pad", 0
        rts
@np     jsr pstr
        !scr "    ", 0
        rts

; A = filter mode nibble: two letters
modename
        asl
        tax
        lda modenames,x
        jsr putc
        lda modenames+1,x
        jmp putc
modenames !scr "of", "lp", "bp", "lb", "hp", "nt", "bh", "al"

; A = scale degree 0-6 -> pitch class 0-11 of that chord root (key + the scale's note)
degnote tax
        lda SONG+H_SCALE
        tay
        lda sccnt,y
        sta t0
        txa
@m      cmp t0
        bcc @o
        sbc t0
        jmp @m
@o      sta t1
        lda scrow,y
        clc
        adc t1
        tax
        lda scdeg,x
        clc
        adc SONG+H_KEY
@w      cmp #12
        bcc @d
        sbc #12
        bne @w
@d      rts

; ---- scales
scdeg   !byte 0, 2, 4, 5, 7, 9, 11, 0
        !byte 0, 2, 3, 5, 7, 8, 10, 0
        !byte 0, 3, 5, 7, 10, 0, 0, 0
        !byte 0, 2, 4, 7, 9, 0, 0, 0
        !byte 0, 2, 3, 5, 7, 9, 10, 0
        !byte 0, 3, 5, 6, 7, 10, 0, 0
scrow   !byte 0, 8, 16, 24, 32, 40
sccnt   !byte 7, 7, 5, 5, 7, 6
s12     !byte 0, 12, 24, 36, 48, 60
; membership: the scale's 12 relative pitch classes
scmask  !byte 1,0,1,0,1,1,0,1,0,1,0,1
        !byte 1,0,1,1,0,1,0,1,1,0,1,0
        !byte 1,0,0,1,0,1,0,1,0,0,1,0
        !byte 1,0,1,0,1,0,0,1,0,1,0,0
        !byte 1,0,1,1,0,1,0,1,0,1,1,0
        !byte 1,0,0,1,0,1,1,1,0,0,1,0

; ================================================================================================ notes
; A = note 1-96 -> X = octave, A = pitch class
pcof    sec
        sbc #1
        ldx #0
@l      cmp #12
        bcc @d
        sbc #12
        inx
        bne @l
@d      rts

; carry set if note A is in the song's scale
inscale jsr pcof
        sec
        sbc SONG+H_KEY
        bcs @p
        adc #12
@p      sta t4
        ldx SONG+H_SCALE
        lda s12,x
        clc
        adc t4
        tax
        lda scmask,x
        lsr
        rts

; next scale note above / below A (stays put at the ends)
scup    sta t6
@l      inc t6
        lda t6
        cmp #97
        bcs @e
        jsr inscale
        bcc @l
        lda t6
        rts
@e      lda #96
        rts
scdn    sta t6
@l      dec t6
        beq @e
        lda t6
        jsr inscale
        bcc @l
        lda t6
        rts
@e      lda #1
        rts

; snap A to the scale (downwards)
snap    sta t6
@l      lda t6
        jsr inscale
        bcs @d
        dec t6
        bne @l
        lda #1
        rts
@d      lda t6
        rts

; the note A as three characters: C-4 C#4 or --- or off
pnote   cmp #0
        bne @n
        lda #45
        jsr putc
        lda #45
        jsr putc
        lda #45
        jmp putc
@n      cmp #255
        bne @v
        lda #15                 ; o
        jsr putc
        lda #6                  ; f
        jsr putc
        lda #6
        jmp putc
@v      jsr pcof
        stx t3
        sta t2
        tax
        lda notenm1,x
        jsr putc
        ldx t2
        lda notenm2,x
        jsr putc
        lda t3
        jmp pdig
notenm1 !scr "ccddeffggaab"
notenm2 !scr "-#-#--#-#-#-"

; ================================================================================================ the lanes: keys
; the pattern number of the cursor's bar -> A
getbar  ldx ctrk
        lda barlo,x
        sta bp
        lda barhi,x
        sta bp+1
        ldy cbar
        lda (bp),y
        rts

l_up    lda ctrk
        beq @r
        dec ctrk
        jsr load_csnd
        lda #1
        sta dirty
@r      rts
l_down  lda ctrk
        cmp #7
        beq @r
        inc ctrk
        jsr load_csnd
        lda #1
        sta dirty
@r      rts
l_left  lda cbar
        beq @r
        dec cbar
        lda #1
        sta dirty
@r      rts
l_right lda cbar
        cmp #127
        beq @r
        inc cbar
        lda #1
        sta dirty
@r      rts
l_home  lda #0
        sta cbar
        lda #1
        sta dirty
        rts
l_page  lda kshiftn
        bne @b
        lda cbar
        clc
        adc #10
        cmp #128
        bcc @s
        lda #127
@s      sta cbar
        lda #1
        sta dirty
        rts
@b      lda cbar
        sec
        sbc #10
        bcs @s2
        lda #0
@s2     sta cbar
        lda #1
        sta dirty
        rts
l_plus  jsr getbar
        cmp #48
        bcs @r
        clc
        adc #1
        sta (bp),y
        lda #1
        sta dirty
@r      rts
l_minus jsr getbar
        beq @r
        sec
        sbc #1
        sta (bp),y
        lda #1
        sta dirty
@r      rts
l_mute  ldx ctrk
        lda mstate,x
        cmp #1
        beq @off
        lda #1
        bne @s
@off    lda #0
@s      sta mstate,x
        jmp mutes
l_solo  ldx ctrk
        lda mstate,x
        cmp #2
        beq @off
        lda #2
        bne @s
@off    lda #0
@s      sta mstate,x
mutes   ldx #7                  ; any solo at all?
        lda #0
        sta t0
@a      lda mstate,x
        cmp #2
        bne @n
        inc t0
@n      dex
        bpl @a
        ldx #7
@t      lda mstate,x
        ldy t0
        bne @solo
        cmp #1                  ; no solo: mute = muted
        beq @m
        lda #0
        beq @w
@m      lda #1
        bne @w
@solo   cmp #2                  ; solos: everything else is silent
        beq @no
        lda #1
        bne @w
@no     lda #0
@w      sta tmute,x
        dex
        bpl @t
        lda #1
        sta dirty
        rts

l_open  jsr ensure_pat
        bcs @r
        lda #MODE_PAT
        sta mode
        inc clrf
        lda #0
        sta cstep
        lda #1
        sta dirty
@r      rts
l_snd   lda #MODE_SND
        sta mode
        inc clrf
        lda csnd
        sta ssel
        lda #1
        sta dirty
        rts

; the cursor bar gets a pattern if it has none: the first of the track's patterns that is empty and in no bar. Carry set = none free.
ensure_pat
        jsr getbar
        bne @ok
        lda #1
        sta t0                  ; candidate pattern
@cand   ldx ctrk
        lda t0
        jsr patptr              ; ip
        ldy #15                 ; empty? (the 16 notes)
@e      lda (ip),y
        bne @next
        dey
        bpl @e
        ldy #0                  ; in a bar?
@u      lda (bp),y
        cmp t0
        beq @next
        iny
        cpy #128
        bne @u
        ldy cbar
        lda t0
        sta (bp),y
        lda #1
        sta dirty
@ok     clc
        rts
@next   inc t0
        lda t0
        cmp #49
        bcc @cand
        jsr msg
        !scr "no free pattern on this track", 0
        sec
        rts

; pattern A (1-48) of track X -> ip
patptr  tay
        lda plot,y
        sta ip
        lda phit,y
        clc
        adc pbhi,x
        sta ip+1
        rts

; the pattern being edited -> ip (carry set if the bar has none)
curpat  jsr getbar
        beq @none
        ldx ctrk
        jsr patptr
        clc
        rts
@none   sec
        rts

load_csnd
        ldx ctrk
        lda SONG+H_TSND,x
        sta csnd
        rts

; ---- the song's settings
l_key   ldx SONG+H_KEY
        inx
        cpx #12
        bcc @s
        ldx #0
@s      stx SONG+H_KEY
        lda #1
        sta dirty
        rts
l_scale ldx SONG+H_SCALE
        inx
        cpx #6
        bcc @s
        ldx #0
@s      stx SONG+H_SCALE
        lda #1
        sta dirty
        rts
l_chords
        jsr msg
        !scr "chords: four digits 1-7", 0
        lda #0
        sta li
@w      jsr waitkey
        cmp #$03
        beq @x
        cmp #'1'
        bcc @w
        cmp #'8'
        bcs @w
        sec
        sbc #'1'
        ldx li
        sta SONG+H_CHORDS,x
        lda #1
        sta dirty
        jsr redraw
        inc li
        lda li
        cmp #4
        bne @w
@x      jsr clr_msg
        rts
l_lenm  lda SONG+H_LEN
        ldx kshiftn
        beq @1
        sec
        sbc #3
@1      sec
        sbc #1
        beq @r
        bcc @r
        sta SONG+H_LEN
        lda #1
        sta dirty
@r      rts
l_lenp  lda SONG+H_LEN
        clc
        adc #1
        ldx kshiftn
        beq @1
        clc
        adc #3
@1      cmp #129
        bcs @r
        sta SONG+H_LEN
        lda #1
        sta dirty
@r      rts
l_spdm  lda SONG+H_SPEED
        cmp #2
        bcc @r
        dec SONG+H_SPEED
        lda #1
        sta dirty
@r      rts
l_spdp  lda SONG+H_SPEED
        cmp #31
        bcs @r
        inc SONG+H_SPEED
        lda #1
        sta dirty
@r      rts
l_tsm   ldx ctrk
        lda SONG+H_TSND,x
        cmp #2
        bcc @r
        sec
        sbc #1
        sta SONG+H_TSND,x
        jsr load_csnd
        jmp tsmsg
@r      rts
l_tsp   ldx ctrk
        lda SONG+H_TSND,x
        cmp #31
        bcs tsm_r
        clc
        adc #1
        sta SONG+H_TSND,x
        jsr load_csnd
tsmsg   jsr msg
        !scr "this track's roll sound: ", 0
        lda csnd
        jmp pdec2
tsm_r   rts
l_role  ldx ctrk
        lda SONG+H_ROLE,x
        clc
        adc #1
        and #7
        sta SONG+H_ROLE,x
        tax
        jsr msg
        !scr "roll style: ", 0
        ldx ctrk
        lda SONG+H_ROLE,x
        asl
        asl
        asl
        tax
        lda #6
        sta t5
@l      stx t6
        lda rolenames,x
        jsr putc
        ldx t6
        inx
        dec t5
        bne @l
        rts
rolenames !scr "pad   lead  bass  reese drums hats  bells fx    "
l_new   ldx #<m_new
        ldy #>m_new
        jsr askyn
        bcc @r
        jsr new_song
@r      rts
m_new   !scr "start a new empty song? y/n", 0

; the dials
d_cutm  ldx ctrk
        lda SONG+H_DCUT,x
        sec
        sbc #8
        bcs @s
        lda #0
@s      sta SONG+H_DCUT,x
        jmp d_done
d_cutp  ldx ctrk
        lda SONG+H_DCUT,x
        clc
        adc #8
        bcc @s
        lda #255
@s      sta SONG+H_DCUT,x
        jmp d_done
d_resm  ldx ctrk
        lda SONG+H_DRES,x
        sec
        sbc #$10
        bcs @s
        lda #0
@s      sta SONG+H_DRES,x
        jmp d_done
d_resp  ldx ctrk
        lda SONG+H_DRES,x
        clc
        adc #$10
        bcc @s
        lda #$f0
@s      sta SONG+H_DRES,x
        jmp d_done
d_mode  ldx ctrk
        lda SONG+H_DMV,x
        clc
        adc #$10
        and #$70
        sta t0
        lda SONG+H_DMV,x
        and #$0f
        ora t0
        sta SONG+H_DMV,x
        jmp d_done
d_volm  ldx ctrk
        lda SONG+H_DMV,x
        and #$0f
        beq d_done
        dec SONG+H_DMV,x
        jmp d_done
d_volp  ldx ctrk
        lda SONG+H_DMV,x
        and #$0f
        cmp #15
        beq d_done
        inc SONG+H_DMV,x
d_done  lda #1
        sta dirty
        rts
d_lfo   ldx ctrk                ; the filter sweep: off, then four presets
        lda SONG+H_LFO,x
        ldy #0
@f      cmp lfopre,y
        beq @g
        iny
        cpy #5
        bne @f
        ldy #4                  ; (an odd value from a song: treat as the last)
@g      iny
        cpy #5
        bcc @s
        ldy #0
@s      lda lfopre,y
        sta SONG+H_LFO,x
        jmp d_done
lfopre  !byte 0, $82, $f3, $f6, $8c
d_paddle
        lda padon
        eor #1
        sta padon
        jmp d_done

; ================================================================================================ the pattern editor
draw_pat
        ldx #0
        ldy #9
        jsr txtpos
        ldx ctrk
        lda vcol,x
        sta tcol
        jsr pstr
        !scr "track ", 0
        lda ctrk
        clc
        adc #1
        jsr pdig
        lda #$20
        jsr putc
        ldx ctrk
        lda jnoff,x
        tax
        lda #6
        sta t5
@nm     stx t6
        lda SONG+H_NAMES,x
        and #$3f
        jsr putc
        ldx t6
        inx
        dec t5
        bne @nm
        lda #1
        sta tcol
        jsr pstr
        !scr "  bar ", 0
        lda cbar
        clc
        adc #1
        jsr pdec3
        jsr pstr
        !scr "  pattern ", 0
        jsr getbar
        jsr pdec2
        jsr curpat
        bcc @pat
        rts
@pat    lda #0
        sta li
@step   lda li                  ; step i: row 10 + i mod 8, column 2 + 18 * (i div 8)
        and #7
        clc
        adc #10
        tay
        ldx #3
        lda li
        cmp #8
        bcc @c
        ldx #23
@c      jsr txtpos
        lda #0
        sta rvf
        lda li
        cmp cstep
        bne @nr
        lda #$80
        sta rvf
@nr     lda #11
        sta tcol
        lda playing
        beq @pc
        lda li
        cmp step
        bne @pc
        lda cbar
        cmp pos
        bne @pc
        lda #1
        sta tcol
@pc     lda li
        clc
        adc #1
        jsr pdec2
        lda #$20
        jsr putc
        ldx ctrk
        lda vcol,x
        sta tcol
        ldy li
        lda (ip),y
        jsr pnote
        lda #$20
        jsr putc
        ldy li
        lda (ip),y
        beq @nos
        cmp #255
        beq @nos
        tya
        clc
        adc #16
        tay
        lda (ip),y
        jsr pdec2
        jmp @sd
@nos    lda #$20
        jsr putc
        lda #$20
        jsr putc
@sd     lda #0
        sta rvf
        inc li
        lda li
        cmp #16
        beq @stepd
        jmp @step
@stepd
        ldx #0                  ; row 19: what the keys will enter
        ldy #19
        jsr txtpos
        lda #1
        sta tcol
        jsr pstr
        !scr "key ", 0
        jsr putkey
        jsr pstr
        !scr " ", 0
        jsr putscale
        jsr pstr
        !scr " oct ", 0
        lda coct
        jsr pdig
        jsr pstr
        !scr "  sound ", 0
        lda csnd
        jsr pdec2
        ldx #<h_pat2
        ldy #>h_pat2
        stx jp
        sty jp+1
        ldx #0
        ldy #23
        jsr txtpos
        lda #12
        sta tcol
        jsr puts
        ldx #<h_pat
        ldy #>h_pat
        jmp helpbar
h_pat   !scr "keys a-k notes  up/dn scale  ret back", 0
h_pat2  !scr "z x oct  o off  del  +- sound  r roll", 0

; pattern step: ip,y
p_back  lda #MODE_LANES
        sta mode
        inc clrf
        lda #1
        sta dirty
        rts
p_snd   jmp l_snd
p_left  lda cstep
        sec
        sbc #1
        and #15
        sta cstep
        lda #1
        sta dirty
        rts
p_right lda cstep
        clc
        adc #1
        and #15
        sta cstep
        lda #1
        sta dirty
        rts
p_up    jsr curpat
        bcc @ok1
        rts
@ok1
        ldy cstep
        lda (ip),y
        beq @first
        cmp #255
        beq @first
        jsr scup
        jmp p_put
@first  lda lastnote
        jmp p_put
p_down  jsr curpat
        bcc @ok2
        rts
@ok2
        ldy cstep
        lda (ip),y
        beq @first
        cmp #255
        beq @first
        jsr scdn
        jmp p_put
@first  lda lastnote
; A = the note for the step: store it and hear it
p_put   pha
        jsr curpat
        ldy cstep
        pla
        sta (ip),y
        sta lastnote
        pha
        tya
        clc
        adc #16
        tay
        lda csnd
        sta (ip),y
        pla
        jsr hear
        lda #1
        sta dirty
p_r     rts
p_key   lda t0                  ; the key that was pressed (kept by dispatch)
        ldx #12
@f      cmp pkeys,x
        beq @got
        dex
        bpl @f
        rts
@got    txa
        pha
        jsr oct12
        sta t1
        pla
        clc
        adc t1
        clc
        adc #1
        cmp #97
        bcc @ok
        lda #96
@ok     jsr snap
        jsr p_put
        jmp p_right             ; step entry: on to the next step
oct12   lda coct
        asl
        asl
        sta t1
        asl
        clc
        adc t1
        rts
pkeys   !byte 'A','W','S','E','D','F','T','G','Y','H','U','J','K'
p_octm  lda coct
        beq @r
        dec coct
        lda #1
        sta dirty
@r      rts
p_octp  lda coct
        cmp #7
        bcs @r
        inc coct
        lda #1
        sta dirty
@r      rts
p_off   jsr curpat
        bcc @ok3
        rts
@ok3
        ldy cstep
        lda #255
        sta (ip),y
        jsr p_right
        rts
p_clear jsr curpat
        bcc @ok4
        rts
@ok4
        ldy cstep
        lda #0
        sta (ip),y
        tya
        clc
        adc #16
        tay
        lda #0
        sta (ip),y
        lda #1
        sta dirty
        rts
p_sndp  jsr curpat
        bcc @ok5
        rts
@ok5
        ldy cstep
        tya
        clc
        adc #16
        tay
        lda (ip),y
        cmp #31
        bcs @r
        clc
        adc #1
        sta (ip),y
        sta csnd
        lda #1
        sta dirty
@r      rts
p_sndm  jsr curpat
        bcc @ok6
        rts
@ok6
        ldy cstep
        tya
        clc
        adc #16
        tay
        lda (ip),y
        cmp #2
        bcc @r
        sec
        sbc #1
        sta (ip),y
        sta csnd
        lda #1
        sta dirty
@r      rts
p_hear  jsr curpat
        bcc @ok7
        rts
@ok7
        ldy cstep
        lda (ip),y
        bne @ok8
        rts
@ok8
        cmp #255
        bne @ok9
        rts
@ok9
        pha
        tya
        clc
        adc #16
        tay
        lda (ip),y
        sta csnd
        pla
        jmp hear
; note A on the cursor's track with sound csnd
hear    ldx ctrk
        ldy csnd
        stx audtrk
        sei
        jsr pl_trig
        cli
        lda #28
        sta audt
        rts
p_roll  jsr curpat
        bcc @ok10
        rts
@ok10
        lda cbar
        and #3
        sta rchord
        jsr roll_pat
        lda #1
        sta dirty
        rts

; ================================================================================================ the sound editor
; field order = the sound's 16 bytes.  Left column 0-7, right column 8-15.
draw_snd
        ldx #0
        ldy #9
        jsr txtpos
        lda #7
        sta tcol
        jsr pstr
        !scr "sound ", 0
        lda ssel
        jsr pdec2
        jsr pstr
        !scr "   (left / right = other sound)", 0
        lda #0
        sta li
@f      lda li
        and #7
        clc
        adc #10
        tay
        ldx #1
        lda li
        cmp #8
        bcc @c
        ldx #21
@c      jsr txtpos
        lda #1
        sta tcol
        lda li
        asl
        asl
        tax
        lda #4
        sta t5
@lb     stx t6
        lda fldname,x
        jsr putc
        ldx t6
        inx
        dec t5
        bne @lb
        lda #$20
        jsr putc
        lda #0
        sta rvf
        lda li
        cmp sfield
        bne @nr
        lda #$80
        sta rvf
@nr     lda #7
        sta tcol
        jsr sndptr
        ldy li
        lda (sp),y
        sta t4
        ldx li
        lda fldtype,x
        cmp #2
        beq @voic
        lda #$24                ; $
        jsr putc
        lda t4
        jsr phex2
        jmp @e
@voic   lda t4                  ; the voicing's name
        asl
        asl
        asl
        tax
        lda #6
        sta t5
@vn     stx t6
        lda voicnames,x
        jsr putc
        ldx t6
        inx
        dec t5
        bne @vn
@e      lda #0
        sta rvf
        inc li
        lda li
        cmp #16
        beq @fd
        jmp @f
@fd     ldx #<h_snd
        ldy #>h_snd
        jmp helpbar2
h_snd   !scr "up/dn field  +- value  space hear  ret", 0
helpbar2
        stx jp
        sty jp+1
        ldx #0
        ldy #23
        jsr txtpos
        lda #12
        sta tcol
        jsr pstr
        !scr "left/right sound  shift+- = fine", 0
        ldx #0
        ldy #24
        jsr txtpos
        lda #11
        sta tcol
        jmp puts
fldname !scr "wave"
        !scr "ad  "
        !scr "sr  "
        !scr "pw  "
        !scr "pwm "
        !scr "vib "
        !scr "voic"
        !scr "detu"
        !scr "arp "
        !scr "glid"
        !scr "filt"
        !scr "wp1 "
        !scr "wp2 "
        !scr "wp3 "
        !scr "wp4 "
        !scr "fall"
; 0 plain number, 1 wave byte, 2 voicing, 3 nibble pair (ad, sr)
fldtype !byte 1, 3, 3, 0, 0, 0, 2, 0, 0, 0, 0, 1, 1, 1, 1, 0
fldmax  !byte 0, 0, 0, 15, 15, 15, 6, 15, 7, 15, 1, 0, 0, 0, 0, 15
voicnames
        !scr "one     "
        !scr "unison  "
        !scr "octave  "
        !scr "power   "
        !scr "major   "
        !scr "minor   "
        !scr "drums   "
        !scr "        "

sndptr  ldx ssel
        lda sndlo,x
        sta sp
        lda sndhi,x
        sta sp+1
        rts

s_up    lda sfield
        beq @r
        dec sfield
        lda #1
        sta dirty
@r      rts
s_down  lda sfield
        cmp #15
        beq @r
        inc sfield
        lda #1
        sta dirty
@r      rts
s_prev  lda ssel
        cmp #2
        bcc @r
        dec ssel
        lda ssel
        sta csnd
        lda #1
        sta dirty
@r      rts
s_next  lda ssel
        cmp #31
        bcs @r
        inc ssel
        lda ssel
        sta csnd
        lda #1
        sta dirty
@r      rts
s_back  lda #MODE_LANES
        sta mode
        inc clrf
        lda #1
        sta dirty
        rts
s_pat   jmp l_open
s_hear  jsr oct12
        clc
        adc #1
        ldx ssel
        stx csnd
        jmp hear
s_plus  lda #1
        bne s_chg
s_minus lda #$ff
s_chg   sta t2                  ; +1 / -1
        jsr sndptr
        ldx sfield
        ldy sfield
        lda (sp),y
        sta t3
        lda fldtype,x
        bne @nn1
        jmp @num
@nn1    cmp #2
        bne @nn2
        jmp @num
@nn2        cmp #3
        beq @nib
        ; a wave byte: the wave bits 4-7 (shifted keys: ring / sync bits)
        lda kshiftn
        bne @rs
        lda t3
        lsr
        lsr
        lsr
        lsr
        clc
        adc t2
        bmi @wmin
        cmp #9
        bcs @wmax
        asl
        asl
        asl
        asl
        sta t4
        lda t3
        and #$0f
        ora t4
        jmp @store
@wmin   lda #0
        beq @wl
@wmax   lda #8
@wl     asl
        asl
        asl
        asl
        sta t4
        lda t3
        and #$0f
        ora t4
        jmp @store
@rs     lda t3                  ; the low bits: next of none / sync / ring / both
        clc
        adc #2
        and #6
        sta t4
        lda t3
        and #$f0
        ora t4
        jmp @store
@nib    lda kshiftn             ; AD / SR: the high nibble, or with shift the low one
        bne @low
        lda t3
        lsr
        lsr
        lsr
        lsr
        clc
        adc t2
        and #15
        asl
        asl
        asl
        asl
        sta t4
        lda t3
        and #15
        ora t4
        jmp @store
@low    lda t3
        and #15
        clc
        adc t2
        and #15
        sta t4
        lda t3
        and #$f0
        ora t4
        jmp @store
@num    lda t3
        clc
        adc t2
        bmi @r
        cmp fldmax,x
        beq @store
        bcs @r
@store  ldy sfield
        sta (sp),y
        sei
        jsr pl_inval
        cli
        lda #1
        sta dirty
@r      rts

; ================================================================================================ the song
new_song
        sei
        jsr pl_stop
        cli
        lda #<SONG              ; the song area to zero, then the defaults
        sta ip
        lda #>SONG
        sta ip+1
        lda #>SONGSIZE
        sta t0
@pg     lda #0
        ldy #0
@b      sta (ip),y
        iny
        bne @b
        inc ip+1
        dec t0
        bne @pg
        lda #6
        sta SONG+H_SPEED
        lda #9
        sta SONG+H_KEY
        lda #1
        sta SONG+H_SCALE
        lda #0
        sta SONG+H_CHORDS
        lda #5
        sta SONG+H_CHORDS+1
        lda #3
        sta SONG+H_CHORDS+2
        lda #4
        sta SONG+H_CHORDS+3
        lda #32
        sta SONG+H_LEN
        ldx #0
@h      lda defnames,x
        sta SONG+H_NAMES,x
        inx
        cpx #48
        bne @h
        ldx #7
@t      txa
        sta SONG+H_ROLE,x
        lda deftsnd,x
        sta SONG+H_TSND,x
        lda #160
        sta SONG+H_DCUT,x
        lda #$20
        sta SONG+H_DRES,x
        lda #$1f
        sta SONG+H_DMV,x
        dex
        bpl @t
        ldx #0
@n      lda defsname,x
        sta SONG+H_SNAME,x
        inx
        cpx #16
        bne @n
        ; the default sounds: copied from the table
        ldx #0
@s      lda defsounds,x
        sta SND+16,x
        inx
        cpx #144
        bne @s
        sei
        jsr pl_inval
        cli
        jsr eq_reset
        lda #0
        sta cbar
        sta ctrk
        sta cstep
        sta mode
        inc clrf
        ldx #7
@m      sta mstate,x
        sta tmute,x
        dex
        bpl @m
        jsr load_csnd
        lda #1
        sta dirty
        rts
deftsnd !byte 1, 2, 3, 4, 5, 7, 8, 9
defnames !text "PAD   LEAD  BASS  REESE DRUMS HATS  BELLS FX    "
defsname !text "NEW SONG        "

!source "sounds.inc"
!source "roll.asm"
!source "disk.asm"

; ================================================================================================ editor variables
mode    !byte 0
ctrk    !byte 0
cbar    !byte 0
cstep   !byte 0
coct    !byte 3
csnd    !byte 1
ssel    !byte 1
sfield  !byte 0
dirty   !byte 0
padon   !byte 0
audt    !byte 0
audtrk  !byte 0
msgt    !byte 0
lastnote !byte 49
lpos    !byte $ff
lstep   !byte 0
ws      !byte 0
li      !byte 0
lt      !byte 0
rchord  !byte 0
clrf    !byte 1
rnd     !word $3ca5
mstate  !fill 8, 0
editor_end
!if editor_end > STAGE { !error "the editor runs into the song stage" }
