; player.asm - the Octo Weaver player: 8 tracks, one per SID, 3 voices a SID.  ACME.  By Mong00se (Octophonic 64).
; Assembled at $1000 into the editor, into NAME PLAY and into a demo's NAME.OWP.  No screen code.  The song sits at SONG
; (defs.inc).  Interface (for a demo):
;   JSR $1000   init: A = the bar to start at (0 = the beginning).  Wakes all 8 SIDs, starts playing.
;   JSR $1003   play: once a frame from the demo's raster IRQ.  Keeps the registers it uses to itself? NO: it trashes A X Y.
;   JSR $1006   stop: all 8 SIDs silenced (volume 0, then the gates off)
;   (the editor also uses: $1009 trig X=track A=note Y=sound, $100C gate X=track, $100F quiet, $1012 inval)
; Zero page used: $E0-$EF.  Needs the I/O area visible ($01 bit 1/2 set) and no other use of $1000 to the end of the song.
; How a step happens: at step N-2 frames the next notes are worked out into a buffer (no SID writes), at N-1 the voices about
; to be struck get a hard restart (gate off, AD = SR = 0), at N the buffer is written to the SIDs, a few writes a voice.
!zone player
ZS      = $E0           ; pointer to the SID of the track being worked on
ZP      = $E2           ; pointer to a pattern
ZQ      = $E4           ; pointer to a sound
CT      = $E6           ; the track
CK      = $E7           ; the voice 0-2
VI      = $E8           ; the voice's index in the 24-byte arrays: track + 8 * voice
T0      = $E9
T1      = $EA
T2      = $EB
T3      = $EC
T4      = $ED
FXF     = $EE           ; the track's effect flags
AGE     = $EF           ; frames since the track's note was struck (255 at most)

        * = PLAYER
        jmp pl_init
        jmp pl_play
        jmp pl_stop
        jmp pl_trig
        jmp pl_gate
        jmp pl_quiet
        jmp pl_inval

; ------------------------------------------------------------------------------------------------ init, stop
pl_init sta T0                  ; the start bar
        lda #0
        tax
-       sta VARS,x
        sta VARS+256,x
        sta VARS+512,x
        inx
        bne -
        ldx #7
        lda #1
-       sta fdt,x
        dex
        bpl -
        sta fany
        jsr pl_quiet            ; wakes every SID (a volume write and a control write) and silences it
        lda T0
        cmp SONG+H_LEN
        bcc +
        lda #0
+       sta npos
        jsr refresh
        lda SONG+H_SPEED
        sta tick                ; the first frame runs all three phases
        lda #1
        sta playing
        rts

pl_stop lda #0
        sta playing
pl_quiet
        ldx #23
        lda #0
-       sta vctl,x
        dex
        bpl -
        ldx #7
@l      jsr setzs
        lda #0
        ldy #$18
        sta (ZS),y
        ldy #4
        sta (ZS),y
        ldy #11
        sta (ZS),y
        ldy #18
        sta (ZS),y
        sta pend,x
        sta tr_fx,x
        dex
        bpl @l
        rts

; ZS = SID X (X kept)
setzs   lda sidlo,x
        sta ZS
        lda sidhi,x
        sta ZS+1
        rts

; ------------------------------------------------------------------------------------------------ once a frame
!macro MARK c {
!ifdef PROFILE {
        lda #c
        sta $d020
}
}
pl_play +MARK 2
        jsr fx_all
        +MARK 5
        jsr filters
        +MARK 1
        lda playing
        beq @r
        inc tick
        lda tick                ; four chunks of work in the four frames before the strike: the notes of two tracks each (frame N-4 .. N-1);
        clc                     ; the last also does the hard restart of the voices to be struck.  (At speed < 4 they bunch up.)
        adc #4
        cmp SONG+H_SPEED
        bcc @r
        lda #1
        ldx #0
        jsr chunk
        lda tick
        clc
        adc #3
        cmp SONG+H_SPEED
        bcc @r
        lda #2
        ldx #2
        jsr chunk
        lda tick
        clc
        adc #2
        cmp SONG+H_SPEED
        bcc @r
        lda #4
        ldx #4
        jsr chunk
        lda tick
        clc
        adc #1
        cmp SONG+H_SPEED
        bcc @r
        lda #8
        ldx #6
        jsr chunk
        lda tick                ; the strike
        cmp SONG+H_SPEED
        bcc @r
        +MARK 4
        jsr commit_all
        +MARK 1
        lda #0
        sta tick
        sta phase
        +MARK 8
        jsr advance
        +MARK 1
@r      rts

; chunk A (the phase bit) = the notes of tracks X, X+1, once
chunk   sta chbit
        and phase
        bne @r
        txa
        clc
        adc #2
        tay
        jsr compute_range
        lda chbit
        cmp #8
        bne +
        jsr hr_all
+       lda phase
        ora chbit
        sta phase
@r      rts

; the song position moves on: what was "next" is now playing; work out the next one
advance lda npos
        sta pos
        lda nstep
        sta step
        inc nstep
        lda nstep
        cmp #16
        bne @r
        lda #0
        sta nstep
        inc npos
        lda npos
        cmp SONG+H_LEN
        bcc +
        lda #0
        sta npos
+       jmp refresh
@r      rts

; the pattern pointers of bar npos, all 8 tracks
refresh ldx #7
@t      lda barlo,x
        sta ZP
        lda barhi,x
        sta ZP+1
        ldy npos
        lda (ZP),y
        beq @z
        cmp #49
        bcs @z
        tay
        lda plot,y
        sta pplo,x
        lda phit,y
        clc
        adc pbhi,x
        sta pphi,x
        bne @n
@z      lda #<zeropat
        sta pplo,x
        lda #>zeropat
        sta pphi,x
@n      dex
        bpl @t
        rts

; ------------------------------------------------------------------------------------------------ phase 1: the next notes
; the next notes of tracks X .. Y-1
compute_range
!ifdef PROFILE {
        lda #6
        cpx #4
        bcc +
        lda #7
+       sta $d020
}
        sty cend
@t      lda #0
        sta pend,x
        lda tmute,x
        bne @n
        lda pplo,x
        sta ZP
        lda pphi,x
        sta ZP+1
        ldy nstep
        lda (ZP),y
        beq @n
        cmp #255
        beq @off
        pha
        tya
        clc
        adc #16
        tay
        lda (ZP),y
        tay
        bne +
        ldy #1
+       pla
        jsr comp                ; X = track, A = note, Y = sound (1-31)
        ldx CT
        lda #1
        sta pend,x
        bne @n
@off    lda #2
        sta pend,x
@n      inx
        cpx cend
        bne @t
        rts

; work out track X striking note A with sound Y into the frequency buffer and the track's state.  The sound's own values (the
; voicing, the registers other than the frequency, the effect flags) are parsed once per sound change and kept in arrays
; (tr_ck says for which sound); a strike of the same sound again only looks up the frequencies.
; (The editor calls pl_inval after changing a sound.)
comp    stx CT
        sta cn
        sty cs
        tya
        sta tr_snd,x
        lda tr_note,x
        sta cprev
        lda cn
        sta tr_note,x
        lda #0
        sta tr_age,x
        sta tr_sh,x
        sta tr_pwl,x
        sta tr_pwd,x
        lda tr_ck,x
        cmp cs
        beq @same
        jsr parse
        ldx CT
@same   lda tp_pw,x
        sta tr_pwh,x
        lda tr_sp,x
        bne @special
        lda vb,x                ; the common case: three table lookups
        cmp #$ff
        beq +
        clc
        adc cn
        tay
        lda ftlo,y
        sta bfl,x
        lda fthi,y
        sta bfh,x
+       lda vb+8,x
        cmp #$ff
        beq +
        clc
        adc cn
        tay
        lda ftlo,y
        sta bfl+8,x
        lda fthi,y
        sta bfh+8,x
+       lda vb+16,x
        cmp #$ff
        beq +
        clc
        adc cn
        tay
        lda ftlo,y
        sta bfl+16,x
        lda fthi,y
        sta bfh+16,x
+       lda tr_fxb,x
        sta tr_fx,x
        rts
@special
        jmp voices_special

; the sound (ZQ is its address) into the arrays
parse   lda sndlo,y
        sta ZQ
        lda sndhi,y
        sta ZQ+1
        lda #0
        sta cfx
        sta vsl_lo,x
        sta vsl_lo+8,x
        sta vsl_lo+16,x
        sta vsl_hi,x
        sta vsl_hi+8,x
        sta vsl_hi+16,x
        sta vdt_lo,x
        sta vdt_lo+8,x
        sta vdt_lo+16,x
        sta vdt_hi,x
        sta vdt_hi+8,x
        sta vdt_hi+16,x
        ldy #S_VOICING
        lda (ZQ),y
        sta cv
        sta tr_vc,x
        ldy #S_DETUNE
        lda (ZQ),y
        sta cdet
        sta tp_det,x
        ldy #S_GLIDE
        lda (ZQ),y
        sta cgl
        sta tp_gl,x
        ldy #S_FALL
        lda (ZQ),y
        sta cfall
        sta tp_fall,x
        ldy #S_PW
        lda (ZQ),y
        sta cpw
        sta tp_pw,x
        lda cv                  ; the voicing's three note offsets
        asl
        clc
        adc cv
        tay
        lda vtab,y
        sta vb,x
        lda vtab+1,y
        sta vb+8,x
        lda vtab+2,y
        sta vb+16,x
        lda cv                  ; the drum kit's noise voice only if DETUNE > 0
        cmp #6
        bne +
        lda cdet
        bne +
        lda #$ff
        sta vb+8,x
+       ldy #S_ARP
        lda (ZQ),y
        beq +
        asl
        asl
        sta tr_arp,x
        lda #1
        ora cfx
        sta cfx
+       ldy #S_PWM
        lda (ZQ),y
        beq +
        asl
        asl
        asl
        sta tr_pws,x
        lda #2
        ora cfx
        sta cfx
+       ldy #S_VIB
        lda (ZQ),y
        beq +
        lsr
        lsr
        clc
        adc #1
        sta tr_vib,x
        lda #4
        ora cfx
        sta cfx
+       ldy #S_FILT
        lda (ZQ),y
        beq +
        lda #7
+       sta tr_route,x
        lda #1                  ; the routing changed: this SID's filter registers are written at once
        sta fdt,x
        sta fany
        ldy #S_WP               ; a wave program (any of its four bytes)
        lda (ZQ),y
        iny
        ora (ZQ),y
        iny
        ora (ZQ),y
        iny
        ora (ZQ),y
        beq +
        lda #$10
        ora cfx
        sta cfx
+       lda cfx
        sta tr_fxb,x
        ldy #S_WP
        lda (ZQ),y
        bne +
        ldy #S_WAVE
        lda (ZQ),y
+       sta cwave0
        ldy #S_AD
        lda (ZQ),y
        sta cad
        ldy #S_SR
        lda (ZQ),y
        sta csr
        ; the unison / glide / fall sounds take the slower path
        lda #0
        ldy cgl
        bne @sp
        ldy cfall
        bne @sp
        ldy cv
        cpy #1
        bne +
        ldy cdet
        beq +
@sp     lda #1
+       sta tr_sp,x
        ; the other registers of the three voices
        stx VI
        lda #0
        sta CK
@pv     ldx VI
        lda vb,x
        cmp #$ff
        bne +
        lda #0
        sta bst,x
        beq @pn
+       lda #1
        sta bst,x
        lda cpw
        sta bpw,x
        lda cv                  ; the drum kit's noise voice
        cmp #6
        bne @tone
        lda CK
        cmp #1
        bne @tone
        lda #$81
        sta bctl,x
        lda cdet
        sta bad,x
        lda #0
        sta bsr,x
        beq @pn
@tone   lda cwave0
        ora #1
        sta bctl,x
        lda cad
        sta bad,x
        lda csr
        sta bsr,x
@pn     lda VI
        clc
        adc #8
        sta VI
        inc CK
        lda CK
        cmp #3
        bne @pv
        ldx CT
        lda cs
        sta tr_ck,x
        rts

; the unison / glide / fall sounds: the frequencies of the three voices, one by one
voices_special
        lda tr_fxb,x
        sta cfx
        lda tr_vc,x
        sta cv
        lda tp_det,x
        sta cdet
        lda tp_gl,x
        sta cgl
        lda tp_fall,x
        sta cfall
        lda #0
        sta vsl_lo,x
        sta vsl_lo+8,x
        sta vsl_lo+16,x
        sta vsl_hi,x
        sta vsl_hi+8,x
        sta vsl_hi+16,x
        sta vdt_lo,x
        sta vdt_lo+8,x
        sta vdt_lo+16,x
        sta vdt_hi,x
        sta vdt_hi+8,x
        sta vdt_hi+16,x
        stx VI
        lda #0
        sta CK
@v      ldx VI
        lda vb,x
        cmp #$ff
        bne @vu
        jmp @next
@vu     clc
        adc cn
        sta cidx
        tay
        lda ftlo,y
        sta f0
        lda fthi,y
        sta f1
        ; unison: voice 0 flat, voice 1 sharp by D = hi byte * DETUNE / 4
        lda cv
        cmp #1
        bne @nodet
        lda CK
        cmp #2
        bcs @nodet
        lda cdet
        beq @nodet
        lda CK
        bne @k1
        lda f1
        sta T0
        lda #0
        sta T1
        lda cdet
        jsr mulnib
        lsr T3
        ror T2
        lsr T3
        ror T2
        lda T2
        sta cD
        lda T3
        sta cD+1
        sec
        lda f0
        sbc cD
        sta f0
        lda f1
        sbc cD+1
        sta f1
        sec
        lda #0
        sbc cD
        sta vdt_lo,x
        lda #0
        sbc cD+1
        sta vdt_hi,x
        jmp @detdone
@k1     clc
        lda f0
        adc cD
        sta f0
        lda f1
        adc cD+1
        sta f1
        lda cD
        sta vdt_lo,x
        lda cD+1
        sta vdt_hi,x
@detdone
        lda #$20
        ora cfx
        sta cfx
@nodet  ; glide: start from the last note's pitch and slide
        lda cgl
        beq @nogl
        lda cprev
        beq @nogl
        lda vb,x
        clc
        adc cprev
        tay
        lda ftlo,y
        sta T0
        lda fthi,y
        sta T1
        ldy cidx
        sec
        lda T0
        sbc ftlo,y
        sta vsl_lo,x
        lda T1
        sbc fthi,y
        sta vsl_hi,x
        clc
        lda f0
        adc vsl_lo,x
        sta f0
        lda f1
        adc vsl_hi,x
        sta f1
        lda #8
        ora cfx
        sta cfx
        ldy cgl
        lda gshift,y
        ldx CT
        sta tr_sh,x
        jmp @rec
@nogl   lda cfall               ; fall: start high, drop to the note
        beq @rec
        lda cv
        cmp #6
        bne +
        lda CK
        cmp #1
        beq @rec
+       lda f0
        sta T0
        lda f1
        sta T1
        lsr T1
        ror T0
        lsr T1
        ror T0
        lda cfall
        jsr mulnib
        lda T3
        bpl +
        lda #$7f
        sta T3
        lda #$ff
        sta T2
+       ldx VI
        lda T2
        sta vsl_lo,x
        lda T3
        sta vsl_hi,x
        clc
        lda f0
        adc T2
        sta f0
        lda f1
        adc T3
        sta f1
        bcc +
        lda #$ff
        sta f0
        sta f1
+       lda #8
        ora cfx
        sta cfx
        ldx CT
        lda tr_sh,x
        bne @rec
        lda #2
        sta tr_sh,x
@rec    ldx VI
        lda f0
        sta bfl,x
        lda f1
        sta bfh,x
@next   lda VI
        clc
        adc #8
        sta VI
        inc CK
        lda CK
        cmp #3
        beq +
        jmp @v
+       ldx CT
        lda cfx
        sta tr_fx,x
        rts

; T0/T1 x nibble A -> T2/T3 (16 bits, saturating at $FFFF)
mulnib  sta T4
        lda #0
        sta T2
        sta T3
        ldy #4
@l      lsr T4
        bcc @s
        clc
        lda T2
        adc T0
        sta T2
        lda T3
        adc T1
        sta T3
        bcs @sat
@s      asl T0
        rol T1
        bcc @c
        lda T4
        bne @sat
@c      dey
        bne @l
        rts
@sat    lda #$ff
        sta T2
        sta T3
        rts

; ------------------------------------------------------------------------------------------------ phase 2: hard restart
hr_all  ldx #7
@t      lda pend,x
        cmp #1
        bne @n
        jsr hr_t
@n      dex
        bpl @t
        rts

hr_t    jsr setzs
        lda #0
        ldy vctl,x
        beq +
        ldy #4
        sta (ZS),y
        iny
        sta (ZS),y
        iny
        sta (ZS),y
        sta vctl,x
+       ldy vctl+8,x
        beq +
        ldy #11
        sta (ZS),y
        iny
        sta (ZS),y
        iny
        sta (ZS),y
        sta vctl+8,x
+       ldy vctl+16,x
        beq +
        ldy #18
        sta (ZS),y
        iny
        sta (ZS),y
        iny
        sta (ZS),y
        sta vctl+16,x
+       rts

; ------------------------------------------------------------------------------------------------ phase 3: strike
commit_all
        ldx #0
@t      lda pend,x
        beq @n
        cmp #2
        beq @off
        jsr docommit
        jmp @c
@off    jsr gateoff_t
@c      lda #0
        sta pend,x
@n      inx
        cpx #8
        bne @t
        rts

docommit
        lda cmhi,x
        pha
        lda cmlo,x
        pha
        rts                     ; "returns" into the track's commit routine, which RTSes back to our caller

; the gates of track X off (the release begins); its effects stop
gateoff_t
        jsr setzs
        lda vctl,x
        and #$fe
        sta vctl,x
        ldy #4
        sta (ZS),y
        lda vctl+8,x
        and #$fe
        sta vctl+8,x
        ldy #11
        sta (ZS),y
        lda vctl+16,x
        and #$fe
        sta vctl+16,x
        ldy #18
        sta (ZS),y
        lda #2
        sta ev,x
        lda #0
        sta tr_fx,x
        rts

; editor: play a note now. X = track, A = note, Y = sound
pl_trig jsr comp
        ldx CT
        jsr hr_t
        ldx CT
        jsr docommit
        ldx CT
        rts
; editor: gate off the track in X
pl_gate lda #0
        sta pend,x
        jmp gateoff_t
; editor: a sound was changed - parse the sounds again at the next strike
pl_inval
        lda #0
        ldx #7
-       sta tr_ck,x
        dex
        bpl -
        ldx #7
        lda #1
-       sta fdt,x
        dex
        bpl -
        sta fany
        rts

; the macros that write one track's buffer to its SID
!macro CVOICE vi, sid {
        lda bst+vi
        beq .skip
        lda bfl+vi
        sta sid+0
        lda bfh+vi
        sta sid+1
        lda #0
        sta sid+2
        lda bpw+vi
        sta sid+3
        lda bad+vi
        sta sid+5
        lda bsr+vi
        sta sid+6
        lda bctl+vi
        sta vctl+vi
        sta sid+4
.skip
}
!macro CTRACK T, SIDA {
        +CVOICE T, SIDA+0
        +CVOICE T+8, SIDA+7
        +CVOICE T+16, SIDA+14
        lda #1
        sta ev+T
        rts
}
commits
!for T, 0, 7 {
        +CTRACK T, $D400 + (T & 1)*$20 + (T & 4)*$20 + (T & 2)*$80
}
commits_end
CSZ     = (commits_end - commits) / 8

; ------------------------------------------------------------------------------------------------ every frame: effects
fx_all  ldx #0
@t      lda pend,x
        bne @n
        lda tr_fx,x
        beq @n
        jsr fx_track
@n      inx
        cpx #8
        bne @t
        rts

fx_track
        sta FXF
        stx CT
        lda tr_age,x
        cmp #255
        beq +
        clc
        adc #1
        sta tr_age,x
+       lda tr_age,x
        sta AGE
        jsr setzs
        lda FXF
        and #$10
        beq +
        jsr fx_wp
+       lda FXF
        and #$0d
        beq +
        jsr fx_freq
+       lda FXF
        and #2
        beq +
        jsr fx_pwm
+       ldx CT
        rts

; the wave program: frames 1-3 use its bytes, frame 4 the sound's own wave
fx_wp   ldx CT
        lda tr_snd,x
        tay
        lda sndlo,y
        sta ZQ
        lda sndhi,y
        sta ZQ+1
        lda AGE
        cmp #4
        bcs @end
        clc
        adc #S_WP
        tay
        lda (ZQ),y
        bne @go
        ldy #S_WAVE
        lda (ZQ),y
@go     ora #1
        jmp setctl
@end    lda tr_fx,x
        and #$ef
        sta tr_fx,x
        ldy #S_WAVE
        lda (ZQ),y
        ora #1
; control byte A to the track's voices (the drum kit: voice 0 only)
setctl  sta T0
        ldx CT
        lda vb,x
        cmp #$ff
        beq +
        lda T0
        sta vctl,x
        ldy #4
        sta (ZS),y
+       lda tr_vc,x
        cmp #6
        beq @r
        lda vb+8,x
        cmp #$ff
        beq +
        lda T0
        sta vctl+8,x
        ldy #11
        sta (ZS),y
+       lda vb+16,x
        cmp #$ff
        beq @r
        lda T0
        sta vctl+16,x
        ldy #18
        sta (ZS),y
@r      rts

; the notes' frequencies again: arp, slide, vibrato
fx_freq lda #0
        sta CK
        sta YR
        lda CT
        sta VI
@v      ldx VI
        lda vb,x
        cmp #$ff
        bne @go
        jmp @next
@go     ldx CT
        clc
        adc tr_note,x
        sta T0
        lda FXF
        and #1
        beq +
        lda AGE
        and #3
        clc
        adc tr_arp,x
        tay
        lda arptab,y
        clc
        adc T0
        sta T0
+       ldy T0
        lda ftlo,y
        sta T1
        lda fthi,y
        sta T2
        ldx VI
        lda FXF
        and #$20
        beq +
        clc
        lda T1
        adc vdt_lo,x
        sta T1
        lda T2
        adc vdt_hi,x
        sta T2
+       lda FXF
        and #8
        beq @nosl
        clc
        lda T1
        adc vsl_lo,x
        sta T1
        lda T2
        adc vsl_hi,x
        sta T2
        bcc @nosat
        lda vsl_hi,x
        bmi @nosat
        lda #$ff
        sta T1
        sta T2
@nosat  jsr slide_decay
@nosl   lda FXF
        and #4
        beq +
        lda AGE
        cmp #12
        bcc +
        jsr vib_add
+       ldy YR
        lda T1
        sta (ZS),y
        iny
        lda T2
        sta (ZS),y
@next   lda YR
        clc
        adc #7
        sta YR
        lda VI
        clc
        adc #8
        sta VI
        inc CK
        lda CK
        cmp #3
        beq @fin
        jmp @v
@fin    lda FXF                 ; the slides all at rest: stop recomputing for them
        and #8
        beq @r
        ldx CT
        lda vsl_lo,x
        ora vsl_hi,x
        ora vsl_lo+8,x
        ora vsl_hi+8,x
        ora vsl_lo+16,x
        ora vsl_hi+16,x
        bne @r
        lda tr_fx,x
        and #$f7
        sta tr_fx,x
@r      rts

; the slide of voice VI (X) shrinks: s = s - (s >> shift), at least 1 towards 0
slide_decay
        lda vsl_lo,x
        ora vsl_hi,x
        beq @r
        lda vsl_lo,x
        sta T3
        lda vsl_hi,x
        sta T4
        ldy CT
        lda tr_sh,y
        tay
@sh     lda T4
        cmp #$80
        ror T4
        ror T3
        dey
        bne @sh
        lda T3
        ora T4
        bne @sub
        lda vsl_hi,x
        bmi @neg
        lda #1
        sta T3
        lda #0
        sta T4
        beq @sub
@neg    lda #$ff
        sta T3
        sta T4
@sub    sec
        lda vsl_lo,x
        sbc T3
        sta vsl_lo,x
        lda vsl_hi,x
        sbc T4
        sta vsl_hi,x
@r      rts

; T1/T2 += the vibrato for this frame (phase AGE & 7; the size from the voice's own pitch)
vib_add lda AGE
        and #7
        tay
        lda vibtab,y
        beq @r
        sta T0
        lda #0
        sta T4
        lda T2
        sta T3
        ldx CT
        lda tr_vib,x
        cmp #3
        beq @amt
        bcs @big
        cmp #2
        beq @b2
        lsr T3
@b2     lsr T3
        jmp @amt
@big    asl T3
        rol T4
@amt    lda T0                  ; 1 and 3 are the half-height beats of the wave
        and #1
        beq +
        lsr T4
        ror T3
+       lda T0
        cmp #3
        bcs @sub
        clc
        lda T1
        adc T3
        sta T1
        lda T2
        adc T4
        sta T2
        rts
@sub    sec
        lda T1
        sbc T3
        sta T1
        lda T2
        sbc T4
        sta T2
@r      rts

; pulse width motion
fx_pwm  ldx CT
        lda tr_pwd,x
        bne @down
        clc
        lda tr_pwl,x
        adc tr_pws,x
        sta tr_pwl,x
        lda tr_pwh,x
        adc #0
        sta tr_pwh,x
        cmp #$0e
        bcc @wr
        lda #1
        sta tr_pwd,x
        bne @wr
@down   sec
        lda tr_pwl,x
        sbc tr_pws,x
        sta tr_pwl,x
        lda tr_pwh,x
        sbc #0
        sta tr_pwh,x
        cmp #$02
        bcs @wr
        lda #0
        sta tr_pwd,x
@wr     lda vb,x
        cmp #$ff
        beq +
        ldy #2
        lda tr_pwl,x
        sta (ZS),y
        iny
        lda tr_pwh,x
        sta (ZS),y
+       lda vb+8,x
        cmp #$ff
        beq +
        ldy #9
        lda tr_pwl,x
        sta (ZS),y
        iny
        lda tr_pwh,x
        sta (ZS),y
+       lda vb+16,x
        cmp #$ff
        beq @r
        ldy #16
        lda tr_pwl,x
        sta (ZS),y
        iny
        lda tr_pwh,x
        sta (ZS),y
@r      rts

; ------------------------------------------------------------------------------------------------ the dials
; Each SID's filter registers ($16 cutoff, $17 resonance + routing, $18 mode + volume) are written once every 4 frames (SID n in
; frame group n & 3), at once after a start, a stop, a sound change that changes the routing (fdt), or the editor's pl_inval.
; X = track: write its three registers (X kept)
filt_one
        jsr setzs
        jsr lfo_cut             ; A = the cutoff: the dial, plus a slow triangle sweep if the track has an LFO
        ldy #$16
        sta (ZS),y
        lda SONG+H_DRES,x
        ora tr_route,x
        iny
        sta (ZS),y
        lda SONG+H_DMV,x
        iny
        sta (ZS),y
        rts
; X = track -> A = the cutoff now.  H_LFO: rate in the low nibble (phase step a frame), depth in the high nibble:
; cutoff = dial + triangle (0-127) * depth / 16, at most 255.  X is kept.  (Called every 4 frames: the phase moves 4 x the rate.)
lfo_cut lda SONG+H_LFO,x
        bne @on
        lda SONG+H_DCUT,x
        rts
@on     and #15
        asl
        asl
        clc
        adc lfop,x
        sta lfop,x              ; the phase 0-255
        bpl @up
        eor #$ff                ; the falling half
@up     and #$7f
        sta T0
        lda SONG+H_LFO,x
        lsr
        lsr
        lsr
        lsr
        sta T1
        lda #0
        ldy #4
@m      lsr T1
        bcc @s
        clc
        adc T0
@s      lsr
        dey
        bne @m
        clc
        adc SONG+H_DCUT,x
        bcc @r
        lda #255
@r      rts

filters inc fcnt
        lda fcnt
        and #3
        tax
        jsr filt_one            ; SID n & 3 ...
        txa
        ora #4
        tax
        jsr filt_one            ; ... and the one 4 above it
        lda fany
        beq @r
        lda #0
        sta fany
        ldx #7
@l      lda fdt,x
        beq @n
        lda #0
        sta fdt,x
        jsr filt_one
@n      dex
        bpl @l
@r      rts

; ------------------------------------------------------------------------------------------------ tables
!source "ftab.inc"
sidlo   !for N, 0, 7 { !byte <($D400 + (N & 1)*$20 + (N & 4)*$20 + (N & 2)*$80) }
sidhi   !for N, 0, 7 { !byte >($D400 + (N & 1)*$20 + (N & 4)*$20 + (N & 2)*$80) }
sndlo   !for N, 0, 31 { !byte <(SND + N*16) }
sndhi   !for N, 0, 31 { !byte >(SND + N*16) }
barlo   !for N, 0, 7 { !byte <(BAR + N*128) }
barhi   !for N, 0, 7 { !byte >(BAR + N*128) }
pbhi    !for N, 0, 7 { !byte >(PAT + N*1536) }
plot    !byte 0
        !for N, 1, 48 { !byte <((N-1)*32) }
phit    !byte 0
        !for N, 1, 48 { !byte >((N-1)*32) }
rt24    !for N, 0, 7 { !byte N*24 }
cmlo    !for N, 0, 7 { !byte <(commits + N*CSZ - 1) }
cmhi    !for N, 0, 7 { !byte >(commits + N*CSZ - 1) }
; the voicings: three note offsets (+12 bias into the frequency table), $FF = voice off
vtab    !byte 12, $ff, $ff              ; 0 one voice
        !byte 12, 12, $ff               ; 1 unison pair
        !byte 12, 24, 0                 ; 2 octave stack: the note, an octave up, an octave down
        !byte 12, 19, 24                ; 3 power chord: root, fifth, octave
        !byte 12, 16, 19                ; 4 major triad
        !byte 12, 15, 19                ; 5 minor triad
        !byte 12, 24, $ff               ; 6 drums: tone, noise (an octave up), -
; the arp patterns, 4 frames each (semitones added), pattern 0 unused
arptab  !byte 0, 0, 0, 0
        !byte 0, 12, 0, 12              ; 1 octaves
        !byte 0, 4, 7, 12               ; 2 major
        !byte 0, 3, 7, 12               ; 3 minor
        !byte 0, 7, 12, 7               ; 4 fifths
        !byte 0, 12, 7, 12              ; 5 octave-fifth
        !byte 0, 0, 12, 12              ; 6 slow octaves
        !byte 12, 0, 7, 0               ; 7 down-up
vibtab  !byte 0, 1, 2, 1, 0, 3, 4, 3    ; 0 none, 1 +half, 2 +full, 3 -half, 4 -full (3,4 subtract: see vib_add)
gshift  !byte 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4
zeropat !fill 32, 0

; ------------------------------------------------------------------------------------------------ variables
        !align 255, 0
VARS
tr_note !fill 8, 0
tr_snd  !fill 8, 0
tr_fx   !fill 8, 0              ; b0 arp, b1 pwm, b2 vibrato, b3 slide, b4 wave program, b5 detune
tr_age  !fill 8, 0
tr_pwl  !fill 8, 0
tr_pwh  !fill 8, 0
tr_pws  !fill 8, 0
tr_pwd  !fill 8, 0
tr_vib  !fill 8, 0
tr_arp  !fill 8, 0
tr_sh   !fill 8, 0
tr_route !fill 8, 0
tr_vc   !fill 8, 0
tr_sp   !fill 8, 0              ; 1: the sound is a unison / glide / fall sound (slower path)
tr_ck   !fill 8, 0              ; the sound whose values are in tp_* / vb / tr_arp ... (0 = none: parse again)
tr_fxb  !fill 8, 0
tp_det  !fill 8, 0
tp_gl   !fill 8, 0
tp_fall !fill 8, 0
tp_pw   !fill 8, 0
tp_wave0 !fill 8, 0
tp_ad   !fill 8, 0
tp_sr   !fill 8, 0
pend    !fill 8, 0              ; 0 nothing, 1 strike, 2 gate off
pplo    !fill 8, 0
pphi    !fill 8, 0
vb      !fill 24, 0
vsl_lo  !fill 24, 0
vsl_hi  !fill 24, 0
vdt_lo  !fill 24, 0
vdt_hi  !fill 24, 0
vctl    !fill 24, 0
bfl     !fill 24, 0             ; the next notes' frequencies and the rest of what a strike writes, per voice
bfh     !fill 24, 0
bpw     !fill 24, 0
bctl    !fill 24, 0
bad     !fill 24, 0
bsr     !fill 24, 0
bst     !fill 24, 0             ; 1: the voice is used
ev      !fill 8, 0              ; events for the eq, per track: 1 struck, 2 gates off (the eq clears them)
playing !byte 0
tick    !byte 0
phase   !byte 0
chbit   !byte 0
pos     !byte 0                 ; the bar and step now sounding
step    !byte 0
npos    !byte 0                 ; the next
nstep   !byte 0
cn      !byte 0
cs      !byte 0
cv      !byte 0
cdet    !byte 0
cgl     !byte 0
cfall   !byte 0
cpw     !byte 0
cfx     !byte 0
cprev   !byte 0
cidx    !byte 0
cwave   !byte 0
cwave0  !byte 0
cad     !byte 0
csr     !byte 0
crec    !byte 0
f0      !byte 0
f1      !byte 0
cD      !word 0
cend    !byte 0
YR      !byte 0
lfop    !fill 8, 0              ; the filter LFO phases
fdt     !fill 8, 0              ; 1: write this SID's filter registers now
fcnt    !byte 0
fany    !byte 0
VARS_END
tmute   !fill 8, 0              ; nonzero: the track does not strike (the editor's mute / solo)
PLAYER_END = *
!if VARS_END - VARS > 768 { !error "player variables over 512 bytes" }
!if PLAYER_END > SONG { !error "the player runs into the song" }
