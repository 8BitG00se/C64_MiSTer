; REWIND simulation: the 16K "ROM" the simulated C64 starts from (BASIC + KERNAL space, $A000-$BFFF
; and $E000-$FFFF) - just enough to start the test game at $0810 and to pass interrupts on the way the
; KERNAL does ($0314, $0318, $EA81).                                   (c) 2026 Mong00se
; acme -f plain -o rwrom.bin rwrom.asm     (the image: 8K of BASIC space, then 8K of KERNAL space)
        * = $c000               ; (assembled at $C000-$FFFF; the first 8K stands in for $A000-$BFFF)
        !fill $2000, $ea
        * = $e000
reset   sei
        cld
        ldx #$ff
        txs
        lda #$2f
        sta $00
        lda #$37
        sta $01
        jmp $0810
irqv    pha
        txa
        pha
        tya
        pha
        jmp ($0314)
nmiv    jmp ($0318)
        !fill $ea81 - *, $ea
        pla
        tay
        pla
        tax
        pla
        rti
        !fill $fffa - *, $ea
        !word nmiv, reset, irqv
