; OCTOPHONIC 64 V1.1 - the start screen on the real C64 KERNAL and BASIC, in the room the tape
; routines left ($F92C-$FB8D: the core has no tape). By Neal - 8BitG00se.
OCTST   = $02A7         ; 1: OctoVIC is drawing the start screen
AUTORUN = $02A8         ; 1: SHIFT+RUN/STOP asked for LOAD"*",8 - RUN goes in after it
PLOT    = $FFF0
RUNKEYS = $FCCE          ; wedge2.asm, fixed
SHIFTR2 = $F929          ; wedge.asm, fixed
        * = $F92C
; BASIC's cold start calls this instead of printing COMMODORE 64 BASIC V2 / BYTES FREE
newboot jmp boot                ; $F92C: BASIC's cold start (fixed: the KERNAL patch calls it)
        jmp frame               ; $F92F: the screen alone (fixed: SHELL.PRG calls it)
boot    jsr frame               ; the screen, then BASIC's NEW (the program pointers $2B-$2E and
        jmp $A644               ; $0801) as the banner routine it replaces ($E422) did: as a JMP,
                                ; last - NEW's CLR resets the stack and keeps only one return address
frame   lda #$06                ; one colour, border and page (navy, with OctoVIC)
        sta $D020
        sta $D021
        lda #$01
        sta $0286               ; white text
        lda #$93
        jsr $FFD2               ; a clear screen, in the new colours
        ldx #0
-       lda title,x
        beq +
        sta $0400 + 40 + 15,x
        inx
        bne -
+       lda #$4F                ; OctoVIC there?
        sta $D03F
        lda #$38
        sta $D03F
        lda $D61E
        cmp #$8C
        beq octon
        lda #$00
        sta $D03F
        jmp npos
octon   ldx #0
-       lda vicname,x
        beq +
        sta $0400 + 120,x
        lda #$03
        sta $D800 + 120,x
        inx
        bne -
+       lda #$01                ; the VIC's palette: 6 navy, 3 cyan
        sta $D619
        lda #$06
        sta $D61A
        jsr navyrgb
        lda #$03
        sta $D61A
        lda #120
        sta $D61B
        lda #220
        sta $D61C
        lda #255
        sta $D61D
        lda #$02                ; the backdrop (what shows through navy): navy
        sta $D619
        jsr navyrgb
        lda #$00                ; the main palette: bank n, entries 1 (bright) and 2 (dark)
        sta $D619
        ldx #0
        ldy #$11
-       sty $D61A
        lda bandpal,x
        sta $D61B
        lda bandpal+1,x
        sta $D61C
        lda bandpal+2,x
        sta $D61D
        lda bandpal+3,x
        sta $D61B
        lda bandpal+4,x
        sta $D61C
        lda bandpal+5,x
        sta $D61D
        tya
        clc
        adc #$10
        tay
        txa
        clc
        adc #6
        tax
        cpx #48
        bne -
        lda #$00                ; VRAM 0: the block, 16 x 16, 16 colours
        sta $D600
        sta $D601
        sta $D602
        lda #$01
        sta $D603
        ldy #0
-       lda #$11
        cpy #48
        bcc +
        lda #$22
        cpy #96
        bcc +
        lda #$00
+       tax
        tya
        and #$07
        cmp #$06
        txa
        bcc +
        lda #$00
+       sta $D604
        iny
        bpl -
        ldx #0                  ; VRAM $80: the sprite table
-       txa
        asl
        asl
        sta $02
        asl
        clc
        adc $02
        sta $D604               ; X = 12 n
        lda #$00
        sta $D604
        lda #6
        sta $D604               ; Y
        lda #$00
        sta $D604
        sta $D604
        sta $D604               ; GFX 0
        lda #$85
        sta $D604               ; 16 x 16, on
        inx
        txa
        sta $D604               ; palette bank n + 1
        cpx #8
        bne -
        lda #$80
        sta $D613
        lda #$00
        sta $D614
        sta $D615
        sta $D616
        sta $D617
        sta $D618
        lda #8
        sta $D60F
        lda #$06
        sta $D606               ; navy see-through
        lda #$0B
        sta $D605               ; on, the VIC's palette, KEY
        lda #$01                ; (left open while the start screen shows; RUN, SYS and LOAD shut it)
        sta OCTST
npos    ldx #8                  ; OCTOPHONIC OS: F1 BROWSE, right of OCTOVIC 256
-       lda hint,x
        sta $0400 + 120 + 31,x
        lda #$0F
        sta $D800 + 120 + 31,x
        dex
        bpl -
        jsr $F72C               ; the @ and / commands, F1 (wedge.asm)
        ldx #4                  ; READY. comes on row 5
        ldy #0
        clc
        jmp PLOT

; OctoVIC off before a program: LOAD, RUN and SYS come through here
octoff  php
        pha
        lda OCTST
        beq +
        lda #$4F
        sta $D03F
        lda #$38
        sta $D03F
        lda #$00
        sta $D605
        sta $D60F
        sta $D60E
        sta $D03F
        sta OCTST
+       pla
        plp
        rts
w_run   jsr octoff
        jmp $A871
w_sys   jsr octoff
        jmp $E12A
w_load  jsr octoff
        php
        pha
        lda AUTORUN             ; SHIFT+RUN/STOP: RUN waits in the keyboard buffer
        beq +
        jsr RUNKEYS             ; (wedge.asm: R U N RETURN, in full)
+       pla
        plp
        jmp $E168
; SHIFT+RUN/STOP: the buffer gets LOAD"*",8 in full (not the tape's LOAD) and RUN follows the load -
; wedge.asm's SHIFTR2 ($F929), called straight from the KERNAL (patch.py)
shiftrun = SHIFTR2
navyrgb lda #28                 ; navy: 28, 32, 92
        sta $D61B
        lda #32
        sta $D61C
        lda #92
        sta $D61D
        rts

title   !scr "octophonic 64 v1.1", 0
vicname !scr "octovic 256", 0
hint    !scr "f1 browse"
!src "bandpal.inc"
credit  !text "OCTOPHONIC 64 V1.1 - BY NEAL - 8BITG00SE", 0
; the network light, top right of the start screen: the screen editor's wait for a key ($E5CD)
; comes through here. Only at READY in direct mode while the start screen is up (OctoVIC's page open,
; the title still on row 1 - never once a program runs or the screen has scrolled): a dot at the end
; of the title row, coloured by what Octophonic Main says about the network share - none set up:
; not shown; waiting or not there: red; ready: green
netlite lda $C6                 ; the KERNAL's own three instructions
        sta $CC
        sta $0292
        php
        lda OCTST
        beq +
        lda $9D
        bpl +
        lda $0400 + 40 + 15     ; only while the start screen's title is still on row 1 (not
        cmp #$0F                ; scrolled away): the 'O' of OCTOPHONIC
        bne +
        lda $D6FF               ; NET (the mailbox): 0 none set up - no light at all
        and #3
        beq +
        tax
        lda #$51                ; a dot at the end of the title row
        sta $0400 + 40 + 39
        lda litecol,x
        sta $D800 + 40 + 39
+       plp                     ; Z from $C6, for the KERNAL's BEQ
        rts
litecol !byte 6, 2, 5, 2
tapeend
!if tapeend > $FB97 { !error "past the tape room ($FB8E-$FB96 was the tape's write code, unused)" }
