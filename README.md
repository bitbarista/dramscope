# DRAMscope

⚠ **Placeholder name.** Iteration 1 builds, runs and is verified; see
[`SPEC.md`](SPEC.md) for the whole plan and what is still missing.

A memory diagnostic cartridge for the Commodore 64 — for **any** C64, not for any particular
RAM replacement board.

## What it is for

Most C64 memory tests answer *"is the RAM bad?"*. This one is aimed at the three questions
that come next and are harder:

- **Is it even the DRAM?** Colour RAM is a separate 1K × 4 static chip that this tool also
  tests. When it fails you get wrong colours rather than a crash, so it is routinely
  misdiagnosed as a VIC fault. It gets its own indicator and its own verdict, and ⚠ **never
  contributes to the DRAM bit mask** — a fault there must not name a 4164.

- **Which chip?** Each 4164 supplies one bit across the whole address space, so a failing bit
  is a named chip. The tool prints, under the bit number, the designator it maps to:

  ```
   MEMORY FAULT - SEE THE RED CELLS.
   BITS                               D0
   250407                             U21
  ```

  ⚠ The designators sit under a heading naming the **assembly they belong to**, because the
  tool cannot tell which board it is plugged into. **Short boards carry two 41464s, not eight
  4164s** — four bits per chip — so a named chip there would be plain wrong, and the tool
  prints that caveat whenever it names one. The **bit number** is
  always shown and is true on every C64. And if *every* bit fails it names no chip at all —
  eight simultaneously dead DRAMs is not the likely reading, and pointing at eight chips is
  worse than pointing at none.
- **Is it actually the RAM?** A fault in the address multiplexers, their series packs, or the
  PLA looks like bad memory and is not. The tool tells them apart.
- **Why does it only fail when warm?** Marginal, leaky cells pass every fast march test and
  drop bits an hour into a session. P7 writes the whole map, waits 12 seconds, and reads it
  back (`RETENTION` on screen). ⚠ **Refresh cannot be suppressed from software on a C64** — the VIC refreshes
  unconditionally, and blanking the screen actually gives the *CPU* more cycles while
  refresh carries on unchanged. So this is retention *against a working refresh*: the cells
  it catches are the ones leaking faster than refresh at specification can sustain.
  **Temperature is the other lever and it is not a software one — run it again on a warm
  machine.**

And it shows the whole 64 KB as a live map while it works, because the *shape* of a fault —
a stripe, a quadrant, a scatter — usually says more than its address.

## What it is not

**It is not a replacement for Dead Test, and it is not a competitor to DesTestMAX.**

- **Dead Test** is still the right first move on a machine that will not boot. It is proven,
  it is everywhere, and it needs no working RAM — and being a real cartridge it is mapped by a
  cold reset rather than launched from a menu, which ⚠ **is the one thing this tool depends on
  its device for**. See the note below.
- **DesTest / DesTestMAX** are mature and thorough, and **MAX-Switch** solves the Ultimax
  4 KB ceiling properly, with hardware.

This tool is an *alternative view*, not a better one. It adds linked-fault coverage, physical
row/column patterns, retention testing and chip naming. It borrows nothing from any of them —
see [`PROVENANCE.md`](PROVENANCE.md), which is a deliberately strict policy about what may
even be looked at.

## Where it came from

It is a spin-out of [DRAMa Free 64](../c64-ice40-ram), an FPGA replacement for the eight
4164 DRAMs on a C64 Assy 250407. Building that required a memory test good enough to trust a
board with, and the result turned out to be more generally useful than the board it was
written for — in particular the **address-dependent pattern** (`value = lo XOR hi XOR seed`),
which catches address-decode aliasing that a fixed-pattern march test misses entirely.

The two projects stay separate. This one has no dependency on that board and never will.

## Status

| | |
|---|---|
| Specification | ✅ [`SPEC.md`](SPEC.md) |
| Provenance policy | ✅ [`PROVENANCE.md`](PROVENANCE.md) |
| **P0** bring-up probe, assumes no working RAM | ✅ **verified with every DRAM removed** — red screen, not a hang |
| **P1** `DATA LINES` — walking ones/zeroes/rails | ✅ |
| **P2** `ADDR LINES` — **all 16 lines, A0–A15** | ✅ |
| Display — 256-page map, bus lanes, verdict | ✅ |
| Fault injection + headless VICE harness | ✅ 14 mutations, one shared hook |
| Whole-screen golden comparison | ✅ [`test/golden/`](test/golden/) |
| **Variant matrix** — every C64 model VICE emulates | ✅ 18 model × CIA combinations |
| Gate G1 — EasyFlash mode switching | ✅ **closed** — Ultimate II+ *and* Kung Fu Flash, `$DE02 = $02` |
| EasyFlash delivery — boots in Ultimax, **needs no working RAM or KERNAL to start** | ✅ measured with the DRAMs out; ⚠ the launcher must map the cartridge without a menu |
| Engine relocated to `$C000`, banks out with `$01 = $30` | ✅ |
| **P3** `MARCH B` — 17n, address-dependent pattern, 59,648 of 65,536 bytes | ✅ ~17 s |
| **P4** `MARCH LR` — 14n, **fixed** patterns — linked faults | ✅ ~11 s |
| **P5** `ROW/COLUMN` — topographical patterns — physical adjacency | ✅ ~34 s |
| **P6** `LOW MEMORY` / `OWN MEMORY` — zero page, stack and the engine's home — 9n, registers-only | ✅ |
| **P7** `RETENTION` — write, dwell 12 s, verify | ✅ |
| **Burn-in** — cycles continuously, counts runs, accumulates faults | ✅ |
| **P9** `COLOUR RAM` — the separate 1K × 4 chip | ✅ |
| ~~P8 disturb~~ | ⚠ **declined** — a 6502 reaches ~400 row activations per refresh interval against the 10⁴–10⁵ rowhammer needs. See `SPEC.md` |
| **Chip naming** from the failing-bit mask, Assy 250407 | ✅ |
| Classification rules beyond chip naming (stride, region, mux pairing) | ⬜ |
| Board profiles for 250425 and the short boards | ⬜ |
| Verified on real hardware (Ultimate II+) | ✅ 2026-09-26 |
| Licence | ⬜ undecided |

## Building

```
bash build.sh          # clean build + every fault-injected variant
bash test/run.sh       # 13 fault-injection cases on one machine
bash test/models.sh    # the same build across every C64 variant VICE emulates
```

The two harnesses answer different questions and neither substitutes for the other:
`run.sh` proves the tool **reports faults correctly**, `models.sh` proves it **behaves
identically on every machine**. The matrix covers PAL, NTSC (both VIC revisions), PAL-N,
C64C, C64GS and the Educator 64, each against both the 6526 and 8521 CIA — and ⚠ boots one
with a **KERNAL of 8 KB of `$FF`**, which a normal autostart cartridge could not survive,
since it needs the KERNAL's own `JSR $FD02` to be handed control. Latest results:
[`docs/VARIANT-MATRIX.txt`](docs/VARIANT-MATRIX.txt).

⚠ **What simulation cannot cover, and the docs do not pretend otherwise:** VICE models the
machine, not the DRAM arrangement. A short board's two 41464s and a long board's eight
4164s look identical to it, so **chip naming can only ever be verified on real hardware**.

Needs `acme`, and VICE for `cartconv` and `x64sc`.

⚠ **The harness uses the real Commodore ROMs** and finds them wherever VICE keeps them
(`~/.local/share/vice/C64/`). They are **not** included here and must not be — they are
copyrighted. The upside of using the real KERNAL rather than a stub is that the genuine
autostart handshake runs: `JSR $FD02` pushes a return address and therefore needs the
stack page, which is this delivery vehicle's honest limit and something a stub cannot
exercise.

### What a run looks like

It is an **EasyFlash cartridge** and boots in Ultimax, so it takes the reset vector straight
from the cartridge and runs with **no working KERNAL** — proven by booting it against a KERNAL
of 8 KB of `$FF` across all 18 model × CIA combinations — and with **no working RAM**, proven
on a machine with every DRAM pulled. A machine too broken to reach BASIC can still be tested,
which is the machine most in need of it.

> ✅ **It starts and reports on a machine with every DRAM removed — measured, 2026-09-27.**
>
> On a **Kung Fu Flash**, with all eight DRAMs out of their sockets, it boots and puts up a
> **solid red screen**. `C_RED` appears at exactly one place in the source — `p0a_dead` — so
> that screen is unambiguous: the cartridge took control, found that the zero-page scratch
> would not hold a value, and reported instead of hanging. ⚠ **VICE cannot emulate a C64 with
> empty sockets, so this could only ever have been shown on the bench.**
>
> ⚠ **The launcher is part of the dependency chain, and that is the one real caveat.** KFF
> remembers the last cartridge loaded and boots straight into it, with no menu — which is what
> makes the no-RAM case reachable at all. The **Ultimate II+ menu is itself a C64 program**,
> running on the 6510 out of C64 RAM and drawing to the screen matrix in C64 RAM, so with no
> DRAM fitted it cannot run and the `.crt` cannot be reached. **The cartridge must be mapped
> without a menu.**
>
> ⚠ **And it cannot *test* memory that is not there.** The screen matrix is DRAM too, so on a
> machine with nothing fitted the only possible output is the border — the whole display in one
> colour, since `DEN=0`. "Low memory does not respond" is true and actionable; a map, a bit
> number and a chip name are not derivable without memory to test.
>
> Written up as **G6** in [`SPEC.md`](SPEC.md), together with a hypothesis it disproved: the P0
> probes were expected to possibly *pass falsely* on an undriven bus, since each writes a byte
> and immediately reads the same address back. They do not. No code change needed.



**The panel is a checklist**, headed `TESTS AND RESULTS`. Every test has a named row and a
status cell — `..` not started, a turning marker while it runs, `OK` or `X` when it finishes —
so the screen answers "what has been done to this machine, and did it pass" without anyone
reading a manual:

```
 DRAMSCOPE  RUNS $0001  BAD BYTES $0000
 ----------------------------------------
   0123456789ABCDEF TESTS AND RESULTS
 0 **#*****######## DATA LINES   OK
 1 ################  76543210
 2 ################  ########
 3 ################ ADDR LINES   OK
 …                   FEDCBA98
 8 ################ MARCH B      OK
 9 ################ MARCH LR     OK
 A ################ ROW/COLUMN   OK
 B ################ LOW MEMORY   OK
 C **************** OWN MEMORY   OK
 D ################ COLOUR RAM   OK
 E ################ RETENTION    OK
 F ################
 64K MAP: #=FULL *=LIGHTER X=BAD     1.4
 ----------------------------------------
 ALL TESTS PASSED.
 59,648 FULL + 5,886 LIGHTER = 65,534

 RUNS UNTIL YOU RESET.
```

⚠ **The phase numbers used throughout this README and in `SPEC.md` are not on the screen.**
They are the specification's identifiers; the screen names what each test *does*, because
"P5" tells a user nothing and the gap where the declined P8 would sit invited the question
"where is P8?". The mapping is in the table above.

⚠ **`RETENTION` sits below `COLOUR RAM` although it is P7 and the colour RAM is P9.** The
rows are ordered by when a test *completes*: the colour RAM is checked inside the handover
module, which finishes before the retention wait begins. A reader watching a list fill
downwards reads a gap as "that one was skipped", so the order that matters is the visible
one.

**It runs as a burn-in.** One pass takes about 80 seconds; when it finishes it counts the
pass and starts again, and keeps going until the machine is reset. Faults are **cumulative**
— a red cell stays red, **a failed phase keeps its `X`**, the bad-byte count only grows, and
once anything has failed the border pulses red instead of grey for the rest of the run.
⚠ **Passed phases do reset to `..` each pass**, so the column always shows progress through
the *current* one; only failures persist. Those are separable properties and the display
needs both. That is the point: the chip that
fails once an hour is invisible to a single pass, and it is the one people actually chase.

⚠ **On flashing and photosensitivity.** The border pulse is deliberately slow and its rate
is fixed by a CIA timer rather than by how fast the test is running: **0.94 Hz on PAL,
0.98 Hz on NTSC**, against the 3 flashes-per-second limit in WCAG 2.3.1 — a 3.2× margin,
derived from the timer chain and confirmed by sampling the emulator. The spinner changes
faster but is a single character cell, 0.1 % of the display.

**It is visibly alive while it works.** A full run is about a minute, so a spinner turns
beside the phase name and the border pulses between the phase colour and dark grey, a
couple of times a second. ⚠ **A static border once testing has begun means hung** — that is
now the fault report, not an ambiguity.

Border colours report even when the display cannot: white = has control, **red = the zero-page
scratch will not hold a value but RAM is fitted**, **slowly flashing red = nothing in
`$0000–$0FFF` responds at all, so no RAM is fitted (or the PLA is not selecting it)**, purple =
screen page dead, **orange = this device ignores `$DE02` and cannot leave Ultimax**, blue =
`$C000` dead, green = clean, light red = fault found. A black border means the cartridge never
got control at all.

⚠ **Steady red and flashing red are different repairs**, which is why they are different
signals. Both used to be steady red, sending someone to hunt for a faulty chip on a machine
whose sockets were empty. After `P0a` fails, sixteen unrolled probes — one per page of
`$0000–$0FFF`, at offset `$80` so `$0000`/`$0001` are never written, **registers only and no
pointer, because zero page has just failed by definition** — ask whether *anything* holds a
value. Something does → steady red. Nothing does → flashing red.

The flash is a slow alternation rather than a new colour, because every steady colour is
already spoken for and two of them double as running-phase colours. ⚠ **It is timed from the
raster, not from the CIA chain the running pulse uses** — the engine sets those timers up and
on this machine the engine never runs. Measured at **850,000–900,000 PAL cycles per interval**
by bracketing four intervals in emulated cycles, i.e. 0.86–0.91 s, so **0.55–0.58 Hz** against
the 3 flashes/second limit in WCAG 2.3.1 — a ≥5.2× margin, wider than the running pulse's 3.2×
on purpose, because `DEN=0` makes this fill the whole screen rather than just the border.

## Credits

Prior art, gratefully acknowledged: **Dead Test**, **DesTest**, **DesTestMAX** and
**MAX-Switch**, and their authors' published fault reports. The bar they set is why this
specification is as demanding as it is.

Algorithms come from the published memory-test literature — van de Goor's March B and
March LR — and hardware facts from Commodore's schematics and Bauer's VIC-II reference. Every
one is traced in [`PROVENANCE.md`](PROVENANCE.md).


## Coverage — what is tested, and how deeply

⚠ The figure below was **silently lost for several revisions** and is now tied to the run
table by an assembly-time `!error`, so the strings and the table cannot drift apart again.

**65,534 of 65,536 — every byte of RAM there is**, and the verdict line prints the split
rather than rounding it to a claim: `59,648 FULL + 5,886 LIGHTER = 65,534.` The map
distinguishes depth rather than averaging it:

| Mark | Meaning | Where |
|---|---|---|
| solid | **45** operations per byte — March B 17n, March LR 14n, topographical 12n, dwell 2n | 59,648 bytes |
| `*` | **9** operations per byte | zero page, stack, screen matrix, the engine's own 4 KB — 5,630 bytes |
| `X` | a bad byte somewhere in that page | wherever a fault was found |
| `-` | yellow, moving — the page under test right now | one cell, transient |
| `.` | dark grey — not reached yet | none on a finished run |

⚠ **`+` has been retired.** It marked "probed but not yet marched" and appeared only
mid-run, in a legend line with no room to explain it. An unexplained glyph on a diagnostic
screen is worse than a coarser one, so those pages now draw `*` — still true, since "lighter
than full" covers both — and keep their cyan to distinguish them for anyone who looks. The
internal state is unchanged, because it is the reason the map cannot over-claim.

⚠ **The legend used to say `.=NOT RAM`, and that was simply false.** Every one of the 256
pages is RAM and every one is tested, `$D000–$DFFF` included — marched with the I/O chips
banked out. `.` means *not reached yet*, and it is dark grey on black so that it reads as
absence. The two bytes that genuinely are not RAM are `$0000` and `$0001`, the CPU's
data-direction register and banking latch, which is why the total is 65,534 and not 65,536.

The `*` regions get a shorter march because the test is standing on them: the engine's home
is marched by a module copied to `$3000`, which then re-copies the engine from cartridge ROM
and jumps back; the screen matrix is stashed, marched, and put back with the display
blanked.
