; (c) 2026 Mong00se
; OCTOPHONIC FAST LOAD (Fix 49) - the 1541's side. Original code, written for the Octophonic 64.
;
; "Fast talk": a file that is open in the drive, by the DOS, in the ordinary way, is handed to the
; C64 over the core's parallel port instead of the serial bus. Nothing about the file is ours: the
; DOS opened it, the DOS reads its blocks (its own two buffers, its own read-ahead) and the DOS
; knows where the file ends. This routine only takes each byte the DOS has ready and passes it
; across - so whenever it stops (ATN: the C64 has started any serial bus command) the DOS's
; channel stands exactly where the C64 has read to, and the serial bus carries on from there.
;
; WHERE THIS CODE LIVES: in a ROM of its own in the core's 1541, at $1000-$11FF (nothing is there in a
; real 1541) - rtl/iec_drive/c1541_logic.sv, only while the drive runs the built-in standard ROM.
; None of the drive's RAM is used, nothing has to be sent to the drive first. The C64 starts it
; with the DOS command  M-E $00 $10 <secondary address>  (fastload.asm).
;
; The wires (the core's "parallel port": C64 user port <-> the 1541's VIA 1, and the serial bus):
;   port A -> PB0-7       the byte
;   CLK                   changes with every byte: low for the first, high for the second, ... The
;                         C64 keeps count (the core's register at $D03C), so it knows which way
;                         means "the next byte is there" - no pulse to catch, nothing to let go
;   DATA                  with it: low = more follow, high = this byte is the file's last
;   PC2 -> CB1            the C64 has read it (its CIA pulses PC2 by itself): on to the next
;   ATN                   at any time: the drive lets go and is back in the DOS, which answers
; No timing anywhere: each side waits for the other, so an interrupt on either is harmless.
;
; DOS 2.6 (901229-05) names used: the channel for a secondary address ($D0EB), its state ($F2,X:
; b7 readable, b3 not the last byte), the byte it has ready ($023E,X), "next byte" ($D3AA), its
; file type ($D125), the active buffer's pointer ($D12F -> $99,X) and where the last block ends
; ($0244,Y). The core only maps this ROM beside that DOS.

VIA1B   = $1800         ; the serial bus: b1 DATA out, b3 CLK out (b4, the ATN answer, stays 0), b7 ATN in (1: low)
DDRA    = $1803
IFR     = $180D         ; b4: CB1 (the C64's strobe), b1: CA1 (ATN)
PA      = $180F         ; port A, no handshake
SA      = $83           ; the DOS's current secondary address...
LINDX   = $82           ; ...and its channel
ATNPND  = $7C           ; the DOS's IRQ saw ATN
CHNRDY  = $F2           ; ,X: b7 the channel can be read, b3 clear: the byte ready is the last
CHNDAT  = $023E         ; ,X: the byte ready
LSTCHR  = $0244         ; ,Y: the last block: the index of its last byte (0: not the last block)
DIRLST  = $0254         ; the directory is being listed (LOAD"$")
BUFTAB  = $99           ; ,X: the active buffer's pointer: the next byte the DOS will take
CMDSA   = $0205         ; the M-E command's sixth byte: the secondary address to talk on
FNDRCH  = $D0EB         ; the channel for SA -> LINDX (carry set: none)
TYPFIL  = $D125         ; its file type -> A (carry clear: DEL SEQ PRG USR), X = LINDX
GETACT  = $D12F         ; X = the active buffer's pointer (BUFTAB,X), Y = LINDX
GETBYT  = $D3AA         ; the next byte into CHNDAT (reads the next block when it must: needs the DOS's IRQ)

JOBS    = $00           ; the disk controller's six jobs (b7: still to do; $80: read)
DRVST   = $20           ; drive 0: b5 ready, b7 the motor coming up, b6 the head stepping, b4 idle
DRVTRK  = $40           ; the track the controller is working on
HDRPNT  = $32           ; -> the job's track and sector
JOBN    = $3F           ; the controller's "this job"
SAVSP   = $49           ; its saved stack pointer
CONTRL  = $F2B0         ; the disk controller (the DOS's interrupt calls it on VIA 2's timer)
JOBSET  = $F393         ; job JOBN: HDRPNT and the rest
DOJOB   = $F48D         ; "do job X now": for a read, find its header, read, decode, done
VIA2PCR = $1C0C
VIA2IFR = $1C0D         ; b6: that timer
DATA    = $02           ; VIA1B: DATA out (1: low)
CLK     = $08           ;        CLK out (1: low)

        * = $1000
; (The DOS's "ATN seen" flag can be standing from the UNLISTEN that ended this very command - its
; interrupt comes in late when the DOS was already answering - so it is cleared here, unless ATN is
; low right now.)
start   bit VIA1B
        bmi quit0               ; ATN is low: back to the DOS
        lda #0
        sta ATNPND
        lda #$FF
        sta DDRA                ; port A out
        lda CMDSA
        and #$0F
        sta SA
        jsr FNDRCH
        bcs quit                ; no such channel (the C64 gives up waiting and asks the serial way)
next    ldx LINDX
        lda CHNRDY,x
        bmi ready
no      lda ATNPND              ; nothing (more) to read: the lines stay as they are - DATA high after
        beq no                  ; the last byte - until the C64 says anything on the serial bus
quit    lda #0
        sta DDRA                ; port A in
        sta VIA1B               ; CLK and DATA let go
        lda #$0F                ; the DOS is still inside its M-E command: the command channel again
        sta SA
        jmp FNDRCH              ; (and back to the DOS, which answers the ATN)
quit0   rts

single  ldx LINDX
        lda CHNRDY,x
        and #$08
        cmp #$08                ; carry: more follow
        ldy CHNDAT,x
        jsr send
        bcs quit                ; ATN: not read - it is still the DOS's byte ready
fetch   cli
        jsr GETBYT              ; the DOS's next byte (and, when it must, its next block)
        lda ATNPND
        bne +
        jmp next
+       jmp quit

; a plain file with more than one byte to go in this block: every byte up to the block's last but one
; straight from the DOS's buffer (the DOS takes 200 cycles over each; this loop a quarter of that) -
; then the pointer is left on the last byte and the DOS takes it, and what follows it, as always
ready   sei                     ; the DOS's interrupt rests while the C64 keeps up (see "wait")
        and #$08
        beq single              ; the byte ready is the file's last
        ldy SA
        cpy #$0F
        beq single              ; the command channel
        tya
        bne plain
        lda DIRLST              ; SA 0 is LOAD: of the directory? (its lines are made as they go)
        bne single
plain   jsr TYPFIL
        bcs single              ; relative files and the rest: the DOS's way
        ldy CHNDAT,x            ; first the byte that is ready...
        sec
        jsr send
        bcs quit                ; ATN: not read - it is still the DOS's byte ready
        jsr GETACT              ; ...then from the pointer on (X: the pointer's index, Y: the channel)
        lda LSTCHR,y
        bne +
        lda #$FF                ; (not the last block: its last byte is at 255)
+       sec
        sbc BUFTAB,x            ; how many before the block's last byte
        beq pump                ; none: the DOS takes the last one now
        bcc pump                ; (never: the pointer is past it)
        tay
bulk    lda (BUFTAB,x)
        sta PA
        lda VIA1B               ; (reading it also clears the strobe's flag)
        and #CLK
        eor #CLK+DATA           ; CLK the other way, DATA low
        sta VIA1B
        jsr wait
        bcs tofetch             ; ATN: that byte was not read - the DOS takes it up as its byte ready
        inc BUFTAB,x
        dey
        bne bulk

; The block is across but for its last byte, and the DOS is about to want the next block - which
; it asked the disk controller for a block ago. The controller is a routine the DOS's timer
; interrupt calls every 15 ms; here it is called at once, and after that on the timer's own flag
; as ever, until the block is in.
pump    jsr try
-       ldx #5
--      lda JOBS,x
        bmi +
        dex
        bpl --
tofetch jmp fetch               ; nothing is asked of the controller (any more)
+       lda IFR
        and #$02
        bne tofetch             ; ATN
        bit VIA2IFR
        bvc -                   ; not time yet
        jsr try
        jmp -

; The controller, called as its interrupt calls it, reads whichever sector header comes next and
; only takes up a sector that is two to seven on from it - and the sector wanted now is the next
; but one or so (the disk's interleave, less the time the block took to cross), so it would let
; it go by and wait a whole turn of the disk. But its own routine for a read looks for the one
; header it wants and nothing else: so when what is asked is a plain read on the track the head
; is on, with the motor up and the head still (all as the controller left it), go straight in.
try     ldx #5
-       lda JOBS,x
        bmi +
        dex
        bpl -
        rts
+       cmp #$80                ; a read, drive 0
        bne +
        lda DRVST
        and #$E0
        cmp #$20                ; ready: the motor up, not stepping
        bne +
        stx JOBN
        jsr JOBSET              ; (its header's pointer, Y = 0)
        lda (HDRPNT),y
        cmp DRVTRK              ; on this track
        bne +
        lda #$20
        sta DRVST               ; (in use: the controller's own mark - no motor-off count running)
        tsx
        stx SAVSP               ; the controller leaves through its saved stack pointer: to our caller
        lda VIA2PCR
        ora #$0E
        sta VIA2PCR             ; "byte ready" on, as the controller's own first step
        ldx JOBN
        jmp DOJOB
+       jmp CONTRL

; the byte in Y to the C64 (carry set: more follow), then wait for it to be read
send    sty PA
        lda VIA1B
        and #CLK
        eor #CLK                ; CLK the other way
        bcc +
        ora #DATA               ; DATA low
+       sta VIA1B
; Wait for the C64's strobe (carry clear) or ATN (carry set). A C64 that is reading as fast as it
; can answers within 3 ms, and for that long the DOS's interrupt rests; one that takes its time (a
; BASIC program, a player with other things to do) gets the DOS as it always is meanwhile.
wait    tya
        pha
        ldy #0
-       lda IFR
        and #$12
        bne +
        dey
        bne -
        cli
-       lda ATNPND
        bne ++
        lda IFR
        and #$10
        beq -
        sei
+       lsr
        lsr                     ; carry: ATN (the flag's bit 1)
        !byte $24               ; (BIT: skips the SEC)
++      sec
        pla
        tay
        rts
        !text "(C)2026 MONG00SE"
drv_end
        !if drv_end > $1200 { !error "the drive's routine is over 512 bytes" }
        !fill $1200 - drv_end, $FF
