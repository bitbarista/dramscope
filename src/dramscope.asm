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
;   red      FATAL: the zero-page scratch $F5-$FE will not hold a value, but
;            SOMETHING in $0000-$0FFF does -- so memory is fitted and a chip
;            is faulty
;   red, slowly flashing on and off
;            FATAL: NOTHING in $0000-$0FFF holds a value. No RAM fitted, or
;            CASRAM/the PLA is not selecting it. There is no chip to find
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
        !ifndef INJECT_ALL { !ifndef INJECT_LR { !ifndef INJECT_TOPO {
        !ifndef INJECT_ZP { !ifndef INJECT_HV { !ifndef INJECT_RET {
        !ifndef INJECT_COL { !ifndef INJECT_ONCE {
        !ifndef INJECT_P0A { !ifndef INJECT_NORAM {
        !to "build/dramscope_roml.bin", plain } } } } } } } } } } } } } }

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
ENG_PAGES = 16                  ; ⚠ the engine now fills $C000-$CFFF exactly                  ; ⚠ pages copied; the march must skip them

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
CH_STAR  = $2a                  ; *  marched, but at 9n not 31n + topo
CH_SPACE = $20

; ---------------------------------------------------- display geometry
MAP_ROW  = 3
MAP_COL  = 2
; ⚠ THE PANEL IS A CHECKLIST. Carl, 2026-09-26: "it's not particularly obvious
; what tests have run and their status." It was not -- the panel showed the two
; bus lanes and the word DONE, so nothing on screen said whether March B,
; March LR, the topographical passes, zero page, the handover, the dwell or
; the colour RAM had run at all, let alone whether each had passed. Every
; phase now has a named row and a status cell: '..' not yet, a turning spinner
; while it runs, OK or X when it finishes.
PAN_COL  = 19
STAT_COL = 32
DB_ROW   = 5                    ; data bus lane   (heading -2, bit numbers -1)
AH_ROW   = 8                    ; address lane A15..A8
AL_ROW   = 10                   ; address lane A7..A0
V_ROW    = 21
NPHASE   = 9


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
RASTER   = $d012
CIA2_TAL = $dd04                ; ⚠ the flash-rate time base -- see tick
CIA2_TBL = $dd06
CIA2_CRA = $dd0e
CIA2_CRB = $dd0f
DWELL    = 10                   ; units of 60 frames -- see P7
FRAMES   = 60                   ; ⚠ 60, not 50, so "at least N seconds" is
                                ; true on PAL (1.2 s/unit) and NTSC (1.0)

; ---------------------------------------------------- workspace RAM
; ⚠⚠ MOVED OUT OF THE SCREEN PAGE, AND THE MOVE IS LOAD-BEARING.
; It used to live in the 24 bytes at $07E8 that the VIC never fetches, which
; was neat until P5 needed five more fields and three were left. The two that
; overflowed landed on $0800 and $0801 -- the first two bytes of the region P5
; MARCHES -- so the phase overwrote its own w_hpar and w_pmode on its first
; write and then failed 40,961 cells against patterns it had corrupted itself.
; It now sits just above the engine, inside the region P0c proves and every
; march already excludes: still verified before use, still never marched, and
; no longer able to run out of room silently.
; ⚠⚠ THE WORKSPACE MUST BE RAM IN *EVERY* BANKING MODE, and that rules out
; most of memory. The engine outgrew fifteen pages when P7 landed and now
; fills $C000-$CFFF exactly, so $CF00 was no longer free. The obvious next
; choice, $BF00, IS BASIC ROM whenever I/O is banked in -- writes went to the
; RAM underneath and every read came back out of BASIC, so the dwell counter
; never decremented and the cartridge hung. $0300 is plain RAM under $37, $30
; and Ultimax alike. It is excluded from the run table and marched by the
; handover, like every other region the test has to stand on.
WORK     = $0300
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
w_patt   = WORK+21              ; P5 pattern index
w_pflags = WORK+22              ; bit0 use lo, bit1 use hi, bit2 invert
w_lomask = WORK+23
w_hpar   = WORK+24              ; the pattern's per-page constant half
w_pmode  = WORK+25              ; 0 = write pass, 1 = verify pass
w_tick   = WORK+26              ; liveness counter, one per page processed
w_phcol  = WORK+27              ; this phase's border colour, for the pulse
w_p6start= WORK+28              ; first index P6 may touch in the current page
w_p6seed = WORK+29              ; P for this page, and its complement
w_p6inv  = WORK+30
w_p6bad  = WORK+31
w_hvscr  = WORK+32              ; handover: screen region failed
w_hveng  = WORK+33              ; handover: engine region failed
w_dwell  = WORK+34              ; P7 countdown, in units
w_frames = WORK+35
w_passlo = WORK+36              ; completed passes, for the burn-in
w_passhi = WORK+37
w_colbad = WORK+38              ; colour RAM failed -- a SEPARATE chip
w_phidx  = WORK+39              ; which phase is running
w_snaplo = WORK+40              ; error count when it started
w_snaphi = WORK+41
w_phextra= WORK+42              ; a phase's own verdict, beyond the error count
w_faddr  = WORK+45              ; ⚠ WHERE the first bad byte was
w_dmask  = WORK+47              ; ⚠ draw_diag's mask, kept because the slot
                                ; loop destroys w_tmp with asl
w_dlo    = WORK+48              ; dec16's working value
w_dhi    = WORK+49
w_nz     = WORK+50              ; a non-zero digit has been emitted
w_phfail = WORK+43              ; ⚠ one bit per phase: has it EVER failed?
                                ; (two bytes, nine phases)

; P2's base. ⚠ Every base+2^n must be RAM under BANK_RAM, including
; base+$8000 = $8800, which is why the engine had to leave the cartridge.
ABASE    = $0800

; ---------------------------------------------------- handover scratch
; ⚠ All inside $08-$BF, which P3/P4/P5 have already marched by the time any of
; it is used. The handover phase is the last thing to run for that reason.
HV_SCR   = $2000                ; 1024 bytes, the screen matrix stashed
HV_COL   = $2400                ; 1024 bytes, its colour
HV_WRK   = $2800                ; 64 bytes, the workspace stashed
HV_CODE  = $3000                ; the handover module itself
HV_PAGES = 5

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
        ; ⚠ THE MUTATION CORRUPTS A, NOT THE MEMORY. Skipping the store would
        ; leave the comparison reading whatever VICE happened to power up with,
        ; and if that were $55 the probe would PASS and the mutation would test
        ; nothing. Flipping A makes the mismatch certain whatever the RAM holds.
!ifdef INJECT_P0A { eor #$ff }
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

; ---------------------------------------------------------------------------
; ⚠ P0a FAILED -- AND "the scratch will not hold a value" HAS TWO CAUSES THAT
; CALL FOR COMPLETELY DIFFERENT WORK:
;
;   * a bad byte in the scratch range  -> memory IS fitted, one chip is faulty
;   * nothing fitted at all, or CASRAM/PLA not selecting -> there is no chip
;     to find, and the sockets or the PLA are the place to look
;
; Both used to report the same steady red screen, which sends someone hunting
; for a faulty chip on a machine that has none in it. ⚠ Drawing the distinction
; only became worth doing once the no-RAM case was measured on hardware
; (SPEC.md G6): with every DRAM out, a Kung Fu Flash boots the cartridge and
; P0a correctly refuses -- so this path is genuinely reached by real machines.
;
; ⚠ REGISTERS ONLY, AND NO POINTER, WHICH IS WHY IT IS UNROLLED. The scratch
; has just failed, so zero page is unusable BY DEFINITION -- that rules out
; (mptr),y and therefore any loop over pages. Sixteen unrolled probes is the
; price of asking the question; ROML has ~2.5 KB spare while the engine has 16.
;
; ⚠ OFFSET $80 IN EVERY PAGE, AND NEVER $0000 OR $0001. Those two are the CPU's
; data-direction register and banking latch, not RAM. Writing a test pattern to
; them would change the memory map underneath this very code.
;
; ⚠ IN ULTIMAX $0000-$0FFF IS THE ONLY RAM THERE IS. $1000-$7FFF is unmapped,
; so there is nowhere else to ask. That is a limit of the question, not a gap:
; on both long and short boards every chip serves every page, so a machine with
; memory fitted answers on all sixteen and a machine without answers on none.
; ---------------------------------------------------------------------------
!macro PROBEPAGE .a {
        lda #$55
        sta .a
!ifdef INJECT_NORAM { eor #$ff }
        cmp .a
        bne .no
        lda #$aa                ; ⚠ two complementary patterns, so a data line
        sta .a                  ; stuck high or low cannot fake a response
!ifdef INJECT_NORAM { eor #$ff }
        cmp .a
        bne .no
        jmp p0a_scratch         ; this page holds what it was given
.no:
}

p0a_dead:
        +PROBEPAGE $0080
        +PROBEPAGE $0180
        +PROBEPAGE $0280
        +PROBEPAGE $0380
        +PROBEPAGE $0480
        +PROBEPAGE $0580
        +PROBEPAGE $0680
        +PROBEPAGE $0780
        +PROBEPAGE $0880
        +PROBEPAGE $0980
        +PROBEPAGE $0a80
        +PROBEPAGE $0b80
        +PROBEPAGE $0c80
        +PROBEPAGE $0d80
        +PROBEPAGE $0e80
        +PROBEPAGE $0f80
        jmp p0a_noram           ; nothing, anywhere, in the only RAM we can see

; ---- verdict: memory IS fitted, but the scratch bytes are bad --------------
p0a_scratch:
        lda #C_RED
        sta BORDER
        jmp rom_halt

; ---------------------------------------------------------------------------
; ---- verdict: nothing responds anywhere -----------------------------------
;
; ⚠ A SLOW ALTERNATION, NOT A NEW COLOUR. Every steady colour is already spoken
; for and two of them double as running-phase colours, so another one would add
; an ambiguity rather than remove one. Red going on and off cannot be mistaken
; for any steady colour, and cannot be mistaken for a steady black "never got
; control" either, because it changes.
;
; ⚠ THE FLASH-RATE ARGUMENT IS MADE AGAIN HERE, BECAUSE THIS ONE FILLS THE
; SCREEN. DEN is 0, so there is no display and the whole frame is border --
; exactly the large-area case WCAG 2.3.1 is strictest about. 45 frames per
; colour is 0.9 s on PAL and 0.75 s on NTSC, so a full cycle is 1.8 s / 1.5 s:
; 0.56 Hz PAL, 0.67 Hz NTSC against the three-per-second limit. That is a 5.4x
; margin, wider than the 3.2x the running pulse has, and wider on purpose
; because of the area.
;
; ⚠ TIMED FROM THE RASTER, NOT FROM A CYCLE COUNT. The CIA timer chain the
; running pulse uses is set up by the engine, and on this machine the engine
; has not run and never will. Raster line $80 exists on PAL and on NTSC, and
; this is the same frame-counting idiom p7 uses -- one rule for the flash rate,
; not two.
; ---------------------------------------------------------------------------
NR_FRAMES = 45

p0a_noram:
        ldy #C_RED
nr_flip:
        sty BORDER
        ldx #NR_FRAMES
nr_frame:
        lda RASTER              ; wait for the raster to reach line $80
        cmp #$80
        bne nr_frame
nr_left:
        lda RASTER              ; and then to leave it -- that is one frame
        cmp #$80
        beq nr_left
        dex
        bne nr_frame
nr_toggle:                      ; ⚠ THE HARNESS BREAKS HERE. BORDER still holds
        tya                     ; the colour just shown for a whole interval, so
        eor #C_RED              ; one break per interval samples the alternation.
        tay                     ; ⚠ EOR toggles RED<->BLACK only because
        jmp nr_flip             ; C_BLACK is 0; this is not a general toggle.

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
        ; ⚠ Two ranges: the workspace page, which is relied on the moment the
        ; engine starts, and the engine's own home. They are not adjacent.
        ; ⚠⚠ THE STOP PAGE GOES IN ZERO PAGE, NOT INTO THE INSTRUCTION.
        ; This routine runs from CARTRIDGE ROM, where a store to its own
        ; operand does nothing at all -- the first version did exactly that,
        ; so the comparison kept its assembled value of $00 and the probe ran
        ; from $03 all the way round through the I/O page to $00, writing
        ; test patterns over the entire machine. P0a has already proven the
        ; zero page scratch, so pval is available and costs nothing.
        lda #>WORK
        sta mptr+1
        lda #(>WORK)+1
        sta pval
        jsr p0c_range
        lda #>ENGINE
        sta mptr+1
        lda #$d0
        sta pval
        jsr p0c_range
        jmp p0c_copy

p0c_range:
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
        cmp pval
        bne p0c_pg
        rts

p0c_copy:

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
        ; ⚠ The flash-rate time base. CIA2 timer A free-runs on phi2 and
        ; timer B counts its underflows, so B's low byte steps about every
        ; 66 ms on PAL and 61 ms on NTSC -- a clock that does not care how
        ; fast the test is running. Nothing else uses these timers and no
        ; interrupt is enabled for them.
        lda #$ff
        sta CIA2_TAL
        sta CIA2_TAL+1
        sta CIA2_TBL
        sta CIA2_TBL+1
        lda #$11                        ; TA: load, start, continuous, phi2
        sta CIA2_CRA
        lda #$51                        ; TB: load, start, count TA underflows
        sta CIA2_CRB

        ; ⚠ EVERY CUMULATIVE COUNTER IS CLEARED HERE, ONCE, AND NOWHERE ELSE.
        ; Each phase used to zero its own results on entry, which was right
        ; for a single run and wrong the moment the burn-in looped: pass two
        ; wiped pass one's findings and the totals never grew past what the
        ; last pass happened to see. The workspace starts full of P0c's probe
        ; pattern, so these are garbage until cleared.
        lda #0
        sta w_phfail
        sta w_phfail+1
        sta w_dbmask
        sta w_ablo
        sta w_abhi
        sta w_bitmask
        sta w_errlo
        sta w_errhi
        sta w_passlo
        sta w_passhi
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
        sta w_phcol
        lda #0
        jsr ph_begin

        lda #$01                        ; walking ones
        sta w_tmp
p1_one:
        lda w_tmp
        sta ABASE
        lda ABASE
; ⚠ P1 and P2 keep inline injections: neither reads through (mptr),y, so the
; hook's page/offset contract does not apply to them. Both are single
; instructions with no flag dependency after them.
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
        lda w_dbmask                    ; P1's verdict is its mask, not a count
        sta w_phextra
        jsr ph_end

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
        sta w_phcol
        lda #1
        jsr ph_begin

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
        lda w_ablo                      ; P2's verdict is its masks
        ora w_abhi
        sta w_phextra
        jsr ph_end


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
;     $C000-$CFFF   the engine, and the workspace just above it
; ⚠ 23 pages = 5,888 bytes are excluded, so 233 pages = 59,648 bytes are
; marched here. THESE FIGURES ARE ENFORCED at assembly time against runtab --
; see the !error guards by s_ok2. Three different wrong numbers (59,904, 60,928,
; 5,632) were in the comments and docs at once, all of them predating the
; engine growing from 12 pages to 16. Reaching the rest needs a
; second pass with the engine and display relocated, which is a later
; iteration. ⚠ CLAIMING 64 KB WHILE MARCHING 59,648 IS EXACTLY THE QUIET
; OVER-CLAIM PROVENANCE.md EXISTS TO PREVENT, so the verdict prints the figure.
;
; ⚠ MARCHED PER CONTIGUOUS RUN, not per page, so coupling faults BETWEEN pages
; within a run are covered. The runs are simply what the exclusions leave.
;
; ⚠ THE WHOLE MARCH RUNS WITH $01 = $30 -- all RAM, no ROMs, no I/O, no
; cartridge. march_fail does its own bank dance for the one thing that needs I/O.
; ---------------------------------------------------------------------------
p3:
        lda #C_GREEN
        sta BORDER
        sta w_phcol
        lda #2
        jsr ph_begin
        lda #0                          ; ⚠ per-pass loop state only; the
        sta w_runidx                    ; counters above are cumulative
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
        jsr ph_end
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
        lda #C_CYAN
        sta BORDER
        sta w_phcol
        lda #3
        jsr ph_begin
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
        jsr ph_end
        jsr draw_errors
        jmp p5


; ---------------------------------------------------------------------------
; P5 -- topographical patterns. PHYSICAL row/column adjacency, not address
; order.
;
; ⚠ GATE G2, ANSWERED FROM BAUER §3.13: the VIC's 8-bit refresh counter
; generates "256 DRAM row addresses" and its table places REF7..REF0 on
; address bits 7..0. A counter that only moves the low byte cannot produce 256
; distinct ROWS unless the row address IS the low byte. So:
;
;       ROW    = A0-A7    the offset within a page
;       COLUMN = A8-A15   the page number
;
; ⚠ WHICH IS THE OPPOSITE OF WHAT THE ADDRESS SPACE SUGGESTS. Two cells in the
; same DRAM row, adjacent columns, are 256 BYTES APART. Two cells in the same
; column, adjacent rows, are 1 byte apart. A march walking addresses in order
; is walking DOWN a column, one row at a time -- it never moves along a row at
; all. That is the gap this phase fills.
;
; Six passes: row stripes, column stripes, checkerboard, and each inverted.
; Every pass writes the whole covered space, then verifies it, so a cell that
; is disturbed by its physical neighbours is caught on the read-back.
;
; ⚠⚠ HONEST LIMIT, AND IT IS STATED WHEREVER THE CLAIM IS MADE: this is row and
; column adjacency AS ADDRESSED. It does NOT model true die layout. Real 4164
; dies use address scrambling, array folding and true/complement bitlines that
; differ by manufacturer and die revision, and that is proprietary layout data
; absent from every datasheet. A C64 holds whatever chips someone fitted, often
; mixed. A CONFIDENTLY WRONG PHYSICAL MAP IS WORSE THAN NONE, because it claims
; adjacency coverage it is not delivering. So there is no per-manufacturer
; scrambler here and no claim of one.
; ---------------------------------------------------------------------------
p5:
        lda #C_PURPLE
        sta BORDER
        sta w_phcol
        lda #4
        jsr ph_begin
        lda #0
        sta w_patt
p5_pat:
        ldx w_patt
        cpx #6
        beq p5_done
        lda pattab,x
        sta w_pflags
        and #$01                        ; lo contributes only if bit 0 is set
        sta w_lomask
        lda #0                          ; write pass
        sta w_pmode
        jsr p5_pass
        lda #1                          ; verify pass
        sta w_pmode
        jsr p5_pass
        inc w_patt
        jmp p5_pat
p5_done:
        jsr ph_end
        jsr draw_errors
        jmp phv

; p5_pass -- one walk of every covered run, writing or verifying w_patt
p5_pass:
        lda #0
        sta w_runidx
p5p_run:
        ldx w_runidx
        lda runtab,x
        bne p5p_go
        rts                             ; ⚠ the run table's terminator, taken
                                        ; as an early return rather than a long
                                        ; branch past the whole page loop
p5p_go:
        sta w_startpg
        lda runtab+1,x
        sta w_endpg
        jsr set_asc
        lda #BANK_RAM                   ; ⚠ I/O IS GONE FROM HERE
        sta CPUPORT
p5p_pg:
        jsr tick
        ; ⚠ The column half of the pattern is constant across a page, because
        ; the column IS the page. Compute it once per page, not per cell.
        lda #$00
        ldx w_pflags
        txa
        and #$02
        beq p5p_nohi
        lda mptr+1
        and #$01
p5p_nohi:
        sta w_hpar
        lda w_pflags
        and #$04
        beq p5p_noinv
        lda w_hpar
        eor #$01
        sta w_hpar
p5p_noinv:
        ldy #0
p5p_c:  tya                             ; the row half varies per cell
        and w_lomask
        eor w_hpar
        lsr
        lda #$00
        bcc p5p_val
        lda #$ff
p5p_val:
        ldx w_pmode
        bne p5p_ver
        sta (mptr),y
        jmp p5p_nx
p5p_ver:
        tax                             ; X = expected
        lda (mptr),y
!ifdef INJECT_TOPO { jsr inj_hook }
        stx w_tmp
        cmp w_tmp
        beq p5p_nx
        jsr march_fail                  ; A = got, X = expected
p5p_nx:
        ; ⚠ jmp, not a relative branch: with the fault-injection block present
        ; the loop head is more than 128 bytes back and the assembler refuses.
        ; Same cost, and it does not change with the next edit to the body.
        iny
        beq p5p_pgend
        jmp p5p_c
p5p_pgend:
        jsr nx_asc
        beq p5p_runend
        jmp p5p_pg
p5p_runend:
        lda #BANK_IO                    ; ⚠ I/O BACK BEFORE ANYTHING ELSE
        sta CPUPORT
        lda w_runidx
        clc
        adc #2
        sta w_runidx
        jmp p5p_run

; --- M0  (w 0) -------------------------------------------------------------
lr0:    jsr set_asc
lr0_pg:
        jsr tick
        ldy #0
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
lr1_pg:
        jsr tick
        ldy #$ff
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
lr2_pg:
        jsr tick
        ldy #0
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
lr3_pg:
        jsr tick
        ldy #0
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
lr4_pg:
        jsr tick
        ldy #0
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
lr5_pg:
        jsr tick
        ldy #0
lr5_c:  lda (mptr),y
!ifdef INJECT_LR { jsr inj_hook }
        bne lr5_e1
lr5_k1: iny
        bne lr5_c
        jsr nx_asc
        bne lr5_pg
        rts
lr5_e1: ldx #$00
        jsr march_fail
        jmp lr5_k1


; ---------------------------------------------------------------------------
; tick -- one page processed. THE PROGRAM MUST LOOK ALIVE.
;
; ⚠ Carl, 2026-09-26: "whilst the crt is running it is impossible to know
; whether it is proceeding or crashed." A full run is about a minute and the
; marches spend ~20 s stretches with nothing on screen changing, so a frozen
; picture and a working picture looked identical -- unacceptable in a tool
; whose whole job is to be believed.
;
; Two indicators, because they fail differently:
;
;   * A SPINNER beside the phase name. ⚠ This needs NO bank switching, and
;     that is the point: the screen MATRIX is RAM and stays visible under
;     $01 = $30. Only its colour cell needed I/O, and that is set once.
;   * A BORDER PULSE between the phase colour and dark grey, visible across a
;     room. This one does need I/O, so it pays for a bank dance -- once every
;     32 pages, a couple of times a second.
;
; ⚠ A STOPPED BORDER NOW MEANS HUNG. The documented border codes still hold
; for the fatal cases, which all happen before any march; from P1 onwards a
; static border is itself the fault report.
;
; ⚠ MAY ONLY BE CALLED FROM INSIDE THE BANKED WINDOW -- it restores BANK_RAM
; unconditionally. Preserves A and Y; clobbers X, which no caller has live at
; a page boundary.
; ---------------------------------------------------------------------------
tick:
        pha
        tya
        pha
        inc w_tick                      ; ⚠ kept: the harness asserts it moves
        lda #BANK_IO
        sta CPUPORT
        ; ⚠⚠ THE RATE COMES FROM A TIMER, NOT FROM THE TICK COUNT. Both
        ; indicators used to advance once every N pages, which made their
        ; frequency an emergent property of how fast each phase walks memory --
        ; measured at 1.81 Hz in P4/P5 and calculated near 2.5 Hz in P7's short
        ; passes, against a 3 Hz limit, with nothing stopping a future phase
        ; from crossing it. CIA2 timer B now decrements every ~66 ms
        ; regardless, so bit 3 gives a fixed ~1 Hz pulse and bits 2-1 a ~2 Hz
        ; spinner, whatever the phase is doing.
        lda CIA2_TBL
        lsr
        and #$03
        tax
        lda spinchr,x
tick_sp:
        sta SCREEN                      ; ⚠ operand patched by ph_begin, so the
                                        ; spinner turns in the running phase's
                                        ; own status cell
        lda CIA2_TBL
        and #$08
        beq tick_on
        ; ⚠ Once ANYTHING has failed the pulse alternates with red and stays
        ; that way for the rest of the burn-in. On a run that has been going
        ; for an hour, "a fault was found at some point" has to be visible
        ; from across the room without reading the counters.
        lda w_errlo
        ora w_errhi
        ora w_dbmask
        ora w_ablo
        ora w_abhi
        beq tick_clean
        lda #C_LTRED
        bne tick_set
tick_clean:
        lda #C_DKGREY
        bne tick_set                    ; always: 11 is not zero
tick_on:
        lda w_phcol
tick_set:
        sta BORDER
        lda #BANK_RAM                   ; ⚠ BACK OUT, unconditionally
        sta CPUPORT
        pla
        tay
        pla
        rts




; ---------------------------------------------------------------------------
; P7 -- RETENTION. The marginal chip that passes every fast test.
;
; Write the address-dependent pattern everywhere, let real time pass, read it
; back. A cell that leaks faster than refresh can sustain drops a bit; a cell
; that is merely slow passes every march ever written and fails an hour into
; a game.
;
; ⚠⚠ REFRESH CANNOT BE SUPPRESSED FROM SOFTWARE ON A C64, AND ANY DESIGN THAT
; ASSUMES OTHERWISE IS WRONG. The VIC performs five refresh cycles per raster
; line unconditionally -- 78,000/s PAL -- computed from raster geometry with no
; display-state term. Blanking the screen suppresses badline character fetches
; and sprite fetches; refresh is not a badline activity. The irony is that
; blanking does the OPPOSITE of what a refresh-starvation design wants: losing
; badlines gives the CPU MORE cycles, so a delay loop runs faster while refresh
; carries on unchanged.
;
; So this tests retention AGAINST A WORKING REFRESH. That is a weaker stress
; than starving it would be, and it is the only one actually available -- but
; it is exactly the marginal cell that nothing else catches, and the reading is
; honest. ⚠ Temperature is the other lever and it is not a software one: the
; documentation tells the user to run it again on a warm machine.
;
; ⚠ COVERS THE RUN TABLE ONLY -- 59,648 bytes. Zero page, the stack, the
; screen and the engine cannot hold a test pattern for ten seconds while the
; engine is running out of them, and no amount of relocation changes that.
; ---------------------------------------------------------------------------
p7:
        lda #C_BLUE
        sta BORDER
        sta w_phcol
        lda #7
        jsr ph_begin

        lda #0                          ; ---- fill
        sta w_runidx
p7_wrun:
        ldx w_runidx
        lda runtab,x
        bne p7_wgo
        jmp p7_dwell
p7_wgo:
        sta w_startpg
        lda runtab+1,x
        sta w_endpg
        jsr set_asc
        lda #BANK_RAM
        sta CPUPORT
p7_wpg: jsr tick
        ldy #0
p7_wc:  tya
        eor mptr+1
        eor #SEED
        sta (mptr),y
        iny
        bne p7_wc
        jsr nx_asc
        bne p7_wpg
        lda #BANK_IO
        sta CPUPORT
        lda w_runidx
        clc
        adc #2
        sta w_runidx
        jmp p7_wrun

; ---- the wait. ⚠ Nothing may write to the covered regions here.
p7_dwell:
        lda #DWELL
        sta w_dwell
p7_dl:  jsr p7_show
        lda #FRAMES
        sta w_frames
p7_fr:  lda RASTER                      ; one pass of raster line $80 is one
        cmp #$80                        ; frame, and needs no interrupt
        bne p7_fr
p7_fr2: lda RASTER
        cmp #$80
        beq p7_fr2
        ; ⚠ The dwell is twelve seconds with nothing else happening, so it
        ; drives the border from the SAME timer as tick does -- one rule for
        ; the flash rate, not two.
        lda CIA2_TBL
        and #$08
        beq p7_bon
        lda #C_DKGREY
        bne p7_bset
p7_bon: lda w_phcol
p7_bset:sta BORDER
        dec w_frames
        bne p7_fr
        dec w_dwell
        bne p7_dl
        jsr p7_show

        lda #0                          ; ---- verify
        sta w_runidx
p7_vrun:
        ldx w_runidx
        lda runtab,x
        bne p7_vgo
        jmp p7_done
p7_vgo:
        sta w_startpg
        lda runtab+1,x
        sta w_endpg
        jsr set_asc
        lda #BANK_RAM
        sta CPUPORT
p7_vpg: jsr tick
        ldy #0
p7_vc:  tya
        eor mptr+1
        eor #SEED
        sta pval
        lda (mptr),y
!ifdef INJECT_RET { jsr inj_hook }
        cmp pval
        beq p7_vk
        ldx pval
        jsr march_fail
p7_vk:  iny
        bne p7_vc
        jsr nx_asc
        bne p7_vpg
        lda #BANK_IO
        sta CPUPORT
        lda w_runidx
        clc
        adc #2
        sta w_runidx
        jmp p7_vrun

p7_done:
        jsr ph_end
        jsr draw_errors
        jmp verdict

; p7_show -- the countdown, which doubles as liveness through the wait
p7_show:
        ; ⚠ The countdown goes in P7's own status cell, which is two characters
        ; wide and therefore exactly two hex digits. During the dwell tick is
        ; not called, so this is what keeps that row alive.
        jsr ph_cell
        ldy #0
        lda w_dwell
        jmp hexpair

; ---------------------------------------------------------------------------
; P6b -- THE HANDOVER. The two regions no march could reach, because the test
; was standing on them.
;
; ⚠ Carl asked whether the coverage shortfall was a limitation. The 501 bytes
; of zero page and stack were the urgent part and P6 closed them. These are
; the rest: the screen matrix the display is using, and the 4 KB the engine
; itself occupies. Both got P0b/P0c's single pass and showed '+'; neither had
; been marched.
;
; The trick is the same for both -- move off the region, march it, move back --
; but the two differ in what "move off" means:
;
;   SCREEN   $0400-$07FF   The display is blanked, the matrix and its colour
;                          are stashed to already-marched RAM, the region is
;                          marched, then both are put back. ⚠ Cheaper than
;                          relocating the VIC, which would mean every display
;                          write going through a base pointer instead of a
;                          constant.
;
;   ENGINE   $C000-$CFFF   ⚠ The code performing the march CANNOT be in the
;                          region being marched. A small module is copied to
;                          $3000 and jumped to; it marches the engine's home
;                          out from under the engine, re-copies the engine
;                          from cartridge ROM -- which is still mapped at
;                          $8000 -- and jumps back in at a resume point.
;
; ⚠ THE WORKSPACE LIVES AT $CF00, INSIDE THE SECOND REGION. Everything
; accumulated so far -- the failing-bit mask, the error counts, the bus
; results -- would be marched over. It is stashed to $2800 and restored, and
; any faults the handover itself finds are accumulated in module-local bytes
; until the workspace is back.
;
; 9n, as P6 is, so these regions paint '*' and not solid: they get a march,
; but not the 31n plus six topographical passes the rest of memory gets.
; ---------------------------------------------------------------------------
phv:
        lda #C_GREY
        sta BORDER
        sta w_phcol
        lda #6
        jsr ph_begin
        lda #0
        sta w_hvscr
        sta w_hveng

        ; ⚠ COPIES HV_PAGES PAGES, not a hardcoded three. The unrolled version
        ; moved exactly three while HV_PAGES said four, so the colour-RAM phase
        ; landed 64 bytes short and jumping into it hung the machine. The
        ; !error below checks the module fits; it could not check that the
        ; copy loop agreed with it. Now they cannot disagree.
        lda #<hv_src
        sta sptr
        lda #>hv_src
        sta sptr+1
        lda #0
        sta cptr
        lda #>HV_CODE
        sta cptr+1
        ldx #HV_PAGES
phv_cp: ldy #0
phv_cb: lda (sptr),y
        sta (cptr),y
        iny
        bne phv_cb
        inc sptr+1
        inc cptr+1
        dex
        bne phv_cp
        jmp HV_CODE

; ⚠ Where the handover module jumps back to, after the engine has been
; re-copied from ROM. It must not re-run anything.
eng_resume:
        lda w_hvscr
        beq phv_scr_ok
        ldx #3
        bne phv_scr_m
phv_scr_ok:
        ldx #5                          ; marched at 9n
phv_scr_m:
        stx w_tmp
        ldx #$04
phv_sl: txa
        pha
        ldx w_tmp
        jsr mark_page_keep
        pla
        tax
        inx
        cpx #$08
        bne phv_sl

        lda w_hveng
        beq phv_eng_ok
        ldx #3
        bne phv_eng_m
phv_eng_ok:
        ldx #5
phv_eng_m:
        stx w_tmp
        lda #>WORK                      ; the workspace page shares the verdict
        ldx w_tmp
        jsr mark_page_keep
        ldx #$c0
phv_el: txa
        pha
        ldx w_tmp
        jsr mark_page_keep
        pla
        tax
        inx
        cpx #$d0
        bne phv_el

        lda w_hvscr                     ; P6B: its own two flags
        ora w_hveng
        sta w_phextra
        jsr ph_end

        lda #8                          ; P9 colour RAM -- marked here because
        jsr ph_begin                    ; the module that ran it has no screen
        lda w_colbad                    ; code of its own
        sta w_phextra
        jsr ph_end

        jsr draw_errors
        jmp p7



; ===========================================================================
; inj_hook -- ⚠ FAULT-INJECTION BUILDS ONLY. One mechanism, written once.
;
; ⚠⚠ WHY THIS EXISTS. Every mutation used to be hand-written inline at its own
; site, and three of them damaged the very thing they were meant to observe:
;   * INJECT_LR clobbered the Z flag that March LR's bare `r 0` branches on,
;     and reported 59,416 errors instead of 1
;   * INJECT_ONCE loaded the pass counter into A -- over the byte just read --
;     and fired 53,294 times instead of once
;   * INJECT_ZP pushed onto the stack page it was in the middle of marching
; A mutation that perturbs the program is not testing the program. Ten copies
; of a delicate thing is ten chances to get it wrong; this is one copy.
;
; CONTRACT, and every line of it matters:
;   in    A = the byte just read, Y = offset within the page, mptr+1 = page
;   out   A = that byte EOR INJ_MASK if (page, offset) match, else unchanged
;   ⚠     X and Y preserved, stack balanced, and the FLAGS SET FROM A on every
;         path -- callers that branch straight off the load depend on it
; ===========================================================================
; ⚠ ONE BODY, TWO INSTANTIATIONS -- and the second is not optional.
; The engine's copy cannot serve the handover: phase B marches $C000-$CFFF,
; so a `jsr` into the engine from inside that march calls code that is being
; overwritten as it runs. That hung the build the moment the shared hook went
; in. A macro keeps it one piece of source while letting it exist in both
; places, which is the whole point -- one thing to get right, not two.
!macro INJHOOK {
        cpy #INJ_OFF
        bne .keep
        ; ⚠⚠ THE STACK, NOT A WORKSPACE BYTE. The first version kept its
        ; scratch at $032D -- inside the page the handover marches -- so the
        ; hook corrupted the memory under test and produced a second, entirely
        ; real fault in a region it was not aiming at. The stack is safe at
        ; every site that uses this hook, because the one phase that marches
        ; the stack page (P6) keeps its own inline injection for exactly that
        ; reason.
        pha                             ; the byte under test
        txa
        pha
!ifdef INJ_FIRSTPASS {
        lda w_passlo                    ; ⚠ a TRANSIENT fault: pass 1 only
        bne .restore
}
; ⚠ THE INVERSE, and it exists to test a DISPLAY bug rather than a memory one:
; a fault that appears only from run 2 makes the verdict CHANGE KIND mid
; session, which is what left one verdict's tail under the next. Every other
; mutation shows a single verdict for the whole session.
!ifdef INJ_LATERPASS {
        lda w_passlo
        beq .restore
}
        lda mptr+1
        cmp #INJ_PG
        bne .restore
        pla
        tax
        pla
        eor #INJ_MASK
        jmp .flags
.restore:
        pla
        tax
        pla
.keep:
.flags: cmp #$00                        ; ⚠ flags from A on EVERY path
        rts
}

!ifdef INJ_MASK {
inj_hook:
        +INJHOOK
}

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
m0_pg:
        jsr tick
        ldy #0
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
m1_pg:
        jsr tick
        ldy #0
m1_c:   tya
        eor mptr+1
        eor #SEED
        sta pval
        eor #$ff
        sta pinv
        lda (mptr),y
; ⚠ Three mutations share this site -- one stuck bit, all eight bits, and a
; transient that fires on pass 1 only. They differ ONLY in the -D values the
; build passes, which is the point of having one hook.
!ifdef INJECT_MEM  { jsr inj_hook }
!ifdef INJECT_ALL  { jsr inj_hook }
!ifdef INJECT_ONCE { jsr inj_hook }
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
m2_pg:
        jsr tick
        ldy #0
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
m3_pg:
        jsr tick
        ldy #$ff
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
m4_pg:
        jsr tick
        ldy #$ff
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
        ; ⚠ WHERE, recorded once. A repairer given a bit and a chip still has
        ; to find the fault; an address is the difference between "somewhere
        ; in 64K" and a place to put a probe.
        lda w_errlo
        ora w_errhi
        bne mf_haveaddr
        sty w_faddr
        lda mptr+1
        sta w_faddr+1
mf_haveaddr:
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
        ldx #1                          ; testing
        jsr mark_page_keep
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
        ldx #2                          ; pass
        jsr mark_page_keep
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
; ⚠⚠ SHORT BOARDS ARE NOT EIGHT CHIPS. Carl, 2026-09-26: a C64 short board
; (250469 and relatives) carries TWO 41464s -- 64K x 4 -- not eight 4164s.
; Each chip therefore supplies FOUR bits, so a single failing bit narrows to
; one of two chips and no further, and the designators below are simply not
; that board's designators. The tool cannot tell which board it is plugged
; into, so it does three things: it prints the BIT, which is true everywhere;
; it prints designators only under a heading naming the assembly they belong
; to; and when it names a chip at all it prints the short-board caveat
; underneath. Guessing here would send someone to desolder the wrong part.
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
        sta w_dmask                     ; ⚠ kept: the slot loop asl's w_tmp away
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

        ; ⚠ "dN" is generated rather than read from a 32-byte table. The
        ; engine is capped at 4 KB by the I/O page and the table was worth
        ; twenty-two bytes that the colour-RAM phase needed more.
        lda #V_ROW+1
        ldx w_col
        jsr setpos
        ldy #0
        lda #$04                        ; screen code for 'd'
        sta (sptr),y
        lda #C_LTRED
        sta (cptr),y
        iny
        lda w_tidx
        lsr
        lsr                             ; table offset back to a bit number
        tax
        lda s_hex,x
        sta (sptr),y
        lda #C_LTRED
        sta (cptr),y

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
        ; ⚠ A named chip gets the 41464 note under it, replacing "RUNS UNTIL
        ; YOU RESET." That line matters most when nothing is wrong; this one
        ; matters most when the tool is telling someone which part to replace.
        lda w_chipok
        beq dg_end
        ; ⚠ BLANK THE ROW FIRST. This replaces a line of a different length --
        ; writing straight over it once left a tail showing and the screen read
        ; "...NAMES DIFFER.RAM". Padding the string would fix it until the next
        ; time either line changed length; clearing the row fixes it for good.
        lda #V_ROW+3
        ldx #1
        jsr setpos
        ldy #37
        lda #CH_SPACE
dg_clr: sta (sptr),y
        dey
        bpl dg_clr

        lda #C_ORANGE
        sta w_col2
        lda #V_ROW+3
        sta w_row
        lda #1
        sta w_col

        ; ⚠ WHICH NIBBLE FAILED, BECAUSE ON A 41464 BOARD FOUR BITS ARE ONE
        ; CHIP. The old line said only "SHORT BOARD? 2 CHIPS, NAMES DIFFER",
        ; which warned that the names were wrong without saying what was right,
        ; and was itself wrong: 250466 is a LONG board with two 41464s, so the
        ; chip count does not identify the board type.
        ; ⚠ NO DESIGNATOR IS NAMED FOR A 41464 BOARD, ON PURPOSE. The two of
        ; them disagree and nothing on screen can tell them apart:
        ;     250469 (short)  U10 = D0-D3   U11 = D4-D7
        ;     250466 (long)   U10 = D0-D3   U9  = D4-D7
        ; The nibble grouping is a DATASHEET fact -- a 41464 is four bits wide
        ; whatever board it is on -- so it can be stated without knowing the
        ; board. The designators cannot, and are on the bench sheet instead.
        ; ⚠ w_dmask, NOT w_tmp: the slot loop above destroyed w_tmp with asl.
        lda w_dmask
        and #$0f
        beq dg_n_hi                     ; nothing in the low nibble
        lda w_dmask
        and #$f0
        bne dg_n_both
        lda #<s_niblo
        ldy #>s_niblo
        jmp prstr
dg_n_hi:
        lda #<s_nibhi
        ldy #>s_nibhi
        jmp prstr
dg_n_both:
        lda #<s_nibboth
        ldy #>s_nibboth
        jmp prstr
dg_end: rts


; ---------------------------------------------------------------------------
; ph_begin -- A = phase index. Marks that phase running and aims the spinner
; at its status cell.
; ph_end   -- decides OK or X from the error count delta plus w_phextra, which
;             a phase sets when its verdict is not an error count (P1's data
;             mask, P2's address masks, P9's colour flag).
; ---------------------------------------------------------------------------
ph_begin:
        sta w_phidx
        lda w_errlo
        sta w_snaplo
        lda w_errhi
        sta w_snaphi
        lda #0
        sta w_phextra
        jsr ph_cell
        lda sptr                        ; aim tick's spinner here
        sta tick_sp+1
        lda sptr+1
        sta tick_sp+2
        ldy #0
        lda #C_YELLOW
        sta (cptr),y
        iny
        sta (cptr),y
        lda #CH_SPACE
        sta (sptr),y
        rts

; ph_cell -- sptr/cptr point at the current phase's status cell
ph_cell:
        ldx w_phidx
        lda phrow,x
        ldx #STAT_COL
        jmp setpos

; ⚠⚠ A PHASE THAT HAS EVER FAILED STAYS FAILED, for the life of the run.
; Carl asked whether the statuses should reset to '..' between passes. They
; should not -- that would read as "not tested", which is false after the
; first pass. But what was happening was worse than either option: the error
; counts are cumulative, so a phase that failed in pass 1 showed no DELTA in
; pass 2 and had its X quietly overwritten with OK. Demonstrated with a
; transient fault: one bad byte in pass 1, checklist OKOK X OK.. at the end of
; pass 1, and OKOK OK OK.. at the end of pass 2 -- while the map cell and the
; bad-byte count both still said the fault had happened.
;
; That is the same defect mark_page_keep exists to prevent on the map, and the
; exact failure a burn-in is FOR: the fault that happened once, an hour ago.
ph_end:
        lda w_errlo
        cmp w_snaplo
        bne ph_bad
        lda w_errhi
        cmp w_snaphi
        bne ph_bad
        lda w_phextra
        bne ph_bad
        jsr ph_isfail                   ; clean THIS pass -- but ever failed?
        bne ph_showbad
        jsr ph_cell
        ldy #0
        lda #$0f                        ; 'O'
        sta (sptr),y
        lda #C_GREEN
        sta (cptr),y
        iny
        lda #$0b                        ; 'K'
        sta (sptr),y
        lda #C_GREEN
        sta (cptr),y
        rts
ph_bad:
        jsr ph_setfail
ph_showbad:
        jsr ph_cell
        ldy #0
        lda #CH_X
        sta (sptr),y
        lda #C_LTRED
        sta (cptr),y
        iny
        lda #CH_SPACE
        sta (sptr),y
        rts

; ph_bitpos -- X = which byte of w_phfail, A = this phase's bit
ph_bitpos:
        ldx #0
        lda w_phidx
        cmp #8
        bcc phb_lo
        sbc #8
        ldx #1
phb_lo: tay
        lda bittab,y
        rts

ph_isfail:
        jsr ph_bitpos
        and w_phfail,x
        rts

ph_setfail:
        jsr ph_bitpos
        ora w_phfail,x
        sta w_phfail,x
        rts

; reset_checklist -- run at the start of every burn-in pass.
;
; ⚠ OK GOES BACK TO '..', X DOES NOT. Carl asked whether the statuses should
; reset between passes and the first answer here was "no", on the grounds that
; the burn-in must not forget anything. That conflated two separable things.
; NOT FORGETTING A FAILURE and NOT RESETTING A PASS are different: a phase
; that has ever failed keeps its X for the life of the run, and everything
; else goes back to '..' so the column shows progress through the CURRENT
; pass. Otherwise pass 2 onwards is a wall of OK from pass 1 with nothing to
; watch, and '..' truthfully means "not run YET, this pass".
reset_checklist:
        ldx #0
rc_l:   stx w_tmp
        stx w_phidx
        jsr ph_isfail                   ; ⚠ ever failed? then leave it alone
        bne rc_keep
        jsr ph_cell
        ldy #1
rc_d:   lda #CH_DOT
        sta (sptr),y
        lda #C_DKGREY
        sta (cptr),y
        dey
        bpl rc_d
rc_keep:
        ldx w_tmp
        inx
        cpx #NPHASE
        bne rc_l
        rts

; draw_phases -- the checklist itself, every phase named and marked not-run
draw_phases:
        ldx #0
dph_l:  stx w_tmp
        lda phrow,x
        sta w_row
        lda #PAN_COL
        sta w_col
        lda #C_GREY
        sta w_col2
        lda phstrl,x
        ldy phstrh,x
        jsr prstr
        ldx w_tmp
        stx w_phidx
        jsr ph_cell
        ldy #1
dph_d:  lda #CH_DOT
        sta (sptr),y
        lda #C_DKGREY
        sta (cptr),y
        dey
        bpl dph_d
        ldx w_tmp
        inx
        cpx #NPHASE
        bne dph_l
        rts

; ---------------------------------------------------------------------------
; ⚠⚠ THESE TWO ARE COUNTS, AND COUNTS ARE DECIMAL.
; They used to be printed in hex with a '$' in front. Carl asked why the '$'
; was there, and the honest answer is that it was covering for the real
; mistake: nobody has run the test $0012 times, and "BAD BYTES $000A" makes the
; reader convert ten into ten. The '$' was treating the symptom.
;
; ⚠ THE ADDRESS STAYS HEX, and that is not an inconsistency. An address IS hex
; vocabulary -- it matches the schematic, and it matches the map's own hex row
; and column labels. Now that the counts are decimal, '$' on this screen means
; exactly one thing: what follows is an address.
;
; ⚠ NOT BCD. The obvious 6502 trick is to keep the counters in BCD so hexpair
; prints them as decimal for free. Two reasons not to: INC does not honour the
; D flag, so every increment would grow anyway; and two BCD bytes stop at 9999
; while a real fault has already produced 40,961 bad bytes in this project's
; own history. Binary keeps the full 16-bit range and dec16 pays the cost once
; per redraw instead of once per counted byte.
; ---------------------------------------------------------------------------
draw_passes:
        lda w_passlo
        sta w_dlo
        lda w_passhi
        sta w_dhi
        lda #0
        ldx #17
        jmp dec16

draw_errors:
        lda w_errlo
        sta w_dlo
        lda w_errhi
        sta w_dhi
        lda #0
        ldx #34
        jmp dec16

; ---------------------------------------------------------------------------
; dec16 -- w_dlo/w_dhi as up to five decimal digits, A = row, X = column.
; ⚠ RIGHT-ALIGNED, LEADING ZEROS BLANKED. "BAD BYTES 0" is what a person reads;
; "BAD BYTES 00000" is what a machine writes. The five columns are fixed width
; so the field never jitters as the count grows.
; ⚠ Repeated subtraction of a power-of-ten table -- no division on a 6502.
; ---------------------------------------------------------------------------
dec16:
        jsr setpos
        ldy #0
        sty w_nz
        sty w_tmp2                      ; ⚠ the running screen offset
        ldx #0                          ; index into the power table
d16_pow:
        lda #0
        pha                             ; digit count for this power
d16_sub:
        lda w_dlo                       ; try value = value - power
        sec
        sbc dec_lo,x
        sta w_tmp
        lda w_dhi
        sbc dec_hi,x
        bcc d16_done                    ; borrowed: it did not fit
        sta w_dhi
        lda w_tmp
        sta w_dlo
        pla
        clc
        adc #1
        pha
        jmp d16_sub
d16_done:
        pla                             ; the digit
        tay
        bne d16_show                    ; non-zero: always shown
        lda w_nz
        bne d16_show                    ; something already shown: keep place
        cpx #4
        beq d16_show                    ; ⚠ the units digit is ALWAYS shown,
        lda #CH_SPACE                   ;   so a count of zero reads "0"
        bne d16_put
d16_show:
        lda #1
        sta w_nz
        tya
        clc
        adc #$30                        ; screen code for '0'
d16_put:
        ldy w_tmp2
        sta (sptr),y
        lda #C_LTGREY
        sta (cptr),y
        inc w_tmp2
        inx
        cpx #5
        bne d16_pow
        rts

dec_lo: !byte <10000, <1000, <100, <10, <1
dec_hi: !byte >10000, >1000, >100, >10, >1

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
; ⚠ Dispatched with jmp, not relative branches: the verdict bodies grew past
; 128 bytes when the failing address was added, and a branch that cannot reach
; is a build failure rather than something to rediscover.
verdict:
        ; ⚠⚠ CLEAR THE VERDICT ROWS FIRST. verdict_line and verdict_line2 write
        ; a string and nothing else, so a SHORTER verdict leaves the tail of a
        ; longer one behind. That is reachable in exactly the situation this
        ; tool exists for: faults are cumulative and the verdict can only
        ; escalate, so a colour-RAM fault in run 1 followed by a memory fault in
        ; run 2 changes which verdict is shown, and row 22 kept "...WRONG
        ; COLOURS." behind the new bit lanes.
        ; ⚠ NOT CAUGHT BY ANY OF THE 16 CASES, because each mutation produces
        ; one kind of fault for the whole run and starts from a blank screen.
        ; The suite never saw a verdict CHANGE KIND. A new case now does.
        ; ⚠ Rows V_ROW..V_ROW+2 only. V_ROW+3 holds "RUNS UNTIL YOU RESET.",
        ; which draw_diag replaces and clears for itself when it names a chip.
        ldx #V_ROW
vq_row: txa
        pha
        ldx #0
        jsr setpos
        ldy #39
        lda #CH_SPACE
vq_col: sta (sptr),y
        dey
        bpl vq_col
        pla
        tax
        inx
        cpx #V_ROW+3
        bne vq_row

        lda w_dbmask
        beq vd_1
        jmp v_data
vd_1:   lda w_ablo
        ora w_abhi
        beq vd_2
        jmp v_addr
vd_2:   lda w_errlo
        ora w_errhi
        beq vd_3
        jmp v_mem
vd_3:
        ; ⚠ A colour-RAM fault must not be reported as "BUS INTEGRITY OK".
        ; The DRAMs genuinely are fine, and the red COL RAM label says so --
        ; but a reader who glances at the verdict line and walks away has been
        ; told the machine is healthy when it is not.
        lda w_colbad
        bne v_col
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

v_col:
        lda #C_LTRED
        sta BORDER
        sta w_col2
        lda #<s_colbad
        ldy #>s_colbad
        jsr verdict_line
        lda #<s_colbad2
        ldy #>s_colbad2
        jsr verdict_line2_nohalt
        jmp pass_end

v_mem:
        lda #C_LTRED
        sta BORDER
        lda #C_LTRED
        sta w_col2
        lda #<s_membad
        ldy #>s_membad
        jsr verdict_line
        lda #V_ROW                      ; the address, right after the '$'
        ldx #34
        jsr setpos
        ldy #0
        lda w_faddr+1
        jsr hexpair
        lda w_faddr
        jsr hexpair
        lda w_bitmask                   ; ⚠ no second verdict line here: the
        sta w_tmp                       ; bit and chip lines are rows 22 and 23
        jsr draw_diag                   ; and say more than a sentence would
        jmp pass_end

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
        jmp pass_end

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

; ---------------------------------------------------------------------------
; End of a pass. ⚠ THE BURN-IN LOOP.
;
; Carl, 2026-09-26: "the RAM test runs once only. Typically ram tests have a
; burn in whereby they cycle and count the number of cycles." One pass catches
; a dead chip; it does not catch the one that fails once an hour, and that is
; the fault people actually chase.
;
; ⚠ It loops back to P1, NOT to the top. Re-running eng_start would clear the
; screen and re-initialise the map, throwing away every failure found so far.
; The counters and the red cells are cumulative on purpose: the whole value of
; a burn-in is that pass 400 still remembers what pass 3 found.
;
; ⚠ pass_end is also the harness's observation point -- test/check.py
; breakpoints it to read the screen after exactly one pass.
; ---------------------------------------------------------------------------
pass_end:
        inc w_passlo
        bne pe_1
        inc w_passhi
pe_1:   jsr draw_passes
pass_obs:
        jsr reset_checklist
        ; ⚠ THE HARNESS BREAKPOINTS HERE, NOT AT pass_end -- the counter has
        ; to be on screen before the screen is read, and pass_end's first
        ; instruction is the increment.
        jmp p1

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
        jmp pass_end
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

; mark_page_keep -- like mark_page, but ⚠ LEAVES A FAILED CELL ALONE.
; Needed once the burn-in loops: pass two must not paint over pass one's
; findings just because it happened to pass itself.
mark_page_keep:
        stx w_tmp2
        pha
        jsr cell_pos
        ldy #0
        lda (sptr),y
        cmp #CH_X
        beq mpk_skip
        pla
        ldx w_tmp2
        jmp mark_page
mpk_skip:
        pla
        rts

; mark_page -- A = page number, X = state 0..5
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

        lda #1                          ; ⚠ drawn, not stored: the engine is
        jsr draw_rule                   ; hard-capped at 4 KB because $D000 is
        lda #V_ROW-1                    ; I/O, so a 40-byte string for a row of
        jsr draw_rule                   ; dashes is 40 bytes that cannot be
                                        ; spent on a test

        lda #C_GREY
        sta w_col2
        lda #MAP_ROW-1
        sta w_row
        lda #MAP_COL
        sta w_col
        lda #<s_toprow                  ; ⚠ ONE string for the whole row: the
        ldy #>s_toprow                  ; hex ruler and the panel heading are
        jsr prstr                       ; the same screen row, and the engine
                                        ; had 24 bytes free, not 50

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

        lda #C_GREY                     ; only the bit-number rulers remain
        sta w_col2                      ; as separate labels; the phase names
        lda #DB_ROW-1                   ; are drawn by draw_phases
        sta w_row
        lda #PAN_COL+1
        sta w_col
        lda #<s_bitno
        ldy #>s_bitno
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
        jsr draw_phases

        lda #C_GREY                     ; the two running totals, on the title
        sta w_col2                      ; row where there was dead space
        lda #0
        sta w_row
        lda #24
        sta w_col
        lda #<s_errors
        ldy #>s_errors
        jsr prstr
        lda #0
        sta w_row
        lda #12
        sta w_col
        lda #<s_passes
        ldy #>s_passes
        jsr prstr

        lda #0
        sta w_tick

        lda #C_DKGREY                   ; legend -- the glyphs must not be a
        sta w_col2                      ; private language
        lda #V_ROW-2                    ; ⚠ under the MAP, not under the
        sta w_row                       ; verdict: it explains the map, and
        lda #1                          ; the short-board caveat used to
        sta w_col                       ; overwrite it exactly when a fault
        lda #<s_legend                  ; made the map worth reading
        ldy #>s_legend
        jsr prstr
        lda #V_ROW-2                    ; ⚠ the version tucked in the corner:
        sta w_row                       ; on the title row there was no space
        lda #37                         ; left once the counters were named
        sta w_col                       ; for what they actually count
        lda #<s_ver
        ldy #>s_ver
        jsr prstr
        lda #V_ROW+3
        sta w_row
        lda #1
        sta w_col
        lda #<s_running
        ldy #>s_running
        jsr prstr
        rts

; draw_rule -- A = row. A full-width separator, generated rather than stored.
draw_rule:
        ldx #0
        jsr setpos
        ldy #39
        lda #CH_DASH
dr_ch:  sta (sptr),y
        dey
        bpl dr_ch
        ldy #39
        lda #C_DKGREY
dr_co:  sta (cptr),y
        dey
        bpl dr_co
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
; ⚠ "45/byte" and "9/byte" are OPERATIONS PER BYTE, and they are on screen in
; those words because the legend used to say "9n" -- march-test notation that
; means nothing to anyone who has not read the literature. A solid cell got
; March B's 17 plus March LR's 14 plus twelve topographical plus two for the
; dwell = 45 reads and writes of every byte. A '*' cell got the 9n march and
; nothing else. Jargon on a diagnostic screen is a defect.
;
; ⚠ STATE 5 IS THE SAME KIND OF HONESTY AS STATE 4. Zero page and the stack
; get P6's 9n march, not P3+P4+P5's 31n plus six topographical passes -- there
; is no pointer to walk them with and no room to write the long version out
; twice. Painting them the same solid green would claim coverage they did not
; get, so they are '*': marched, but not to the same depth.
; ⚠ STATE 4 NOW DRAWS '*' TOO, AND KEEPS ITS CYAN. It used to draw '+', a
; sixth glyph that only ever appeared mid-run and that the legend had no room
; to explain -- an unexplained mark on a diagnostic screen is worse than a
; coarser one. "Lighter than full" is true of a probed page and of a 9n-marched
; page alike, which is all '*' claims; the colour still separates them for
; anyone who looks, and the real number is on the coverage line. CH_PLUS is
; kept defined because the honesty it stood for is still the reason state 4
; exists at all.
st_char: !byte CH_DOT,    CH_DASH,  CH_FULL, CH_X,    CH_STAR, CH_STAR
st_col:  !byte C_DKGREY,  C_YELLOW, C_GREEN, C_LTRED, C_CYAN,  C_GREEN
bittab:  !byte 1,2,4,8,16,32,64,128

; ⚠ Raw screen codes, not !scr: these are the C64's own line graphics, and the
; rotation only reads as rotation with these four in this order.
spinchr: !byte $40, $4e, $5d, $4d

; ⚠ The checklist. One row per phase, in the order they run, so the screen
; answers "what has been done to this machine" without anyone reading a manual.
; ⚠ RETENTION AND COLOUR RAM ARE SWAPPED RELATIVE TO THEIR PHASE INDEX, ON
; PURPOSE. The colour RAM is checked inside the handover module, which finishes
; before the retention dwell begins, so in index order the list filled in out of
; order: COLOUR RAM went OK while RETENTION above it still read '..'. A reader
; watching a list fill downwards reads a gap as "that one was skipped". The rows
; are ordered by when they COMPLETE, which is what the reader is tracking.
; ⚠ The test harness reads the rows in this same order -- test/check.py PHROW --
; so a position in the checklist string is still a phase index.
phrow:   !byte 3, 6, 11, 12, 13, 14, 15, 17, 16
phstrl:  !byte <s_p1, <s_p2, <s_p3, <s_p4, <s_p5, <s_p6, <s_phv, <s_p7, <s_p9
phstrh:  !byte >s_p1, >s_p2, >s_p3, >s_p4, >s_p5, >s_p6, >s_phv, >s_p7, >s_p9

; P5 patterns: bit0 = row half (low byte) contributes, bit1 = column half
; (page number) contributes, bit2 = invert. Row stripes, column stripes,
; checkerboard, and each inverted.
pattab:  !byte %001, %101, %010, %110, %011, %111

; Pages P2 writes to: ABASE, and ABASE + 2^n for n = 0..15.
p2pages: !byte $08,$09,$0a,$0c,$10,$18,$28,$48,$88,$ff

; ⚠ The contiguous runs P3 marches, as start/end page pairs, $00 terminating.
; What is NOT here is the point: $00-$01 zero page and stack, $04-$07 screen
; and workspace, $C0-$CF the engine. 233 pages, 59,648 bytes of 65,536.
; ⚠ $C0-$CF, SIXTEEN PAGES, NOT $C0-$CB: ENG_PAGES went from 12 to 16 and this
; comment did not follow. The !error guards by s_ok2 are the authority.
runtab:  !byte $02,$02         ; ⚠ $03 is the workspace -- see WORK
         !byte $08,$bf
         !byte $d0,$ff
         !byte $00

; ⚠⚠ s_ok2 PRINTS THESE NUMBERS AND CANNOT RECOMPUTE THEM, so they are tied
; to the table here. The coverage figure was silently lost once already --
; replaced by the vaguer "all ram tested" while making room to mention the
; dwell -- and a figure that drifts out of step with the run table would be
; worse than no figure at all. Change the table, fail the build, fix the
; string.
;   full march (P3+P4+P5+P7), pages:   1 + 184 + 48 = 233  -> 59,648 bytes
;   9n (P6 and the handover),  pages:  2 +   1 +  4 + 16 = 23 -> 5,888
;                                      less $0000/$0001, which are not RAM
;   tested: 59,648 + 5,886 = 65,534 of 65,536
!if ($02-$02+1) + ($bf-$08+1) + ($ff-$d0+1) != 233 {
        !error "run table changed -- the coverage figure in s_ok2 is now wrong"
}
!if ($01-$00+1) + 1 + ($07-$04+1) + ($cf-$c0+1) != 23 {
        !error "excluded pages changed -- the coverage figure in s_ok2 is wrong"
}

; ⚠⚠ ASSEMBLY-TIME GUARDS, BECAUSE THIS WENT WRONG TWICE.
; The workspace has moved three times as the engine grew, and both times it
; landed inside a marched run the symptom was the same and took a bisect to
; find: the march quietly overwrote the run loop's own counters and the phase
; never terminated. A run table and a workspace address that disagree is now a
; BUILD failure, not a hang on someone's C64.
!if (>WORK) >= $02 { !if (>WORK) <= $02 { !error "WORK page is inside run 1" } }
!if (>WORK) >= $08 { !if (>WORK) <= $bf { !error "WORK page is inside run 2" } }
!if (>WORK) >= $d0 { !if (>WORK) <= $ff { !error "WORK page is inside run 3" } }
!if (>ENGINE) >= $08 { !if ((>ENGINE)+ENG_PAGES-1) <= $bf { !error "ENGINE is inside run 2" } }
!if (>SCREEN) >= $02 { !if (>SCREEN) <= $02 { !error "SCREEN is inside run 1" } }
!if (>SCREEN) >= $08 { !if (>SCREEN) <= $bf { !error "SCREEN is inside run 2" } }

addrlo:  !for i, 0, 15 { !byte <(ABASE + (1 << i)) }
addrhi:  !for i, 0, 15 { !byte >(ABASE + (1 << i)) }
rowlo:   !for i, 0, 24 { !byte <(SCREEN + i*40) }
rowhi:   !for i, 0, 24 { !byte >(SCREEN + i*40) }

; ⚠⚠ THE ENGINE IS AT ITS CEILING. It must fit in $C000-$CFFF because $D000 is
; I/O, and it is within a few dozen bytes of 4096 with every fault-injection
; variant needing to fit too. Strings here have already been trimmed twice.
; WHEN THE NEXT PHASE NEEDS ROOM, MOVE P6 INTO THE HANDOVER MODULE -- it is
; ~350 bytes, it is self-contained, it already runs registers-only with
; self-modifying code (which works in the module, since that is RAM too), and
; it only needs phase/mark_page/draw_errors from the engine, all of which are
; intact at the point it runs. Do not shave strings a third time.
;
; ⚠ acme's !scr maps LOWERCASE source to uppercase screen codes, so every
; string here is written lower case on purpose.
s_title:    !scr "dramscope", 0
; ⚠ TWO LABELS, ONE STRING, AND THAT IS DELIBERATE.
; The panel had no heading: a reader had to work out for themselves that the
; right-hand column was a list of tests and their outcomes, which was the
; specific complaint. The heading lives on the same screen row as the map's hex
; ruler, so printing it separately cost 24 bytes of setup in an engine that had
; 24 bytes left. Printed from s_toprow it costs only its own characters.
; ⚠ s_hex must stay the first 16 bytes: dc_rows indexes it for the map's row
; labels. Do not insert anything between the label and the digits.
s_toprow:
s_hex:      !scr "0123456789abcdef tests and results", 0
s_bitno:    !scr "76543210", 0
s_ahno:     !scr "fedcba98", 0
s_alno:     !scr "76543210", 0
s_p1:       !scr "data lines", 0
s_p2:       !scr "addr lines", 0
s_p3:       !scr "march b", 0
s_p4:       !scr "march lr", 0
s_p5:       !scr "row/column", 0
s_p6:       !scr "low memory", 0
s_phv:      !scr "own memory", 0
s_p7:       !scr "retention", 0
s_errors:   !scr "bad bytes", 0
s_passes:   !scr "runs", 0
s_p9:       !scr "colour ram", 0
; ⚠ THE OLD LEGEND SAID ".=NOT RAM" AND THAT WAS SIMPLY FALSE. Every one of
; the 256 pages is RAM and every one gets tested -- even $D000-$DFFF, which is
; marched with I/O banked out. '.' is state 0, "not reached yet", and it is
; dark grey on black precisely so it reads as absence; a mark nobody can see
; does not need a legend entry, so it has none.
; ⚠ ADDING 'x' IS THE POINT OF THE REWRITE. The legend explained the two
; resting states and said nothing about the failure state, which had it exactly
; backwards: a red x on a page is the single most important mark on the screen.
; ⚠ '-' IS DELIBERATELY NOT LISTED. It is one yellow cell, moving, with a
; spinner turning in the running phase's row at the same time -- it reads as
; "here" with no help, and listing it pushed the line into the version number
; in the corner. The budget is col 1 to col 35; the version owns 37-39.
; ⚠⚠ THE LEGEND'S FIRST GLYPH IS CH_FULL ITSELF, NOT AN ASCII '#'.
; A "full" map cell is screen code $A0, the INVERSE SPACE -- a solid block.
; The legend used to print a literal '#' (screen code $23), which looks nothing
; like it, so the key named a symbol that appears nowhere on the screen.
; ⚠ SIXTEEN AUTOMATED CASES COULD NOT SEE THIS. test/check.py's GLYPH table
; mapped BOTH $A0 and $23 to the Python character "#", so the golden screens
; rendered the two identically and compared equal. It was found by rendering
; the screen through the real character ROM and looking at it.
s_legend:   !scr "64k map: "
            !byte CH_FULL
            !scr "=full *=lighter x=bad", 0
s_ver:      !scr "1.4", 0   ; ⚠ 3 chars at col 37: the legend must end by 35
; ⚠ Nothing told the user it never stops, or how to end it.

; ⚠ Four bytes per entry, space padded, indexed by bit*4. The designators are
; Assy 250407 ONLY -- schematic 251138, via c64-ice40-ram README §2.2.
; The matching bit labels are generated in draw_diag, not stored.
chips407:   !scr "u21 u9  u22 u10 u23 u11 u24 u12 ", 0
; ⚠ Headlines are short because the DETAIL is on the next two rows and the
; lanes are on screen already. "see data lines" told a reader to look at
; something they were already looking at.
; ⚠ No second line for the memory or data-bus verdicts: draw_diag owns rows
; 22 and 23 and says more than a sentence would. The strings that used to
; live there were dead for several commits, still costing 63 bytes of an
; engine capped at 4 KB.
s_bits:     !scr "bits", 0
; ⚠⚠ THE LABEL SAYS "LIKELY" BECAUSE THE CHIP NAME IS AN INFERENCE AND THE BIT
; NUMBER IS A MEASUREMENT. "4164  U21" reads as an instruction to desolder U21;
; "LIKELY  U21" reads as what it actually is. Carl: a user who changes the
; wrong chip on our say-so blames us, and rightly.
; ⚠ AND IT IS NOT ONLY ABOUT THE BOARD TYPE. Even on a correctly identified
; board, a failing bit means the fault is somewhere on THAT DATA LINE -- the
; DRAM is the likeliest part on it, but a dry joint, a corroded socket pin, the
; PLA or the CPU end of the line look identical to this test. Nothing in
; software can tell them apart, so nothing here may claim to.
; ⚠ The designators are identical on 326298, 250407 and 250425 -- schematic
; 251138 plus the opencbm reference, which reproduces all eight. The board
; assumption moved to the line below, which had room for it.
s_assy:     !scr "likely", 0

eng_end:
}

; ⚠ The bootstrap copies exactly eight pages. If the engine outgrows them it
; would be copied half-way and jumped into, which is not a failure mode worth
; discovering on someone else's hardware.
!if eng_end - eng_start > ENG_PAGES * $100 {
        !error "engine does not fit in the pages the bootstrap copies"
}

; ---------------------------------------------------------------------------
; ⚠ THESE STRINGS LIVE IN ROML, OUTSIDE THE ENGINE, AND THAT IS DELIBERATE.
; The engine is hard-capped at 4 KB by the I/O page and the tightest fault
; build has SIXTEEN BYTES SPARE; these three lines are 110. They sit here at
; their real $8xxx addresses instead, and because they are outside the
; !pseudopc block the engine's references to them assemble to $8xxx too.
;
; ⚠ SAFE ONLY BECAUSE THE DISPLAY RUNS WITH $01 = $37. In 8K cartridge mode
; that maps ROML at $8000-$9FFF, so the engine can read them. Nothing here may
; ever be read with $01 = $30 -- during the march $8000-$9FFF is plain RAM and
; these bytes are not there. draw_diag is only ever reached from the verdict
; path, which runs with I/O banked in.
; ⚠ The march WRITES to $8000-$9FFF as RAM; that does not touch the ROM, and
; reading with $01 = $37 returns these bytes, not what the march left.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; ⚠ MOVED OUT OF THE ENGINE, same reason and same rules as the nibble lines
; above: these are ~300 bytes of verdict and banner text in a 4 KB engine that
; had 23 spare, and every one of them is drawn ONLY from the display path,
; which runs with $01 = $37 and therefore has ROML mapped.
; ⚠ NOTHING HERE MAY BE READ WITH $01 = $30. During the march $8000-$9FFF is
; plain RAM and these bytes are not visible; the march writes over that RAM
; freely, which does not touch the ROM underneath.
; ⚠ The handover module at $3000 must not reference these either -- it runs
; with the engine marched away and does its own banking.
; ---------------------------------------------------------------------------
s_colbad:   !scr "colour ram bad - a separate chip.", 0
s_colbad2:  !scr "not a dram. causes wrong colours.", 0
s_running:  !scr "runs until you reset.", 0
s_ok:       !scr "all tests passed.", 0
s_ok2:      !scr "59,648 full + 5,886 lighter = 65,534", 0
s_databad:  !scr "data line fault.", 0
s_addrbad:  !scr "address line fault.", 0
s_addrbad2: !scr "two of a pair? suspect u13/u25/rp1/rp2", 0
s_membad:   !scr "memory fault, first bad byte at $", 0
s_allbits:  !scr "all 8 bits bad - not one chip. see pla", 0

; ⚠ These carry the BOARD ASSUMPTION that used to be the row label above, so
; nothing was lost by changing it to "likely". Max 37 chars: cleared to col 38.
s_niblo:    !scr "8x4164 assumed. 41464? d0-d3=1 chip.", 0
s_nibhi:    !scr "8x4164 assumed. 41464? d4-d7=1 chip.", 0
s_nibboth:  !scr "8x4164 assumed. 41464? 2 chips.", 0


; ===========================================================================
; The handover module. Assembled to run at $3000 and copied there by phv.
; ⚠ SELF-CONTAINED ON PURPOSE: phase B marches the engine's home out from
; under it, so this may not call a single thing that lives at $C000.
; ===========================================================================
hv_src:
!pseudopc HV_CODE {
hv_entry:
        lda #0
        sta hv_bit
        sta hv_elo
        sta hv_ehi
        sta hv_bad
        jmp p6                          ; ⚠ P6 runs first, then falls into A

; ---------------------------------------------------------------------------
; ⚠ P6 LIVES IN THIS MODULE, NOT IN THE ENGINE. The engine is capped at 4 KB
; by the I/O page and ran out; P6 was the right ~350 bytes to move because it
; is self-contained, it needs only phase / mark_page_keep / draw_errors from
; the engine (all intact when it runs), and its self-modifying code works here
; exactly as it did there -- this module is RAM too.
;
; ⚠ It could move and P7 could not: P7 marches $08-$BF, which includes this
; module's own home at $3000. A phase that marches cannot live in marched RAM.
;
; P6 -- ZERO PAGE AND THE STACK. The 501 bytes nothing else could reach.
;
; ⚠ Carl asked whether the coverage shortfall was a limitation. It was, and this was
; the part that mattered: every other excluded region gets at least P0b or
; P0c's single address-dependent pass and shows as '+', but $0000-$00F4 and
; $0100-$01FF had NOTHING run against them. They are also the most heavily
; used bytes in the machine -- a bad stack byte crashes everything and a bad
; zero-page byte corrupts almost any program, usually in a way that looks like
; some other fault entirely.
;
; ⚠ REGISTERS AND SELF-MODIFYING CODE ONLY. This phase tests the pointers and
; the stack it would otherwise be standing on, so: no (ptr),y, and NO JSR --
; the whole phase is reached and left by jmp. Self-modification is available
; because the engine runs from RAM; it is NOT available in the ROML bootstrap,
; which is why P0a and P0b are written out longhand instead.
;
; ⚠⚠ $0000 AND $0001 ARE NOT RAM. They are the CPU's data-direction register
; and banking latch. Writing a march pattern to $0001 would rearrange memory
; underneath the running program. The scan starts at $0002 on page zero.
;
; 9n rather than March B's 17n: the algorithm is written out twice over (once
; per page) because there is no pointer to walk, and the shorter march still
; covers stuck-at, transition and address-decoder faults over 510 bytes.
;
;   M0        (w P)
;   M1  up    (r P,  w ~P)
;   M2  up    (r ~P, w P)
;   M3  down  (r P,  w ~P)
;   M4  down  (r ~P, w P)
;
; ⚠⚠ NOTHING IN THIS PHASE MAY TOUCH THE STACK WHILE PAGE $01 IS UNDER TEST.
; Not jsr, not pha, not an interrupt -- every one of them writes into the page
; being marched and corrupts a cell the test has already verified. The phase
; is entered and left by jmp with a self-modified exit for exactly this
; reason, interrupts are already masked, and A is the only register that ever
; needs saving here, which is why Y is kept free.
;
; ⚠ On the FIRST failure the phase stops. Zero page or the stack being broken
; is catastrophic rather than interesting, and a census of 510 bad bytes helps
; nobody. The border goes red BEFORE the display is attempted, so if a bad
; stack strands the report, a frozen red border still says "fault here".
; ---------------------------------------------------------------------------
p6:
        lda #C_ORANGE
        sta BORDER
        sta w_phcol
        lda #5                          ; ⚠ marked running BEFORE zero page and
        jsr ph_begin                    ; the stack go under test, since this
                                        ; needs both
        lda #0
        sta w_p6bad

        lda #BANK_RAM
        sta CPUPORT

        ; ---- page $01, the stack ----
        lda #$01
        jsr p6_patch
        lda #$01
        eor #SEED
        sta w_p6seed
        eor #$ff
        sta w_p6inv
        lda #$00                        ; the whole page is RAM
        sta w_p6start
        ; ⚠⚠ jmp, NOT jsr. A jsr here leaves its return address in $01xx --
        ; the very page about to be filled with march patterns -- so the rts
        ; would return into garbage. The exit is a self-modified jmp instead.
        ; This is the trap the "no JSR" note above is about, and the first
        ; version of this phase walked straight into it and hung.
        lda #<p6_r1
        sta p6_exit+1
        lda #>p6_r1
        sta p6_exit+2
        jmp p6_run
p6_r1:

        ; ---- page $00, the zero page ----
        lda w_p6bad
        bne p6_done
        lda #$00
        jsr p6_patch
        lda #$00
        eor #SEED
        sta w_p6seed
        eor #$ff
        sta w_p6inv
        lda #$02                        ; ⚠ $0000/$0001 are the CPU port
        sta w_p6start
        lda #<p6_r2
        sta p6_exit+1
        lda #>p6_r2
        sta p6_exit+2
        jmp p6_run
p6_r2:

p6_done:
        lda #BANK_IO
        sta CPUPORT
        lda w_p6bad
        beq p6_ok
        lda #C_LTRED                    ; ⚠ red BEFORE the display is tried
        sta BORDER
        lda #$00
        ldx #3
        jsr mark_page
        lda #$01
        ldx #3
        jsr mark_page
        jmp p6_end
p6_ok:
        lda #$00
        ldx #5                          ; marched, but at 9n
        jsr mark_page_keep
        lda #$01
        ldx #5
        jsr mark_page_keep
p6_end:
        lda w_p6bad                     ; P6 stops on its first failure, so the
        sta w_phextra                   ; error delta alone could be zero
        jsr ph_end
        jsr draw_errors
        jmp hv_screen

; p6_patch -- A = page. Writes the high byte into every address operand below.
; ⚠ This is the self-modification the phase depends on. It is legal only
; because the engine was copied into RAM; the same trick in the ROML bootstrap
; would silently do nothing.
p6_patch:
        sta p6a+2
        sta p6b+2
        sta p6c+2
        sta p6d+2
        sta p6e+2
        sta p6f+2
        sta p6g+2
        sta p6h+2
        sta p6i+2
        sta p6f_rd+2
        rts

p6_run:
        ; M0  (w P)
        ldx w_p6start
p6_m0:  txa
        eor w_p6seed
p6a:    sta $0000,x
        inx
        bne p6_m0

        ; M1  up (r P, w ~P)
        ldx w_p6start
p6_m1:  txa
        eor w_p6seed
; ⚠ P6 CANNOT use the hook: `jsr` puts a return address in the stack page
; that P6 is in the middle of marching. That is the same trap that made the
; first version of this mutation report seven bad bits instead of one, and it
; is why this one site stays inline and uses Y rather than the stack.
!ifdef INJECT_ZP {                      ; mutation: one bad byte at $0140
        ; ⚠ NO pha HERE, AND THAT IS NOT A STYLE CHOICE. The first version of
        ; this mutation saved A on the stack -- while marching the stack page.
        ; The push landed in a cell the march had already verified, so instead
        ; of one wrong bit it reported seven. Y is unused by P6, so it does the
        ; work; w_p6start tells the pages apart ($00 for the stack, $02 for the
        ; zero page, which starts above the CPU port).
        cpx #$40
        bne inj_z_out
        ldy w_p6start
        bne inj_z_out
        eor #$04
inj_z_out:
}
p6b:    cmp $0000,x
        bne p6_fail
        txa
        eor w_p6inv
p6c:    sta $0000,x
        inx
        bne p6_m1

        ; M2  up (r ~P, w P)
        ldx w_p6start
p6_m2:  txa
        eor w_p6inv
p6d:    cmp $0000,x
        bne p6_fail
        txa
        eor w_p6seed
p6e:    sta $0000,x
        inx
        bne p6_m2

        ; M3  down (r P, w ~P)
        ldx #$ff
p6_m3:  txa
        eor w_p6seed
p6f:    cmp $0000,x
        bne p6_fail
        txa
        eor w_p6inv
p6g:    sta $0000,x
        cpx w_p6start                   ; ⚠ test THEN decrement: a start of $00
        beq p6_m3x                      ; would wrap dex round to $FF forever
        dex
        jmp p6_m3
p6_m3x:

        ; M4  down (r ~P, w P)
        ldx #$ff
p6_m4:  txa
        eor w_p6inv
p6h:    cmp $0000,x
        bne p6_fail
        txa
        eor w_p6seed
p6i:    sta $0000,x
        cpx w_p6start
        beq p6_m4x
        dex
        jmp p6_m4
p6_m4x:
p6_exit:
        jmp $0000                       ; ⚠ patched by the caller, see above

; ⚠ A = expected, X = index. Records, flags, and abandons the phase.
; ⚠ Leaves through the same patched exit, for the same reason.
p6_fail:
        sta w_tmp
        lda w_errlo                     ; ⚠ P6 records it too: w_p6seed is
        ora w_errhi                     ; page EOR SEED, so the page comes
        bne p6f_haveaddr                ; straight back out of it
        stx w_faddr
        lda w_p6seed
        eor #SEED
        sta w_faddr+1
p6f_haveaddr:
p6f_rd: lda $0000,x
        eor w_tmp
        ora w_bitmask
        sta w_bitmask
        inc w_errlo
        bne p6f_1
        inc w_errhi
p6f_1:  lda #1
        sta w_p6bad
        jmp p6_exit

; ---- A: the screen matrix -------------------------------------------------
hv_screen:
        ; ⚠ Re-mark P6B as the running phase. P6 lives in this module and set
        ; the phase index to its own when it started, so without this the
        ; handover's status cell was never claimed and stayed at '..' while
        ; P6's cell got the handover's verdict.
        lda #6
        jsr ph_begin
        lda #$0b                        ; blank: the matrix is about to become
        sta VICCTL1                      ; march patterns
        ldx #0
hv_stash:
        lda SCREEN,x
        sta HV_SCR,x
        lda SCREEN+$100,x
        sta HV_SCR+$100,x
        lda SCREEN+$200,x
        sta HV_SCR+$200,x
        lda SCREEN+$300,x
        sta HV_SCR+$300,x
        lda COLRAM,x
        sta HV_COL,x
        lda COLRAM+$100,x
        sta HV_COL+$100,x
        lda COLRAM+$200,x
        sta HV_COL+$200,x
        lda COLRAM+$300,x
        sta HV_COL+$300,x
        inx
        bne hv_stash

        lda #$04
        sta hv_first
        lda #$07
        sta hv_last
        jsr hv_march
        lda hv_bad
        sta hv_scrbad

        ldx #0                          ; put the display back
hv_rest:
        lda HV_SCR,x
        sta SCREEN,x
        lda HV_SCR+$100,x
        sta SCREEN+$100,x
        lda HV_SCR+$200,x
        sta SCREEN+$200,x
        lda HV_SCR+$300,x
        sta SCREEN+$300,x
        lda HV_COL,x
        sta COLRAM,x
        lda HV_COL+$100,x
        sta COLRAM+$100,x
        lda HV_COL+$200,x
        sta COLRAM+$200,x
        lda HV_COL+$300,x
        sta COLRAM+$300,x
        inx
        bne hv_rest
        lda #$1b
        sta VICCTL1

; ---- B: the engine's own 4 KB ---------------------------------------------
        ldx #0                          ; ⚠ stash the workspace FIRST: it is
hv_wst: lda WORK,x                      ; at $CF00, inside what we march next
        sta HV_WRK,x
        inx
        cpx #64
        bne hv_wst

        ; ⚠ The workspace page first, while the engine is still intact: stash,
        ; march $0300-$03FF, restore. It is separate from the engine's block
        ; because $0300 and $C000 are nowhere near each other.
        lda #0
        sta hv_bad
        lda #>WORK
        sta hv_first
        sta hv_last
        jsr hv_march
        ldx #0
hv_wr2: lda HV_WRK,x
        sta WORK,x
        inx
        cpx #64
        bne hv_wr2
        lda hv_bad
        sta hv_wrkbad

        ldx #0                          ; stash again for the engine's block
hv_wst2:lda WORK,x
        sta HV_WRK,x
        inx
        cpx #64
        bne hv_wst2

        lda #0
        sta hv_bad
        lda #$c0
        sta hv_first
        lda #$cf
        sta hv_last
        jsr hv_march
        lda hv_bad
        sta hv_engbad

        ; ⚠ Re-copy the engine from cartridge ROM. ROML is still mapped at
        ; $8000 -- nothing here ever banked it out -- so the original is
        ; simply still there to copy again.
        lda #<eng_src
        sta sptr
        lda #>eng_src
        sta sptr+1
        lda #0
        sta cptr
        lda #>ENGINE
        sta cptr+1
        ldx #ENG_PAGES
hv_ecp: ldy #0
hv_ecb: lda (sptr),y
        sta (cptr),y
        iny
        bne hv_ecb
        inc sptr+1
        inc cptr+1
        dex
        bne hv_ecp

        ldx #0                          ; workspace back
hv_wrs: lda HV_WRK,x
        sta WORK,x
        inx
        cpx #64
        bne hv_wrs

; ---- C: COLOUR RAM ---------------------------------------------------------
; ⚠ A SEPARATE 1K x 4 STATIC CHIP. It is not part of the 64 KB, no march above
; has ever touched it, and this board does not replace it. When it fails you
; get wrong colours rather than a crash, so it is routinely misdiagnosed as a
; VIC fault -- which is the whole reason to test it.
;
; ⚠ Four bits wide. The upper nibble reads back as open bus, so every compare
; masks to $0F or it would fail on healthy hardware.
;
; ⚠ Needs I/O banked in, which it is throughout this module, and the VIC is
; reading it continuously for the display -- so it is stashed and restored
; like the screen matrix was.
        ldx #0
hv_cst: lda COLRAM,x
        sta HV_COL,x
        lda COLRAM+$100,x
        sta HV_COL+$100,x
        lda COLRAM+$200,x
        sta HV_COL+$200,x
        lda COLRAM+$300,x
        sta HV_COL+$300,x
        inx
        bne hv_cst

        ; ⚠ COLOUR RAM IS A DIFFERENT CHIP. Its failures must not reach the
        ; DRAM failing-bit mask or the bad-byte count, or the classifier would
        ; name a 4164 for a fault in the 2114.
        lda hv_bit
        sta hv_savbit
        lda hv_elo
        sta hv_savlo
        lda hv_ehi
        sta hv_savhi
        lda #0
        sta hv_bad
        lda #$d8
        sta hv_first
        lda #$db
        sta hv_last
        jsr hv_cmarch
        lda hv_bad
        sta hv_colbad
        lda hv_savbit                   ; DRAM's totals, untouched by the above
        sta hv_bit
        lda hv_savlo
        sta hv_elo
        lda hv_savhi
        sta hv_ehi

        ldx #0
hv_crs: lda HV_COL,x
        sta COLRAM,x
        lda HV_COL+$100,x
        sta COLRAM+$100,x
        lda HV_COL+$200,x
        sta COLRAM+$200,x
        lda HV_COL+$300,x
        sta COLRAM+$300,x
        inx
        bne hv_crs
        lda hv_colbad
        sta w_colbad

        ; merge what the handover found into the restored counters
        lda hv_bit
        ora w_bitmask
        sta w_bitmask
        clc
        lda hv_elo
        adc w_errlo
        sta w_errlo
        lda hv_ehi
        adc w_errhi
        sta w_errhi
        lda hv_scrbad
        sta w_hvscr
        lda hv_engbad
        ora hv_wrkbad
        sta w_hveng
        jmp eng_resume

; ⚠ NOT AT THE TOP OF THE MODULE. phv enters with `jmp HV_CODE`, which lands
; on the module's FIRST byte -- so anything placed ahead of hv_entry is jumped
; into instead of it. That broke every build, not just the ones using the
; hook, because the handover runs in all of them.
!ifdef INJ_MASK {
hv_inj_hook:
        +INJHOOK
}

; ---------------------------------------------------------------------------
; hv_cmarch -- the same 9n shape over COLOUR RAM, masked to four bits.
; ⚠ Kept separate from hv_march rather than adding a mask flag to it: the mask
; belongs in every compare and every write, and a phase that silently applied
; it to DRAM would pass on a chip with a dead upper nibble.
; ---------------------------------------------------------------------------
hv_cmarch:
        jsr hv_top                      ; M0  (w P)
hc_0:   ldy #0
hc_0c:  jsr hv_cpat
        lda pval
        sta (mptr),y
        iny
        bne hc_0c
        jsr hv_nxt
        bne hc_0

        jsr hv_top                      ; M1 up (r P, w ~P)
hc_1:   ldy #0
hc_1c:  jsr hv_cpat
        lda (mptr),y
        and #$0f
!ifdef INJECT_COL { jsr hv_inj_hook }
        cmp pval
        beq hc_1k
        ldx pval
        jsr hv_fail
hc_1k:  lda pinv
        sta (mptr),y
        iny
        bne hc_1c
        jsr hv_nxt
        bne hc_1

        jsr hv_top                      ; M2 up (r ~P, w P)
hc_2:   ldy #0
hc_2c:  jsr hv_cpat
        lda (mptr),y
        and #$0f
        cmp pinv
        beq hc_2k
        ldx pinv
        jsr hv_fail
hc_2k:  lda pval
        sta (mptr),y
        iny
        bne hc_2c
        jsr hv_nxt
        bne hc_2

        jsr hv_bot                      ; M3 down (r P, w ~P)
hc_3:   ldy #$ff
hc_3c:  jsr hv_cpat
        lda (mptr),y
        and #$0f
        cmp pval
        beq hc_3k
        ldx pval
        jsr hv_fail
hc_3k:  lda pinv
        sta (mptr),y
        dey
        cpy #$ff
        bne hc_3c
        jsr hv_prv
        bne hc_3

        jsr hv_bot                      ; M4 down (r ~P, w P)
hc_4:   ldy #$ff
hc_4c:  jsr hv_cpat
        lda (mptr),y
        and #$0f
        cmp pinv
        beq hc_4k
        ldx pinv
        jsr hv_fail
hc_4k:  lda pval
        sta (mptr),y
        dey
        cpy #$ff
        bne hc_4c
        jsr hv_prv
        bne hc_4
        rts

hv_cpat:
        tya
        eor mptr+1
        eor #SEED
        and #$0f                        ; ⚠ four bits, always
        sta pval
        eor #$0f
        sta pinv
        rts

; ---------------------------------------------------------------------------
; hv_march -- 9n over hv_first..hv_last, address-dependent pattern.
; Uses the zero-page pointer, which P6 has just proven.
; ---------------------------------------------------------------------------
hv_march:
        ; M0  (w P)
        jsr hv_top
hv_0:   ldy #0
hv_0c:  tya
        eor mptr+1
        eor #SEED
        sta (mptr),y
        iny
        bne hv_0c
        jsr hv_nxt
        bne hv_0

        ; M1 up (r P, w ~P)
        jsr hv_top
hv_1:   ldy #0
hv_1c:  jsr hv_pat
        lda (mptr),y
!ifdef INJECT_HV { jsr hv_inj_hook }
        cmp pval
        beq hv_1k
        ldx pval
        jsr hv_fail
hv_1k:  lda pinv
        sta (mptr),y
        iny
        bne hv_1c
        jsr hv_nxt
        bne hv_1

        ; M2 up (r ~P, w P)
        jsr hv_top
hv_2:   ldy #0
hv_2c:  jsr hv_pat
        lda (mptr),y
        cmp pinv
        beq hv_2k
        ldx pinv
        jsr hv_fail
hv_2k:  lda pval
        sta (mptr),y
        iny
        bne hv_2c
        jsr hv_nxt
        bne hv_2

        ; M3 down (r P, w ~P)
        jsr hv_bot
hv_3:   ldy #$ff
hv_3c:  jsr hv_pat
        lda (mptr),y
        cmp pval
        beq hv_3k
        ldx pval
        jsr hv_fail
hv_3k:  lda pinv
        sta (mptr),y
        dey
        cpy #$ff
        bne hv_3c
        jsr hv_prv
        bne hv_3

        ; M4 down (r ~P, w P)
        jsr hv_bot
hv_4:   ldy #$ff
hv_4c:  jsr hv_pat
        lda (mptr),y
        cmp pinv
        beq hv_4k
        ldx pinv
        jsr hv_fail
hv_4k:  lda pval
        sta (mptr),y
        dey
        cpy #$ff
        bne hv_4c
        jsr hv_prv
        bne hv_4
        rts

hv_pat: tya
        eor mptr+1
        eor #SEED
        sta pval
        eor #$ff
        sta pinv
        rts

hv_top: lda hv_first
        sta mptr+1
        lda #0
        sta mptr
        jmp hv_cnt
hv_bot: lda hv_last
        sta mptr+1
        lda #0
        sta mptr
hv_cnt: lda hv_last
        sec
        sbc hv_first
        clc
        adc #1
        sta hv_npg
        rts
hv_nxt: inc mptr+1
        dec hv_npg
        rts
hv_prv: dec mptr+1
        dec hv_npg
        rts

; hv_fail -- A = got, X = expected. ⚠ Accumulates LOCALLY: during phase B the
; workspace is stashed and the real counters are not there to add to.
hv_fail:
        stx hv_tmp
        eor hv_tmp
        ora hv_bit
        sta hv_bit
        inc hv_elo
        bne hv_f1
        inc hv_ehi
hv_f1:  lda #1
        sta hv_bad
        rts

hv_first:  !byte 0
hv_last:   !byte 0
hv_npg:    !byte 0
hv_bit:    !byte 0
hv_elo:    !byte 0
hv_ehi:    !byte 0
hv_bad:    !byte 0
hv_scrbad: !byte 0
hv_engbad: !byte 0
hv_wrkbad: !byte 0
hv_colbad: !byte 0
hv_savbit: !byte 0
hv_savlo:  !byte 0
hv_savhi:  !byte 0
hv_tmp:    !byte 0
hv_end:
}

!if hv_end - hv_entry > HV_PAGES * $100 {
        !error "handover module does not fit in the pages phv copies"
}

        !fill $a000 - *, $ff
