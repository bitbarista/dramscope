; ===========================================================================
; DRAMscope -- Commodore 64 memory diagnostic
; SPEC.md iteration 2: EasyFlash delivery, engine relocated to RAM,
; P0 bring-up probe, P1 data bus, P2 address bus (ALL SIXTEEN LINES).
;
; ⚠ PROVENANCE: nothing here derives from any other RAM test. See PROVENANCE.md.
;
; ---------------------------------------------------------------------------
; DELIVERY VEHICLE -- settled on hardware, 2026-09-26
;
; This is an EasyFlash cartridge. It boots in ULTIMAX, so the 6510 takes its
; reset vector straight from cartridge ROMH and runs with NO KERNAL, NO STACK
; and NO ZERO PAGE required. That removes the dependency the iteration 1 build
; had: a normal autostart cartridge needs the KERNAL's JSR $FD02, which pushes
; a return address, so a machine with a dead stack page died BEFORE the test
; could run -- precisely the machine most in need of testing.
;
; Ultimax only maps $0000-$0FFF of RAM, which is the 4 KB ceiling every
; Ultimax tool hits. ⚠ MEASURED ANSWER, Ultimate II+, 2026-09-26: writing $02
; to the EasyFlash control register at $DE02 leaves Ultimax for 8K cartridge
; mode -- ROML stays at $8000-$9FFF and everything else becomes RAM. Found by
; src/g1probe_roml.asm, which sweeps all eight register values rather than
; assuming one, so the number carries no assumption of ours.
;
; ⚠ KUNG FU FLASH IS STILL UNRUN. If $DE02 does nothing, this build says so
; with an ORANGE border rather than hanging. It does not pretend.
;
; ---------------------------------------------------------------------------
; WHY THE ENGINE MOVES TO $C000
;
; No fixed base can reach all sixteen address lines: with the cartridge at
; $8000-$9FFF and ROMs above, base+$8000 always lands on something that is not
; RAM. The fix is to bank everything out with $01 = $30 -- all RAM, no ROMs,
; no I/O, no cartridge -- which is only survivable if the code is in none of
; them. $C000-$CFFF is RAM in every mode, so the engine is proven there and
; copied there before P1/P2 run.
;
; ---------------------------------------------------------------------------
; BORDER CODES -- the display needs working RAM, the border does not.
;
;   white    the cartridge has control    (set by the FIRST instruction)
;   red      FATAL: zero-page scratch $F9-$FE unusable
;   purple   FATAL: screen home page $0400-$07FF unusable
;   orange   FATAL: $DE02 did nothing -- this device cannot leave Ultimax
;   blue     FATAL: $C000-$CFFF unusable, the engine has nowhere to live
;   yellow   P1 data bus running
;   cyan     P2 address bus running
;   green    finished, no fault found
;   lt red   finished, fault found
;
; A BLACK border means the cartridge never got control at all.
;
; ⚠ NO SELF-MODIFYING CODE IN THE ROML HALF. It is cartridge ROM.
; ===========================================================================

; ⚠ BOTH fault builds pass -o, and an unguarded !to here would warn "output
; file name already chosen" on every one of them. A build that prints a
; warning it is expected to ignore is where a real warning goes to hide.
!ifndef INJECT_DB { !ifndef INJECT_AB { !ifndef INJECT_NOEF { !ifndef INJECT_MEM {
        !ifndef INJECT_ALL { !ifndef INJECT_LR {
        !to "build/dramscope_roml.bin", plain } } } } } }

; ---------------------------------------------------------------- hardware
BORDER   = $d020
BGCOL    = $d021
VICCTL1  = $d011
VICMEM   = $d018
CIA2PRA  = $dd00
CIA2DDRA = $dd02
EFCTRL   = $de02                ; EasyFlash control register
EF_8K    = $02                  ; ⚠ MEASURED on Ultimate II+ -- see the header
CPUDDR   = $00
CPUPORT  = $01
BANK_IO  = $37                  ; ROMs + I/O visible
BANK_RAM = $30                  ; ⚠ ALL RAM: no ROMs, no I/O, no cartridge
SCREEN   = $0400
COLRAM   = $d800
ENGINE   = $c000
ENG_PAGES = 12                  ; ⚠ pages copied; the march must skip them

; ------------------------------------------------------------------ colours
C_BLACK  = 0
C_WHITE  = 1
C_RED    = 2
C_CYAN   = 3
C_PURPLE = 4
C_GREEN  = 5
C_BLUE   = 6
C_YELLOW = 7
C_ORANGE = 8
C_LTRED  = 10
C_DKGREY = 11
C_GREY   = 12
C_LTGREY = 15

; ------------------------------------------------------- screen code glyphs
CH_DOT   = $2e                  ; .  untested
CH_DASH  = $2d                  ; -  separator
CH_FULL  = $a0                  ;    pass -- inverse space, a solid cell
CH_X     = $18                  ; X  fail
CH_PLUS  = $2b                  ; +  probed, but NOT marched
CH_SPACE = $20

; ---------------------------------------------------- display geometry
MAP_ROW  = 3
MAP_COL  = 2
PAN_COL  = 21
DB_ROW   = 5                    ; data bus lane   (heading -2, bit numbers -1)
AH_ROW   = 9                    ; address lane A15..A8
AL_ROW   = 11                   ; address lane A7..A0
PH_ROW   = 14
V_ROW    = 21

; ---------------------------------------------------- zero-page scratch
; ⚠ SIX BYTES, PROVEN BEFORE ANYTHING USES THEM (P0a). An engine that needs a
; pointer cannot assume it has one.
mptr     = $f5                  ; march pointer -- walks the run
pval     = $f7                  ; P     for this cell
pinv     = $f8                  ; ~P    for this cell
strp     = $f9
sptr     = $fb
cptr     = $fd
SEED     = $5a

; ---------------------------------------------------- workspace RAM
; ⚠ LIVES IN THE SCREEN PAGE ON PURPOSE. The matrix is 1000 bytes of a 1024
; byte page, so $07E8-$07FF is 24 bytes the VIC never fetches -- and P0b has
; already proven the whole page before any of it is relied on.
WORK     = $07e8
w_dbmask = WORK+0               ; data bus    -- 1 = that bit misbehaved
w_ablo   = WORK+1               ; A7..A0      -- 1 = that line faulty
w_abhi   = WORK+2               ; A15..A8     -- 1 = that line faulty
w_tmp    = WORK+3
w_tmp2   = WORK+4
w_row    = WORK+5
w_col    = WORK+6
w_col2   = WORK+7
w_label  = WORK+8               ; one mutable character, for map row labels
w_labelz = WORK+9               ; its zero terminator
w_endpg  = WORK+10              ; the run being marched
w_startpg= WORK+11
w_runidx = WORK+12
w_bitmask= WORK+13              ; OR of (expected EOR got) -- names the chip
w_errlo  = WORK+14
w_errhi  = WORK+15
w_npg    = WORK+16
w_lastfp = WORK+17              ; last page already painted red
w_tidx   = WORK+18              ; table offset while naming chips
w_slot   = WORK+19
w_chipok = WORK+20              ; 0 = show the bits but name no chip

; P2's base. ⚠ Every base+2^n must be RAM under BANK_RAM, including
; base+$8000 = $8800, which is why the engine had to leave the cartridge.
ABASE    = $0800

; ===========================================================================
; ROML -- mapped at $8000 in BOTH Ultimax and 8K mode, which is what makes it
; the only safe place to stand while switching between them.
; ===========================================================================
* = $8000

entry:
        lda #C_WHITE                    ; ⚠ FIRST INSTRUCTION SETS A COLOUR
        sta BORDER
        lda #C_BLACK
        sta BGCOL
        sei
        cld
        ldx #$ff
        txs                             ; ⚠ no JSR until RAM is proven
        lda #$0b                        ; DEN=0 -- display off through the
        sta VICCTL1                     ;   blind phase, which also sidesteps
                                        ;   the Ultimax VIC $3000 quirk (G4)

; ---------------------------------------------------------------------------
; P0a -- prove the six zero-page scratch bytes. REGISTERS ONLY, no pointer.
; Zero page is visible in Ultimax, so this needs nothing but the CPU.
; ---------------------------------------------------------------------------
        ldx #9                          ; $F5-$FE, ten bytes
p0a_l:
        lda #$55
        sta mptr,x
        cmp mptr,x
        bne p0a_dead
        lda #$aa
        sta mptr,x
        cmp mptr,x
        bne p0a_dead
        txa                             ; address-dependent, so a byte that
        eor #SEED                       ; aliases onto its neighbour fails too
        sta mptr,x
        cmp mptr,x
        bne p0a_dead
        dex
        bpl p0a_l
        jmp p0b

p0a_dead:
        lda #C_RED
        sta BORDER
        jmp rom_halt

; ---------------------------------------------------------------------------
; P0b -- prove the screen home page $0400-$07FF. REGISTERS ONLY.
; absolute,X reaches a whole page with no pointer. Four pages written out
; rather than self-modified, because this is cartridge ROM.
; ---------------------------------------------------------------------------
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
        jmp leave_ultimax

p0b_dead:
        lda #C_PURPLE
        sta BORDER
        jmp rom_halt

; ---------------------------------------------------------------------------
; Leave Ultimax. ⚠ AND CHECK THAT IT WORKED, rather than assuming.
; ---------------------------------------------------------------------------
leave_ultimax:
        lda #EF_8K
        ; ⚠ The mutation SKIPS the store rather than writing a different value.
        ; Writing junk here banks the cartridge out from under the CPU, which
        ; models a destructive device, not an indifferent one. What we need to
        ; prove is the KFF case: the register is simply not there, the machine
        ; stays in Ultimax, and the build must SAY SO instead of hanging.
!ifndef INJECT_NOEF { sta EFCTRL }

        lda #BANK_IO                    ; ⚠ LATCH FIRST, THEN DDR. Writing the
        sta CPUPORT                     ; DDR while the latch still holds its
        lda #$2f                        ; power-on $00 drives mode $30 and
        sta CPUDDR                      ; banks the cartridge out mid-run.

        ; $2000 is unmapped in Ultimax and RAM in 8K mode. That is the test.
        lda #$a5
        sta $2000
        cmp $2000
        bne no_switch
        lda #$5a
        sta $2000
        cmp $2000
        beq p0c

no_switch:
        ; ⚠ This device ignores $DE02. Say so; do not hang pretending to work.
        lda #C_ORANGE
        sta BORDER
        jmp rom_halt

; ---------------------------------------------------------------------------
; P0c -- prove $C000-$CFFF, the engine's new home. REGISTERS ONLY.
; ---------------------------------------------------------------------------
p0c:
        ; ⚠ P0a has already proven the zero page scratch, so unlike P0a/P0b
        ; this may use a pointer -- which is why it can cover all sixteen
        ; pages in a fraction of the code the unrolled version needed.
        lda #>ENGINE
        sta mptr+1
        lda #0
        sta mptr
p0c_pg:
        ldy #0
p0c_w:  tya
        eor mptr+1
        eor #SEED
        sta (mptr),y
        iny
        bne p0c_w
        ldy #0
p0c_v:  tya
        eor mptr+1
        eor #SEED
        cmp (mptr),y
        bne p0c_dead
        iny
        bne p0c_v
        inc mptr+1
        lda mptr+1
        cmp #$d0
        bne p0c_pg

        ; --- copy the engine into proven RAM and go
        lda #<eng_src
        sta sptr
        lda #>eng_src
        sta sptr+1
        lda #0
        sta cptr
        lda #>ENGINE
        sta cptr+1
        ldx #ENG_PAGES
ecopy_pg:
        ldy #0
ecopy_b:
        lda (sptr),y
        sta (cptr),y
        iny
        bne ecopy_b
        inc sptr+1
        inc cptr+1
        dex
        bne ecopy_pg
        jmp ENGINE

p0c_dead:
        lda #C_BLUE
        sta BORDER
rom_halt:
        jmp rom_halt

; ===========================================================================
; The engine. Assembled to run at $C000 and copied there by the bootstrap.
; ===========================================================================
eng_src:
!pseudopc ENGINE {
eng_start:
        jsr clear_screen
        jsr draw_chrome
        jsr map_init
        lda CIA2DDRA
        ora #$03
        sta CIA2DDRA
        lda CIA2PRA
        ora #$03                        ; VIC bank 0
        sta CIA2PRA
        lda #$14                        ; matrix $0400, char ROM $1000
        sta VICMEM
        lda #$1b                        ; DEN=1 -- display on
        sta VICCTL1

; ---------------------------------------------------------------------------
; P1 -- data bus integrity. Walking ones, walking zeroes, both rails, at one
; proven address. Instant, and it runs before any march test: a shorted data
; line makes every later result confusing and should be NAMED in the first
; millisecond rather than inferred from a thousand march failures.
; ---------------------------------------------------------------------------
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

; ---------------------------------------------------------------------------
; P2 -- address bus integrity, ALL SIXTEEN LINES.
;
; Write a distinct value to the base and to base+2^n for every line, then read
; them all back. A line that is stuck, open or shorted makes two addresses
; collide, and WHICH addresses collide says WHICH line.
;
; ⚠ RUNS WITH $01 = $30: ALL RAM, NO ROMS, NO I/O, NO CARTRIDGE. base+$8000 is
; $8800, which is cartridge ROML in normal banking -- iteration 1 could not
; test A15 at all and said so on the display. The engine is at $C000, which is
; RAM in every mode, so it survives the bank-out. ⚠ NOTHING inside the banked
; window may touch $D0xx-$DFxx: the VIC, colour RAM and the border are simply
; not there. Every display update happens after $01 is restored.
; ---------------------------------------------------------------------------
p2:
        lda #C_CYAN
        sta BORDER
        lda #<s_p2
        ldy #>s_p2
        jsr phase
        lda #0
        sta w_ablo
        sta w_abhi

        lda #BANK_RAM                   ; ⚠ I/O IS GONE FROM HERE
        sta CPUPORT

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
        cpx #16
        bne p2_write

        ; The base must still read $00. If it does not, some line aliased onto
        ; it -- and we cannot yet say which, so every line is reported suspect
        ; rather than guessed at.
        lda ABASE
        beq p2_read_all
        lda #$ff
        sta w_ablo
        sta w_abhi
        jmp p2_restore

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
        cpx #16
        bne p2_read

p2_restore:
        lda #BANK_IO                    ; ⚠ I/O BACK BEFORE ANY DISPLAY WORK
        sta CPUPORT

        jsr mark_p2_pages
        lda w_abhi                      ; A15..A8
        sta w_tmp
        lda #$00                        ; ⚠ all sixteen lines are tested now
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


; ---------------------------------------------------------------------------
; P3 -- March B, 17n, with an ADDRESS-DEPENDENT pattern.
;
; van de Goor's March B, five elements, seventeen operations per cell:
;
;   M0  (w P)                                 direction irrelevant
;   M1  ascending  (r P, w ~P, r ~P, w P, r P, w ~P)
;   M2  ascending  (r ~P, w P, w ~P)
;   M3  descending (r ~P, w P, w ~P, w P)
;   M4  descending (r P, w ~P, w P)
;
; ⚠ P IS ADDRESS-DEPENDENT: lo EOR hi EOR SEED, not a fixed 0/1. March B needs
; only two COMPLEMENTARY values, so the substitution preserves the algorithm
; exactly while adding address-decoder coverage a fixed-pattern March B does
; not have -- a read from the WRONG address returns the WRONG value. It is the
; one original piece in this project, carried from the sibling board's own
; diagnostic with its rationale intact. See PROVENANCE.md.
;
; ⚠ THREE REGIONS ARE NOT MARCHED, AND THE MAP LEAVES THEM AS DOTS:
;     $0000-$01FF   zero page and the stack -- the engine uses both
;     $0400-$07FF   the screen matrix and this test's own workspace
;     $C000-$CBFF   the engine itself
; 4,608 bytes of 65,536, so 60,928 are covered. Reaching the rest needs a
; second pass with the engine and display relocated, which is a later
; iteration. ⚠ CLAIMING 64 KB WHILE MARCHING 60,928 IS EXACTLY THE QUIET
; OVER-CLAIM PROVENANCE.md EXISTS TO PREVENT, so the verdict prints the figure.
;
; ⚠ MARCHED PER CONTIGUOUS RUN, not per page, so coupling faults BETWEEN pages
; within a run are covered. The runs are simply what the exclusions leave.
;
; ⚠ THE WHOLE MARCH RUNS WITH $01 = $30 -- all RAM, no ROMs, no I/O, no
; cartridge. march_fail does its own bank dance for the one thing that needs I/O.
; ---------------------------------------------------------------------------
p3:
        lda #C_YELLOW
        sta BORDER
        lda #<s_p3
        ldy #>s_p3
        jsr phase
        lda #0
        sta w_bitmask
        sta w_errlo
        sta w_errhi
        sta w_runidx
        sta w_lastfp                    ; page $00 is never marched, so 0 = none

p3_run:
        ldx w_runidx
        lda runtab,x
        beq p3_done                     ; $00 terminates: no run starts there
        sta w_startpg
        lda runtab+1,x
        sta w_endpg
        jsr mark_run_testing

        lda #BANK_RAM                   ; ⚠ I/O IS GONE FROM HERE
        sta CPUPORT
        jsr m0
        jsr m1
        jsr m2
        jsr m3
        jsr m4
        lda #BANK_IO                    ; ⚠ I/O BACK BEFORE ANY DISPLAY WORK
        sta CPUPORT

        jsr mark_run_done
        lda w_runidx
        clc
        adc #2
        sta w_runidx
        jmp p3_run

p3_done:
        jsr draw_errors
        jmp p4


; ---------------------------------------------------------------------------
; P4 -- March LR, 14n. LINKED FAULTS.
;
;   M0  (w 0)
;   M1  DESCENDING (r 0, w 1)
;   M2  ascending  (r 1, w 0, r 0, w 1)
;   M3  ascending  (r 1, w 0)
;   M4  ascending  (r 0, w 1, r 1, w 0)
;   M5  ascending  (r 0)
;
; A linked fault is two defects close enough that the write exposing one masks
; the other. March B's guarantee does not cover them; March LR is the published
; answer, and at 14n it is CHEAPER than March B's 17n, so this is not a
; trade-off -- both run, for 31n total.
;
; ⚠⚠ FIXED PATTERNS HERE, NOT THE ADDRESS-DEPENDENT ONE, AND THAT IS
; DELIBERATE. Gate G3 asked whether "March B needs only two complementary
; values, so P/~P preserves it" carries over to March LR. It does not. That
; argument is sound for single-cell faults -- stuck-at, transition, decoder --
; but COUPLING faults are detected only when the aggressor transitions WHILE
; THE VICTIM HOLDS A PARTICULAR VALUE. A fixed-pattern march guarantees that
; coincidence by construction, because every cell is in the same state at the
; same point. With P = lo EOR hi EOR SEED they are not: half hold 0 and half
; hold 1 at every step, so whether a given aggressor/victim pair is sensitised
; depends on whether P happens to differ between them. Coverage probably
; survives across elements with opposite resting states -- but "probably" is
; not a proof, and the whole point of March LR is a proof. So P3 keeps the
; address-dependent pattern for the decoder coverage it was introduced for,
; and P4 uses $00/$FF where the published proof holds as written.
; See PROVENANCE.md.
;
; ⚠ The march_fail handler, the bad-byte count and the failing-bit mask are
; shared with P3, so a fault found by either phase names the same chip.
; ---------------------------------------------------------------------------
p4:
        lda #C_YELLOW
        sta BORDER
        lda #<s_p4
        ldy #>s_p4
        jsr phase
        lda #0
        sta w_runidx
p4_run:
        ldx w_runidx
        lda runtab,x
        beq p4_done
        sta w_startpg
        lda runtab+1,x
        sta w_endpg
        jsr mark_run_testing
        lda #BANK_RAM                   ; ⚠ I/O IS GONE FROM HERE
        sta CPUPORT
        jsr lr0
        jsr lr1
        jsr lr2
        jsr lr3
        jsr lr4
        jsr lr5
        lda #BANK_IO
        sta CPUPORT
        jsr mark_run_done
        lda w_runidx
        clc
        adc #2
        sta w_runidx
        jmp p4_run
p4_done:
        jsr draw_errors
        jmp verdict

; --- M0  (w 0) -------------------------------------------------------------
lr0:    jsr set_asc
lr0_pg: ldy #0
        lda #$00
lr0_c:  sta (mptr),y
        iny
        bne lr0_c
        jsr nx_asc
        bne lr0_pg
        rts

; --- M1  DESCENDING (r 0, w 1) ---------------------------------------------
; ⚠ This descending element, immediately after M0, is what makes LR an LR:
; it breaks the single address order that lets one fault mask another.
lr1:    jsr set_desc
lr1_pg: ldy #$ff
lr1_c:  lda (mptr),y
        bne lr1_e1
lr1_k1: lda #$ff
        sta (mptr),y
        dey
        cpy #$ff
        bne lr1_c
        jsr nx_desc
        bne lr1_pg
        rts
lr1_e1: ldx #$00
        jsr march_fail
        jmp lr1_k1

; --- M2  ascending (r 1, w 0, r 0, w 1) ------------------------------------
lr2:    jsr set_asc
lr2_pg: ldy #0
lr2_c:  lda (mptr),y
        cmp #$ff
        bne lr2_e1
lr2_k1: lda #$00
        sta (mptr),y
        lda (mptr),y
        bne lr2_e2
lr2_k2: lda #$ff
        sta (mptr),y
        iny
        bne lr2_c
        jsr nx_asc
        bne lr2_pg
        rts
lr2_e1: ldx #$ff
        jsr march_fail
        jmp lr2_k1
lr2_e2: ldx #$00
        jsr march_fail
        jmp lr2_k2

; --- M3  ascending (r 1, w 0) ----------------------------------------------
lr3:    jsr set_asc
lr3_pg: ldy #0
lr3_c:  lda (mptr),y
        cmp #$ff
        bne lr3_e1
lr3_k1: lda #$00
        sta (mptr),y
        iny
        bne lr3_c
        jsr nx_asc
        bne lr3_pg
        rts
lr3_e1: ldx #$ff
        jsr march_fail
        jmp lr3_k1

; --- M4  ascending (r 0, w 1, r 1, w 0) ------------------------------------
lr4:    jsr set_asc
lr4_pg: ldy #0
lr4_c:  lda (mptr),y
        bne lr4_e1
lr4_k1: lda #$ff
        sta (mptr),y
        lda (mptr),y
        cmp #$ff
        bne lr4_e2
lr4_k2: lda #$00
        sta (mptr),y
        iny
        bne lr4_c
        jsr nx_asc
        bne lr4_pg
        rts
lr4_e1: ldx #$00
        jsr march_fail
        jmp lr4_k1
lr4_e2: ldx #$ff
        jsr march_fail
        jmp lr4_k2

; --- M5  ascending (r 0) ---------------------------------------------------
lr5:    jsr set_asc
lr5_pg: ldy #0
lr5_c:  lda (mptr),y
!ifdef INJECT_LR {                      ; mutation: P4 must be able to fail too
        cpy #$12
        bne inj_l_out
        pha
        lda mptr+1
        cmp #$50
        bne inj_l_pop
        pla
        eor #$80
        jmp inj_l_out
inj_l_pop:
        pla
inj_l_out:
}
        bne lr5_e1
lr5_k1: iny
        bne lr5_c
        jsr nx_asc
        bne lr5_pg
        rts
lr5_e1: ldx #$00
        jsr march_fail
        jmp lr5_k1

; --- run setup -------------------------------------------------------------
set_asc:
        lda w_startpg
        sta mptr+1
        lda #0
        sta mptr
        jmp calc_npg
set_desc:
        lda w_endpg
        sta mptr+1
        lda #0
        sta mptr
calc_npg:
        lda w_endpg
        sec
        sbc w_startpg
        clc
        adc #1
        sta w_npg                       ; ⚠ a 256-page run wraps this to 0,
        rts                             ; which the dec-then-test loops below
                                        ; correctly read as 256.
nx_asc:
        inc mptr+1
        dec w_npg
        rts                             ; Z set when the run is finished
nx_desc:
        dec mptr+1
        dec w_npg
        rts

; --- M0  (w P) -------------------------------------------------------------
m0:     jsr set_asc
m0_pg:  ldy #0
m0_c:   tya
        eor mptr+1
        eor #SEED
        sta (mptr),y
        iny
        bne m0_c
        jsr nx_asc
        bne m0_pg
        rts

; --- M1  ascending (r P, w ~P, r ~P, w P, r P, w ~P) -----------------------
m1:     jsr set_asc
m1_pg:  ldy #0
m1_c:   tya
        eor mptr+1
        eor #SEED
        sta pval
        eor #$ff
        sta pinv
        lda (mptr),y
!ifdef INJECT_MEM {                     ; mutation: one stuck bit at $4037
        cpy #$37
        bne inj_m_out
        pha
        lda mptr+1
        cmp #$40
        bne inj_m_pop
        pla
        eor #$01
        jmp inj_m_out
inj_m_pop:
        pla
inj_m_out:
}
!ifdef INJECT_ALL {                     ; mutation: ALL EIGHT bits wrong.
        cpy #$37                        ; ⚠ This must make the tool REFUSE to
        bne inj_a_out                   ; name a chip. Eight simultaneously
        pha                             ; dead DRAMs is not the likely reading,
        lda mptr+1                      ; and pointing at eight chips is worse
        cmp #$40                        ; than pointing at none.
        bne inj_a_pop
        pla
        eor #$ff
        jmp inj_a_out
inj_a_pop:
        pla
inj_a_out:
}
        cmp pval
        bne m1_e1
m1_k1:  lda pinv
        sta (mptr),y
        lda (mptr),y
        cmp pinv
        bne m1_e2
m1_k2:  lda pval
        sta (mptr),y
        lda (mptr),y
        cmp pval
        bne m1_e3
m1_k3:  lda pinv
        sta (mptr),y
        iny
        bne m1_c
        jsr nx_asc
        bne m1_pg
        rts
m1_e1:  ldx pval
        jsr march_fail
        jmp m1_k1
m1_e2:  ldx pinv
        jsr march_fail
        jmp m1_k2
m1_e3:  ldx pval
        jsr march_fail
        jmp m1_k3

; --- M2  ascending (r ~P, w P, w ~P) ---------------------------------------
m2:     jsr set_asc
m2_pg:  ldy #0
m2_c:   tya
        eor mptr+1
        eor #SEED
        sta pval
        eor #$ff
        sta pinv
        lda (mptr),y
        cmp pinv
        bne m2_e1
m2_k1:  lda pval
        sta (mptr),y
        lda pinv
        sta (mptr),y
        iny
        bne m2_c
        jsr nx_asc
        bne m2_pg
        rts
m2_e1:  ldx pinv
        jsr march_fail
        jmp m2_k1

; --- M3  descending (r ~P, w P, w ~P, w P) ---------------------------------
m3:     jsr set_desc
m3_pg:  ldy #$ff
m3_c:   tya
        eor mptr+1
        eor #SEED
        sta pval
        eor #$ff
        sta pinv
        lda (mptr),y
        cmp pinv
        bne m3_e1
m3_k1:  lda pval
        sta (mptr),y
        lda pinv
        sta (mptr),y
        lda pval
        sta (mptr),y
        dey
        cpy #$ff                        ; dey from $00 wraps to $ff: 256 cells
        bne m3_c
        jsr nx_desc
        bne m3_pg
        rts
m3_e1:  ldx pinv
        jsr march_fail
        jmp m3_k1

; --- M4  descending (r P, w ~P, w P) ---------------------------------------
m4:     jsr set_desc
m4_pg:  ldy #$ff
m4_c:   tya
        eor mptr+1
        eor #SEED
        sta pval
        eor #$ff
        sta pinv
        lda (mptr),y
        cmp pval
        bne m4_e1
m4_k1:  lda pinv
        sta (mptr),y
        lda pval
        sta (mptr),y
        dey
        cpy #$ff
        bne m4_c
        jsr nx_desc
        bne m4_pg
        rts
m4_e1:  ldx pval
        jsr march_fail
        jmp m4_k1

; ---------------------------------------------------------------------------
; march_fail -- X = expected, A = got.
; ⚠ PRESERVES Y AND mptr, because it is called from the middle of a march
; element that is still walking a page. mark_page clobbers Y, hence the save.
; ⚠ Called from inside the banked window, so it banks I/O back in around the
; one thing that needs it.
; ---------------------------------------------------------------------------
march_fail:
        sta w_tmp2                      ; got
        stx w_tmp                       ; expected
        tya
        pha
        lda w_tmp
        eor w_tmp2                      ; WHICH BITS differ -- this is what
        ora w_bitmask                   ; names the chip, later
        sta w_bitmask
        inc w_errlo
        bne mf_1
        inc w_errhi
mf_1:
        ; ⚠ Paint a page red only the FIRST time it fails. A page with 256 bad
        ; bytes must not repaint its cell 256 times.
        lda mptr+1
        cmp w_lastfp
        beq mf_out
        sta w_lastfp
        lda #BANK_IO
        sta CPUPORT
        lda mptr+1
        ldx #3                          ; fail
        jsr mark_page
        lda #BANK_RAM
        sta CPUPORT
mf_out:
        pla
        tay
        rts

; --- map painting for a whole run ------------------------------------------
; ⚠ SKIPS CELLS ALREADY MARKED X, and that is not cosmetic. P4 runs over the
; same pages P3 did, so without this its "now testing" repaint erased every
; fault P3 had found -- and the tidy-up pass then painted the cell green,
; because it was no longer an X to skip. A page that failed stays failed.
mark_run_testing:
        lda w_startpg
        sta w_tmp
mrt_l:  lda w_tmp
        jsr cell_pos
        ldy #0
        lda (sptr),y
        cmp #CH_X
        beq mrt_skip
        lda w_tmp
        ldx #1                          ; testing
        jsr mark_page
mrt_skip:
        lda w_tmp
        cmp w_endpg
        beq mrt_x
        inc w_tmp
        jmp mrt_l
mrt_x:  rts

; ⚠ Green UNLESS the cell is already an X. A page that failed mid-run must not
; be painted over by the tidy-up pass that follows it.
mark_run_done:
        lda w_startpg
        sta w_tmp
mrd_l:  lda w_tmp
        jsr cell_pos
        ldy #0
        lda (sptr),y
        cmp #CH_X
        beq mrd_skip
        lda w_tmp
        ldx #2                          ; pass
        jsr mark_page
mrd_skip:
        lda w_tmp
        cmp w_endpg
        beq mrd_x
        inc w_tmp
        jmp mrd_l
mrd_x:  rts


; ---------------------------------------------------------------------------
; draw_diag -- name the failing bits, and the chips that carry them.
; Caller puts the failing-bit mask in w_tmp.
;
; ⚠ THIS IS THE ONE OUTPUT THAT IS A CLAIM ABOUT SOMEONE ELSE'S HARDWARE.
; "Replace U10" costs them a chip, an hour, and their trust in every other
; line on the screen if it is wrong. So:
;
;   * the designators are printed UNDER a heading that names the assembly
;     they belong to, because 250425 and the short boards differ and this
;     tool cannot tell which board it is plugged into;
;   * the BIT number is always shown, and is true on every C64;
;   * ⚠ if EVERY bit failed, no chip is named at all -- eight simultaneous
;     dead DRAMs is not the likely reading, and pointing at eight chips
;     would be worse than pointing at none. See rule 4 in SPEC.md §5.
;
; Source for the mapping: Commodore schematic 251138, via c64-ice40-ram
; README §2.2, which places the RAMs in bus order U12, U24, U11, U23, U10,
; U22, U9, U21 against D7..D0. Recorded in PROVENANCE.md.
; ---------------------------------------------------------------------------
draw_diag:
        lda #C_LTRED
        sta w_col2
        lda #V_ROW+1
        sta w_row
        lda #1
        sta w_col
        lda #<s_bits
        ldy #>s_bits
        jsr prstr

        lda #C_YELLOW
        sta w_col2
        lda #V_ROW+2
        sta w_row
        lda #1
        sta w_col
        lda w_tmp
        cmp #$ff                        ; ⚠ every bit -- name no chip
        beq dg_allbits
        lda #1
        sta w_chipok
        lda #<s_assy
        ldy #>s_assy
        jsr prstr
        jmp dg_slots

dg_allbits:
        ; ⚠ The BIT list is still drawn -- it is true on every C64 and it is
        ; what the reader needs. Only the designators are withheld.
        lda #0
        sta w_chipok
        lda #<s_allbits
        ldy #>s_allbits
        jsr prstr

dg_slots:
        lda #0
        sta w_slot
dg_slot:
        asl w_tmp                       ; MSB first, so slot 0 is D7
        bcc dg_next

        lda #7                          ; bit number = 7 - slot
        sec
        sbc w_slot
        asl
        asl                             ; x4, four bytes per table entry
        sta w_tidx
        lda w_slot                      ; column = 8 + slot*4
        asl
        asl
        clc
        adc #8
        sta w_col

        lda #V_ROW+1
        ldx w_col
        jsr setpos
        ldx w_tidx
        ldy #0
dg_c1:  lda bitlbl,x
        sta (sptr),y
        lda #C_LTRED
        sta (cptr),y
        inx
        iny
        cpy #4
        bne dg_c1

        lda w_chipok
        beq dg_next
        lda #V_ROW+2
        ldx w_col
        jsr setpos
        ldx w_tidx
        ldy #0
dg_c2:  lda chips407,x
        sta (sptr),y
        lda #C_YELLOW
        sta (cptr),y
        inx
        iny
        cpy #4
        bne dg_c2

dg_next:
        inc w_slot
        lda w_slot
        cmp #8
        bne dg_slot
        rts

; --- error count ------------------------------------------------------------
draw_errors:
        lda #C_GREY
        sta w_col2
        lda #PH_ROW+2
        sta w_row
        lda #PAN_COL
        sta w_col
        lda #<s_errors
        ldy #>s_errors
        jsr prstr
        lda #PH_ROW+3
        ldx #PAN_COL+1
        jsr setpos
        ldy #0
        lda w_errhi
        jsr hexpair
        lda w_errlo
        jsr hexpair
        rts

; hexpair -- A = byte, Y = offset from sptr; writes two screen codes
hexpair:
        pha
        lsr
        lsr
        lsr
        lsr
        tax
        lda s_hex,x
        sta (sptr),y
        lda #C_LTGREY
        sta (cptr),y
        iny
        pla
        and #$0f
        tax
        lda s_hex,x
        sta (sptr),y
        lda #C_LTGREY
        sta (cptr),y
        iny
        rts

; ---------------------------------------------------------------------------
; Verdict
; ---------------------------------------------------------------------------
verdict:
        lda #<s_pdone
        ldy #>s_pdone
        jsr phase
        lda w_dbmask
        bne v_data
        lda w_ablo
        ora w_abhi
        bne v_addr
        lda w_errlo
        ora w_errhi
        bne v_mem
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

v_mem:
        lda #C_LTRED
        sta BORDER
        lda #C_LTRED
        sta w_col2
        lda #<s_membad
        ldy #>s_membad
        jsr verdict_line
        lda w_bitmask                   ; ⚠ no second verdict line here: the
        sta w_tmp                       ; bit and chip lines are rows 22 and 23
        jsr draw_diag                   ; and say more than a sentence would
        jmp halt

v_data:
        lda #C_LTRED
        sta BORDER
        lda #C_LTRED
        sta w_col2
        lda #<s_databad
        ldy #>s_databad
        jsr verdict_line
        lda w_dbmask
        sta w_tmp
        jsr draw_diag
        jmp halt

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
        jsr verdict_line2_nohalt
        jmp halt
verdict_line2_nohalt:
        sta strp
        sty strp+1
        lda #V_ROW+1
        ldx #1
        jsr setpos
        ldx w_col2
        jmp putstr

; ---------------------------------------------------------------------------
; addr_for_line -- X = line index 0..15, sets sptr = ABASE + (1 << X)
; Table-driven. Preserves X, clobbers A.
; ---------------------------------------------------------------------------
addr_for_line:
        lda addrlo,x
        sta sptr
        lda addrhi,x
        sta sptr+1
        rts

; ---------------------------------------------------------------------------
; set_addr_fault -- X = line index 0..15, sets its bit in w_ablo / w_abhi
; Preserves X.
; ---------------------------------------------------------------------------
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

; ---------------------------------------------------------------------------
; Display primitives
; ---------------------------------------------------------------------------

; setpos -- A = row, X = column. Sets sptr (screen) and cptr (colour).
; ⚠ Colour RAM is exactly screen + $D400 while the matrix is at $0400.
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
;   w_tmp  = fault mask (bit 7 is the leftmost cell), w_tmp2 = untested mask
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

; cell_pos -- A = page number -> sptr/cptr point at that page's map cell
cell_pos:
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
        jmp setpos

; mark_page -- A = page number, X = state 0..3
mark_page:
        stx w_tmp2
        jsr cell_pos
        ldx w_tmp2
        lda st_char,x
        ldy #0
        sta (sptr),y
        lda st_col,x
        sta (cptr),y
        rts

; ---------------------------------------------------------------------------
; Screen construction
; ---------------------------------------------------------------------------
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
        lda #0                          ; the row label is one RAM byte plus
        sta w_labelz                    ; a terminator
        lda #C_LTGREY
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

        lda #C_DKGREY                   ; legend -- the glyphs must not be a
        sta w_col2                      ; private language
        lda #V_ROW+3
        sta w_row
        lda #1
        sta w_col
        lda #<s_legend
        ldy #>s_legend
        jsr prstr
        rts

; map_init -- all 256 pages untested, then mark what P0 proved
map_init:
        ldx #0
mi_l:   txa
        pha
        ldx #0
        jsr mark_page
        pla
        tax
        inx
        bne mi_l
        ldx #$04                        ; P0b probed $0400-$07FF
mi_p0:  txa
        pha
        ldx #4                          ; probed, not marched
        jsr mark_page
        pla
        tax
        inx
        cpx #$08
        bne mi_p0
        ldx #$c0                        ; P0c probed $C000-$CFFF
mi_p0c: txa
        pha
        ldx #4                          ; probed, not marched
        jsr mark_page
        pla
        tax
        inx
        cpx #$d0
        bne mi_p0c
        rts

; mark_p2_pages -- mark the pages P2 actually touched.
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
        ldx #3
        bne mp_go
mp_pass:
        ldx #2
mp_go:  pla
        jsr mark_page
        ldx w_tmp
        inx
        bne mp_l
mp_end: rts

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
; ⚠ STATE 4 EXISTS SO THE MAP CANNOT OVER-CLAIM. P0b and P0c prove their
; regions with a single address-dependent write/verify pass -- a real test,
; but not 17n March B. Painting them the same solid green as a marched page
; would tell the reader those bytes got the full algorithm when they did not.
; '+' means probed; a solid cell means marched.
st_char: !byte CH_DOT,    CH_DASH,  CH_FULL, CH_X,    CH_PLUS
st_col:  !byte C_DKGREY,  C_YELLOW, C_GREEN, C_LTRED, C_CYAN
bittab:  !byte 1,2,4,8,16,32,64,128

; Pages P2 writes to: ABASE, and ABASE + 2^n for n = 0..15.
p2pages: !byte $08,$09,$0a,$0c,$10,$18,$28,$48,$88,$ff

; ⚠ The contiguous runs P3 marches, as start/end page pairs, $00 terminating.
; What is NOT here is the point: $00-$01 zero page and stack, $04-$07 screen
; and workspace, $C0-$CB the engine. 238 pages, 60,928 bytes of 65,536.
runtab:  !byte $02,$03
         !byte $08,$bf
         !byte $cc,$ff
         !byte $00

addrlo:  !for i, 0, 15 { !byte <(ABASE + (1 << i)) }
addrhi:  !for i, 0, 15 { !byte >(ABASE + (1 << i)) }
rowlo:   !for i, 0, 24 { !byte <(SCREEN + i*40) }
rowhi:   !for i, 0, 24 { !byte >(SCREEN + i*40) }

; ⚠ acme's !scr maps LOWERCASE source to uppercase screen codes, so every
; string here is written lower case on purpose.
s_title:    !scr "dramscope 0.4", 0
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
s_p3:       !scr "p3 march b", 0
s_p4:       !scr "p4 march lr", 0
s_errors:   !scr "bad bytes", 0
s_legend:   !scr "solid=marched  +=probed  .=untested", 0

; ⚠ Four bytes per entry, space padded, indexed by bit*4. The designators are
; Assy 250407 ONLY -- schematic 251138, via c64-ice40-ram README §2.2.
bitlbl:     !scr "d0  d1  d2  d3  d4  d5  d6  d7  "
chips407:   !scr "u21 u9  u22 u10 u23 u11 u24 u12 ", 0
s_pdone:    !scr "done", 0
s_ok:       !scr "bus integrity ok, all 16 lines.", 0
s_ok2:      !scr "march b + lr, 31n, 60,928 of 65,536.", 0
s_databad:  !scr "data bus fault - see the d lane.", 0
s_databad2: !scr "a marked bit is stuck, shorted or open.", 0
s_addrbad:  !scr "address line fault - see the a lanes.", 0
s_addrbad2: !scr "both of a pair = mux u13/u25 or rp1/rp2.", 0
s_membad:   !scr "memory fault - see the red cells.", 0
s_membad2:  !scr "march b + march lr, 31n.", 0
s_bits:     !scr "bits", 0
s_assy:     !scr "250407", 0
s_allbits:  !scr "all 8 bits - not one chip. check pla.", 0

eng_end:
}

; ⚠ The bootstrap copies exactly eight pages. If the engine outgrows them it
; would be copied half-way and jumped into, which is not a failure mode worth
; discovering on someone else's hardware.
!if eng_end - eng_start > ENG_PAGES * $100 {
        !error "engine does not fit in the pages the bootstrap copies"
}

        !fill $a000 - *, $ff
