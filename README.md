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
  back. ⚠ **Refresh cannot be suppressed from software on a C64** — the VIC refreshes
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
  it is everywhere, and it needs no working RAM.
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
| **P0** bring-up probe, no RAM assumed | ✅ |
| **P1** data bus — walking ones/zeroes/rails | ✅ |
| **P2** address bus — **all 16 lines, A0–A15** | ✅ |
| Display — 256-page map, bus lanes, verdict | ✅ |
| Fault injection + headless VICE harness | ✅ 14 mutations, one shared hook |
| Whole-screen golden comparison | ✅ [`test/golden/`](test/golden/) |
| **Variant matrix** — every C64 model VICE emulates | ✅ 18 model × CIA combinations |
| Gate G1 — EasyFlash mode switching | ✅ **closed** — Ultimate II+ *and* Kung Fu Flash, `$DE02 = $02` |
| EasyFlash delivery — boots in Ultimax, **needs no working RAM to start** | ✅ |
| Engine relocated to `$C000`, banks out with `$01 = $30` | ✅ |
| **P3** March B 17n, address-dependent pattern, 60,928 of 65,536 bytes | ✅ ~17 s |
| **P4** March LR 14n, **fixed** patterns — linked faults | ✅ ~11 s |
| **P5** topographical row/column patterns — physical adjacency | ✅ ~34 s |
| **P6** zero page and the stack — 9n, registers-only | ✅ |
| **P7** retention — write, dwell 12 s, verify | ✅ |
| **Burn-in** — cycles continuously, counts passes, accumulates faults | ✅ |
| **P9** colour RAM — the separate 1K × 4 chip | ✅ |
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
from the cartridge and runs with no KERNAL, no stack and no zero page required. A machine
whose low memory is dead can still be tested — which is the machine most in need of it.

**The panel is a checklist.** Every phase has a named row and a status cell — `..` not
started, a turning marker while it runs, `OK` or `X` when it finishes — so the screen answers
"what has been done to this machine, and did it pass" without anyone reading a manual:

```
 DRAMSCOPE 1.2      BAD 0000 PASS 0001
   0123456789ABCDEF P1 DATA BUS  OK
 0 **#*****########  76543210
 1 ################  ########
 2 ################ P2 ADDR BUS  OK
 …                   FEDCBA98
 8 ################ P3 MARCH B   OK
 9 ################ P4 MARCH LR  OK
 A ################ P5 TOPO      OK
 B ################ P6 ZP+STACK  OK
 C **************** P6B HANDOVER OK
 D ################ P7 DWELL     OK
 E ################ P9 COL RAM   OK
```

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
couple of times a second. ⚠ **A static border from P1 onwards means hung** — that is now
the fault report, not an ambiguity.

Border colours report even when the display cannot: white = has control, red = zero-page
scratch dead, purple = screen page dead, **orange = this device ignores `$DE02` and cannot
leave Ultimax**, blue = `$C000` dead, green = clean, light red = fault found. A black border
means the cartridge never got control at all.

## Credits

Prior art, gratefully acknowledged: **Dead Test**, **DesTest**, **DesTestMAX** and
**MAX-Switch**, and their authors' published fault reports. The bar they set is why this
specification is as demanding as it is.

Algorithms come from the published memory-test literature — van de Goor's March B and
March LR — and hardware facts from Commodore's schematics and Bauer's VIC-II reference. Every
one is traced in [`PROVENANCE.md`](PROVENANCE.md).


## Coverage — what is tested, and how deeply

**60,414 of 65,536 bytes.** The map distinguishes the depths rather than averaging them:

**65,534 of 65,536 — every byte of RAM there is**, and the verdict line prints the split
rather than rounding it to a claim: `59,648 FULL + 5,886 LIGHTER = 65,534.` The map
distinguishes depth rather than averaging it:

| Mark | Meaning | Where |
|---|---|---|
| solid | **45** operations per byte — March B 17n, March LR 14n, topographical 12n, dwell 2n | 59,648 bytes |
| `*` | **9** operations per byte | zero page, stack, screen matrix, the engine's own 4 KB — 5,630 bytes |
| `+` | probed but not yet marched | shown only *during* a run, before the handover |
| `.` | nothing | `$0000`/`$0001` — ⚠ **not RAM**, they are the CPU's DDR and banking latch |

The `*` regions get a shorter march because the test is standing on them: the engine's home
is marched by a module copied to `$3000`, which then re-copies the engine from cartridge ROM
and jumps back; the screen matrix is stashed, marched, and put back with the display
blanked.
