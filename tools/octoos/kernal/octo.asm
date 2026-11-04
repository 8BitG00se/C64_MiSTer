; OCTOPHONIC 64 V1.1 - the start screen on the real C64 KERNAL and BASIC (approved: Neal's mock-up 12,
; 4 Nov 2026). By Neal - 8BitG00se.
;
;   EQ x8        OCTOPHONIC 64                  NET      o    rows 0-1: a dark box, its words a
;   8 SIDS       OCTOVIC 256                    16M REU       cyan-to-violet gradient a line
;   ==========================================================   a 1-pixel gradient rule
;   38911 BASIC BYTES FREE
;   READY.                                                     the screen editor scrolls rows 0-23
;   ...                                                        only; the top box scrolls away with
;   ==========================================================   the text, the bar stays
;   F1 BROWSE F3 LOAD F5 SIDS F7 DUAL F8 SET                   row 24
;
; How OctoVIC draws it (docs/OCTOVIC.md), no sprites. The VIC's page colour 6 is KEY (see-through)
; to the backdrop, navy. Over the box the copper makes KEY colour 3 instead - the box's words and the
; eq's cells (reverse spaces) - so colour 6 shows the VIC palette's 6, the box's dark, and the
; colour-3 pixels show layer 0: a 512 x 256 bitmap (VRAM $010000) whose rows 1-16 are the words'
; gradient, a palette entry a line (160 + 10 i), with the 8 eq bars in rows 1-8 (drawn by the IRQ
; from each SID's ENV3). Row 0 is the rules' gradient (palette 160-239, 4 pixels a step); the copper
; switches layer 0 on for each rule's one line, with SCROLLY set so that line shows row 0. The copper
; writes only KEY, SCROLLY and layer 0's LCTRL, each on its own line (exact on the core and the
; emulator). The network light is the VIC's ball (as before) at the end of the title row, coloured
; by the IRQ from NET. With no OctoVIC (a stock VIC): the same words, plain, and the 25-row editor.
;
; The screen editor's rows (patch.py): its own CPX #25 / #24 / #23 and LDX #24 read R25-R23 instead,
; 24 while the start screen is up, 25 otherwise (CINT, RUN, SYS, LOAD) - so typing and scrolling
; never reach the bar, and every program gets the stock 25-row editor.
;
; The code sits where the core never runs (it has no tape, and device 1 can't be opened): the tape
; room $F92C-$FB96, the tape LOAD and SAVE bodies, OPEN / CHRIN / CHROUT / CLOSE's tape paths, the
; tape's messages, the old banner ($E422-$E446, $E473-$E4AB - the start screen prints BYTES FREE
; itself), the KERNAL's unused $E4B7-$E4D2 and BASIC's $BF53-$BF70. octo.bin starts at $BF53;
; patch.py copies each piece (seg_x to seg_xe) into the ROM.
OCTST   = $02A7         ; 1: OctoVIC is drawing the start screen
AUTORUN = $02A8         ; 1: SHIFT+RUN/STOP asked for LOAD"*",8 - RUN goes in after it
TOPY    = $02B0         ; the top box: 0, scrolled up 8 a line, gone at -24
BUFSEL  = $02B1         ; the copper list in use: VRAM $00xx00, xx toggled by 3 (each layout)
TMP     = $02B9
ROW     = $02BA
HT      = $02C0         ; - $02C7: the eq bars this frame
R25     = $B0           ; the screen editor's rows (25, or 24 above the bar) - the tape's timing
R24     = $B1           ; bytes, unused without a tape
R23     = $BE
PLOT    = $FFF0
RUNKEYS = $FCCE         ; wedge2.asm, fixed
SHIFTR2 = $F929         ; wedge.asm, fixed
VA0     = $D600
VA1     = $D601
VA2     = $D602
VINC    = $D603
VDATA   = $D604

; -------------------- BASIC $BF53-$BF70 (30 bytes; only what the start screen runs with BASIC in)
        * = $BF53
seg_h
; the bar on row 24: the keys (bit 7 set in bar1) yellow, the labels pale
drawbar ldx #39
dbl     lda bar1,x
        asl
        php
        lsr
        sta $0400 + 960,x
        lda #15
        plp
        bcc dbc
        lda #7
dbc     sta $D800 + 960,x
        dex
        bpl dbl
        rts
cls     lda #$93
        jmp $FFD2
seg_he
!if seg_he > $BF71 { !error "past the room at $BF53" }

; ------------------------------------------ KERNAL $E422-$E446 (37 bytes: the old banner routine)
        * = $E422
seg_e
; the copper list (layout): line (under 128: from the box's top, 51 + TOPY; SCROLLY there less
; TOPY), register, value
coptab  !byte 0,$06,3, 0,$2A,1, 0,$20,$19       ; the box: KEY 3; layer 0 on, bitmap row 1 on line 0
        !byte 18,$06,6, 18,$2A,$EE, 19,$20,0    ; line 18: KEY 6, the rule (bitmap row 0); then off
        !byte 241,$2A,$42, 241,$20,$19          ; line 190 (raster 241): the bottom rule, in front
        !byte 241,$05,$0F                       ; of the VIC (row 23's letters never cut it)
        !byte 242,$20,0, 242,$05,$0B, 242,$06,3 ; line 191: KEY 3 - the bar's dark
seg_ee
!if seg_ee > $E447 { !error "past the room at $E422" }

; --------------------------------------------- KERNAL $E473-$E4AB (57 bytes: the old banner text)
        * = $E473
seg_f
; the words of the top box: screen offset, text, 0 (colour 3; 53, OCTOVIC: the rainbow); $FE ends
; the plain screen's, $FF the OctoVIC screen's (the eq's cells; the light)
texts   !byte 13
        !scr "octophonic 64", 0
        !byte 32
        !scr "net", 0
        !byte 40
        !scr "8 sids", 0
        !byte 53
        !scr "octovic", 0
        !byte 61
        !scr "256", 0, $FE
        !byte 0, $A0, $A0, $A0, $A0, $A0, $A0, 0
        !byte 38, $51, 0, $FF                   ; the network light (the IRQ colours it)
seg_fe
!if seg_fe > $E4AC { !error "past the room at $E473" }

; -------------------------------------- KERNAL $E4B7-$E4D2 (28 bytes: unused in the stock KERNAL)
        * = $E4B7
seg_g
; the scroll ($E8F6): the KERNAL's own three, then the top box up a line with the text
scrhk   dec $D6
        dec $C9
        dec $02A5
        lda OCTST
        beq scrx
        lda TOPY
        cmp #$E8
        beq scrx
        sec
        sbc #8
        jsr boxat
scrx    ldx #$FF
        rts
seg_ge
!if seg_ge > $E4D3 { !error "past the room at $E4B7" }

; ------------------------------ KERNAL $F0D8-$F105 (46 bytes: PRESS PLAY / RECORD & PLAY ON TAPE)
        * = $F0D8
seg_d
reut    !scr "16m", 0, "8m", 0, "4m", 0, "2m", 0, "1m", 0, "512k", 0, "256k", 0, "128k", 0, "no", 0
rsfx    !scr " reu", 0
n38911  !scr "38911"
seg_de
!if seg_de > $F106 { !error "past the room at $F0D8" }

; ---------------------------- KERNAL $F17C-$F1AC (49 bytes: CHRIN from tape - F179 now JMP $F70A)
        * = $F17C
seg_l
bar1    !byte $86, $B1, $20, $02, $12, $0F, $17, $13, $05, $20, $86, $B3, $20, $0C, $0F, $01, $04, $20, $86, $B5
        !byte $20, $13, $09, $04, $13, $20, $86, $B7, $20, $04, $15, $01, $0C, $20, $86, $B8, $20, $13, $05, $14   ; F1 BROWSE F3 LOAD F5 SIDS F7 DUAL F8 SET (keys: bit 7)

reuix   !byte 0, 4, 7, 10, 13, 16, 21, 26, 31  ; where each size's name starts in reut
seg_le
!if seg_le > $F1AD { !error "past the room at $F17C" }

; ----------------------------- KERNAL $F1E8-$F1FB (20 bytes: CHROUT to tape - F1E5 now JMP $F1FC)
        * = $F1E8
seg_m
; CLR ($E86E): the top box goes with its words
clrhk   jsr $E544
        lda OCTST
        beq clrx
        lda #$E8
boxat   sta TOPY
        jmp layout
clrx    rts

seg_me
!if seg_me > $F1FC { !error "past the room at $F1E8" }

; ----------------------- KERNAL $F2CB-$F2ED (35 bytes: CLOSE of a tape file - F2C8 now JMP $F2F1)
        * = $F2CB
seg_k
w_run   jsr octoff
        jmp $A871
w_sys   jsr octoff
        jmp $E12A
w_load  jsr octoff
        php
        pha
        lda AUTORUN             ; SHIFT+RUN/STOP: RUN waits in the keyboard buffer
        beq wl1
        jsr RUNKEYS             ; (wedge.asm: R U N RETURN, in full)
wl1     pla
        plp
        jmp $E168
; SHIFT+RUN/STOP: the buffer gets LOAD"*",8 in full (not the tape's LOAD) and RUN follows the load -
; wedge.asm's SHIFTR2 ($F929), called straight from the KERNAL (patch.py)
; SHIFT+RUN/STOP: the buffer gets LOAD"*",8 in full (not the tape's LOAD) and RUN follows the load -
; wedge.asm's SHIFTR2 ($F929), called straight from the KERNAL (patch.py)
shiftrun = SHIFTR2

seg_ke
!if seg_ke > $F2EE { !error "past the room at $F2CB" }

; ------------------------ KERNAL $F38E-$F3D2 (69 bytes: OPEN of a tape file, after its JMP $F713)
        * = $F38E
seg_i
; OctoVIC off before a program: LOAD, RUN and SYS come through here (and CINT); the 25-row
; editor again
octoff  php
        pha
        ldx #25
        jsr rows
        lda OCTST
        beq offx
        lda #0
        sta OCTST               ; first, so the IRQ leaves OctoVIC alone from here
        lda #$4F
        sta $D03F
        lda #$38
        sta $D03F
        lda #$00
        sta $D605
        sta $D60E
        sta $D03F
        lda #$20                ; the bar's row becomes an ordinary one
        ldx #39
offb    sta $0400 + 960,x
        dex
        bpl offb
        lda $F1
        ora #$80
        sta $F1
offx    pla
        plp
        rts

; CINT (reset, RUN/STOP+RESTORE, a cartridge's start): OctoVIC off, the editor's 25 rows, then
; the KERNAL's own
cinthk  jsr octoff
        jmp $E5A0

; wait for the bottom border (raster line 256 on), A kept
vbl     bit $D011
        bpl vbl
        rts

seg_ie
!if seg_ie > $F3D3 { !error "past the room at $F38E" }

; -------------------------------------------------- KERNAL $F539-$F5AD (117 bytes: the tape LOAD)
        * = $F539
seg_b
; R, G, B: first the backdrop (navy), then the VIC's 0-15 (VICPAL): 0 1 as they are, O C T O V I C in 2 8 9 5 10 14 4, 3 the words
; under the gradient (and SHELL.PRG's path), 6 the box, 7 the keys, 11 the border, 15 the labels;
; 12 13 as they were (SHELL.PRG's grey, its disks' green). Then the main palette's 1-10: the eq
; bars 1-8, the empty slot, the box.
pdat    !byte 28,32,92
        !byte 0,0,0, 255,255,255, 255,80,80, 120,220,255, 170,100,255, 120,230,90, 16,18,56
        !byte 255,200,60, 255,150,40, 255,230,60, 60,220,220, 20,22,70, 108,108,108, 154,210,132
        !byte 80,140,255, 200,205,255
        !byte 255,80,80, 255,150,40, 255,230,60, 120,230,90, 60,220,220, 80,140,255
        !byte 170,100,255, 255,90,200, 32,36,90, 16,18,56
rainbow !byte 2, 8, 9, 5, 10, 14, 4
ptab    !byte 2, 0, 3, 1, 0, 51, 0, 1, 81
litecol !byte 6, 2, 5, 2               ; the light: none, red, green, red
rows    stx R25                 ; the editor's rows: X (24 or 25)
        dex
        stx R24
        dex
        stx R23
        ldx #0
        rts
seg_be
!if seg_be > $F5AE { !error "past the room at $F539" }

; --------------------------------------------------- KERNAL $F65F-$F68D (47 bytes: the tape SAVE)
        * = $F65F
seg_c
; the REU really attached, as the REU's bank register says: written 0, it reads back the bits the
; REU hasn't got as 1s ($00 16M, $E0 2M, $F8 512K; $FF none) - on row 1 from column 32
reutext lda #0
        sta $DF06
        lda $DF06
        ldx #$FF
rtk     inx
        asl
        bcs rtk
        lda reuix,x
        tax
        ldy #72
        jsr rstr
        ldx #rsfx-reut
rstr    lda reut,x
        beq rsend
        sta $0400,y
        lda #3
        sta $D800,y
        inx
        iny
        bne rstr
rsend   rts

seg_ce
!if seg_ce > $F68E { !error "past the room at $F65F" }

; ---------------------------------------------------------- the tape room $F92C-$FB96 (619 bytes)
        * = $F92C
seg_a
newboot jmp boot                ; $F92C: BASIC's cold start (fixed: the KERNAL patch calls it)
        jmp frame               ; $F92F: the screen alone (fixed: SHELL.PRG calls it)
boot    jsr frame               ; the screen, 38911 BASIC BYTES FREE on row 3 (the bytes free at a
        ldx #4                  ; cold start: $0801-$9FFF, always), then BASIC's NEW (the program
fbf     lda n38911,x            ; pointers $2B-$2E and $0801) as the banner routine it replaces
        sta $0400 + 120,x       ; ($E422) did: as a JMP, last - NEW's CLR resets the stack and
        lda #15                 ; keeps only one return address
        sta $D800 + 120,x
        dex
        bpl fbf
        sta $0286               ; (15, the labels' pale)
        ldx #3
        ldy #5
        clc
        jsr PLOT
        lda #$60                ; " BASIC BYTES FREE"
        ldy #$E4
        jsr $AB1E
        lda #$01
        sta $0286
        jmp $A644

frame   lda #$4F                ; OctoVIC there?
        sta $D03F
        lda #$38
        sta $D03F
        lda #0
        sta OCTST               ; (the IRQ leaves OctoVIC alone while this sets it up)
        sta TOPY
        ldx #24                 ; OctoVIC: the editor's rows 0-23 (the bar on 24), the border 11
        ldy #11
        lda $D61E
        cmp #$8C
        beq fo
        ldx #25                 ; a stock VIC: the words, plain, and the 25-row editor
        ldy #6                  ; (and Z clear for the PHP below)
        stx $D03F               ; (anything but $4F, $38 shuts OctoVIC's page: the SID mirrors again)
fo      php
        sty $D020
        lda #6
        sta $D021
        jsr rows
        jsr cls
        jsr prtext
        plp
        beq fon
        jmp ftail
fon     lda #0                  ; OctoVIC from a clean start: no sprites, $D627-$D684 0 (layer 0's
        sta $D60F               ; scroll, layer 1, the animation, the interrupt) - CTRL, KEY, the
        ldy #$5D                ; copper and layer 0's bitmap left as they are (the browser's FRAME:
fz      sta $D627,y             ; the box stays up while this runs)
        dey
        bpl fz
        inx
        jsr prtext              ; the eq's cells
        ldx #0                  ; the palettes (ptab: select, first entry, end in pdat): the
        ldy #0                  ; backdrop, the VIC's 0-15, the main 1-10
fpal    lda ptab,y
        sta $D619
        lda ptab+1,y
        sta $D61A
fpl     jsr rgbv
        txa
        cmp ptab+2,y
        bne fpl
        iny
        iny
        iny
        cpy #9
        bne fpal
        lda #160                ; 160-239: the rules' gradient, cyan (120,220,255) to violet
        sta $D61A               ; (200,120,255), 4 pixels a step - and bitmap row 0 with it
        ldy #0
        tya
        ldx #1
        jsr va                  ; VRAM $010000: the bitmap
        tax
        clc
fpr     txa
        adc #120
        sta $D61B
        txa
        lsr
        lsr
        sta TMP
        txa
        clc
        adc TMP
        eor #$FF
        adc #221
        sta $D61C
        lda #255
        sta $D61D
        txa
        adc #159                ; (carry set: 160)
        ldy #4
fpr4    sta VDATA
        dey
        bne fpr4
        inx
        cpx #80
        bne fpr
        lda #0                  ; the rest of row 0: nothing
        ldy #192
fpr0    sta VDATA
        dey
        bne fpr0
        sty ROW                 ; bitmap rows 1-18: the words' gradient (line i of a text row:
frw     lda ROW                 ; the rules' 160 + 10 i, the same colour)
        and #7
        sta TMP
        asl
        asl
        adc TMP
        asl
        adc #160
        ldy #0
        ldx #2
frw0    sta VDATA
        iny
        bne frw0
        dex
        bne frw0
        inc ROW
        lda ROW
        cmp #18
        bne frw
        lda #1                  ; layer 0's bitmap at $010000
        sta $D626
        lda #$0B
        sta $D605               ; on, the VIC's palette, KEY
        jsr layout              ; the copper list (TOPY 0), then the copper on
        lda #1
        sta $D60E
        jsr drawbar
        inc OCTST               ; 1 (left open while the start screen shows; RUN, SYS and LOAD shut it)
ftail   jsr reutext
        jsr $F72C               ; the @ and / commands, F1 (wedge.asm)
        ldx #4                  ; READY. comes on row 5
        ldy #0
        clc
        jmp PLOT
rgbv    lda pdat,x              ; R, G, B from pdat (X steps on 3)
        sta $D61B
        lda pdat+1,x
        sta $D61C
        lda pdat+2,x
        sta $D61D
        inx
        inx
        inx
        rts
va      sty VA0                 ; VRAM address X:A:Y, a byte at a time
        sta VA1
        stx VA2
        ldy #1
        sty VINC
        rts

; the words: the records from X in texts (X left on the end mark)
prtext  ldy texts,x
        cpy #$FE
        bcs ptend
        inx
ptc     lda texts,x
        beq ptnext
        sta $0400,y
        lda #3
        cpy #53
        bcc ptcol
        cpy #60
        bcs ptcol
        lda rainbow-53,y        ; OCTOVIC: the rainbow
ptcol   sta $D800,y
        inx
        iny
        bne ptc
ptnext  inx
        bne prtext
ptend   rts

; the copper list for TOPY (the box scrolled up 0, 8, 16, 24 lines), into the list not in use:
; coptab's entries, a line under 128 counted from the box's top (51 + TOPY: SCROLLY there less TOPY)
layout  php
        sei
        lda BUFSEL
        eor #$03
        sta BUFSEL
        ldx #0
        ldy #0
        jsr va
lyl     ldy coptab+2,x
        lda coptab,x
        bmi lyw
        clc
        adc #51
        clc
        adc TOPY
        pha
        lda coptab+1,x
        cmp #$2A
        bne lyp
        tya
        sec
        sbc TOPY
        tay
lyp     pla
lyw     sta VDATA
        lda #0
        sta VDATA
        lda coptab+1,x
        sta VDATA
        sty VDATA
        inx
        inx
        inx
        cpx #36
        bne lyl
        lda #$FF                ; the end: line $FFFF
        sta VDATA
        sta VDATA
        lda BUFSEL
        jsr vbl                 ; switched to in the bottom border: the copper idles from a switch
        sta $D611               ; to the next line 0, and never mid-picture (KEY would stay 3)
        plp
lyrts   rts

; the IRQ ($EA31 calls this instead of UDTIM): the eq bars move with what the 8 SIDs play (each
; SID's voice 3 envelope, ENV3, 7 pixels at most; idle: 1, redrawn every other frame) and the
; network light

irqhk   jsr $FFEA
        lda OCTST
        beq lyrts               ; (an RTS: layout's)
        lda $A2                 ; every other frame (the jiffy clock UDTIM just moved on)
        lsr
        bcs lyrts
        ldx #7                  ; each SID's voice 3 envelope: 1-7 pixels
eqenv   txa                     ; SID k: $D400 + $20 (k&1) + $100 (k&2) + $80 (k&4)
        and #5
        asl
        asl
        asl
        asl
        asl
        tay
        txa
        and #2
        bne eqhi
        lda $D41C,y
        bcc eqh                 ; (carry clear from the ASLs: always)
eqhi    lda $D51C,y
eqh     lsr
        lsr
        lsr
        lsr
        lsr
        bne eqs
        lda #1
eqs     sta HT,x
        dex
        bpl eqenv
        inx
        stx ROW
eqrow   lda ROW                 ; bitmap row 1 + ROW, x 0-47: bar k lit (k+1) or its slot (9),
        asl                     ; then the box (10); row 8 the box
        adc #2
        ldx #1
        ldy #0
        jsr va
        ldx #0
eqbar   lda #10
        ldy ROW
        cpy #7
        beq eqput
        lda HT,x
        clc
        adc ROW
        cmp #7
        lda #9
        bcc eqput
        txa
        adc #0
eqput   ldy #5
eqw     sta VDATA
        dey
        bne eqw
        lda #10
        sta VDATA
        inx
        cpx #8
        bne eqbar
        inc ROW
        lda ROW
        cmp #8
        bne eqrow
        lda TOPY                ; the network light (while the box is at the top): NET 0 none
        bne iout                ; set up - the box's colour, 2 there - green, 1 waiting and
        lda $D6FF               ; 3 not there - red
        and #3
        tax
        lda litecol,x
        sta $D800 + 38
iout    rts

seg_ae
!if seg_ae > $FB97 { !error "past the room at $F92C" }

