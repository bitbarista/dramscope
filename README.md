# DRAMscope

⚠ **Placeholder name.** Iteration 1 builds, runs and is verified; see
[`SPEC.md`](SPEC.md) for the whole plan and what is still missing.

A memory diagnostic cartridge for the Commodore 64 — for **any** C64, not for any particular
RAM replacement board.

## What it is for

Most C64 memory tests answer *"is the RAM bad?"*. This one is aimed at the three questions
that come next and are harder:

- **Which chip?** Each 4164 supplies one bit across the whole address space, so a failing bit
  is a named chip. The tool says which one rather than printing an address.
- **Is it actually the RAM?** A fault in the address multiplexers, their series packs, or the
  PLA looks like bad memory and is not. The tool tells them apart.
- **Why does it only fail when warm?** Marginal, leaky cells pass every fast march test and
  drop bits an hour into a session. A dwell phase catches them.

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
| **P2** address bus — A0–A14 (⚠ A15 needs iteration 2) | ✅ |
| Display — 256-page map, bus lanes, verdict | ✅ |
| Fault injection + headless VICE harness | ✅ 3/3 |
| Gate G1 — EasyFlash mode switching on KFF / U2+ | ⬜ **next, and it decides the architecture** |
| **P3–P9** march, topographical, dwell, disturb, colour RAM | ⬜ |
| Classification engine and board profiles | ⬜ |
| Licence | ⬜ undecided |

## Building

```
bash build.sh        # clean build + two fault-injected variants
bash test/run.sh     # run all three headless in VICE and assert the results
```

Needs `acme`, and VICE for `cartconv` and `x64sc`.

⚠ **The harness uses the real Commodore ROMs** and finds them wherever VICE keeps them
(`~/.local/share/vice/C64/`). They are **not** included here and must not be — they are
copyrighted. The upside of using the real KERNAL rather than a stub is that the genuine
autostart handshake runs: `JSR $FD02` pushes a return address and therefore needs the
stack page, which is this delivery vehicle's honest limit and something a stub cannot
exercise.

### What a run looks like

Border colours report even when the display cannot: white = has control, red = zero-page
scratch dead, purple = screen page dead, green = clean, light red = fault found. A black
border means the cartridge never got control at all.

## Credits

Prior art, gratefully acknowledged: **Dead Test**, **DesTest**, **DesTestMAX** and
**MAX-Switch**, and their authors' published fault reports. The bar they set is why this
specification is as demanding as it is.

Algorithms come from the published memory-test literature — van de Goor's March B and
March LR — and hardware facts from Commodore's schematics and Bauer's VIC-II reference. Every
one is traced in [`PROVENANCE.md`](PROVENANCE.md).
