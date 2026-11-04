; HELLO.ASM - a first program for the
; Octophonic 64: colour bars, a
; scrolling message and a note.
;
; Change something below, then press
; F2: it is compiled and run at once.
; RUN/STOP+RESTORE comes back here.
; You can't break anything - try it!

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

; the message: small letters, numbers
; and spaces. A 0 ends it.
message !scr "hello from the "
        !scr "octophonic 64!     "
        !scr "press run/stop and "
        !scr "restore for the "
        !scr "editor.     "
        !byte 0

textcol = 7     ; its colour (0-15)
speed   = 2     ; scroll speed: 1 2 4

; the bars: red, green, blue (0-255)
bar1    !byte 255,60,40     ; red
bar2    !byte 40,255,90     ; green
bar3    !byte 70,110,255    ; blue

note    = $22   ; the note at the start
                ; (try $11 or $44)

; ======== the program ================

start   sei
        lda #0
        sta $d020       ; black border
        sta $d021       ; black screen
        ldx #0
clear   lda #32         ; spaces
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        lda #textcol
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne clear
        jsr sound
        jsr shades
        jsr barson
        jsr draw        ; the first bars

main    lda #255        ; wait for the
-       cmp $d012       ; bottom of the
        bne -           ; picture
        jsr scroll
        jsr upload      ; the bars out
        jsr draw        ; the next ones
        inc phase       ; they move on
        jmp main

; ---- the note: SID 1, voice 1
sound   lda #15
        sta $d418       ; loud
        lda #$09
        sta $d405       ; attack, decay
        lda #$00
        sta $d406       ; sustain 0
        sta $d400
        lda #note
        sta $d401       ; the pitch
        lda #$21
        sta $d404       ; sawtooth, on
        rts

; ---- the message moves left
row     = $0400 + 12*40 ; screen row 12
scroll  lda fine
        sec
        sbc #speed
        bcs +
        and #7          ; a whole letter
        sta fine        ; gone: move the
        jsr shift       ; row along
        jmp ++
+       sta fine
++      lda fine
        sta $d016       ; fine scroll
        rts

shift   ldx #0
-       lda row+1,x
        sta row,x
        inx
        cpx #39
        bne -
        ldy pos
        lda message,y   ; next letter
        bne +
        ldy #0          ; the end: again
        sty pos
        lda message
+       sta row+39
        inc pos
        rts

; ---- the bars, with OctoVIC's copper:
; each raster line it sets the VIC's
; colour 0 (black) to any of 16 million
; colours. The list is in VRAM $010000.
line0   = 70            ; first line
lines   = 160           ; how many
red     = $3000         ; this frame's
green   = $3100         ; colours,
blue    = $3200         ; line by line

barson lda #$4f        ; OctoVIC on:
        sta $d03f       ; $4f then $38
        lda #$38        ; into $d03f
        sta $d03f
        lda #1
        sta $d619       ; VIC palette
        lda #2
        sta $d605       ; VIC colours
        lda #0          ; from OctoVIC
        sta $d600
        sta $d601
        lda #1
        sta $d602       ; VRAM $010000
        sta $d603       ; step 1
        lda #line0
        sta lnum
-       ldy #$1a        ; colour number,
--      lda lnum        ; red, green,
        sta $d604       ; blue: four
        lda #0          ; copper steps
        sta $d604       ; a line
        sty $d604
        sta $d604
        iny
        cpy #$1e
        bne --
        inc lnum
        lda lnum
        cmp #line0+lines+1
        bne -
        lda #$ff        ; the list's end
        sta $d604
        sta $d604
        lda #0
        sta $d610       ; the copper:
        sta $d611       ; its list
        lda #1
        sta $d612
        sta $d60e       ; and on
        rts

; the colours into the list
upload  lda #3
        sta $d600
        lda #0
        sta $d601
        lda #1
        sta $d602
        lda #4
        sta $d603       ; every 4th byte
        ldx #0
-       lda #0
        sta $d604       ; colour 0
        lda red,x
        sta $d604
        lda green,x
        sta $d604
        lda blue,x
        sta $d604
        inx
        cpx #lines
        bne -
        rts

; the bars into red, green, blue
draw    ldx #0
        lda #0          ; all black
-       sta red,x
        sta green,x
        sta blue,x
        inx
        cpx #lines
        bne -
        lda #0          ; bar 1
        ldx #0
        jsr bar
        lda #42         ; bar 2
        ldx #32
        jsr bar
        lda #84         ; bar 3
        ldx #64

; a bar: A how far behind, X its
; first line in the shaded colours
bar     clc
        adc phase       ; (it moves at
        lsr             ; half speed)
        and #63
        tay
        lda sine,y      ; where it is
        tay
        lda #32         ; 32 lines
        sta i
-       lda sred,x
        sta red,y
        lda sgreen,x
        sta green,y
        lda sblue,x
        sta blue,y
        inx
        iny
        dec i
        bne -
        rts

; once at the start: each bar's 32
; lines, dark at the edges and bright
; in the middle
sred    = $3300
sgreen  = $3380
sblue   = $3400
shades  ldx #0          ; line 0-95
-       txa
        and #31
        tay
        lda shape,y     ; how dark
        sta sh
        txa
        lsr             ; which bar:
        lsr             ; 0, 3 or 6
        lsr
        lsr
        lsr
        sta i
        asl
        adc i
        tay
        lda bar1,y
        jsr shade
        sta sred,x
        lda bar1+1,y
        jsr shade
        sta sgreen,x
        lda bar1+2,y
        jsr shade
        sta sblue,x
        inx
        cpx #96
        bne -
        rts

shade   sty i           ; halve it sh
        ldy sh          ; times
        beq +
-       lsr
        dey
        bne -
+       ldy i
        rts

shape   !byte 5,4,4,3,3,2,2,2,1,1,1,1
        !byte 0,0,0,0,0,0,0,0,1,1,1,1
        !byte 2,2,2,3,3,4,4,5
sine    !byte 64,70,76,83,88,94,100
        !byte 105,109,113,117,120,123
        !byte 125,127,128,128,128,127
        !byte 125,123,120,117,113,109
        !byte 105,100,94,88,83,76,70
        !byte 64,58,52,45,40,34,28,23
        !byte 19,15,11,8,5,3,1,0,0,0,1
        !byte 3,5,8,11,15,19,23,28,34
        !byte 40,45,52,58

fine    !byte 0
pos     !byte 0
phase   !byte 0
lnum    !byte 0
i       !byte 0
sh      !byte 0
