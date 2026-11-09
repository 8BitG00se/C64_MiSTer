;(C) 2026 Mong00se. All rights reserved.
;            ▗▄▄▄▄▄▄▄▄▄▄▄▖
;          ▗▀             ▀▖
;         ▗▘  ┌──┐   ┌──┐  ▝▖
;         ▌   │ o│   │ o│   ▕
;         ▌   └──┘   └──┘   ▕
;         ▝▖     ▝▄▄▄▘     ▗▘
;          ▝▖             ▗▘
;        ▗▄▄▘▗▘▗▘ ▌ ▕ ▝▖▝▖▝▄▄▖
;       ▗▘  ▗▘▗▘ ▗▘ ▕  ▝▖▝▖  ▝▖
;       ▝▖ ▗▘ ▌ ▗▘  ▕   ▝▖▕  ▗▘
;      o ▝▄▘ ▗▘ ▌   ▝▖  ▕ ▝▖▝▄▘ o
;           o ▝▄▘ o  ▝▄▘ o ▝▄ o
;      2026: AN OCTOPHONIC ODYSSEY
;     ▗▄▄▖
;    ▗▘o  ▀▄▖    CODE:  MONG00SE
;     ▝▖ ▗▄▄▘    MUSIC: STRAUSS II,
;      ▌ ▕              ARR. MONG00SE
;      ▌ ▝▖      IMAGE: NASA, ESA,
;     ▗▘   ▌            CSA, STSCI
;     ▀▀▀▀▀▝▄▄▄▖
;
; HOW TO PLAY WITH IT (OCTOCODE):
; F2  COMPILE AND RUN (ON ANY PART)
; F5  SAVE (AFTER F2: THE PROGRAM TOO)
; F3  LOAD A PART   F1 BROWSE   F7 READY
; CHANGE ANYTHING - IT'S YOURS TO PLAY
; ON A PC IT BUILDS WITH ACME TOO:
;     acme -f cbm odyssey.asm
;
; ODYSSEY.ASM - "2026: AN OCTOPHONIC ODYSSEY", by Mong00se.
; Octophonic 64 and OctoVIC by Mong00se (github.com/8BitG00se).
;
; ONE program for three machines. It looks at the machine it is on:
;  - an OCTOPHONIC 64 (OctoVIC 2+ and our .reu in the REU): the
;    Webb picture in 256 colours, a slow camera through the cliffs,
;    all 8 SIDs (OCTO.ASM)
;  - a C64 with a SECOND SID (at $D420, $D500 or $DE00): the tour
;    below, the music in stereo on 2 SIDs
;  - a STOCK C64: the tour of the Cosmic Cliffs in multicolour
;    bitmaps loaded from the disk, the music on 1 SID (SHOW.ASM)
; Picture: the James Webb Space Telescope's "Cosmic Cliffs" in the
; Carina Nebula - NASA, ESA, CSA, STScI.
; Music: The Blue Danube, Johann Strauss II (1866), arranged by
; Mong00se (SONG.ASM, played by PLAYER.ASM).
;
; THE SOURCE IN PARTS. The whole program is too big for one OCTOCODE
; file, so it is in parts, each one loads in OCTOCODE on its own:
;   ODYSSEY.ASM  this: the start, the machine test, shared bits
;   PLAYER.ASM   the music player (1, 2 or the first 2 of 8 SIDs)
;   SHOW.ASM     the stock / 2-SID show: the tour, loading the views
;   FX.ASM       its scroll text, equaliser, twinkles, sparkles, comet
;   IRIS.ASM     its changes: the iris, the fades, the raster bars
;   OCTO.ASM     the Octophonic show (OctoVIC, 8 SIDs, the REU)
;   OCTOFX.ASM   its twinkles, sparkles, comet, sprites, scroll text
;   CAMERA.ASM   its camera through the cliffs
;   SONG.ASM     the notes (made by song.py on the PC)
; Press F2 on ANY of them: each part starts by pulling in this file
; when it is compiled on its own, so F2 always builds the whole demo
; (ODYSSEY.PRG). (Each part's first lines: odytop is 1 while this
; file is being read, 0 after; a part read first pulls this in.)
; The parts must be beside the disk on the SD card -
; "Install to MiSTer.bat" puts them there. F2 saves the part you
; edited there first, so your change is in the next build.
; The pictures are not in the source: the stock views are files on
; this disk (VIEW0-VIEW3), the Octophonic picture is in the .reu.

!set odytop = 1         ; (the parts look for this: see above)
BUILD   = 1

; ---------------------------------------------------- the machine
REU     = $DF00
SIDA    = $D400         ; SID 1
CHROUT  = $FFD2
SETLFS  = $FFBA
SETNAM  = $FFBD
OPEN    = $FFC0
CLOSE   = $FFC3
CHKIN   = $FFC6
CLRCHN  = $FFCC
CHRIN   = $FFCF
READST  = $FFB7

; zero page ($02-$8F: BASIC's, not used here)
zp      = $02
mode    = $02           ; 0 stock, 1 two SIDs, 2 Octophonic
sid2lo  = $03           ; the second SID (0 = none)
sid2hi  = $04
ptr     = $05           ; 2
ptr2    = $07           ; 2
ptr3    = $09           ; 2
tmp     = $0b           ; 4
frame   = $0f           ; counts frames (the interrupt)
rnd     = $10           ; 2: random numbers
cnt     = $12           ; 2

; the BASIC line LIST shows:
; 10 SYS2176:REM (C) 2026 MONG00SE. ALL RIGHTS RESERVED
        * = $0801
        !word basend, 10
        !byte $9e
        !pet "2176:", $8f, " (c) 2026 mong00se. all rights reserved", 0
basend  !word 0
copyr   !text "(C) 2026 MONG00SE. ALL RIGHTS RESERVED.", 0
        !fill $0880 - *, 0
        jmp start       ; $0880 = 2176

; ================================================ the start
!zone start
start   sei
        cld
        lda #$36        ; BASIC off, the KERNAL and I/O on
        sta $01
        lda #0
        sta $d020
        sta $d021
        sta $d015
        sta sid2lo
        sta sid2hi
        lda #$7f        ; no CIA interrupts
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d
        lda #<nmi       ; RESTORE does nothing
        sta $0318
        lda #>nmi
        sta $0319
        lda #$1b
        sta $d011
        lda #$15
        sta $d018
        jsr cls
        ldx #<t_hello
        ldy #>t_hello
        lda #1
        jsr print
        jsr sidclr
        jsr octotest    ; an Octophonic?
        bcc nocto
        jsr reutest     ; ... with our .reu in the REU?
        bcs isocto
        ldx #<t_askreu
        ldy #>t_askreu
        lda #3
        jsr print
        jsr askreu      ; ask Octophonic Main for it
        jsr reutest
        bcs isocto
        ldx #<t_noreu
        ldy #>t_noreu
        lda #3
        jsr print
!zone nocto
nocto   lda #0          ; OctoVIC's page shut: SID mirrors again
        sta $d03f
        jsr findsid2
        lda sid2hi
        beq +
        lda #1
+       sta mode
        jmp show        ; SHOW.ASM: the stock / 2-SID show
!zone isocto
isocto  lda #2
        sta mode
        jmp octo        ; OCTO.ASM: the Octophonic show

!zone nmi
nmi     rti

; ------------------------------------------------ is OctoVIC there?
; carry set: yes (ID $8C, version 2 or more), its page left open
!zone octotest
octotest
        lda #$4f
        sta $d03f
        lda #$38
        sta $d03f
        lda $d61e
        cmp #$8c
        bne +
        lda $d61e
        cmp #$8c
        bne +
        lda $d61f
        cmp #2
        bcc +
        cmp #16
        bcs +
        sec
        rts
+       clc
        rts

; ------------------------------------------------ our data in the REU?
; the .reu starts with "ODYSSEY1" (only looked at on an Octophonic)
!zone reutest
reutest lda #<tmpbuf
        sta REU+2
        lda #>tmpbuf
        sta REU+3
        lda #0
        sta REU+4
        sta REU+5
        sta REU+6
        sta REU+8
        sta REU+10
        lda #8
        sta REU+7
        lda #$91        ; REU to C64, now
        sta REU+1
        ldx #7
-       lda tmpbuf,x
        cmp magic,x
        bne +
        dex
        bpl -
        sec
        rts
+       clc
        rts
!zone magic
magic   !text "ODYSSEY1"
!zone tmpbuf
tmpbuf  !fill 8,0

; ------------------------------------------------ ask Main for the .reu
; (OCTOOS.md, "A running program asks for its .reu"): command $18
; with the name; give up after 40 seconds
!zone askreu
askreu  lda #$4f
        sta $d03f
        lda #$38
        sta $d03f
        sta $d6f9       ; NAME: empty
        ldx #0
-       lda reuname,x
        beq +
        sta $d6f8
        inx
        bne -
+       lda #0
        sta $d6f6       ; ARG: not again if it is in already
        sta $d6f7       ; VALUE
        sta cnt
        sta cnt+1
        lda $d6fe       ; a request number of our own
        clc
        adc #1
        sta tmp
        sta $d6fd       ; SEQ
        lda #$18        ; REU
        sta $d6f0
-       jsr waitline    ; (a frame)
        inc cnt
        bne +
        inc cnt+1
+       lda cnt+1
        cmp #8          ; 2048 frames: 40 seconds
        bcs +
        lda $d6f1       ; STATUS: 1 busy
        cmp #1
        beq -
        ldx $d6fe       ; the answer must carry our number
        cpx tmp
        bne -
+       rts
!zone reuname
reuname !pet "octophonic odyssey", 0

; wait for the next frame (the beam at line 255)
!zone waitline
waitline
-       lda $d012
        cmp #$ff
        bne -
-       lda $d012
        cmp #$ff
        beq -
        rts

; ------------------------------------------------ a second SID?
; Tries $D420, $D500, $DE00. On a C64 with one SID, $D400-$D7FF
; all reach that one SID (mirrors) - so: SID 1's voice 3 is stopped
; (test bit), the candidate's voice 3 runs noise. A real second SID:
; its OSC3 moves, SID 1's stays still, and its OSC3 stops when its
; voice 3 is stopped too (an empty $DE00 reads the bus: no).
!zone findsid2
findsid2
        ldx #0
-       lda candlo,x
        sta ptr
        lda candhi,x
        sta ptr+1
        txa
        pha
        jsr trysid
        pla
        tax
        bcs +
        inx
        cpx #3
        bne -
        lda #0
        sta sid2lo
        sta sid2hi
        jsr sidclr
        rts
+       lda ptr
        sta sid2lo
        lda ptr+1
        sta sid2hi
        jsr sidclr
        rts
!zone candlo
candlo  !byte $20, $00, $00
!zone candhi
candhi  !byte $d4, $d5, $de

; carry set: a real SID at (ptr)
!zone trysid
trysid  ldy #$18        ; wake it (the Octophonic's SIDs sleep
        lda #$0f        ; until they have had a volume and a
        sta (ptr),y     ; control write)
        ldy #$12
        lda #$08
        sta (ptr),y
        jsr sidclr      ; SID 1: all quiet, voice 3 stopped
        lda #$08
        sta $d412
        lda #$ff        ; the candidate's voice 3: noise, fast
        ldy #$0e
        sta (ptr),y
        iny
        sta (ptr),y
        ldy #$12
        lda #$80
        sta (ptr),y
        jsr osc1still   ; SID 1's OSC3 must stay still
        bcc .no
        ldy #$1b
        jsr moves       ; the candidate's must move
        bcc .no
        ldy #$12        ; stop it: now it must be still
        lda #$08
        sta (ptr),y
        ldy #$1b
        jsr moves
        bcs .no
        ldy #$12
        lda #0
        sta (ptr),y
        sec
        rts
.no     ldy #$12
        lda #0
        sta (ptr),y
        clc
        rts
; carry set: $D41B read the same 32 times
!zone osc1
osc1still
        lda $d41b
        sta tmp
        ldx #32
-       lda $d41b
        cmp tmp
        bne +
        dex
        bne -
        sec
        rts
+       clc
        rts
; carry set: (ptr),y changed in 32 reads
!zone moves
moves   lda (ptr),y
        sta tmp
        ldx #32
-       lda (ptr),y
        cmp tmp
        bne +
        dex
        bne -
        clc
        rts
+       sec
        rts

; all of SID 1 (and its mirrors) quiet
!zone sidclr
sidclr  ldx #$18
        lda #0
-       sta $d400,x
        dex
        bpl -
        rts

; ------------------------------------------------ text
!zone cls
cls     ldx #0
        lda #$20
-       sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        dex
        bne -
        rts
; print the text at X/Y (screen codes, row, column, then the
; letters, 0 ends) in colour A
!zone print
print   stx ptr2
        sty ptr2+1
        sta tmp+3
        ldy #0
        lda (ptr2),y    ; row
        tax
        lda #0
        sta ptr
        lda #$04
        sta ptr+1
-       cpx #0
        beq +
        clc
        lda ptr
        adc #40
        sta ptr
        bcc ++
        inc ptr+1
++      dex
        jmp -
+       iny
        lda (ptr2),y    ; column
        clc
        adc ptr
        sta ptr
        bcc +
        inc ptr+1
+       lda ptr2
        clc
        adc #2
        sta ptr2
        bcc +
        inc ptr2+1
+       ldy #0
-       lda (ptr2),y
        beq +
        sta (ptr),y
        lda ptr+1       ; its colour
        pha
        clc
        adc #$d4
        sta ptr+1
        lda tmp+3
        sta (ptr),y
        pla
        sta ptr+1
        iny
        bne -
+       rts

!zone t_hello
t_hello !byte 10, 6
        !scr "2026: an octophonic odyssey", 0
!zone t_askreu
t_askreu !byte 13, 4
        !scr "asking for octophonic odyssey.reu", 0
!zone t_noreu
t_noreu !byte 15, 7
        !scr "no .reu - the stock show", 0

; ================================================ the parts
        !src "player.asm"
        !src "show.asm"
        !src "fx.asm"
        !src "iris.asm"
        !src "octo.asm"
        !src "octofx.asm"
        !src "camera.asm"
        !src "song.asm"
!zone progend
progend
!if progend > $4000 { !error "the program reaches the pictures" }
!set odytop = 0
