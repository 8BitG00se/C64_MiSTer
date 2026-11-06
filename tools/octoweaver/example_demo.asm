; example_demo.asm - the smallest demo that plays an Octo Weaver song: NAME.OWP (X in the editor) is the player and the song,
; a PRG that loads at $1000 and ends at SONGEND.  This program sits below it ($0801-$0FFF), starts its own raster interrupt and
; calls the player once a frame.  The border shows what the player costs: its colour band is as tall as the player's raster time.
;   put NAME.OWP next to this file, then  acme -f cbm -o demo.prg example_demo.asm  and run demo.prg (the song is inside the prg)
        * = $0801
        !byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00      ; 10 SYS2061
        sei
        lda #$35                ; RAM and I/O (the player needs the I/O area, nothing else)
        sta $01
        lda #$7f
        sta $dc0d               ; no CIA interrupts
        sta $dd0d
        lda $dc0d
        lda $dd0d
        lda #<irq
        sta $fffe
        lda #>irq
        sta $ffff
        lda #<nmi
        sta $fffa
        lda #>nmi
        sta $fffb
        lda #100                ; raster line of the interrupt
        sta $d012
        lda #$1b
        sta $d011
        lda #1
        sta $d01a
        sta $d019
        lda #0                  ; the player: JSR $1000 starts the song at bar 0
        jsr $1000
        cli
loop    jmp loop                ; the demo's own work would go here
nmi     rti
irq     pha
        txa
        pha
        tya
        pha
        lda #$ff
        sta $d019
        lda #2
        sta $d020               ; the band starts
        jsr $1003               ; the player: once a frame
        lda #14
        sta $d020               ; and ends: its height is the player's cost
        pla
        tay
        pla
        tax
        pla
        rti
        ; the player and the song: NAME.OWP loads at $1000 (the file's own two-byte address is skipped here)
        * = $1000
        !binary "NAME.OWP", , 2
