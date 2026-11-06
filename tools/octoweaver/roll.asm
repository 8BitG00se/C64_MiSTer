; roll.asm - ROLL (a musical idea for a track's job, in the song's key and scale, following the chord loop) and SHAPE (BUILD).
!zone roll
rsnd    !byte 1                 ; the sound ROLL writes into the steps
robase  !byte 1                 ; octave * 12 + 1
rtmp    !byte 0
rcnt    !byte 0
rprev   !byte 0
rlast   !byte 0
rhy     !byte 0
mot     !fill 4, 0
bpn     !byte 0
rhi     !byte 0
rwrap   !byte 0

; a random byte
rand    lsr rnd+1
        ror rnd
        bcc @n
        lda rnd+1
        eor #$b4
        sta rnd+1
@n      lda rnd
        eor rnd+1
        rts
; A = a random number 0 .. A-1
randmod sta rtmp
        jsr rand
@l      cmp rtmp
        bcc @d
        sbc rtmp
        jmp @l
@d      rts

; A = octave: the base of the notes
setoct  tax
        lda o12,x
        clc
        adc #1
        sta robase
        rts
o12     !byte 0, 12, 24, 36, 48, 60, 72, 84

; the chord root degree of this ROLL
croot   ldx rchord
        lda SONG+H_CHORDS,x
        rts

; A = a scale degree (0 up, past the scale's size is the next octave) -> A = the note
rdeg    ldx SONG+H_SCALE
        ldy sccnt,x
        sty t1
        sta t2
        lda #0
        sta t3
@l      lda t2
        cmp t1
        bcc @d
        sbc t1
        sta t2
        lda t3
        clc
        adc #12
        sta t3
        jmp @l
@d      lda scrow,x
        clc
        adc t2
        tax
        lda scdeg,x
        clc
        adc t3
        clc
        adc SONG+H_KEY
        ldy rwrap               ; pad / bass / reese: the chord roots stay within one octave
        beq @nw
@w      cmp #12
        bcc @nw
        sbc #12
        bne @w
@nw     clc
        adc robase
        cmp #97
        bcc @r
        lda #96
@r      rts

; A = note, Y = step: the step gets the note and the track's roll sound
rput    sta (ip),y
        pha
        tya
        clc
        adc #16
        tay
        lda rsnd
        sta (ip),y
        pla
        rts

; the pattern at ip, track ctrk, chord rchord: fill it
roll_pat
        ldy #31
        lda #0
@c      sta (ip),y
        dey
        bpl @c
        lda $d012
        eor rnd
        sta rnd
        ldx ctrk
        lda SONG+H_TSND,x
        sta rsnd
        lda SONG+H_ROLE,x
        asl
        tax
        lda roletab,x
        sta jp
        lda roletab+1,x
        sta jp+1
        jmp (jp)
roletab !word r_pad, r_lead, r_bass, r_reese, r_drums, r_hats, r_bells, r_fx

r_pad   lda #1
        sta rwrap
        lda #3
        jsr setoct
        jsr croot
        jsr rdeg
        ldy #0
        jsr rput
        jsr rand
        cmp #128
        bcs @r
        jsr croot
        clc
        adc #4
        jsr rdeg
        ldy #8
        jsr rput
@r      rts

r_reese lda #1
        sta rwrap
        lda #1
        jsr setoct
        jsr croot
        jsr rdeg
        ldy #0
        jsr rput
        jsr rand
        cmp #70
        bcc @r
        jsr rand
        cmp #150
        bcs @f
        jsr croot
        jmp @p
@f      jsr croot
        clc
        adc #4
@p      jsr rdeg
        ldy #8
        jsr rput
@r      rts

r_bass  lda #1
        sta rwrap
        lda #1
        jsr setoct
        jsr croot
        jsr rdeg
        ldy #0
        jsr rput
        lda #0
        sta rcnt
@b      ldx rcnt
        lda bpos,x
        bmi @x
        sta rprev
        jsr rand
        cmp #160
        bcc @root
        cmp #215
        bcc @fifth
        jsr croot               ; a passing note
        clc
        adc #1
        jmp @put
@fifth  jsr croot
        clc
        adc #4
        jmp @put
@root   jsr croot
@put    jsr rdeg
        ldy rprev
        jsr rput
        inc rcnt
        bne @b
@x      lda #0                  ; the offbeats: now and then the root again
        sta rcnt
@o      ldx rcnt
        lda opos,x
        bmi @r
        sta rprev
        jsr rand
        cmp #70
        bcs @no
        jsr croot
        jsr rdeg
        ldy rprev
        jsr rput
@no     inc rcnt
        bne @o
@r      rts
bpos    !byte 4, 8, 12, $ff
opos    !byte 6, 10, 14, $ff

; LEAD: a motif of four notes, stated, restated, the last note changed
rhythms !byte 0, 3, 6, 8, 11, 14, $ff, 0
        !byte 0, 2, 4, 6, 8, 10, 12, $ff
        !byte 0, 4, 6, 8, 12, 14, $ff, 0
r_lead  lda #0
        sta rwrap
        lda #4
        jsr setoct
        lda #3
        jsr randmod
        asl
        asl
        asl
        sta rhy
        lda #3
        jsr randmod
        asl                     ; the first note: root, third or fifth
        sta rtmp
        jsr croot
        clc
        adc rtmp
        sta mot
        ldx #1
@m      stx rcnt
        lda #6
        jsr randmod
        tay
        lda steps6,y
        ldx rcnt
        clc
        adc mot-1,x
        bmi @keep
        cmp #14
        bcs @keep
        sta mot,x
        jmp @nm
@keep   lda mot-1,x
        sta mot,x
@nm     inx
        cpx #4
        bne @m
        lda #0
        sta rcnt                ; the motif's note counter
        sta rprev
        lda rhy
        sta rhi
@p      ldx rhi
        lda rhythms,x
        cmp #$ff
        beq @fin
        sta rlast
        tay
        cpy #8
        bcc @same
        lda rprev
        bne @same
        lda #1
        sta rprev
        lda #0
        sta rcnt                ; the second half starts the motif again
@same   lda rcnt
        and #3
        tay
        lda mot,y
        jsr rdeg
        ldy rlast
        jsr rput
        inc rcnt
        inc rhi
        bne @p
@fin    lda #3                  ; the last note is a chord tone
        jsr randmod
        asl
        sta rtmp
        jsr croot
        clc
        adc rtmp
        jsr rdeg
        ldy rlast
        jmp rput
steps6  !byte $fe, $ff, 1, 2, $ff, 1

r_drums lda #25                 ; kick: C2
        ldy #0
        jsr rput
        jsr rand
        cmp #64
        bcs @a
        lda #25
        ldy #6
        jsr rput
@a      jsr rand
        cmp #128
        bcs @b
        lda #25
        ldy #10
        jsr rput
@b      lda rsnd                ; the snare: the sound after the kick's
        pha
        cmp #31
        bcs @s
        inc rsnd
@s      lda #37
        ldy #8
        jsr rput
        pla
        sta rsnd
        rts

r_hats  lda #0
        sta rcnt
@h      ldx rcnt
        lda hpos,x
        bmi @r
        sta rprev
        jsr rand
        cmp #154
        bcs @n
        lda #73                 ; C6 (the noise does not care)
        ldy rprev
        jsr rput
@n      inc rcnt
        bne @h
@r      rts
hpos    !byte 2, 6, 10, 14, $ff

r_bells lda #0
        sta rwrap
        lda #5
        jsr setoct
        lda #0
        sta rcnt
@b      jsr rand
        cmp #150
        bcs @n
        lda #4
        jsr randmod
        tax
        lda belldeg,x
        sta rtmp
        jsr croot
        clc
        adc rtmp
        jsr rdeg
        pha
        jsr rand
        and #15
        tay
        pla
        jsr rput
@n      inc rcnt
        lda rcnt
        cmp #3
        bne @b
        rts
belldeg !byte 0, 2, 4, 7

r_fx    lda #0
        sta rwrap
        lda #4
        jsr setoct
        jsr rand
        cmp #150
        bcs @a
        jsr croot
        clc
        adc #4
        jsr rdeg
        ldy #0
        jsr rput
@a      jsr rand
        cmp #100
        bcs @r
        jsr croot
        clc
        adc #7
        jsr rdeg
        ldy #14
        jsr rput
@r      rts

; ---- J in the lanes: roll the cursor bar's pattern
l_roll  jsr ensure_pat
        bcs @r
        jsr curpat
        bcs @r
        lda cbar
        and #3
        sta rchord
        jsr roll_pat
        sei
        jsr pl_inval
        cli
        jsr msg
        !scr "rolled. press j for another", 0
        lda #1
        sta dirty
@r      rts

; ---- B: SHAPE.  Tracks enter one at a time, every 2 bars, in track order; bar b plays pattern (b mod 4) + 1; empty patterns are rolled.
l_build ldx #<m_build
        ldy #>m_build
        jsr askyn
        bcs @go
        rts
@go     sei
        jsr pl_stop
        cli
        lda ctrk
        pha
        lda #0
        sta lt
@t      ldx lt
        lda barlo,x
        sta bp
        lda barhi,x
        sta bp+1
        ldy #127
        lda #0
@z      sta (bp),y
        dey
        bpl @z
        lda lt                  ; first bar = 2 * track
        asl
        tay
@b      cpy #24
        bcs @bd
        tya
        and #3
        clc
        adc #1
        sta (bp),y
        iny
        bne @b
@bd     inc lt
        lda lt
        cmp #8
        bne @t
        lda #24
        sta SONG+H_LEN
        lda #0
        sta lt
@tr     lda lt                  ; the four patterns of this track
        sta ctrk
        lda #0
        sta bpn
@p      lda bpn
        clc
        adc #1
        ldx ctrk
        jsr patptr
        ldy #15
@e      lda (ip),y
        bne @have
        dey
        bpl @e
        lda bpn
        sta rchord
        jsr roll_pat
@have   inc bpn
        lda bpn
        cmp #4
        bne @p
        inc lt
        lda lt
        cmp #8
        bne @tr
        pla
        sta ctrk
        sei
        jsr pl_inval
        cli
        lda #0
        sta cbar
        jsr msg
        !scr "built: a track every 2 bars", 0
        lda #1
        sta dirty
@r      rts
m_build !scr "build the arrangement? y/n", 0
