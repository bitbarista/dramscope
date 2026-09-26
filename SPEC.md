# DRAMscope — engineering specification

⚠ **The name is a placeholder.** It is used consistently so it can be changed with one
`sed`, but it should be settled before anything is published.

**Status:** specification, iteration 1. No code written yet.
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

**P3. No verdict without evidence.** The classifier may only state conclusions derivable
from measurements the run actually made. See `PROVENANCE.md`, closing section.

**P4. Honest coverage claims.** Where a phase covers less than its name suggests — and P5
does — the documentation says so in the same place it makes the claim.

**P5. Degrade visibly, not silently.** If the display cannot be trusted because its own
memory is faulty, the tool must say so rather than show a plausible-looking screen.

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

⚠⚠ **THIS IS UNVERIFIED AND IT DECIDES THE ARCHITECTURE. It is gate G1 (§9) and it is the
first thing to do.** If EasyFlash mode switching does not work on KFF and U2+, the fallback
is two binaries — an Ultimax probe and a normal-mode full test — which is what the sibling
project ships today and which works, but loses the headline property.

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

### P3 — March B, address-dependent pattern · ~17 s

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

### P4 — March LR, address-dependent pattern · ~14 s

14n, six elements. **Linked faults** — two defects close enough that the write exposing one
masks the other — are outside March B's guarantee, and March LR is the published answer.

Note that at 14n it is **cheaper than March B, not dearer**. Both run; total 31n.

⚠ **Gate G3 (§9): the P/~P substitution argument must be re-made for March LR, not
inherited.** It very likely holds — LR also requires only complementary values — but this
project does not inherit proofs. Paper exercise, not a build.

### P5 — Topographical patterns · ~12 s

A 4164 is physically **256 rows × 256 columns**, and the row and column addresses *are* the
grid coordinates. Patterns structured by row-index and column-index therefore stress
physically adjacent cells in a way that a logical address sweep does not.

Patterns: row/column parity checkerboard and its inverse, row stripes, column stripes, and
single-cell-in-a-field (write a uniform value, flip one cell, verify the whole row and
column).

⚠ **Gate G2 (§9): which multiplexer half is row and which is column must be determined
first.** The sibling project deliberately never established this — its §5.3 states the
mapping need not be determined *because that design has no refresh or page-mode dependency*.
This phase is precisely that dependency.

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

### P9 — Zero page and stack

Registers-only, no `(ptr),y`, no `JSR`. With an Ultimax start these can be tested first,
before anything depends on them.

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
| 250469 | short board, 2 × 41464 |

⚠ **Gate G5 (§9): these tables must come from Commodore schematics, verified**, not from
recollection. A wrong table prints a confident instruction to replace the wrong chip, which
is the worst output this tool could produce. Until a profile is verified, report the **bit**
and say the profile is unavailable.

The tool should offer a profile selector and default to reporting bits only.

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
| **G1** | Does EasyFlash `$DE02` mode switching work mid-program on Kung Fu Flash and Ultimate II+? | The entire delivery architecture | [A] |
| **G2** | Which multiplexer half carries the row address and which the column? | P5 topographical | [A] |
| **G3** | Does the address-dependent P/~P substitution preserve March LR's linked-fault coverage? | P4 claims | [A] |
| **G4** | In Ultimax, do VIC fetches in `$3000–$3FFF` come from cartridge ROMH? | Screen home selection | [A] |
| **G5** | Bit → chip designator tables per assembly, from schematics | Chip naming in §5 | [A] |

**G1 first.** It is cheap to test and it decides whether this is one binary or two.

---

## 10. Implementation order

Each step is intended to leave something that works.

| # | Step | Leaves |
|---|---|---|
| 1 | Project skeleton, this spec, `PROVENANCE.md` | ✅ done |
| 2 | **Resolve G1** on real KFF and U2+ hardware | the architecture decided |
| 3 | Engine skeleton, P0/P1/P2, display framework, VICE harness | **already a useful tool** — bus faults named in under a second |
| 4 | P3 March B (port the proven engine) + classifier v1 + bit reporting | parity with existing tools, plus shape |
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
