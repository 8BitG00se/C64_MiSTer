; REWIND simulation: a small "game" for the save-and-restore test (sim/rewind) - eight sprites on the
; move, a scrolling row with its colours cycling, a raster split, a CIA 1 timer interrupt, a CIA 2 timer
; NMI, the SID played, a block of memory filled every frame and a main loop that never rests.
; The frame number is on the screen in hex, so a rewind is seen counting down.   (c) 2026 Mong00se
; acme -f plain -o rwgame.bin rwgame.asm        loads at $0810, started by the test ROM (rwrom.asm)

FRAME   = $02           ; 16 bits
TMP     = $04
PTR     = $06
CNT     = $f8           ; the main loop's 24-bit counter
NMIS    = $fb
CIAS    = $fc
SCR     = $0400
COL     = $d800

        * = $0810
start   sei
        lda #$7f
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d
        lda #0
        sta FRAME
        sta FRAME+1
        sta CNT
        sta CNT+1
        sta CNT+2
        sta NMIS
        sta CIAS
        ; the character set at $3000
        ldx #0
cf      lda font,x
        sta $3000,x
        inx
        cpx #19*8
        bne cf
        ; the sprite at $2000
        ldx #63
cb      lda ball,x
        sta $2000,x
        dex
        bpl cb
        ; the screen: empty, a checker row top and bottom of the scroller
        ldx #0
cs      lda #0
        sta SCR,x
        sta SCR+$100,x
        sta SCR+$200,x
        sta SCR+$2e8,x
        lda #1
        sta COL,x
        sta COL+$100,x
        sta COL+$200,x
        sta COL+$2e8,x
        inx
        bne cs
        ldx #39
ck      lda #18
        sta SCR+11*40,x
        sta SCR+13*40,x
        dex
        bpl ck
        ; the VIC-II
        lda #$1c
        sta $d018
        lda #$1b
        sta $d011
        lda #$c8
        sta $d016
        lda #0
        sta $d020
        lda #6
        sta $d021
        ldx #7
sp      lda #$80
        sta $07f8,x
        txa
        clc
        adc #1
        sta $d027,x
        dex
        bpl sp
        lda #$ff
        sta $d015
        lda #0
        sta $d010
        sta $d017
        sta $d01d
        sta $d01b
        sta $d01c
        ; the SID
        ldx #24
ss      lda #0
        sta $d400,x
        dex
        bpl ss
        lda #$0f
        sta $d418
        lda #$22
        sta $d405
        lda #$a8
        sta $d406
        ; the interrupts: raster (line 60, then 150), CIA 1 timer A every 1000 cycles, CIA 2 timer A NMI every 777
        lda #<irq
        sta $0314
        lda #>irq
        sta $0315
        lda #<nmi
        sta $0318
        lda #>nmi
        sta $0319
        lda #60
        sta $d012
        lda #1
        sta $d01a
        sta $d019
        lda #<999
        sta $dc04
        lda #>999
        sta $dc05
        lda #$81
        sta $dc0d
        lda #$11
        sta $dc0e
        lda #<776
        sta $dd04
        lda #>776
        sta $dd05
        lda #$81
        sta $dd0d
        lda #$11
        sta $dd0e
        cli
        ; the main loop: a counter and the stack, all the time
main    inc CNT
        bne m1
        inc CNT+1
        bne m1
        inc CNT+2
m1      jsr work
        jmp main
work    pha
        txa
        pha
        ldx CNT
        lda tri,x
        eor CNT+1
        sta $c000,x
        pla
        tax
        pla
        rts

nmi     pha
        lda $dd0d
        inc NMIS
        pla
        rti

irq     lda $d019
        and #1
        beq icia
        sta $d019
        lda $d012
        cmp #120
        bcs isec
        lda #150                ; line 60: the top colour, the frame's work
        sta $d012
        lda #6
        sta $d021
        jsr frame
        jmp $ea81
isec    lda #60                 ; line 150: the bottom colour
        sta $d012
        lda #11
        sta $d021
        jmp $ea81
icia    lda $dc0d
        inc CIAS
        jmp $ea81

frame   inc FRAME
        bne f1
        inc FRAME+1
f1      ; the frame number, hex, big enough to read: row 2, columns 2-5 (and the counters beside it)
        lda FRAME+1
        ldx #2
        jsr hex
        lda FRAME
        ldx #4
        jsr hex
        lda CIAS
        ldx #10
        jsr hex
        lda NMIS
        ldx #14
        jsr hex
        lda CNT+1
        ldx #18
        jsr hex
        ; the sprites
        ldx #7
        ldy #14
fs      txa
        asl
        asl
        asl
        asl
        asl
        sta TMP
        txa
        clc
        adc #1
        sta TMP+1               ; speed 1-8
        lda FRAME
        ; x = frame * speed + 24 (low byte)
        sta PTR
        lda #24
        clc
fm      adc PTR
        dec TMP+1
        bne fm
        sta $d000,y
        lda FRAME
        asl
        clc
        adc TMP
        stx TMP+1
        tax
        lda tri,x
        ldx TMP+1
        sta $d001,y
        dey
        dey
        dex
        bpl fs
        ; the scroller: row 12 one to the left, a new character on the right; its colours cycle
        ldx #0
fc      lda SCR+12*40+1,x
        sta SCR+12*40,x
        txa
        clc
        adc FRAME
        sta COL+12*40,x
        inx
        cpx #39
        bne fc
        lda FRAME
        and #15
        clc
        adc #1
        sta SCR+12*40+39
        lda FRAME
        sta COL+12*40+39
        ; the border follows the frame
        lda FRAME
        lsr
        lsr
        lsr
        and #15
        sta $d020
        ; the SID: a note a frame, the gate on for 12 frames of 16
        lda FRAME
        and #63
        clc
        adc #8
        sta $d401
        lda FRAME
        and #15
        cmp #12
        lda #$10
        adc #0                  ; $11 while the low 4 bits are 12-15... (carry set) - gate
        sta $d404
        ; a page of memory filled: $4000 + (frame & 7) * 256
        lda FRAME
        and #7
        clc
        adc #$40
        sta PTR+1
        lda #0
        sta PTR
        tay
        lda FRAME
ff      sta (PTR),y
        iny
        bne ff
        rts

hex     pha
        lsr
        lsr
        lsr
        lsr
        clc
        adc #1
        sta SCR+2*40,x
        pla
        and #15
        clc
        adc #1
        sta SCR+2*40+1,x
        rts

!source "rwdata.asm"
