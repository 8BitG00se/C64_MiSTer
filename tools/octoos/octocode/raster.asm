; RASTER.ASM - raster bars for the
; Octophonic 64. OctoVIC's copper sets
; the colour of every raster line, so
; the bars are rock steady and can be
; any of 16 million colours.
;
; Change the bars below, press F2.
; RUN/STOP+RESTORE comes back here.

* = $0801
        !byte $0b,$08,$0a,$00,$9e
        !text "2061"   ; 10 SYS2061
        !byte 0,0,0
        jmp start

; ======== change these ===============

nbars   = 8     ; how many bars (1-8)
gap     = 5     ; the space between them
speed   = 3     ; how fast they swing
height  = 20    ; each bar's height

; a bar: its red, green, blue (0-255)
!macro bar .r, .g, .b {
 !for j, 0, height-1 {
  !byte int(.r*sin((j+1)*3.14159/(height+1)))
 }
 !for j, 0, height-1 {
  !byte int(.g*sin((j+1)*3.14159/(height+1)))
 }
 !for j, 0, height-1 {
  !byte int(.b*sin((j+1)*3.14159/(height+1)))
 }
}

bars    +bar 40, 70, 255        ; blue
        +bar 120, 60, 255       ; violet
        +bar 40, 200, 255       ; sky
        +bar 30, 120, 220       ; sea
        +bar 160, 200, 255      ; ice
        +bar 20, 40, 160        ; navy
        +bar 255, 255, 255      ; white
        +bar 255, 140, 40       ; gold

; ======== the program ================

line0   = 55            ; the first line
lines   = 200           ; how many lines
red     = $3000         ; this frame's
green   = $3100         ; colours, line
blue    = $3200         ; by line
pr      = $f7           ; the bar's red,
pg      = $f9           ; green and
pb      = $fb           ; blue (2 bytes)

start   lda #147
        jsr $ffd2       ; clear the screen
        sei
        lda #0
        sta $d020
        sta $d021
        jsr barson
        ldx #0          ; all black
        txa
-       sta red,x
        sta green,x
        sta blue,x
        inx
        bne -
        jsr draw

main    lda #250        ; wait for the
-       cmp $d012       ; bottom border
        bne -
        jsr upload      ; the bars out
        jsr draw        ; the next ones
        lda phase
        clc
        adc #speed
        sta phase       ; they swing on
        jmp main

; ---- OctoVIC on, and its copper list
; in VRAM $010000: four steps a line,
; the VIC's colour 0 = red, green, blue
barson  lda #$4f        ; OctoVIC on:
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
        cmp #line0+lines
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

; ---- this frame's colours into the list
; (and each line black again behind it,
; ready for the next frame's bars)
upload  lda #3
        sta $d600
        lda #0
        sta $d601
        lda #1
        sta $d602
        lda #4
        sta $d603       ; every 4th byte
        ldx #0
        ldy #0
-       sty $d604       ; colour 0
        lda red,x
        sta $d604
        lda green,x
        sta $d604
        lda blue,x
        sta $d604
        tya             ; black again
        sta red,x
        sta green,x
        sta blue,x
        inx
        cpx #lines
        bne -
        rts

; ---- the bars into red, green, blue
draw    lda #<bars
        sta pr
        lda #>bars
        sta pr+1
        lda phase
        sta pos
        lda #nbars
        sta left
onebar  lda pr          ; its green and
        clc             ; blue come after
        adc #height     ; its red
        sta pg
        lda pr+1
        adc #0
        sta pg+1
        lda pg
        clc
        adc #height
        sta pb
        lda pg+1
        adc #0
        sta pb+1
        ldx pos
        lda sine,x
        tax             ; its top line
        ldy #0
-       lda (pr),y      ; line by line
        sta red,x
        lda (pg),y
        sta green,x
        lda (pb),y
        sta blue,x
        inx
        iny
        cpy #height
        bne -
        lda pb          ; the next bar
        clc
        adc #height
        sta pr
        lda pb+1
        adc #0
        sta pr+1
        lda pos
        clc
        adc #gap
        sta pos
        dec left
        bne onebar
        rts

; where a bar is: a swing up and down
sine    !for i, 0, 255 {
 !byte int((lines-height)/2*(1+sin(i*3.14159/128))*0.99)
}

lnum    !byte 0
phase   !byte 0
pos     !byte 0
left    !byte 0
