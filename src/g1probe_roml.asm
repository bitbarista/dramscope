; ===========================================================================
; G1 PROBE -- does EasyFlash $DE02 mode switching work on real hardware?
;
; SPEC.md gate G1. This answers ONE question and then stops:
;
;   Starting in Ultimax (no RAM needed, only $0000-$0FFF visible), can a write
;   to the EasyFlash control register at $DE02 get us into a mode where the
;   REST of RAM is reachable AND the cartridge is still mapped at $8000?
;
; If yes, DRAMscope can be a single binary that needs no working RAM to start
; and still reaches all 64 KB -- MAX-Switch's capability on hardware people
; already own. If no, it stays two binaries.
;
; ---------------------------------------------------------------------------
; ⚠ IT TRIES ALL EIGHT VALUES RATHER THAN ASSUMING ONE.
; The published EasyFlash register semantics are bit 0 = GAME, bit 1 = EXROM,
; bit 2 = "GAME comes from bit 0", bit 7 = LED -- but the POLARITIES are easy
; to get backwards from documentation, and a probe that tests one guessed
; value returns a false negative when the guess is wrong. So it sweeps $00-$07
; and REPORTS WHICH ONE WORKED. An assumption-free answer is the whole point
; of running it on hardware at all.
;
; ---------------------------------------------------------------------------
; ⚠ THE PROBE RUNS FROM RAM AT $0200, NOT FROM THE CARTRIDGE.
; Some of the eight candidates will bank the cartridge out from under the CPU.
; Code in ROM would die mid-instruction and the machine would simply hang,
; which is indistinguishable from "the register did nothing". $0200 is RAM and
; is visible in Ultimax, so the probe survives every candidate and can still
; report. This is the same class of trap as the $00/$01 write ordering below.
;
; ---------------------------------------------------------------------------
; ⚠ NO JSR ANYWHERE. Ultimax gives no stack page and nothing here has proven
; $0100-$01FF, so every routine is inlined.
;
; ---------------------------------------------------------------------------
; WHAT YOU WILL SEE
;
;   GREEN border + a line of text   the switch works. Read the DE02= value.
;   YELLOW border + text            we left Ultimax but LOST the cartridge.
;                                   Usable, but the engine must be relocated.
;   RED border, no text             no value worked. G1 is a NO on this device.
;   BLACK / nothing                 the cartridge never got control.
;
; Run it on Kung Fu Flash and on Ultimate II+ and report the colour, plus the
; two hex digits if there are any.
; ===========================================================================

!to "build/g1probe_roml.bin", plain
* = $8000

SIG     = $9f00                 ; where the "is the cartridge still here" bytes live

entry:
        sei
        cld
        ldx #$ff
        txs
        lda #1                  ; WHITE: we have control
        sta $d020
        lda #0
        sta $d021

        ; ⚠ Copy the probe to RAM BEFORE touching $DE02. See the header.
        ldx #0
copy:
        lda ram_src,x
        sta $0200,x
        lda ram_src+$100,x
        sta $0300,x
        inx
        bne copy
        jmp $0200

; ---------------------------------------------------------------------------
; Everything below is assembled to run at $0200-$03FF and is copied there.
; ---------------------------------------------------------------------------
ram_src:
!pseudopc $0200 {

probe:
        ldy #0                  ; candidate index
try:
        lda cand,y
        sta $de02

        ; --- is the rest of RAM reachable now?
        ; In Ultimax $2000 is unmapped and reads float, so this fails there.
        lda #$a5
        sta $2000
        cmp $2000
        bne nextc
        lda #$5a
        sta $2000
        cmp $2000
        bne nextc

        ; --- is the cartridge still mapped at $8000?
        ldx #3
sigchk:
        lda SIG,x
        cmp sigtab,x
        bne nocart
        dex
        bpl sigchk

        lda #1                  ; cart still there
        sta okflag
        lda #5                  ; GREEN
        sta $d020
        jmp report
nocart:
        lda #0
        sta okflag
        lda #7                  ; YELLOW
        sta $d020
        jmp report

nextc:
        iny
        cpy #8
        bne try
        lda #2                  ; RED -- nothing worked
        sta $d020
dead:   jmp dead

; ---------------------------------------------------------------------------
; Report. Only reached when $2000 is RAM, so there is memory to draw in.
; ---------------------------------------------------------------------------
report:
        lda cand,y
        sta win

        ; ⚠ LATCH FIRST, THEN DDR. Writing $00 to the DDR while the latch
        ; still holds its power-on $00 drives mode $30 and banks everything
        ; out mid-instruction.
        lda #$37
        sta $01
        lda #$2f
        sta $00

        lda $dd02
        ora #$03
        sta $dd02
        lda $dd00
        ora #$03                ; VIC bank 0
        sta $dd00
        lda #$14                ; matrix $0400, char ROM $1000
        sta $d018
        lda #$1b                ; display on
        sta $d011

        ldx #0
clr:
        lda #$20
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        lda #1
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne clr

        ldx #0
        lda okflag
        beq msg_nc
msg_ok:
        lda t_ok,x
        beq hexout
        sta $0400,x
        inx
        bne msg_ok
msg_nc:
        lda t_nc,x
        beq hexout
        sta $0400,x
        inx
        bne msg_nc

hexout:
        lda win                 ; high nibble
        lsr
        lsr
        lsr
        lsr
        tax
        lda hexchr,x
        sta $0400+5
        lda win                 ; low nibble
        and #$0f
        tax
        lda hexchr,x
        sta $0400+6
stop:   jmp stop

; ---------------------------------------------------------------------------
cand:    !byte $00,$01,$02,$03,$04,$05,$06,$07
sigtab:  !byte $d5,$3a,$c7,$91
hexchr:  !scr "0123456789abcdef"
t_ok:    !scr "de02=xx switched, cart still mapped", 0
t_nc:    !scr "de02=xx switched, cart is gone", 0
win:     !byte 0
okflag:  !byte 0

}
; ---------------------------------------------------------------------------

        !fill SIG - *, $ff
        !byte $d5,$3a,$c7,$91           ; the signature sigchk looks for
        !fill $a000 - *, $ff
