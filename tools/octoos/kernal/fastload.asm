; (c) 2026 Mong00se
; OCTOPHONIC FAST LOAD (Fix 49) - the C64's side. Original code, written for the Octophonic 64.
;
; Reading a file from the core's own 1541 goes over the core's parallel port instead of the serial
; bus - LOAD, VERIFY and a file read with OPEN / CHRIN / GET# / INPUT# alike. The drive's DOS opens
; the file and reads the disk exactly as always; only the way each byte crosses is ours ("fast
; talk": the drive's side is fastdrive.asm, in a ROM of its own in the core's drive). This routine
; stands in for the KERNAL's ACPTR - "a byte from the serial bus" - and asks the drive to talk the
; fast way instead. Whenever anything else happens on the serial bus (ATN) the drive drops back by
; itself and the serial bus carries on from the same byte: nothing is lost, nothing to undo.
;
; WHERE THIS CODE LIVES. The Octophonic KERNAL has no room left, and not one byte of it is changed
; for this. The fast loader is in a second ROM bank: Commodore's stock BASIC and KERNAL with this
; file where the tape routines were ($F72C on) - rtl/fpga64_buslogic.vhd. The core swaps the bank
; in by itself as the 6510 fetches the instruction at $EE13, ACPTR's first, from the KERNAL ROM
; (rtl/fpga64_sid_iec.vhd), and in the bank $EE13 reads JMP $F72C. The bank goes out on any write
; to $D03D: "out" below is that STA, placed by fastload.py three bytes before an RTS of the main
; KERNAL's - so "push an address, JMP out" goes on anywhere in the main KERNAL. While the bank is
; in the machine is a stock C64 (its IRQ, its keyboard scan), so a program's interrupts carry on.
; One thing of the Octophonic KERNAL's is reached from that IRQ - the keyboard's decode vector
; ($028F -> keyhk in wedge2.asm): fastload.py puts a JMP to the stock decoder there in the bank.
;
; WHO IS TALKING. The core listens to what the C64 sends under ATN (rtl/fpga64_sid_iec.vhd) and so
; knows when the last thing said on the bus was "device 8, talk, on secondary address n" (n not 15, the
; command channel) - whatever routine said it, whatever the KERNAL's variables hold:
;   $D03C  read: b7 the drive is talking the fast way, b0-6 a count. Write with b7 set: "it is";
;          with b7 clear: count one - which only counts while device 8 is the talker, or talking
;          the fast way. ATN low clears both, so they can never be out of step with the bus,
;          whatever a program does. The count is the bytes read: the first 16 the serial way,
;          then (its bit 0) which way CLK stands for the next byte.
;   $D03D  read: the secondary address ($60-$6E) device 8 was last told to talk on.
;
; The serial bus's own ACPTR does the work - nothing changes at all - whenever: the drive is not the
; core's 1541 on its built-in ROM, or the port or the fast loader is switched off ($D03E); the
; program has set the user port to outputs, or has the KERNAL's RS-232 going; the talker is not
; device 8, or it is the command channel; fewer than 16 bytes have been read since the file was
; last addressed (a program that reads a byte or a line at a time between other things); or the
; drive does not answer.
; RAM used: ACPTR's own byte ($A4) and nothing else while the bytes come; $A5 and three bytes of
; stack when the drive has to be waited for.

FLCNT   = $D03C
BANKOFF = $D03D         ; write: the bank out
TALKSA  = $D03D         ; read
FLSTAT  = $D03E         ; read: b7 0 the fast loader is here, b0 0 drive 8 can talk the fast way
CIA2PA  = $DD00         ; b7 DATA in, b6 CLK in
CIA2PB  = $DD01         ; the user port: the byte. Every read of it pulses PC2
CIA2DDB = $DD03
ST      = $90
ENABL   = $02A1         ; the KERNAL's RS-232: its interrupts in use
T2      = $A4           ; ACPTR's byte
T3      = $A5           ; ACPTR's counter (and, with X and $A4, our clock)
ACPTR   = $EE13
TALK    = $ED09
LISTEN  = $ED0C
SECOND  = $EDB9
TKSA    = $EDC7
CIOUT   = $EDDD
UNLSN   = $EDFE
; out = (fastload.py): STA BANKOFF there in the bank, and the main KERNAL has an RTS behind it

        * = $F72C
; ---------------------------------------------------------------- ACPTR (the core's trap at $EE13)
; gives A the byte, carry clear, interrupts on, ST's bit 6 with the file's last byte; X and Y kept
ctrap   lda FLCNT
        bmi fbyte               ; the drive is talking the fast way
        cmp #16
        bcs try
        sta FLCNT               ; one more the serial way
stock   sei                     ; ACPTR's first instruction, then the rest of it in the main KERNAL
        lda #>ACPTR
        pha
        lda #<ACPTR
        pha
        jmp out

; a byte the fast way: it is there when CLK is low for an even count, high for an odd one - which
; it nearly always is by now
fbyte   lsr
        bcs +
        bit CIA2PA
        bvc fgot
        bvs fslow
+       bit CIA2PA
        bvc fslow
fgot    lda CIA2PA
        asl                     ; carry: DATA high - the last byte
        lda CIA2PB              ; the byte - and the strobe: "read"
        sta T2
        lda #0
        sta FLCNT               ; count it
        bcc +
        lda ST
        ora #$40                ; end of file
        sta ST
+       lda T2
        cli
        clc
        jmp out

try     lda FLSTAT
        and #$81
        bne stock
        lda CIA2DDB
        bne stock
        lda ENABL
        bne stock               ; the KERNAL's RS-232 is at work on the user port
        txa
        pha

; the drive's command: M-E, its ROM at $1000, and the secondary address to talk on
        lda ST
        pha
        lda #0
        sta ST
        lda #8
        jsr LISTEN
        lda #$6F
        jsr SECOND
        ldx #0
-       lda mecmd,x
        jsr CIOUT
        inx
        cpx #5
        bne -
        lda TALKSA
        jsr CIOUT
        jsr UNLSN
        ldx ST
        pla
        sta ST
        txa
        bmi retalk              ; no drive there: the serial bus says how
        lda #$80
        sta FLCNT               ; fast from here (until ATN)
        lda #1                  ; its first byte within 3 seconds (it has the command to read, and its
        jsr clock               ; DOS may be reading the disk) - or it has none to give
-       jsr there
        beq fgotx
        jsr tick
        bne -
        beq retalk

; not there yet: the drive's DOS is reading the disk (DATA stays low: more to come) - or, DATA high,
; there is no more: the file's last byte has been read
fslow   txa
        pha
        lda #5                  ; some 15 seconds (4 in turbo)
        jsr clock
fwait   jsr there
        beq fgotx
        bit CIA2PA
        bmi fno
        jsr tick
        bne fwait
        beq retalk              ; nothing came

fno     ldx #0                  ; "no more" only if it stands (3 ms): not a line caught as it changes
-       jsr there
        beq fgotx
        bit CIA2PA
        bpl fwait
        dex
        bne -
retalk  lda #8                  ; the serial bus's talk again (ATN: the drive is back in its DOS), and
        jsr TALK                ; the byte by it
        lda TALKSA
        jsr TKSA
        pla
        tax
        jmp stock
fgotx   pla
        tax
        jmp fgot

; is the next byte there? (Z set: yes)
there   lda FLCNT
        lsr
        lda CIA2PA
        and #$40                ; CLK high
        bcc +
        eor #$40
+       rts

; the long waits' clock: A x 3 seconds or so of "tick"s, which answers Z set when they are up
clock   sta T3
        ldx #0
        stx T2
        rts
tick    inx
        bne +
        inc T2
        bne +
        dec T3
+       rts

; RUN/STOP+RESTORE (or a BRK) while the bank is in: the stock KERNAL's warm start at $FE66 comes here
; instead (fastload.py), and goes on at $FE66 of the main KERNAL - its own vectors, its own screen
nmix    lda #$FE
        pha
        lda #$65
        pha
        jmp out

mecmd   !text "M-E"
        !byte $00, $10
        !text "(C)2026 MONG00SE"
fl_end
