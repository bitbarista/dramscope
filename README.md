# DRAMscope

⚠ **Placeholder name, and nothing is built yet.** This repository currently holds a
specification and a provenance policy. See [`SPEC.md`](SPEC.md).

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
| Gate G1 — EasyFlash mode switching on KFF / U2+ | ⬜ **next, and it decides the architecture** |
| Engine, phases P0–P9 | ⬜ |
| Licence | ⬜ undecided |

## Building

Not yet. The toolchain will be `acme` plus VICE's `cartconv`, with a headless VICE harness
for verification — the same tools the sibling project uses.

## Credits

Prior art, gratefully acknowledged: **Dead Test**, **DesTest**, **DesTestMAX** and
**MAX-Switch**, and their authors' published fault reports. The bar they set is why this
specification is as demanding as it is.

Algorithms come from the published memory-test literature — van de Goor's March B and
March LR — and hardware facts from Commodore's schematics and Bauer's VIC-II reference. Every
one is traced in [`PROVENANCE.md`](PROVENANCE.md).
