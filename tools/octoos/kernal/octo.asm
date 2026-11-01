; OCTOPHONIC 64 V1.1 - the start screen on the real C64 KERNAL and BASIC, in the room the tape
; routines left ($F92C-$FB8D: the core has no tape). By Neal - 8BitG00se.
OCTST   = $02A7         ; 1: OctoVIC is drawing the start screen
AUTORUN = $02A8         ; 1: SHIFT+RUN/STOP asked for LOAD"*",8 - RUN goes in after it
PLOT    = $FFF0
        * = $F92C
; BASIC's cold start calls this instead of printing COMMODORE 64 BASIC V2 / BYTES FREE
newboot jsr $A644                ; NEW: the program pointers ($2B-$2E, $0801), as the banner
                                ; routine it replaces ($E422) did on its way out
frame   lda #$06                ; (the browser calls frame: the screen, without the NEW)                ; one colour, border and page (navy, with OctoVIC)
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
        lda #28
        sta $D61B
        lda #32
        sta $D61C
        lda #92
        sta $D61D
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
        lda #28
        sta $D61B
        lda #32
        sta $D61C
        lda #92
        sta $D61D
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
        lda #$00
        sta AUTORUN
        lda #$52                ; R
        sta $0277
        lda #$D5                ; shift-U (RUN abbreviated)
        sta $0278
        lda #$0D
        sta $0279
        lda #3
        sta $C6
+       pla
        plp
        jmp $E168
; SHIFT+RUN/STOP: the buffer gets LOAD"*",8 (not the tape's LOAD) and RUN follows the load
shiftrun sei
        stx $C6
        lda #$01
        sta AUTORUN
        rts

title   !scr "octophonic 64 v1.1", 0
vicname !scr "octovic 256", 0
hint    !scr "f1 browse"
!src "bandpal.inc"
credit  !text "OCTOPHONIC 64 V1.1 - BY NEAL - 8BITG00SE", 0
tapeend
!if tapeend > $FB8E { !error "past the tape room" }
