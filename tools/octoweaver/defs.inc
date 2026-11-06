; defs.inc - shared by weaver.asm, player.asm, play.asm.  Octo Weaver Lite build 1, by Mong00se.
; The memory map (one fixed layout, the same in the editor, in NAME PLAY and in a demo's NAME.OWP):
;   $0801-$17FF  stub, the platform library (OctoVIC, the eq, text, keys) and the PLAY program - the editor uses this very code
;   $1800-$2CFF  the player (init $1800, play $1803, stop $1806 ...)  - see player.asm
;   SONG         the song, SONGSIZE bytes (one page-aligned block, layout below)
;   after that   the editor
PLAYER   = $1800
SONG     = $2D00

; ---- the song: offsets from SONG (docs/OCTOWEAVER.md has every byte)
H_SPEED  = 0            ; frames a step (1-31)
H_KEY    = 1            ; 0-11 (C..B)
H_SCALE  = 2            ; 0-5
H_CHORDS = 3            ; 4 bytes: scale degree 0-6 of each chord's root
H_LEN    = 7            ; bars in the song 1-128
H_NAMES  = 16           ; 8 x 6 bytes, job names (ASCII capitals, space padded)
H_DCUT   = 64           ; 8 bytes: filter cutoff (SID reg $16)
H_DRES   = 72           ; 8 bytes: resonance in the top nibble (SID reg $17 without the routing bits)
H_DMV    = 80           ; 8 bytes: mode in the top nibble, volume in the low (SID reg $18)
H_SNAME  = 96           ; 16 bytes song name
SND      = SONG + 256   ; 32 slots x 16 bytes (slot 0 unused; sound n at SND + 16 n)
PAT      = SONG + 768   ; 8 tracks x 48 patterns x 32 bytes (16 notes, then 16 sounds)
BAR      = PAT + 12288  ; 8 x 128 bytes: the pattern number 0-48 of each bar
SONGEND  = BAR + 1024
SONGSIZE = 14080

; ---- a sound: 16 bytes
S_WAVE   = 0            ; SID control without the gate: waves in b7-4, ring b2, sync b1
S_AD     = 1
S_SR     = 2
S_PW     = 3            ; pulse width 0-15 (x 256)
S_PWM    = 4            ; pulse width motion speed 0-15 (0 off)
S_VIB    = 5            ; vibrato depth 0-15
S_VOICING = 6           ; 0 one voice, 1 unison pair, 2 octave stack, 3 power chord, 4 major, 5 minor, 6 drums
S_DETUNE = 7            ; 0-15 (unison spread; for drums: the noise voice's decay, 0 = no noise voice)
S_ARP    = 8            ; 0 none, 1-7
S_GLIDE  = 9            ; 0-15
S_FILT   = 10           ; 1: through the SID's filter
S_WP     = 11           ; 4 bytes: the wave program (control byte of frames 0-3, 0 = the sound's wave)
S_FALL   = 15           ; 0-15: pitch falls from above (kicks, zaps)

; ---- zero page of the editor and the platform library ($03-$22: BASIC's pointers at $2B-$38 are left alone)
tp      = $03           ; screen pointer
cp      = $05           ; colour pointer
ip      = $07           ; data pointer
jp      = $09           ; second data pointer
t0      = $0b
t1      = $0c
t2      = $0d
t3      = $0e
t4      = $0f
t5      = $10
t6      = $11
t7      = $12

; ---- OctoVIC
VADDR   = $D600
VINC    = $D603
VDATA   = $D604
OCTRL   = $D605
OKEY    = $D606
OSTATUS = $D608
SPRCNT  = $D60F
PALSEL  = $D619
PALIDX  = $D61A
PALR    = $D61B
PALG    = $D61C
PALB    = $D61D
OID     = $D61E
OVER    = $D61F
L1      = $D630
MULA    = $D650
MULB    = $D652
MULR    = $D654
BSRC    = $D670
BDST    = $D673
BW      = $D676
BH      = $D678
BSSTR   = $D67A
BDSTR   = $D67C
BFILL   = $D67E
BCTRL   = $D67F
