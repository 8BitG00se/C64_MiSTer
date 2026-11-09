; (C) 2026 Mong00se
; PLAYER.ASM - the music player of ODYSSEY.ASM (2026: An Octophonic
; Odyssey), by Mong00se. Plays SONG.ASM: 3 voices on SID 1 (stock),
; or 6 (SID 2 too: two SIDs, and the first two of the Octophonic's
; eight). Called once a frame (pl_play). Every voice reads its own
; list of notes (see SONG.ASM); each frame it moves the pulse width
; and a light, late vibrato, bows a tremolo, detunes the second
; SID's strings a little (an ensemble, not one fiddle), and sets the
; strings' lowpass from the song's swell table (fcut); it keeps a
; level for the equaliser (pv_eq: 0-20). Slurred notes ($62) change
; the pitch without a new bow (no new attack).
!ifdef odytop { !set odyp = odytop } else { !set odyp = 0 }
!if odyp = 0 {
        !src "odyssey.asm"
} else {

; the voices' state: 8 bytes a table, voice 0-5
PV      = $ca00
pv_plo  = PV+$00        ; where it is in its list
pv_phi  = PV+$08
pv_tim  = PV+$10        ; frames left of this note
pv_ins  = PV+$18        ; the instrument x 10
pv_note = PV+$20
pv_pwl  = PV+$38        ; the pulse width
pv_pwh  = PV+$40
pv_pwd  = PV+$48        ; 0 widening, 1 narrowing
pv_vbc  = PV+$50        ; frames until the vibrato starts
pv_vbp  = PV+$58        ; the vibrato's step 0-11
pv_vol  = PV+$60        ; the vibrato now (16 bits)
pv_voh  = PV+$68
pv_vd   = PV+$70        ; its step
pv_ctl  = PV+$78        ; the control register (wave, gate)
pv_eq   = PV+$80        ; the equaliser's level
pv_end  = PV+$88        ; 1: the list has ended
pv_rlo  = PV+$90        ; the voice's SID registers
pv_rhi  = PV+$98
mfr     = PV+$a0        ; 2: the song's frame
nvoice  = PV+$a2        ; 3 or 6
pl_f17  = PV+$a4        ; 2: SID 1's and SID 2's filter routing (+ resonance)
pl_sl   = PV+$a6        ; 1: the next note is slurred
pv_flg  = PV+$a8        ; the instrument's flags (a copy, quicker)
FILTRES = $20           ; the strings' filter: resonance 2, lowpass
pl_p    = $14           ; 2 (zero page)
pl_r    = $16           ; 2
pl_t    = $18           ; 2

; A = the voices (3: SID 1; 6: SID 1 and the SID at sid2lo/hi)
!zone pl_init
pl_init sta nvoice
        ldx #2
-       txa             ; SID 1: $D400 + 7 v
        asl
        asl
        asl
        sec
        sbc pl_v7,x
        sta pv_rlo,x
        lda #$d4
        sta pv_rhi,x
        txa             ; SID 2
        asl
        asl
        asl
        sec
        sbc pl_v7,x
        clc
        adc sid2lo
        sta pv_rlo+3,x
        lda sid2hi
        adc #0
        sta pv_rhi+3,x
        dex
        bpl -
        lda #FILTRES    ; the strings' lowpass (cutoff from fcut), volume up
        sta pl_f17
        sta pl_f17+1
        sta $d417
        lda #0
        sta $d415
        sta $d416
        lda #$1f
        sta $d418
        lda #$16        ; SID 2's cutoff and routing: SID 1's own without
        sta pl_c2+1     ; a SID 2 (harmless)
        lda #$17
        sta pl_f2+1
        lda #$d4
        sta pl_c2+2
        sta pl_f2+2
        lda nvoice
        cmp #6
        bne pl_rst
        clc
        lda sid2lo
        sta pl_r
        adc #$16
        sta pl_c2+1
        adc #1
        sta pl_f2+1
        lda sid2hi
        sta pl_r+1
        adc #0
        sta pl_c2+2
        sta pl_f2+2
        ldy #$15
        lda #0
        sta (pl_r),y
        iny
        sta (pl_r),y
        iny
        lda #FILTRES
        sta (pl_r),y
        iny
        lda #$1f
        sta (pl_r),y
; the song from the start
!zone pl_rst
pl_rst  lda #0
        sta mfr
        sta mfr+1
        ldx #5
-       lda vlistlo,x
        sta pv_plo,x
        lda vlisthi,x
        sta pv_phi,x
        lda #1
        sta pv_tim,x
        lda #0
        sta pv_end,x
        sta pv_ins,x
        sta pv_flg,x
        sta pv_ctl,x
        sta pv_eq,x
        dex
        bpl -
        sta pl_sl
        rts
!zone pl_v7
pl_v7   !byte 0, 1, 2       ; 8v - v = 7v
pl_vbit !byte 1, 2, 4, 1, 2, 4  ; the voice's filter routing bit
pl_vsid !byte 0, 0, 0, 1, 1, 1  ; its SID

; ---------------------------------------------------- every frame
!zone pl_play
pl_play inc mfr
        bne +
        inc mfr+1
+       lda mfr
        cmp #<songlen
        bne +
        lda mfr+1
        cmp #>songlen
        bne +
        jsr pl_rst
+       lda mfr         ; the strings' cutoff: fcut[mfr / 16], every 16
        and #15         ; frames
        bne .vs
        lda mfr
        sta pl_t
        lda mfr+1
        lsr
        ror pl_t
        lsr
        ror pl_t
        lsr
        ror pl_t
        lsr
        ror pl_t
        sta pl_t+1
        clc
        lda pl_t
        adc #<fcut
        sta pl_t
        lda pl_t+1
        adc #>fcut
        sta pl_t+1
        ldy #0
        lda (pl_t),y
        sta $d416
pl_c2   sta $d416       ; SID 2's (set by pl_init)
.vs     ldx #0
-       jsr pl_voice
        inx
        cpx nvoice
        bne -
        rts

!zone pl_voice
pl_voice
        lda pv_rlo,x
        sta pl_r
        lda pv_rhi,x
        sta pl_r+1
        lda pv_end,x
        bne .fx
        dec pv_tim,x
        bne .old
        jsr pl_next
        jmp .fx
.old    ldy pv_ins,x    ; time to let go? (not before a "hold on")
        lda pv_tim,x
        cmp instr+8,y
        bne .fx
        lda pv_plo,x
        sta pl_p
        lda pv_phi,x
        sta pl_p+1
        ldy #0
        lda (pl_p),y
        cmp #$61        ; (nor before a slur)
        beq .fx
        cmp #$62
        beq .fx
        jsr pl_off
.fx     jmp pl_fx

; gate off; with a hard restart also the envelope to 0
!zone pl_off
pl_off  lda pv_ctl,x
        and #$fe
        sta pv_ctl,x
        ldy #4
        sta (pl_r),y
        ldy pv_ins,x
        lda instr+7,y
        and #2
        beq +
        lda #0
        ldy #5
        sta (pl_r),y
        iny
        sta (pl_r),y
+       rts

; the next thing in the voice's list
!zone pl_next
pl_next lda pv_plo,x
        sta pl_p
        lda pv_phi,x
        sta pl_p+1
.again  ldy #0
        lda (pl_p),y
        cmp #$ff
        bne +
        lda #1          ; the end: quiet until the song starts again
        sta pv_end,x
        jmp pl_off
+       cmp #$62        ; a slur: the next note without a new bow
        bne +
        sta pl_sl
        jmp .skip1
+       cmp #$80
        bcc +
        and #$1f        ; an instrument (x 10)
        sta pl_t
        asl
        asl
        adc pl_t
        asl
        sta pv_ins,x
.skip1  inc pl_p
        bne .again
        inc pl_p+1
        jmp .again
+       pha
        iny
        lda (pl_p),y    ; the frames
        sta pv_tim,x
        clc
        lda pl_p
        adc #2
        sta pv_plo,x
        lda pl_p+1
        adc #0
        sta pv_phi,x
        pla
        cmp #$61        ; hold on
        bne +
        rts
+       cmp #$60        ; a rest
        bne +
        jmp pl_off
+       sta pv_note,x   ; a note
        lda pl_sl
        beq +
        lda #0          ; slurred: only the pitch (and the vibrato's step)
        sta pl_sl
        jmp pl_vd
+       ldy pv_ins,x
        lda pv_ctl,x    ; still sounding: let go first
        and #1
        beq +
        lda pv_ctl,x
        and #$fe
        ldy #4
        sta (pl_r),y
        ldy pv_ins,x
+       lda instr+1,y   ; the envelope
        pha
        lda instr+2,y
        ldy #6
        sta (pl_r),y
        pla
        dey
        sta (pl_r),y
        ldy pv_ins,x
        lda instr+3,y   ; the pulse width x 16
        sta pv_pwl,x
        lda #0
        asl pv_pwl,x
        rol
        asl pv_pwl,x
        rol
        asl pv_pwl,x
        rol
        asl pv_pwl,x
        rol
        sta pv_pwh,x
        lda #0
        sta pv_pwd,x
        sta pv_vbp,x
        sta pv_vol,x
        sta pv_voh,x
        lda instr+5,y
        sta pv_vbc,x
        lda instr+9,y   ; the equaliser jumps up
        sta pv_eq,x
        lda instr+7,y   ; through the filter or not
        sta pv_flg,x
        and #16
        php
        ldy pl_vsid,x
        lda pl_f17,y
        ora pl_vbit,x
        plp
        bne +
        eor pl_vbit,x
+       sta pl_f17,y
        cpy #0
        bne +
        sta $d417
        jmp ++
+
pl_f2   sta $d417       ; SID 2's (set by pl_init)
++      ldy pv_ins,x
        lda instr,y     ; the wave, gate on
        ora #1
        sta pv_ctl,x
        ldy #4
        sta (pl_r),y
; the vibrato's step: the note's frequency / 256, halved (depth - 1)
; times: depth 1 about 20 cents, 2 about 10, 3 about 5, 4 about 2.5
pl_vd   ldy pv_note,x
        lda freqhi,y
        sta pl_t
        ldy pv_ins,x
        lda instr+6,y
        beq .x
        tay
-       dey
        beq +
        lsr pl_t
        jmp -
+       lda pl_t
        sta pv_vd,x
.x      rts

; pulse width, vibrato, detune, tremolo: the frequency, the pulse
!zone pl_fx
pl_fx   ldy pv_note,x
        lda freqlo,y
        sta pl_t
        lda freqhi,y
        sta pl_t+1
        ldy pv_ins,x    ; the vibrato
        lda instr+6,y
        beq .novib
        lda pv_vbc,x
        beq +
        dec pv_vbc,x
        jmp .novib
+       lda pv_vbp,x    ; steps 0-2 and 9-11 up, 3-8 down
        cmp #3
        bcc .up
        cmp #9
        bcs .up
        sec
        lda pv_vol,x
        sbc pv_vd,x
        sta pv_vol,x
        lda pv_voh,x
        sbc #0
        sta pv_voh,x
        jmp .ph
.up     clc
        lda pv_vol,x
        adc pv_vd,x
        sta pv_vol,x
        lda pv_voh,x
        adc #0
        sta pv_voh,x
.ph     inc pv_vbp,x
        lda pv_vbp,x
        cmp #12
        bcc +
        lda #0
        sta pv_vbp,x
+       clc
        lda pl_t
        adc pv_vol,x
        sta pl_t
        lda pl_t+1
        adc pv_voh,x
        sta pl_t+1
.novib  lda pv_flg,x    ; detuned (SID 2's strings): + frequency / 256,
        and #8          ; about 7 cents
        beq +
        ldy pv_note,x
        lda freqhi,y
        clc
        adc pl_t
        sta pl_t
        bcc +
        inc pl_t+1
+       ldy #0
        lda pl_t
        sta (pl_r),y
        iny
        lda pl_t+1
        sta (pl_r),y
        ldy pv_ins,x    ; the pulse width: up and down
        lda instr+4,y
        beq .pw
        sta pl_t
        lda pv_pwd,x
        bne .dn
        clc
        lda pv_pwl,x
        adc pl_t
        sta pv_pwl,x
        lda pv_pwh,x
        adc #0
        sta pv_pwh,x
        cmp #$0c
        bcc .pw
        lda #1
        sta pv_pwd,x
        bne .pw
.dn     sec
        lda pv_pwl,x
        sbc pl_t
        sta pv_pwl,x
        lda pv_pwh,x
        sbc #0
        sta pv_pwh,x
        cmp #$04
        bcs .pw
        lda #0
        sta pv_pwd,x
.pw     ldy #2
        lda pv_pwl,x
        sta (pl_r),y
        iny
        lda pv_pwh,x
        sta (pl_r),y
        lda pv_flg,x    ; a tremolo: the bow changes every 2 frames
        and #4
        beq .eq
        lda pv_ctl,x
        lsr
        bcc .eq         ; (not while let go)
        lda mfr
        and #2
        beq +
        lda pv_ctl,x
        bne ++
+       lda pv_ctl,x
        and #$fe
++      ldy #4
        sta (pl_r),y
.eq
        lda pv_eq,x     ; the equaliser falls to half while the
        beq .x          ; note is held, to 0 after it
        ldy pv_ins,x
        lda pv_ctl,x
        and #1
        beq +
        lda instr+9,y
        lsr
+       cmp pv_eq,x
        bcs .x
        dec pv_eq,x
.x      rts
}
