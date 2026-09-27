# DRAMscope

A memory diagnostic cartridge for **any** Commodore 64.

<div align="center">

![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-Commodore%2064-4a3aff)
![Cartridge](https://img.shields.io/badge/cartridge-EasyFlash-8b5cf6)
![Version](https://img.shields.io/badge/version-1.6-0369a1)
<a href="https://ko-fi.com/bitbarista" target="_blank"><img src="https://img.shields.io/badge/Ko--fi-Support%20the%20Project-FF5E5B?logo=ko-fi&logoColor=white" alt="Support on Ko-fi"></a>

</div>

It boots from the cartridge in Ultimax mode with its own reset vector, so it needs **no
working KERNAL and no working RAM to start** — verified on a machine with every DRAM pulled
from its sockets. It tests every byte of RAM, names the failing data bit and,
where it can do so safely, the chip that carries it.

**[What it can do, what it cannot, and how much of that is
proven](#-what-it-can-do-what-it-cannot-and-how-much-of-that-is-proven)** sets out every claim
with the evidence behind it, and says which results come from an emulator and which from a real
machine. Worth a minute before you act on a result.

## Running it

1. **[Download `dramscope.crt`](https://github.com/bitbarista/dramscope/releases/latest/download/dramscope.crt)** — always the current version.
2. Put it on an **Ultimate II+**, **Kung Fu Flash** or other EasyFlash-capable cartridge and
   start it.
3. It runs continuously until you reset the machine, counting completed runs.
4. **[Download the bench sheet](https://github.com/bitbarista/dramscope/releases/latest/download/READ-ME-FIRST.txt)**
   and **[the printable chip chart (PDF)](https://github.com/bitbarista/dramscope/releases/latest/download/CHIP-CHART.pdf)** —
   every colour, every mark on the map, and the bit→chip table for all five board assemblies.

> ### ⚠ Set it up **before** you need it
>
> Both devices can boot straight into the cartridge with no menu — **and both have to be told
> to, on a machine that still works.**
>
> - **Ultimate II+** — use **Copy to Flash**. The `.crt` is copied into the device's own flash
>   and loads on restart.
> - **Kung Fu Flash** — it boots the last cartridge you selected.
>
> ⚠ **Either way the menu is a C64 program**: it runs on the 6510, holds its state in C64 RAM
> and draws to the screen matrix in C64 RAM. On a machine with no working RAM you cannot reach
> it. **So arm the device while the machine is healthy** — that is what makes DRAMscope
> available later, when it is not.

## What it runs on

⚠ **It is an EasyFlash cartridge, not a plain ROM image**, and that is not a packaging choice —
it is the whole reason the tool can do what it does.

It boots in **Ultimax** mode, which is the only mode where the *cartridge* supplies the reset
vector at `$FFFC` instead of the KERNAL. That is what lets it start with no working KERNAL and
no working RAM. But Ultimax maps only `$0000–$0FFF` of RAM, so it would be stuck testing 4 KB.
Writing `$02` to the EasyFlash control register at **`$DE02`** releases GAME, leaving Ultimax
for 8 K mode with the cartridge still at `$8000` — and the other 60 KB becomes reachable.

| Hardware | Works? |
|---|---|
| **Ultimate II+** | ✅ confirmed on hardware — `$DE02 = $02`, measured |
| **Kung Fu Flash** | ✅ confirmed on hardware, reports identically |
| **A real EasyFlash 1 or 3** | ✅ expected — this is exactly the hardware `$DE02` belongs to, and flashing one gives you a **dedicated test cartridge**. Untested by us; please report. |
| Other EasyFlash-capable carts | ✅ expected if the `$DE02` emulation is faithful. Untested. |
| Action Replay, Retro Replay, Final Cartridge III, MMC Replay … | ⚠ **the hardware can do it, this build cannot.** See below. |
| ⚠ **A plain EPROM cartridge** | ❌ **not fully.** See below. |

### ⚠ EasyFlash is not the only cartridge that can do this

**The requirement is a software-settable GAME line, and EasyFlash is one implementation of
that, not the only one.** Several cartridges expose GAME and EXROM in a control register:

| Cartridge | Register |
|---|---|
| **EasyFlash** | `$DE02` — what this build uses |
| **Final Cartridge III** | `$DFFF`, **bit 4 = EXROM, bit 5 = GAME** |
| **Action Replay / Retro Replay / MMC Replay** | control register in `$DE00`–`$DE01` |

⚠ **And in hardware it is genuinely small.** A software-controllable cartridge is, at its
core, a single **74LS273** octal flip-flop with its inputs on the data bus, two of its outputs
driving GAME and EXROM, and its clock from an I/O-area decode **[S5][S11]**. So "you need an EasyFlash" is
too strong: a homebrew cartridge needs two 8 KB ROM windows, Ultimax strapping at reset, and
**one latch**.

⚠ **What this build cannot do is speak to any of them but EasyFlash.** It writes `$02` to
`$DE02`. Supporting Final Cartridge III would mean a different address and different bit
meanings, and choosing between them at runtime is not free — see below.

### ⚠ Why it does not simply try every known register

`g1probe` can sweep registers safely because **it copies itself to RAM at `$0200` first**. A
wrong write can bank the cartridge out from under the CPU, and code running from ROM would die
mid-instruction — indistinguishable from "the register did nothing".

DRAMscope has no such luxury. It runs from ROM, in Ultimax, on a machine whose RAM may not
work at all — that is the entire point of it. A speculative write to an unknown register could
unmap `ROML` mid-instruction and hang with no way to report anything. **So it uses one
register, measured on real hardware, rather than guessing at several.**

⚠ **Widening it is a hardware question and is not planned.** The author owns a Kung Fu Flash
and an Ultimate II+ and nothing else, so there is nothing here to measure on — and EasyFlash is
the homebrew standard anyway, so a dedicated cartridge means an EF1 or EF3 rather than
reflashing a freezer cartridge.

**If you have a Final Cartridge III, Retro Replay or similar and want DRAMscope on it**, that is
a welcome contribution: extend `g1probe` to sweep `$DFFF` and `$DE00`–`$DE01` as well as
`$DE02`, run it, and open an issue with what it reports. Gate **G7** in
[`SPEC.md`](SPEC.md) has the detail. No claim is made for those cartridges until someone
measures one.

### ⚠ Why a plain EPROM cartridge is still not enough

A plain EPROM cart has no `$DE02` — GAME and EXROM are strapped by hardware and cannot change.
So it can be *one* mode, not two:

- **Strapped for Ultimax**, it boots and runs, but the write to `$DE02` does nothing. The tool
  detects that and says so with an **orange border** rather than pretending — but it can only
  ever see the 4 KB at `$0000–$0FFF`.
- **Strapped for 8 K or 16 K**, the cartridge is mapped but the *KERNAL* supplies the reset
  vector, so it can only be entered through the autostart handshake — which needs a working
  KERNAL, a working stack and working zero page. That discards the one property the tool is
  built around.

**Building a dedicated cartridge?** You need two 8 KB windows (ROML + ROMH), Ultimax strapping
at reset, and a latch at `$DE02` that can release GAME. That last part is what makes it an
EasyFlash rather than a ROM cart — so the easy route is a real EasyFlash 1/3, and the raw
`dramscope_roml.bin` and `dramscope_romh.bin` are attached to the release for anyone building
their own. ⚠ ROMH holds only the reset vectors, and in Ultimax it appears at `$E000–$FFFF`.

**Got a cartridge not listed above?** `g1probe.crt` (also in the release) answers the one
question that matters: it sweeps all eight values of `$DE02` and reports on screen which, if
any, leaves Ultimax with the cartridge still mapped. Green means DRAMscope will work on it.

A healthy machine finishes a run in about 80 seconds and looks like this:

```
 DRAMSCOPE  RUNS     1  BAD BYTES     0
 ----------------------------------------
   0123456789ABCDEF TESTS AND RESULTS
 0 **#*****######## DATA LINES   OK
 …
 64K MAP: #=FULL *=LIGHTER X=BAD   1.6
 ----------------------------------------
 ALL TESTS PASSED.
 59,648 FULL + 5,886 LIGHTER = 65,534

 RUNS UNTIL YOU RESET.
```

## What it is for

Most C64 memory tests answer *"is the RAM bad?"*. This one is aimed at the three questions
that come next and are harder:

- **Is it even the DRAM?** Colour RAM is a separate 1K × 4 static chip that this tool also
  tests. When it fails you get wrong colours rather than a crash, so it is routinely
  misdiagnosed as a VIC fault. It gets its own indicator and its own verdict, and ⚠ **never
  contributes to the DRAM bit mask** — a fault there must not name a 4164.

- **Which chip?** Each 4164 supplies one bit across the whole address space **[S1][S4]**, so a
  failing bit is a named chip. The tool prints, under the bit number, the designator it maps to:

  ```
   MEMORY FAULT, FIRST BAD BYTE AT $4037
   BITS                               D0
   LIKELY                             U21
   8X4164 ASSUMED. 41464? D0-D3=1 CHIP.
  ```

  ⚠ The designators sit under a heading naming the **part they belong to**, because the tool
  cannot tell which board it is plugged into. The row says `4164`, which is the number printed
  on the chip itself, so it can be checked by looking. **Boards with only two RAM chips carry
  41464s** — four bits per chip — so a named chip there would be plain wrong, and the tool
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

## ⚠ What it can do, what it cannot, and how much of that is proven

Every claim here carries the evidence behind it, and anything shown only in an emulator is
labelled **emulator** so you can weigh it against the ones measured on a real machine. The
limits are set out as plainly as the capabilities.

### It can

| | Evidence |
|---|---|
| Start with **no working KERNAL** | Booted against a KERNAL of 8 KB of `$FF`, on 18 model × CIA combinations — **emulator** |
| Start with **no working RAM**, not even the stack | **Real hardware.** Every DRAM pulled from its sockets; it boots and puts up a solid red screen |
| Test **65,534 bytes**, including `$D000–$DFFF` marched with the I/O chips banked out | Coverage figure tied to the run table by an assembly-time `!error` |
| Name the failing **data bit** | Derived from the failing-bit mask; true on every C64 ever made |
| Name a **chip**, on boards with eight 4164s | Bit→chip table, every row confirmed by two independent sources |
| Run as a **burn-in**, accumulating faults across runs | Exercised by a transient-fault mutation — **emulator** |
| Report rather than hang when it cannot run at all | Mutations for "device ignores `$DE02`" and the MAX Machine — **emulator** |

### It cannot

| | Why |
|---|---|
| Test RAM that is **not fitted** | It reports it — flashing red — but there is nothing to test |
| **Suppress refresh** | The VIC refreshes unconditionally, 5 cycles per raster line. `RETENTION` tests *against a working refresh*, which is a weaker test than a bench DRAM tester's |
| Test at **temperature** | Not a software lever. Run it again on a machine that has been on for an hour |
| Tell which **board** it is plugged into | Hence `LIKELY` and the assumption printed under it |
| Name a chip on a **two-chip (41464) board** | The two such assemblies are wired the opposite way round and nothing on screen distinguishes them |
| Catch **stuck-open faults** reliably | A known limitation of march tests generally, not of this implementation |
| Cover **NPSF** (neighbourhood pattern sensitive faults) | Not claimed anywhere. `ROW/COLUMN` samples neighbourhood conditions; it is not an NPSF test |
| Prove the **chip** is at fault rather than the line | A failing bit means the fault is somewhere on that data line |

### ⚠ How it was tested — and what that is worth

**Almost all of it is simulated.** 23 fault-injection cases, 25 whole-screen golden comparisons,
18 model × CIA combinations, a hostile power-on test — **all of that runs in VICE.**

⚠ **Injecting a fault proves the reporting works. It does not prove the algorithm finds a real
fault of that class.** No genuinely faulty DRAM has ever been tested with this tool. Nobody has
a curated library of chips with known coupling faults, linked faults or marginal retention, so
the coverage claims rest on **the published algorithms being implemented faithfully — which you
can check by reading the source** — and not on having caught one in the wild.

**Where simulation reached its limit — and what was done about it.** Two faults in earlier
versions showed up only on real hardware:

- **`$D016` was never initialised**, so a real machine ran in 38-column mode and the VIC blanked
  columns 0 and 39. Every golden screen passed, because VICE powers up with CSEL already set.
- **The CIA interrupt masks were never cleared.** `SEI` does not mask NMI, and during the march
  the NMI vector is RAM under test. VICE powers up quiet, so nothing ever fired.

Both are fixed, and both now have tests that **deliberately corrupt the power-on state before
the cartridge runs**, so that class cannot pass again — each proven against a mutation that
skips the fix. ⚠ The useful lesson is the general one: **the emulator powers up kinder than a
cold C64**, so anything the KERNAL would normally set up is a place to look. That is why real
hardware reports are valuable here, and why they are acted on.

⚠ **Hardware coverage is narrow.** Two cartridge devices (Ultimate II+ and Kung Fu Flash), the
author's own machines, and **no known-faulty RAM at all**. As far as this project knows it has
**never been run on a two-chip (41464) board**, so the chip chart's short-board rows are
researched but not exercised.

**If it tells you something surprising, doubt it and say so.** Issues and corrections are
genuinely welcome — several of the fixes above came from exactly that.

## Where it came from

It is a spin-out of DRAMa Free 64 (the author's own, unpublished), an FPGA replacement for the eight
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
| Fault injection + headless VICE harness | ✅ 23 cases, one shared hook — ⚠ **emulated** |
| Whole-screen golden comparison | ✅ [`test/golden/`](test/golden/) — ⚠ **emulated** |
| **Variant matrix** — every C64 model VICE emulates | ✅ 18 model × CIA combinations — ⚠ **emulated** |
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
| **Chip naming** from the failing-bit mask | ✅ all five assemblies researched — see below |
| Classification rules beyond chip naming (stride, region, mux pairing) | ⬜ |
| Board profiles, all five assemblies | ✅ researched and corroborated — ⚠ **never run on a two-chip board** |
| Verified on real hardware | ✅ Ultimate II+ and Kung Fu Flash; no-RAM boot measured with the DRAMs out |
| Tested against a genuinely faulty DRAM | ⬜ **never** — see the section above |
| Licence | ✅ [MIT](LICENSE) |

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
> boots the last cartridge you selected, and an **Ultimate II+ does it through *Copy to
> Flash*** — the `.crt` is copied into the device's own flash and loads on restart. ⚠ **Both
> have to be armed from the menu first, and the menu is a C64 program** running on the 6510 out
> of C64 RAM. So the constraint is not *which device*, it is *when*: **set it up while the
> machine still works.**
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
 DRAMSCOPE  RUNS     1  BAD BYTES     0
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
 64K MAP: #=FULL *=LIGHTER X=BAD   1.6
 ----------------------------------------
 ALL TESTS PASSED.
 59,648 FULL + 5,886 LIGHTER = 65,534

 RUNS UNTIL YOU RESET.
```

⚠ **`RUNS` and `BAD BYTES` are decimal; `$` on this screen always means an address.** They
were hex with a `$` in front until Carl asked what the `$` was for — and the honest answer was
that it covered for the real mistake, since nobody has run the test `$0012` times and
`BAD BYTES $000A` makes the reader convert ten into ten. The counters stayed 16-bit **binary**
rather than becoming BCD: `INC` ignores the D flag, and two BCD bytes stop at 9999 while a real
fault in this project's own history produced **40,961** bad bytes. `dec16` converts once per
redraw instead, right-aligned with leading zeros blanked.

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
0.98 Hz on NTSC** **[M]**, against the 3 flashes-per-second limit in WCAG 2.3.1 **[S10]** — a 3.2× margin,
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

## Which chip carries which bit

Researched from published hardware references, 2026-09-27. ⚠ Commodore schematics and hardware
reference guides are permitted source material under [`PROVENANCE.md`](PROVENANCE.md) — the same
class as schematic 251138, which this project already used.

| Assembly | Board | RAM | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 |
|---|---|---|---|---|---|---|---|---|---|---|
| 326298 | long | 8 × 4164 | U21 | U9 | U22 | U10 | U23 | U11 | U24 | U12 |
| **250407** | long | 8 × 4164 | U21 | U9 | U22 | U10 | U23 | U11 | U24 | U12 |
| 250425 | long | 8 × 4164 | U21 | U9 | U22 | U10 | U23 | U11 | U24 | U12 |
| 250466 | **long** | 2 × 41464 | U10 | U10 | U10 | U10 | U9 | U9 | U9 | U9 |
| 250469 | short | 2 × 41464 | U10 | U10 | U10 | U10 | U11 | U11 | U11 | U11 |

### ⚠ The bit is measured. The chip is a suggestion.

The row says **`LIKELY`**, not the designator as a fact, and that wording is deliberate.
DRAMscope proves that a given data bit did not hold what was written to it — that is a
measurement. Turning the bit into a chip is a **lookup**, resting on two things the tool
cannot check:

1. **That you have the board it assumes.** It cannot see which board it is plugged into.
2. ⚠ **That the fault is in the chip at all.** A failing bit means the fault is somewhere *on
   that data line*. The RAM is the likeliest part on it, but a dry joint, a corroded socket
   contact, a broken track, the PLA, or the CPU end of the line are **indistinguishable to any
   software test**.

So the advice is: reseat the chip, reflow its joints, check continuity along the line — and
only then swap the part, keeping the old one until the repair is confirmed. If the same bit
fails with a new chip, the chip was never the fault, and that is information rather than a
wasted part.

**No warranty** — see [LICENSE](LICENSE). The tool reports what it measured; deciding what to
replace is the user's.

✅ **All three 8 × 4164 boards are identical**, and the table matches schematic 251138 on all
eight bits. The screen therefore names chips for any of them, and the row is labelled `4164` —
the number printed on the part, which the user can check by looking — rather than `250407`,
which claimed one board for a table that was right for three.

⚠ **The two 41464 boards are reversed relative to each other** and nothing on screen can tell
them apart, so the tool **does not name a chip for them**. It prints the nibble instead —
`41464? D0-D3 IS ONE CHIP - SEE SHEET.` — because "a 41464 is four bits wide" is a *datasheet*
fact that holds on any board, while the designator is not. The full chart is on the bench sheet.

⚠ **250466 is a long board with two RAM chips**, so counting chips does not identify the board
type. The old on-screen caveat `SHORT BOARD? 2 CHIPS` was wrong on that point and is gone.

## Documentation in this repository

| File | Who it is for |
|---|---|
| [`docs/BENCH-SHEET.txt`](docs/BENCH-SHEET.txt) | **Read this one.** Every colour, every mark on the map, and the chip chart for all five board assemblies. It ships alongside the `.crt`. |
| **[CHIP-CHART.pdf](https://github.com/bitbarista/dramscope/releases/latest/download/CHIP-CHART.pdf)** | **Print this one.** Two A4 pages for a mono laser and a bench wall: page 1 is the bit→chip table, derived from schematics and checked by the tests; ⚠ **page 2 is advice on buying and substituting DRAM, and says on itself that it is not measured.** Generated by [`tools/make-chip-chart.py`](tools/make-chip-chart.py). |
| [`docs/CHIP-CHART.txt`](docs/CHIP-CHART.txt) | The same chart as plain text, for reading on screen or on a machine with no PDF viewer. |
| [`docs/VARIANT-MATRIX.txt`](docs/VARIANT-MATRIX.txt) | Generated proof that a clean run looks identical on every C64 model VICE emulates. |
| [`SPEC.md`](SPEC.md) | *Background.* Why each algorithm was chosen, what was tried and rejected, and what is still open. |
| [`PROVENANCE.md`](PROVENANCE.md) | *Background.* Where every algorithm and hardware fact came from, with the rule about not reading other RAM tests' code. |

## Licence

[MIT](LICENSE). Use it, fork it, bundle it with a flash cart — attribution is all that is asked.

## Support

DRAMscope is a spare-time open source project, written to give something back to the C64
community rather than to compete with anything. If it has found a fault for you — or saved you
from replacing a chip that was never the problem — you can support continued development and
testing.

<div align="center">

<a href="https://ko-fi.com/bitbarista" target="_blank"><img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Support on Ko-fi"></a>

</div>

---

## Sources

⚠ **Every factual claim in this repository must be traceable to a source.** That rule, the
keyed source list, and the claim-by-claim detail are in [`PROVENANCE.md`](PROVENANCE.md) —
including a record of the statements that were **invented and later corrected**, kept
deliberately, because a file that only lists what survived teaches nothing about how the wrong
things got in.

| Key | Source |
|---|---|
| **[S1]** | Commodore schematic **251138** (Assy 250407) |
| **[S2]** | Bauer, *The MOS 6567/6569 video controller (VIC-II) and its application in the Commodore 64* |
| **[S3]** | van de Goor, *Testing Semiconductor Memories: Theory and Practice*; March LR literature |
| **[S4]** | [opencbm *Hardware Reference and Repair Guide*](https://opencbm.org/doc/c64/hardware_reference_and_repair_guide/), per-PCB component tables |
| **[S5]** | [C64-Wiki](https://www.c64-wiki.com/) |
| **[S6]** | [myoldcomputer.nl](https://myoldcomputer.nl/technical-info/mainboards/commodore-64/) mainboard pages |
| **[S7]** | [retrorewind support wiki](https://hd.retrorewind.ca/commodore/c64) — assembly numbers and board types |
| **[S8]** | 4164 / 41464 datasheets |
| **[S9]** | DRAM cross-references — [minuszerodegrees](https://minuszerodegrees.net/memory/4164.htm), [pcbjunkie](https://pcbjunkie.net/index.php/resources/ram-info-and-cross-reference-page/), [amiga-stuff](https://www.amiga-stuff.com/hardware/64kx1-dram.html) |
| **[S10]** | WCAG 2.3.1, three flashes per second |
| **[S11]** | Community discussion — 6502.org, Lemon64, arcade-museum, Parallax, modwiggler. ⚠ Corroboration, never a sole source for anything actionable |
| **[S12]** | Open reproduction projects — [bwack 250407](https://github.com/bwack/C64-250407-Replica-KiCad) and [bwack 250469](https://github.com/bwack/C64C-250469-KiCAD-Replica) KiCad replicas, reverse-engineered from real boards and prototype-verified |
| **[S13]** | ⚠ Modified derivative boards — [250466 Plus](https://bitbucket.org/fade0ff/c64-250466/src/master/). **Not 1:1 replicas**; a cross-reference only, never corroboration for a detail the author may have changed |
| **[M]** | Measured by this project — the VICE harness, or Carl's hardware. The measuring artefact is named with the claim |

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

**All 65,534 bytes of RAM.** A C64 has 65,536 *addresses*, but two of them are not memory:
`$0000` and `$0001` are the CPU's data-direction register and banking latch. 65,534 is
therefore the whole of the RAM, not a shortfall against it.

The verdict line prints the split rather than rounding it to a claim —
`59,648 FULL + 5,886 LIGHTER = 65,534` — and the map distinguishes depth rather than
averaging it:

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
