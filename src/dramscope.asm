; ===========================================================================
; DRAMscope -- Commodore 64 memory diagnostic
; SPEC.md iteration 1: P0 bring-up probe, P1 data bus, P2 address bus,
; and the display framework every later phase hangs on.
;
; ⚠ PROVENANCE: nothing here derives from any other RAM test. See PROVENANCE.md.
;
; ---------------------------------------------------------------------------
; DELIVERY VEHICLE -- and its honest limit
;
; This is a normal 8 KB autostart cartridge, so the KERNAL's reset does
; JSR $FD02 to find the CBM80 signature, and that JSR needs $0100-$01FF.
; A machine with a dead stack page dies BEFORE this gets control. Removing
; that dependency is gate G1 (EasyFlash $DE02 mode switching, SPEC.md §2.2)
; and is the next thing to resolve. Until then Dead Test remains the right
; first move on a machine that will not boot at all.
;
; ---------------------------------------------------------------------------
; BORDER CODES -- the display needs working RAM, the border does not, so a
; fault that stops the display can still report itself:
;
;   white    the cartridge has control     (set by the FIRST instruction)
;   red      FATAL: zero-page scratch $F9-$FE unusable
;   purple   FATAL: screen home page $0400-$07FF unusable
;   yellow   P1 data bus running
;   cyan     P2 address bus running
;   green    finished, no fault found
;   lt red   finished, fault found
;
; A BLACK border means the cartridge never got control at all -- not that it
; started and hung. Every phase changes the colour, so the last one shown
; localises a hang even with no display.
;
; ---------------------------------------------------------------------------
; ⚠ NO SELF-MODIFYING CODE ANYWHERE. The engine runs from cartridge ROM, so
; the relocate-and-self-modify trick the sibling project uses is unavailable
; here. Every address is either absolute, absolute,X within one page, or read
; from a ROM table. Iteration 2 relocates into RAM and can then do better.
; ===========================================================================

; ⚠ BOTH fault builds pass -o, and an unguarded !to here would warn "output
; file name already chosen" on every one of them. A build that prints a
; warning it is expected to ignore is where a real warning goes to hide.
!ifndef INJECT_DB { !ifndef INJECT_AB { !to "build/dramscope.bin", plain } }

; ---------------------------------------------------------------- hardware
BORDER   = $d020
BGCOL    = $d021
VICCTL1  = $d011
VICMEM   = $d018
CIA2PRA  = $dd00
CIA2DDRA = $dd02
CPUDDR   = $00
CPUPORT  = $01
SCREEN   = $0400
COLRAM   = $d800

; ------------------------------------------------------------------ colours
C_BLACK  = 0
C_WHITE  = 1
C_RED    = 2
C_CYAN   = 3
C_PURPLE = 4
C_GREEN  = 5
C_YELLOW = 7
C_LTRED  = 10
C_DKGREY = 11
C_GREY   = 12
C_LTGREY = 15

; ------------------------------------------------------- screen code glyphs
CH_DOT   = $2e                  ; .  untested
CH_DASH  = $2d                  ; -  separator / testing
CH_FULL  = $a0                  ;    pass -- inverse space, a solid cell
CH_X     = $18                  ; X  fail
CH_SPACE = $20

; ---------------------------------------------------- display geometry
MAP_ROW  = 3                    ; first map row
MAP_COL  = 2                    ; first map column
PAN_COL  = 21                   ; right-hand panel
DB_ROW   = 5                    ; data bus lane   (heading -2, bit numbers -1)
AH_ROW   = 9                    ; address lane A15..A8
AL_ROW   = 11                   ; address lane A7..A0
PH_ROW   = 14                   ; phase text
V_ROW    = 21                   ; verdict

; ---------------------------------------------------- zero-page scratch
; ⚠ SIX BYTES, PROVEN FROM ROM BEFORE ANYTHING USES THEM (P0a). The precedent
; is the sibling project, which proves $FB/$FC in its stage 0 for exactly this
; reason: an engine that needs a pointer cannot assume it has one.
strp     = $f9                  ; source -- ROM string
sptr     = $fb                  ; destination -- screen
cptr     = $fd                  ; destination -- colour RAM

; ---------------------------------------------------- workspace RAM
; ⚠ LIVES IN THE SCREEN PAGE ON PURPOSE. The matrix is 1000 bytes of a 1024
; byte page, so $07E8-$07FF is 24 bytes the VIC never fetches -- and P0b has
; already proven the whole page before any of it is relied on. One proven
; region instead of two.
WORK     = $07e8
w_dbmask = WORK+0               ; data bus    -- 1 = that bit misbehaved
w_ablo   = WORK+1               ; A7..A0      -- 1 = that line faulty
w_abhi   = WORK+2               ; A15..A8     -- 1 = that line faulty
w_tmp    = WORK+3
w_tmp2   = WORK+4
w_row    = WORK+5
w_col    = WORK+6
w_col2   = WORK+7
w_label  = WORK+8               ; one mutable character, for the map row labels
w_labelz = WORK+9               ; its zero terminator

; P2's base: RAM, not the screen, not under the cartridge.
ABASE    = $0800

; ===========================================================================
* = $8000
        !word cold
        !word cold
        !byte $c3,$c2,$cd,$38,$30       ; CBM80 autostart signature

; ------------------------------------------------------------------- entry
cold:
        lda #C_WHITE                    ; ⚠ FIRST INSTRUCTION SETS A COLOUR
        sta BORDER
        lda #C_BLACK
        sta BGCOL
        sei
        cld
        ldx #$ff
        txs

        ; ⚠⚠ ORDER MATTERS AND GETTING IT WRONG KILLS THE MACHINE MID-INSTRUCTION.
        ; $00 is the CPU port's DATA DIRECTION register, $01 the latch. At reset
        ; DDR = 0, so the banking pins are INPUTS floating high -- which reads as
        ; mode $37 and is why this cartridge is visible at all. Write $00 to the
        ; DDR first and the pins become OUTPUTS driving the latch's power-on $00,
        ; i.e. mode $30: cartridge banked out while the CPU executes from it.
        ; So load the latch while the pins are still inputs, THEN make them
        ; outputs, and they come up already holding $37.
        lda #$37
        sta CPUPORT
        lda #$2f
        sta CPUDDR

        lda #$0b                        ; DEN=0 -- display off for the blind phase
        sta VICCTL1
        lda #$14                        ; matrix $0400, char ROM $1000
        sta VICMEM
        lda CIA2DDRA
        ora #$03
        sta CIA2DDRA
        lda CIA2PRA
        ora #$03                        ; VIC bank 0
        sta CIA2PRA

; ===========================================================================
; P0a -- prove the six zero-page scratch bytes. REGISTERS ONLY.
; Nothing may use a pointer until this passes, so this may not use one either.
; ===========================================================================
        ldx #5
p0a_l:
        lda #$55
        sta strp,x
        cmp strp,x
        bne p0a_dead
        lda #$aa
        sta strp,x
        cmp strp,x
        bne p0a_dead
        txa                             ; address-dependent, so a byte that
        eor #$5a                        ; aliases onto its neighbour still fails
        sta strp,x
        cmp strp,x
        bne p0a_dead
        dex
        bpl p0a_l
        jmp p0b

p0a_dead:
        lda #C_RED
        sta BORDER
        jmp halt

; ===========================================================================
; P0b -- prove the screen home page $0400-$07FF. REGISTERS ONLY.
; absolute,X reaches a whole page with no pointer, so this still needs no RAM.
; Four pages, written out rather than self-modified, because this is ROM.
; The display AND the workspace both live here, so everything after this
; depends on it and nothing before it may.
; ===========================================================================
p0b:
        ldx #0
p0b_1:  txa
        eor #$5a
        sta SCREEN,x
        inx
        bne p0b_1
        ldx #0
p0b_1v: txa
        eor #$5a
        cmp SCREEN,x
        bne p0b_dead
        inx
        bne p0b_1v

        ldx #0
p0b_2:  txa
        eor #$a5
        sta SCREEN+$100,x
        inx
        bne p0b_2
        ldx #0
p0b_2v: txa
        eor #$a5
        cmp SCREEN+$100,x
        bne p0b_dead
        inx
        bne p0b_2v

        ldx #0
p0b_3:  txa
        eor #$3c
        sta SCREEN+$200,x
        inx
        bne p0b_3
        ldx #0
p0b_3v: txa
        eor #$3c
        cmp SCREEN+$200,x
        bne p0b_dead
        inx
        bne p0b_3v

        ldx #0
p0b_4:  txa
        eor #$c3
        sta SCREEN+$300,x
        inx
        bne p0b_4
        ldx #0
p0b_4v: txa
        eor #$c3
        cmp SCREEN+$300,x
        bne p0b_dead
        inx
        bne p0b_4v
        jmp screen_up

p0b_dead:
        lda #C_PURPLE
        sta BORDER
        jmp halt

; ===========================================================================
; Bring the display up. From here the map is live.
; ===========================================================================
screen_up:
        jsr clear_screen
        jsr draw_chrome
        jsr map_init
        lda #$1b                        ; DEN=1 -- display on
        sta VICCTL1

; ===========================================================================
; P1 -- data bus integrity. Walking ones, walking zeroes, both rails, at one
; proven address. Instant, and it runs before any march test: a shorted data
; line makes every later result confusing, and it should be NAMED in the first
; millisecond rather than inferred from a thousand march failures.
; ===========================================================================
p1:
        lda #C_YELLOW
        sta BORDER
        lda #<s_p1
        ldy #>s_p1
        jsr phase
        lda #0
        sta w_dbmask

        lda #$01                        ; walking ones
        sta w_tmp
p1_one:
        lda w_tmp
        sta ABASE
        lda ABASE
!ifdef INJECT_DB { eor #$08 }           ; mutation: D3 reads back inverted
        eor w_tmp                       ; any set bit = a bit that misbehaved
        ora w_dbmask
        sta w_dbmask
        asl w_tmp
        bne p1_one

        lda #$01                        ; walking zeroes
        sta w_tmp
p1_zero:
        lda w_tmp
        eor #$ff
        sta w_tmp2
        sta ABASE
        lda ABASE
        eor w_tmp2
        ora w_dbmask
        sta w_dbmask
        asl w_tmp
        bne p1_zero

        lda #$00                        ; both rails -- catches a line stuck
        sta ABASE                       ; at its own idle value
        lda ABASE
        ora w_dbmask
        sta w_dbmask
        lda #$ff
        sta ABASE
        lda ABASE
        eor #$ff
        ora w_dbmask
        sta w_dbmask

        lda w_dbmask
        sta w_tmp
        lda #$00                        ; every data bit was tested
        sta w_tmp2
        lda #DB_ROW
        ldx #PAN_COL+1
        jsr draw_lane

; ===========================================================================
; P2 -- address bus integrity.
;
; Write a distinct value to the base and to base+2^n for every line, then read
; them all back. A line that is stuck, open or shorted makes two addresses
; collide, and WHICH addresses collide says WHICH line.
;
; ⚠ A15 IS NOT TESTED AND THE DISPLAY SAYS SO. base+$8000 lands in the
; cartridge's own ROML window, so reaching it needs the engine relocated into
; RAM first -- iteration 2. Claiming 16 lines while testing 15 is exactly the
; quiet over-claim PROVENANCE.md exists to prevent.
; ===========================================================================
p2:
        lda #C_CYAN
        sta BORDER
        lda #<s_p2
        ldy #>s_p2
        jsr phase
        lda #0
        sta w_ablo
        sta w_abhi

        lda #$00
        sta ABASE
        ldx #0
p2_write:
        jsr addr_for_line               ; sptr = ABASE + (1 << X)
        txa
        clc
        adc #1                          ; value = index+1, never $00
        ldy #0
        sta (sptr),y
        inx
        cpx #15
        bne p2_write

        ; The base must still read $00. If it does not, some line aliased onto
        ; it -- and we cannot yet say which, so every line is reported suspect
        ; rather than guessed at.
        lda ABASE
        beq p2_read_all
        lda #$ff
        sta w_ablo
        lda #$7f
        sta w_abhi
        jmp p2_done

p2_read_all:
        ldx #0
p2_read:
        jsr addr_for_line
        ldy #0
        lda (sptr),y
!ifdef INJECT_AB {                      ; mutation: A5 returns a wrong value
        cpx #5
        bne inj_ab_skip
        lda #$ff
inj_ab_skip:
}
        sta w_tmp2
        txa
        clc
        adc #1
        cmp w_tmp2
        beq p2_ok
        jsr set_addr_fault              ; X = the faulty line
p2_ok:
        inx
        cpx #15
        bne p2_read

p2_done:
        jsr mark_p2_pages
        lda w_abhi                      ; A15..A8
        sta w_tmp
        lda #$80                        ; ⚠ A15 untested, shown as such
        sta w_tmp2
        lda #AH_ROW
        ldx #PAN_COL+1
        jsr draw_lane
        lda w_ablo                      ; A7..A0
        sta w_tmp
        lda #$00
        sta w_tmp2
        lda #AL_ROW
        ldx #PAN_COL+1
        jsr draw_lane

; ===========================================================================
; Verdict
; ===========================================================================
verdict:
        lda #<s_pdone
        ldy #>s_pdone
        jsr phase
        lda w_dbmask
        bne v_data
        lda w_ablo
        ora w_abhi
        bne v_addr
        lda #C_GREEN
        sta BORDER
        lda #C_GREEN
        sta w_col2
        lda #<s_ok
        ldy #>s_ok
        jsr verdict_line
        lda #<s_ok2
        ldy #>s_ok2
        jmp verdict_line2

v_data:
        lda #C_LTRED
        sta BORDER
        lda #C_LTRED
        sta w_col2
        lda #<s_databad
        ldy #>s_databad
        jsr verdict_line
        lda #<s_databad2
        ldy #>s_databad2
        jmp verdict_line2

v_addr:
        lda #C_LTRED
        sta BORDER
        lda #C_LTRED
        sta w_col2
        lda #<s_addrbad
        ldy #>s_addrbad
        jsr verdict_line
        lda #<s_addrbad2
        ldy #>s_addrbad2
        jmp verdict_line2

halt:
        jmp halt

verdict_line:
        sta strp
        sty strp+1
        lda #V_ROW
        ldx #1
        jsr setpos
        ldx w_col2
        jmp putstr
verdict_line2:
        sta strp
        sty strp+1
        lda #V_ROW+1
        ldx #1
        jsr setpos
        ldx w_col2
        jsr putstr
        jmp halt

; ===========================================================================
; addr_for_line -- X = line index 0..14, sets sptr = ABASE + (1 << X)
; Table-driven, because this is ROM and there is nothing to self-modify.
; Preserves X, clobbers A.
; ===========================================================================
addr_for_line:
        lda addrlo,x
        sta sptr
        lda addrhi,x
        sta sptr+1
        rts

; ===========================================================================
; set_addr_fault -- X = line index 0..14, sets its bit in w_ablo / w_abhi
; Preserves X.
; ===========================================================================
set_addr_fault:
        cpx #8
        bcs saf_hi
        lda bittab,x
        ora w_ablo
        sta w_ablo
        rts
saf_hi:
        txa
        sec
        sbc #8
        tay
        lda bittab,y
        ora w_abhi
        sta w_abhi
        rts

; ===========================================================================
; Display primitives
; ===========================================================================

; setpos -- A = row, X = column. Sets sptr (screen) and cptr (colour).
; ⚠ Colour RAM is exactly screen + $D400 while the matrix is at $0400, which
; is the only place iteration 1 puts it.
setpos:
        tay
        txa
        clc
        adc rowlo,y
        sta sptr
        sta cptr
        lda rowhi,y
        adc #0
        sta sptr+1
        clc
        adc #$d4
        sta cptr+1
        rts

; putstr -- strp -> zero-terminated screen codes, sptr/cptr set, X = colour
putstr:
        ldy #0
ps_l:   lda (strp),y
        beq ps_end
        sta (sptr),y
        txa
        sta (cptr),y
        iny
        bne ps_l
ps_end: rts

; prstr -- A/Y = string, w_row/w_col = position, w_col2 = colour
prstr:
        sta strp
        sty strp+1
        lda w_row
        ldx w_col
        jsr setpos
        ldx w_col2
        jmp putstr

; phase -- A/Y = string. Clears the phase line, then writes it.
phase:
        pha
        tya
        pha
        lda #<s_blank
        sta strp
        lda #>s_blank
        sta strp+1
        lda #PH_ROW
        ldx #PAN_COL
        jsr setpos
        ldx #C_BLACK
        jsr putstr
        pla
        tay
        pla
        sta strp
        sty strp+1
        lda #PH_ROW
        ldx #PAN_COL
        jsr setpos
        ldx #C_LTGREY
        jmp putstr

; draw_lane -- eight cells, MSB first.
;   w_tmp  = fault mask   (bit 7 is the leftmost cell)
;   w_tmp2 = untested mask
;   A = row, X = column
draw_lane:
        jsr setpos
        ldy #0
dl_loop:
        asl w_tmp2
        bcs dl_unt
        asl w_tmp
        bcs dl_fail
        lda #CH_FULL
        ldx #C_GREEN
        bne dl_put
dl_fail:
        lda #CH_X
        ldx #C_LTRED
        bne dl_put
dl_unt:
        asl w_tmp                       ; keep both masks in step
        lda #CH_DOT
        ldx #C_GREY
dl_put:
        sta (sptr),y
        txa
        sta (cptr),y
        iny
        cpy #8
        bne dl_loop
        rts

; mark_page -- A = page number, X = state 0..3
mark_page:
        stx w_tmp2
        pha
        lsr
        lsr
        lsr
        lsr
        clc
        adc #MAP_ROW
        sta w_row
        pla
        and #$0f
        clc
        adc #MAP_COL
        tax
        lda w_row
        jsr setpos
        ldx w_tmp2
        lda st_char,x
        ldy #0
        sta (sptr),y
        lda st_col,x
        sta (cptr),y
        rts

; ===========================================================================
; Screen construction
; ===========================================================================
clear_screen:
        ldx #0
cs_l:   lda #CH_SPACE
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x
        lda #C_DKGREY
        sta COLRAM,x
        sta COLRAM+$100,x
        sta COLRAM+$200,x
        sta COLRAM+$2e8,x
        inx
        bne cs_l
        rts

draw_chrome:
        lda #0                          ; ⚠ the row label is one RAM byte plus
        sta w_labelz                    ; a terminator -- this is ROM, there is
        lda #C_LTGREY                   ; nothing here to self-modify
        sta w_col2
        lda #0
        sta w_row
        lda #1
        sta w_col
        lda #<s_title
        ldy #>s_title
        jsr prstr

        lda #C_DKGREY
        sta w_col2
        lda #1
        sta w_row
        lda #0
        sta w_col
        lda #<s_rule
        ldy #>s_rule
        jsr prstr
        lda #V_ROW-1
        sta w_row
        lda #<s_rule
        ldy #>s_rule
        jsr prstr

        ; map column header and row labels
        lda #C_GREY
        sta w_col2
        lda #MAP_ROW-1
        sta w_row
        lda #MAP_COL
        sta w_col
        lda #<s_hex
        ldy #>s_hex
        jsr prstr

        ldx #0
dc_rows:
        stx w_tmp
        txa
        clc
        adc #MAP_ROW
        sta w_row
        lda #0
        sta w_col
        lda #C_GREY
        sta w_col2
        ; one-character label from the hex table
        ldx w_tmp
        lda s_hex,x
        sta w_label
        lda #<w_label
        ldy #>w_label
        jsr prstr
        ldx w_tmp
        inx
        cpx #16
        bne dc_rows

        ; right-hand panel labels
        lda #C_GREY
        sta w_col2
        lda #DB_ROW-2
        sta w_row
        lda #PAN_COL
        sta w_col
        lda #<s_data
        ldy #>s_data
        jsr prstr
        lda #DB_ROW-1
        sta w_row
        lda #PAN_COL+1
        sta w_col
        lda #<s_bitno
        ldy #>s_bitno
        jsr prstr

        lda #AH_ROW-2
        sta w_row
        lda #PAN_COL
        sta w_col
        lda #<s_addr
        ldy #>s_addr
        jsr prstr
        lda #AH_ROW-1
        sta w_row
        lda #PAN_COL+1
        sta w_col
        lda #<s_ahno
        ldy #>s_ahno
        jsr prstr
        lda #AL_ROW-1
        sta w_row
        lda #PAN_COL+1
        sta w_col
        lda #<s_alno
        ldy #>s_alno
        jsr prstr

        lda #PH_ROW-1
        sta w_row
        lda #PAN_COL
        sta w_col
        lda #<s_phase
        ldy #>s_phase
        jsr prstr
        rts

; map_init -- all 256 pages untested, then mark what P0b proved
map_init:
        ldx #0
mi_l:   txa
        pha
        ldx #0                          ; state 0 = untested
        jsr mark_page
        pla
        tax
        inx
        bne mi_l
        ldx #$04                        ; P0b proved $0400-$07FF
mi_p0:  txa
        pha
        ldx #2                          ; state 2 = pass
        jsr mark_page
        pla
        tax
        inx
        cpx #$08
        bne mi_p0
        rts

; mark_p2_pages -- mark the pages P2 actually touched, pass or fail.
; ⚠ Only the pages it TOUCHED. P2 samples one byte per address line; it does
; not sweep memory, and the map must not imply that it did.
mark_p2_pages:
        ldx #0
mp_l:   stx w_tmp
        lda p2pages,x
        cmp #$ff
        beq mp_end
        pha
        lda w_ablo
        ora w_abhi
        beq mp_pass
        ldx #3                          ; state 3 = fail
        bne mp_go
mp_pass:
        ldx #2                          ; state 2 = pass
mp_go:  pla
        jsr mark_page
        ldx w_tmp
        inx
        bne mp_l
mp_end: rts

; ===========================================================================
; Data
; ===========================================================================
st_char: !byte CH_DOT,    CH_DASH,  CH_FULL, CH_X
st_col:  !byte C_DKGREY,  C_YELLOW, C_GREEN, C_LTRED

bittab:  !byte 1,2,4,8,16,32,64,128

; Pages P2 writes to: ABASE, and ABASE + 2^n for n = 0..14.
p2pages: !byte $08,$09,$0a,$0c,$10,$18,$28,$48,$ff

addrlo:  !for i, 0, 14 { !byte <(ABASE + (1 << i)) }
addrhi:  !for i, 0, 14 { !byte >(ABASE + (1 << i)) }

rowlo:   !for i, 0, 24 { !byte <(SCREEN + i*40) }
rowhi:   !for i, 0, 24 { !byte >(SCREEN + i*40) }

; ⚠ acme's !scr maps LOWERCASE source to uppercase screen codes, so every
; string here is written lower case on purpose.
s_title:    !scr "dramscope 0.1", 0
s_rule:     !scr "----------------------------------------", 0
s_hex:      !scr "0123456789abcdef", 0
s_data:     !scr "data bus", 0
s_bitno:    !scr "76543210", 0
s_addr:     !scr "address lines", 0
s_ahno:     !scr "fedcba98", 0
s_alno:     !scr "76543210", 0
s_phase:    !scr "phase", 0
s_blank:    !scr "                 ", 0
s_p1:       !scr "p1 data bus", 0
s_p2:       !scr "p2 addr bus", 0
s_pdone:    !scr "done", 0
s_ok:       !scr "bus integrity ok.", 0
s_ok2:      !scr "no march test run - see spec p3/p4.", 0
s_databad:  !scr "data bus fault - see the d lane.", 0
s_databad2: !scr "a marked bit is stuck, shorted or open.", 0
s_addrbad:  !scr "address line fault - see the a lanes.", 0
s_addrbad2: !scr "both of a pair = mux u13/u25 or rp1/rp2.", 0

        !fill $a000 - *, $ff
