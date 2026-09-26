# DRAMscope — engineering specification

⚠ **The name is a placeholder.** It is used consistently so it can be changed with one
`sed`, but it should be settled before anything is published.

**Status:** iteration 5 implemented and verified — EasyFlash delivery (boots in Ultimax,
needs no working RAM), engine relocated to `$C000`, P0/P1/P2 with **all sixteen address
lines**, **P3 March B 17n**, **P4 March LR 14n** and **P5 topographical patterns** over 59,904 of
65,536 bytes, plus chip naming from the failing-bit mask. Verified on an Ultimate II+ and a
Kung Fu Flash as well as in VICE. Measured end to end: 58–61 M cycles, **about 62 s on
PAL**. P6 onwards not started.
**Target:** Commodore 64, all assemblies. **Not specific to any one board or RAM replacement.**

---

## 0. What this is

A memory diagnostic cartridge for the Commodore 64 that does three things existing tools do
not do together:

1. **Tests beyond the standard march algorithms** — linked faults, physical row/column
   coupling, and retention under load.
2. **Names the faulty part**, rather than reporting an address and a bit.
3. **Shows a live map of the whole address space**, so a fault's *shape* is visible — which
   is usually more diagnostic than its address.

### What this is not

⚠ **It is not a replacement for Dead Test, and it does not compete with DesTestMAX.**

Dead Test is the right first move on a machine that will not boot: it is proven, it is
everywhere, and it needs no working RAM. DesTestMAX and MAX-Switch are mature, thorough, and
MAX-Switch's hardware mode-switching solves the 4 KB problem properly.

This tool exists to add three things to that landscape, not to displace any of it:

| | Covered by existing tools | Added here |
|---|---|---|
| Stuck-at, transition, unlinked coupling | ✅ March B | — |
| **Linked faults** | ❌ | **March LR** |
| **Physical row/column coupling** | ❌ logical addressing only | **Topographical patterns** |
| **Retention / marginal cells** | ❌ | **Dwell and disturb phases** |
| **Naming the failing chip** | ❌ | **Board profiles** |
| **Whole-map visual** | ❌ | **256-page live grid** |

Credit to prior art belongs in the README and on the title screen, and it should be
generous. See `PROVENANCE.md` for the rule about what may and may not be looked at.

---

## 1. Design principles

**P1. The runtime is itself a check.** Publish expected durations per phase. A run that
completes much faster than documented is a stale build or a skipped phase, and that has
already caught a real defect in the sibling project.

**P2. Every gate must be able to fail.** No phase ships without a fault-injection build that
proves it reports the fault it claims to catch. A test that cannot fail is decoration.

⚠⚠ **AND EVERY ASSERTION MUST BE READ.** `test/check.py` once populated its observed values
inside a conditional and then compared by iterating the **observed** dictionary — so a case
that asserted a key the reader never filled had that assertion silently dropped. Five cases
were affected and one of them was hiding a genuinely broken mutation for four commits. The
comparison now iterates the **expected** dictionary, and every key has a reader, so an
assertion that is not read is a `KeyError` rather than a pass.

**P3. No verdict without evidence.** The classifier may only state conclusions derivable
from measurements the run actually made. See `PROVENANCE.md`, closing section.

**P4. Honest coverage claims.** Where a phase covers less than its name suggests — and P5
does — the documentation says so in the same place it makes the claim.

**P5. Degrade visibly, not silently.** If the display cannot be trusted because its own
memory is faulty, the tool must say so rather than show a plausible-looking screen.

**P7. One pass is a spot check; a burn-in is a test.** ⚠ Carl, 2026-09-26: *"the RAM test
runs once only. Typically ram tests have a burn in whereby they cycle and count the number
of cycles."* The phases loop back to P1 rather than halting, and every result is cumulative:
the map's red cells, the bad-byte count and the failing-bit mask all persist, and the
liveness pulse turns red permanently once anything has failed. ⚠ **Each phase used to zero
its own results on entry** — correct for a single run, and wrong the instant it looped,
because pass two wiped pass one's findings. The counters are now cleared exactly once, in
`eng_start`.

**P8. ⚠ THE FLASH RATE IS A SAFETY REQUIREMENT, NOT A DESIGN PREFERENCE.**
Carl, 2026-09-26: *"we don't want to risk it affecting anyone with epilepsy."* WCAG 2.3.1
allows at most **three flashes per second** in anything occupying more than 25 % of the
visual field, and the C64 border qualifies. Both liveness indicators are therefore driven by
a **CIA timer, not by a tick count**, so the rate cannot vary with how fast a phase happens
to run:

| | |
|---|---|
| CIA2 timer A, latch `$FFFF` on φ2 | underflows every 65,536 cycles |
| CIA2 timer B counts those underflows | bit 3 flips every 8 decrements |
| One full on/off cycle | 1,048,576 cycles |
| **PAL** | 1.064 s → **0.94 Hz** |
| **NTSC** | 1.025 s → **0.98 Hz** |
| WCAG limit | 3.00 Hz — **3.2× margin** |

⚠ **The previous tick-based version measured 1.81 Hz** in P4/P5 and calculated near 2.5 Hz
in P7's short passes, with nothing in the design stopping a future phase from crossing 3 Hz.
That is the failure mode this replaces: not a rate that was wrong, but a rate that was
unbounded.

The spinner runs at 7.5 changes/s but occupies **one character cell — 0.1 % of the display**,
far below the 25 %-of-field threshold, and is a shape change rather than a luminance flash.

**P6. A working run must not look like a hung one.** ⚠ Carl, 2026-09-26: *"whilst the crt
is running it is impossible to know whether it is proceeding or crashed."* A run takes about
a minute and the marches spend ~20 s stretches with nothing on screen changing. Every long
phase therefore drives a spinner and a border pulse, and a **static border from P1 onwards
is itself the fault report**. The harness asserts the tick counter is non-zero, because the
final phase text blanks the spinner cell and the screen alone cannot prove it ever ran.

---

## 2. The two problems that shape the architecture

### 2.1 The screen is made of the thing under test

The VIC fetches its character matrix — 1000 bytes — from DRAM. Anything displayed therefore
occupies memory that cannot simultaneously be under test. This is the same trap that
produced **ERRATA F-16** in the sibling project, where the test could not test the block it
was running from.

Three facts make it tractable:

- **Colour RAM (`$D800–$DBFF`) is a separate 1K × 4 static chip.** It is not part of the
  64 KB, it is not under test, and it is always available. **A display encoded in colour
  keeps working even over a region whose character matrix is full of test patterns.**
- **The character generator is ROM**, fetched by the VIC at `$1000–$1FFF` and `$9000–$9FFF`
  of its own address space. No DRAM required.
- **The matrix pointer moves.** `$D018` bits 7–4 place it on any 1 KB boundary within the
  current VIC bank; CIA2 `$DD00` bits 0–1 select the bank. 64 possible homes.

⚠ **Char ROM appears only in VIC banks 0 and 2.** Banks 1 and 3 would need a character set
in RAM — more DRAM, for no gain. So screen homes are restricted to `$0000–$3FFF` and
`$8000–$BFFF`.

⚠ **A screen home under the cartridge is free real estate.** The VIC always reads RAM and
never sees cartridge ROM, so a matrix at, say, `$8400` displays correctly while the CPU sees
cartridge ROM at `$8000`. Bank 2 is the natural second home.

**The resulting display strategy:**

| Stage | Display | Tests |
|---|---|---|
| **Blind** | border colour only | screen home A, and whatever the engine needs |
| **Visual** | full, matrix at home A | everything except home A |
| **Handover** | full, matrix moved to home B | home A |

Home A is in bank 0, home B in bank 2. The blind stage is about a second; everything after
it is visible.

### 2.2 Reaching all 64 KB without needing RAM to start

A normal autostart cartridge needs the stack page, because the KERNAL's reset does
`JSR $FD02` to look for the CBM80 signature. A machine with a dead stack page dies *before*
the cartridge gets control. That is not hypothetical — it is exactly what a failing board
did in the sibling project, and why `maxtest` was written.

Ultimax mode removes every prerequisite: the cartridge supplies the reset vector at `$FFFC`
and the 6510 runs straight from ROM with no KERNAL, no stack and no zero page. **But Ultimax
maps only `$0000–$0FFF` of RAM**, which is the 4 KB ceiling every Ultimax-based tool hits.

**The intended answer: start in Ultimax, then switch.** The EasyFlash control register at
`$DE02` drives GAME/EXROM under software control, and both Kung Fu Flash and Ultimate II+
emulate EasyFlash because commercial titles depend on it. If that emulation is faithful, the
tool boots needing no RAM at all, tests low memory unaided, then switches to 8K/16K mode to
reach the other 60 KB — matching MAX-Switch's capability **on hardware people already own**.

✅ **ANSWERED ON HARDWARE, 2026-09-26 — Ultimate II+ reports `DE02=02 SWITCHED, CART STILL
MAPPED`.** `$02` asserts EXROM with GAME released, i.e. 8 K cartridge mode: ROML stays at
`$8000–$9FFF` and everything else is RAM. So the tool boots in Ultimax needing **no working
RAM at all**, proves low memory unaided, then switches and reaches the other 60 KB — on
hardware people already own. Measured with `src/g1probe_roml.asm`, which sweeps all eight
register values rather than assuming one, so the result carries no assumption.

✅ **Kung Fu Flash reports identically** (2026-09-26). Two independent devices agree, so the
delivery vehicle is settled.

⚠ **The visible failure path stays anyway.** Two devices are not every device, and a future
cartridge that ignores `$DE02` must say so with an orange border rather than hang. The
`INJECT_NOEF` mutation keeps that path honest — it is now the only one of the five that
tests something no device in hand does.

---

## 3. Execution model

| Mode | Code runs from | RAM needed | Reaches |
|---|---|---|---|
| Ultimax | ROMH `$E000–$FFFF` | **none** — registers only, no stack, no zero page | `$0000–$0FFF` |
| 16K | ROML `$8000–$9FFF` | engine workspace only | all, banking via `$01` |
| Relocated | tested RAM | the region it sits in | regions under the cartridge |

Rules carried from the sibling project's engine, all of which were learned the hard way:

- ⚠ **Write the `$01` latch before making the pins outputs.** At reset the CPU port's DDR is
  0 and the pins float high, reading as mode `$37`. Writing `$00` to `$00` first makes them
  outputs driving the latch's power-on `$00` — mode `$30`, cartridge banked out, machine
  dead mid-instruction.
- **Registers and self-modifying code** in any phase that tests zero page or the stack.
- **The first instruction sets a visible border colour**, so "black screen" can only mean the
  cartridge never got control — never that it started and hung.
- **Every phase changes the border**, so the last colour shown localises a hang even with no
  display.

---

## 4. Test phases

Ordered cheapest-and-most-diagnostic first, because a shorted data line makes every later
result confusing and should be named in the first millisecond rather than inferred from a
thousand march failures.

### P0 — Bring-up probe · no RAM required

Ultimax, registers only. Proves the machine executes and that *some* RAM responds at all.
Border-coded, readable across a room. Equivalent in role to the sibling project's `maxtest`.

**Always runs first. Always runs, even if everything else is skipped.**

### P1 — Data bus integrity · instant

Walking 1s and walking 0s across D0–D7 at a single address, plus complements.

Catches stuck, shorted and open data lines immediately, and distinguishes them:

| Observation | Verdict |
|---|---|
| One bit never changes | stuck-at on that line |
| Two bits always track each other | shorted pair |
| One bit follows the last value written to another | coupled / open |

### P2 — Address bus integrity · instant

Write a distinct signature to `$0000` and to each power-of-two address (`$0001`, `$0002`,
`$0004` … `$8000`), then read all back. Any address line that is stuck, open or shorted
produces aliasing, and **which** addresses alias identifies **which** line.

⚠ **This is where the multiplexers show up.** `An` and `An+8` share `MAn` through U13/U25,
so a failure that implicates both members of a pair points at the multiplexer or its 330 Ω
series pack rather than at a RAM chip. That distinction is worth a great deal to whoever is
holding the soldering iron.

### P3 — March B, address-dependent pattern · ✅ **implemented; measured 16.5–16.8 M cycles, ~17 s PAL**

17n, five elements, as proven in the sibling project:

```
M0  ⇕(w P)
M1  ⇑(r P, w ~P, r ~P, w P, r P, w ~P)
M2  ⇑(r ~P, w P, w ~P)
M3  ⇓(r ~P, w P, w ~P, w P)
M4  ⇓(r P, w ~P, w P)
```

⚠ **`P` is address-dependent**: `lo XOR hi XOR seed`, not a fixed 0/1. March B requires only
two *complementary* values, so the substitution preserves the algorithm exactly while adding
address-decoder coverage that a textbook fixed-pattern March B does not have. A read from
the wrong address returns the wrong value.

Covers: SAF, TF, unlinked CFin/CFid/CFst, AF.

⚠ **THREE REGIONS ARE NOT MARCHED, AND THE MAP DISTINGUISHES THEM RATHER THAN HIDING IT:**
`$0000–$01FF` (zero page and stack, the engine uses both), `$0400–$07FF` (screen matrix and
workspace) and `$C000–$CBFF` (the engine). That is 4,608 bytes, so **60,928 of 65,536 are
marched** and the verdict line prints the figure. `$0400–$07FF` and `$C000–$CFFF` *are*
probed by P0b/P0c with a single address-dependent write/verify pass — a real test, but not
17n — so they paint as **`+` probed**, never as a solid marched cell. Reaching the rest needs
a second pass with the engine and display relocated.

⚠ **Marched per contiguous run, not per page**, so coupling faults *between* pages within a
run are covered. The runs are simply what the exclusions leave: `$02–$03`, `$08–$BF`,
`$CC–$FF`.

**Measured runtime**, by bisecting `-limitcycles` until the border goes green: not yet done
at 16.5 M cycles, done by 16.8 M. That is **271 cycles per byte, 15.9 per operation** — close
to the sibling project's independently measured 15.03, which is a useful cross-check that
nothing silly is happening in the inner loop.

### P4 — March LR, **fixed patterns** · ✅ **implemented; ~11 s**

14n, six elements. **Linked faults** — two defects close enough that the write exposing one
masks the other — are outside March B's guarantee, and March LR is the published answer.

Note that at 14n it is **cheaper than March B, not dearer**. Both run; total 31n, measured
end to end at 26–28 M cycles, about 28 s on PAL.

⚠ **Gate G3 ANSWERED, and not the way it was expected to go: the substitution is NOT used
here.** The "only two complementary values are needed" argument holds for single-cell fault
classes but **not for coupling faults**, which are detected only when the aggressor
transitions *while the victim holds a particular value* — a coincidence a fixed-pattern
march guarantees by construction and an address-dependent one does not. So **March LR runs
with fixed `$00`/`$FF`**, where the published linked-fault proof holds exactly as written,
and March B keeps the address-dependent pattern for the decoder coverage it was introduced
for. Full reasoning in `PROVENANCE.md`.

### P5 — Topographical patterns · ✅ **implemented; ~34 s**

A 4164 is physically **256 rows × 256 columns**, and the row and column addresses *are* the
grid coordinates. Patterns structured by row-index and column-index therefore stress
physically adjacent cells in a way that a logical address sweep does not.

Patterns: row/column parity checkerboard and its inverse, row stripes, column stripes, and
single-cell-in-a-field (write a uniform value, flip one cell, verify the whole row and
column).

✅ **Gate G2 ANSWERED: ROW = A0–A7, COLUMN = A8–A15**, from Bauer §3.13 — the refresh
counter generates *"256 DRAM row addresses"* and its table puts `REF7..REF0` on bits 7..0.

⚠ **This inverts the intuitive reading.** A DRAM *row* is one byte offset taken across all
256 pages, so physically row-adjacent cells are **256 bytes apart**; a DRAM *column* is a
single page, so column-adjacent cells are **1 byte apart**. The patterns are built from that,
not from address order.

⚠⚠ **HONEST LIMIT, AND IT MUST BE STATED WHEREVER THE CLAIM IS MADE.** This covers row and
column adjacency **as addressed**. It does **not** model true die layout. Real 4164 dies use
address scrambling, array folding and true/complement bitlines that differ by manufacturer
and die revision, and that information is proprietary layout data absent from every
datasheet. A C64 contains whatever chips the factory fitted or a repairer replaced, often
mixed. **A confidently wrong physical map is worse than none**, because it claims adjacency
coverage it is not delivering. So: no per-manufacturer scrambler, and no claim of one.

### P6 — Retention / dwell · configurable

Write the full address-dependent pattern, let real time pass, verify.

⚠⚠ **REFRESH CANNOT BE SUPPRESSED FROM SOFTWARE ON A C64, AND ANY DESIGN THAT ASSUMES
OTHERWISE IS WRONG.** The VIC performs 5 refresh cycles per raster line unconditionally —
78,000/s PAL, 78,600/s NTSC, computed from raster geometry with no display-state term.
`DEN=0` suppresses badline character fetches and sprite fetches; refresh is not a badline
activity and continues regardless.

The irony is that blanking does the *opposite* of what a refresh-starvation design wants:
removing badlines gives the **CPU** more cycles, so the dwell loop runs faster while refresh
carries on unchanged.

**So this phase tests retention against a working refresh** — it catches cells so leaky they
fail even with refresh at specification. That is exactly the marginal chip that passes every
fast march and drops bits an hour into a warm session, and nothing else catches it.

Dwell configurable: 30 s / 2 min / 10 min. **The documentation should tell users to run it
on a warm machine**, because temperature is the other lever and it is not a software one.

### P7 — Disturb · bounded, configurable

Hammer one row with repeated accesses while its neighbours hold a known pattern, then verify
the neighbours. A proto-rowhammer: it stresses coupling and weak cells under access load
rather than under time.

### P8 — Colour RAM · instant

`$D800–$DBFF`, 4 bits wide, a separate static RAM chip. Needs no working DRAM, and fails
often enough to matter — and when it does you get wrong colours rather than a crash, so it
is routinely misdiagnosed as a VIC fault.

⚠ Mask reads to 4 bits; the upper nibble is open bus.

### P6 — Zero page and the stack · ✅ **implemented**

Registers-only and self-modifying, 9n rather than 17n because there is no pointer to walk
with and no room to write the long march out twice.

⚠⚠ **Nothing in the phase may touch the stack while page `$01` is under test** — not `JSR`,
not `PHA`, not an interrupt. Each writes into the page being marched and corrupts a cell the
test has already verified. The phase is entered and left by `jmp` with a self-modified exit
for that reason. Both traps were hit during development: the first version used `jsr p6_run`
and hung when the return address was overwritten, and the first fault-injection used `PHA`
and reported seven bad bits instead of one.

⚠ **`$0000` and `$0001` are not RAM** — the CPU's data-direction register and banking latch.
The scan starts at `$0002`.

---

## 5. The classification engine

**This is the feature that makes the tool useful rather than merely thorough**, and it is
mostly bookkeeping rather than new science. The phases above already generate the evidence;
today nothing interprets it.

Rules, evaluated in order — first match wins:

| Evidence | Verdict |
|---|---|
| P1 fails | **Data line fault.** Name the bits and whether stuck, shorted or coupled |
| P2 fails, implicating both members of an `An`/`An+8` pair | **Address multiplexer or series pack** — U13/U25, RP1/RP2 |
| P2 fails on a single line | **Address line fault.** Name the line |
| Every bit fails at every address | **Not a RAM chip.** Suspect PLA/CASRAM, or no RAM fitted |
| One bit lane fails across ≥2 distinct regions | **Single DRAM chip.** Name it from the board profile |
| Failures at a regular address stride | **Decoder / aliasing.** Name the implicated address bit |
| Failures confined to one page or small region | **Localised cell fault.** Report addresses |
| P3/P4 pass, P6 fails | **Retention — leaky cells.** Name the chip. Marginal, will worsen warm |
| P3/P4/P6 pass, P5/P7 fail | **Coupling.** Name the bit and the neighbourhood |
| Colour wrong, memory clean | **Colour RAM chip** |

### Board profiles

Chip naming is a lookup from **data bit → designator**, per motherboard assembly. Held as a
data table, not code, so profiles can be added without touching the engine.

| Assembly | Notes |
|---|---|
| 250407 | 8 × 4164, U9–U12 and U21–U24 |
| 250425 | 8 × 4164, different bank geometry |
| 250469 and relatives | ⚠ **short board — TWO 41464s, 64K × 4.** Each chip carries **four** bits, so a failing bit narrows to one of two chips and no further, and the 250407 designators are simply wrong there. Carl, 2026-09-26. |

✅ **250407 is verified and implemented** — `D0=U21, D1=U9, D2=U22, D3=U10, D4=U23, D5=U11,
D6=U24, D7=U12`, from schematic 251138 via `c64-ice40-ram` README §2.2. The other two
profiles are not, and until they are the tool must not name a chip for them.

⚠ **These tables must come from Commodore schematics, verified**, not from
recollection. A wrong table prints a confident instruction to replace the wrong chip, which
is the worst output this tool could produce. Until a profile is verified, report the **bit**
and say the profile is unavailable.

The tool should offer a profile selector and default to reporting bits only.

⚠ **Until a selector exists, a named chip carries the short-board caveat on screen** —
`SHORT BOARD? 2X41464 - NAMES DIFFER.` — printed in place of the legend, because the legend
matters most when nothing is wrong and this matters most when the tool is telling someone
which part to desolder.

---

## 6. Display design

```
+--------------------------------+-------------+
|  page map   16 x 16            | D0 . . . .  |
|  row = high nibble             | D1 . . . .  |
|  col = low  nibble             | ...         |
|  each cell = one 256-byte page | D7 . . . .  |
|                                |             |
|                                | PHASE  4/9  |
|                                | PASS      2 |
|                                | ERRORS    0 |
|                                | TIME   0:47 |
+--------------------------------+-------------+
| verdict / error log                          |
+----------------------------------------------+
```

- **The 16 × 16 grid is the address space.** Row is the high nibble of the page number,
  column the low nibble; top-left is `$0000`, bottom-right is `$FF00`. A fault's *shape* —
  a stripe, a quadrant, a scatter — is visible at a glance and is usually more diagnostic
  than its address.
- **State by glyph *and* colour**, never colour alone: `.` untested, `-` testing, solid
  pass, `X` fail. Colour-blind readers and monochrome monitors both exist.
- ⚠ **The colour layer must carry the map on its own.** Colour RAM is a different chip, so
  if the matrix region itself develops a fault the glyphs go to garbage while the colours
  stay correct. Design for that degradation deliberately — and per principle P5, say on
  screen that the display is suspect rather than showing a plausible-looking lie.
- **No KERNAL, no BASIC.** Direct writes, screen codes not PETSCII.

---

## 7. Runtime budget

Measured baseline from the sibling project: **255.6 cycles per byte for 17n March B**, i.e.
**15.0 cycles per operation**, on a PAL machine at 0.985 MHz.

| Phase | Ops | Estimate |
|---|---|---|
| P0 probe | — | instant |
| P1 data bus | ~64 | instant |
| P2 address bus | ~34 | instant |
| P3 March B | 17n = 1.11 M | **~17 s** |
| P4 March LR | 14n = 0.92 M | **~14 s** |
| P5 topographical | ~12n | **~12 s** |
| P6 dwell | 2n + T | **T + 2 s** |
| P7 disturb | bounded | configurable |
| P8 colour RAM | 1 KB | instant |
| **Full run, no dwell** | | **~45 s** |
| **Full run, 60 s dwell** | | **~1 min 50 s** |

Per principle P1, publish these. A run that greens in 20 s has skipped something.

---

## 8a. Verification across the family

⚠ **Carl, 2026-09-26: *"it really needs a thorough simulation test, on various C64
variants."*** Until then the tool had run on exactly two machines — VICE's default PAL C64
and one Ultimate II+ / Kung Fu Flash — and several things it depends on are not constant
across the family: raster geometry (P7 waits on line `$80`), φ2 frequency (the dwell and the
flash rate), and the CIA revision (which now *is* the flash rate).

`test/models.sh` runs a complete pass on every model VICE emulates, against both CIAs:

| | |
|---|---|
| Models | c64, c64c, c64old, ntsc, newntsc, oldntsc, drean (PAL-N), c64gs, pet64 |
| CIA | 6526 and 8521 |
| Assertion | identical outcome — GREEN, 0 errors, map row 0 `**#*****########`, PASSES 0001 |

Two cases earn their place beyond the sweep:

- ⚠ **A KERNAL of 8 KB of `$FF`.** The cartridge boots in Ultimax and supplies its own reset
  vector, so it should never execute a KERNAL byte. That is a *claim*, and this is what
  tests it — a normal autostart cartridge cannot survive it, because it needs the KERNAL's
  own `JSR $FD02` to be handed control.
- ⚠ **The MAX Machine.** 2 KB of RAM and no `$C000`, so the engine has nowhere to live. It
  must **report a fatal border code and hold it**, not hang. It reports ORANGE — the check
  that it failed to leave Ultimax — which is correct and legible.

⚠ **Several models name a KERNAL image not installed here, and VICE refuses to initialise
without one.** The stock ROM is substituted so the run can proceed; the cartridge never
executes it, and what those models actually change — the VIC-II and CIA revisions — is
unaffected. ⚠ **A machine VICE cannot start is reported as SKIPPED, never as a failure.**
Reporting a missing ROM as a defect in the cartridge would be a lie, and the harness checks
for it explicitly.

⚠⚠ **WHAT SIMULATION CANNOT COVER.** VICE models the machine, not the DRAM arrangement. A
short board's two 41464s and a long board's eight 4164s are indistinguishable to it, so
**chip naming can only ever be verified on real hardware** — and the short-board caveat on
screen exists precisely because no amount of simulation will catch that error.

## 8. Verification

⚠ **A RAM test that cannot fail is worthless, and this is not a hypothetical concern** — the
sibling project shipped a test that could not test the block it ran from, and only found out
by mutation-testing it (ERRATA F-16).

Every phase ships with:

1. **A fault-injection build** that deliberately breaks the thing the phase claims to catch —
   a stuck bit, an aliased address line, a cell that decays after N frames, a coupled pair.
2. **A headless VICE harness** that runs both builds and asserts clean-passes and
   fault-reports. Pattern already established in the sibling project's `diag/test.sh`.
3. **A recorded expected runtime**, checked by the harness.

⚠ **Debian's VICE is the `+dfsg` build with Commodore's ROMs stripped.** The harness must
supply stub ROMs, as the sibling project does. Note the caveat: a stub KERNAL is not a real
one, so anything depending on genuine KERNAL behaviour cannot be verified this way.

**The classifier needs its own fault injection.** It is the component most likely to be
confidently wrong, and a wrong verdict is worse than no verdict. Every rule in §5 needs a
synthetic failure set that triggers it and a neighbouring set that does not.

---

## 9. Gates — things that must be answered before the code they block

| Gate | Question | Blocks | Tag |
|---|---|---|---|
| ~~**G1**~~ | ✅ **CLOSED. Ultimate II+ and Kung Fu Flash both: `$DE02 = $02`** (2026-09-26, measured on both). | — | [M] |
| ~~**G5**~~ | ✅ **CLOSED for Assy 250407** — the bit→designator table is confirmed from schematic 251138. Other assemblies remain [A]. | — | [D] |
| ~~**G2**~~ | ✅ **ANSWERED: row = A0–A7, column = A8–A15** (Bauer §3.13). | — | [C] |
| ~~**G3**~~ | ⚠ **ANSWERED: no, not provably.** March LR therefore uses fixed patterns. See `PROVENANCE.md`. | — | [M] |
| **G4** | In Ultimax, do VIC fetches in `$3000–$3FFF` come from cartridge ROMH? | Screen home selection | [A] |
| **G5** | Bit → chip designator tables per assembly, from schematics | Chip naming in §5 | [A] |

**G1 first.** It is cheap to test and it decides whether this is one binary or two.

---

## 10. Implementation order

Each step is intended to leave something that works.

| # | Step | Leaves |
|---|---|---|
| 1 | Project skeleton, this spec, `PROVENANCE.md` | ✅ done |
| 2 | **Resolve G1** on real KFF and U2+ hardware | ✅ closed — both devices, `$DE02=$02` |
| 3 | Engine skeleton, P0/P1/P2, display framework, VICE harness | ✅ done — **already a useful tool**, bus faults named in under a second |
| 3b | EasyFlash delivery, engine relocated, A15 closed | ✅ done — **no working RAM needed to start** |
| 4 | P3 March B + bad-byte count + failing-bit mask | ✅ done — parity with existing tools, plus shape |
| 4b | Chip naming from the bit mask, Assy 250407 | ✅ done — and it refuses to name when all 8 bits fail |
| 5 | P4 March LR, fixed patterns (G3 answered first) | ✅ done |
| 6 | P5 topographical patterns (G2 answered first) | ✅ done |
| 6b | P6 dwell / retention | ⬜ **next** |
| 6c | The remaining classifier rules in §5 (stride, region, mux pairing) | ⬜ |
| 5 | Board profiles (G5) → chip naming | the headline feature |
| 6 | P4 March LR (G3 first) | linked faults |
| 7 | G2, then P5 topographical | physical coupling |
| 8 | P6 dwell, P7 disturb | marginal chips |
| 9 | P8 colour RAM | the commonly-misdiagnosed chip |
| 10 | Docs, credits, licence, release | something the community can use |

⚠ **Step 3 is the first release candidate.** A tool that instantly names a shorted data line
or a dead address line, with a live map, is already worth having even with no march test at
all. Do not hold the release for step 8.

---

## 11. Open decisions for Carl

- **The name.** `DRAMscope` is a placeholder used consistently throughout.
- **Licence.** Needs choosing before anything is public. The provenance position is
  independent of the licence, but a permissive licence makes the "not derived from" claim
  easier for others to rely on.
- **Scope of board support.** 250407 only at first, or profiles from the start?
- **Does this ever ship on the DRAMa Free 64 board itself?** The sibling project's
  DEFERRED 14 wants a diagnostic injected into the C64 from the FPGA. The same engine could
  serve both — a `.crt` for everyone, an injected copy for board owners — but that coupling
  should be a deliberate decision, not a drift.
