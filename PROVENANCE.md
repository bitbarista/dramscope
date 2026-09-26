# PROVENANCE — where everything in this project came from

This file exists because the project has one non-negotiable constraint: **nothing here may
derive from another RAM test's code.** That constraint is only worth anything if it can be
demonstrated, and it can only be demonstrated by writing down, as the work happens, where
each algorithm and each number came from.

The same discipline is used in the sibling project `c64-ice40-ram`, where the plug-pin
geometry is traceable to Commodore's own drill file rather than to a drawing. Evidence tags
are used the same way:

| Tag | Meaning |
|---|---|
| **[D]** | Datasheet or primary source |
| **[M]** | Measured, or derived from files held locally |
| **[C]** | Cross-checked against an independent source |
| **[A]** | Assumption, not yet verified |

---

## ⚠ The rule about existing RAM tests

**Dead Test, DesTest, DesTestMAX and MAX-Switch are prior art, not source material.**

What may be used:

- **Their published feature lists and documentation.** What a program tests is a fact about
  the world. Facts are not protectable expression, and knowing that a mature tool covers
  *X* is legitimate information about where the bar sits.
- **Their authors' published fault reports.** A stated diagnosis in a README or a forum post
  is published technical information.

What may **not** be used, at all:

- Their source, if published.
- Their binaries, disassembled, decompiled, traced or inspected in a debugger.
- Their screen layouts, menu structures, wording, colour schemes or glyph choices.

⚠ **The risk is contamination, not just copying.** Once an implementation has been read,
independent creation can no longer be demonstrated — "I only took the idea" is not a
position anyone can defend after the fact. So the rule is stricter than the law requires,
deliberately, because the cost of being strict is a few hours of reading papers and the cost
of being loose is the whole project's reputation.

**If you are working on this and you have read another tool's disassembly, say so here.**
A disclosed contamination can be worked around. An undisclosed one cannot.

### Current status

**No RAM-test source or binary has been inspected by anyone working on this project.**
Assistant sessions have been instructed not to fetch, decompile or disassemble any of them,
and have not done so.

---

## Algorithms — every one traceable to published literature

| Algorithm | Source | Tag |
|---|---|---|
| **March B**, 17n, five elements | van de Goor, *Testing Semiconductor Memories: Theory and Practice* — the standard reference, and the same citation used by `c64-ice40-ram/diag` | [C] |
| **March LR**, 14n, six elements | van de Goor et al., March LR — published linked-fault march test | [C] |
| **Fault models** — SAF, TF, AF, CFin, CFid, CFst, NPSF, linked faults | Standard memory-test taxonomy, same literature | [C] |
| **Walking 1s / 0s** on data and address lines | Classic bus-integrity technique, textbook and pre-dating any of the C64 tools | [C] |
| **Address-dependent pattern** `value = lo XOR hi XOR seed` | Originated in `c64-ice40-ram/diag/ramtest.asm`, this author's own prior work | [M] |

⚠ **The address-dependent pattern is the one genuinely original piece** and it comes from
the sibling project, written to catch address-decode aliasing in an FPGA doing its own
demultiplexing. It is carried here with its rationale intact.

---

## C64 hardware facts

| Fact | Source | Tag |
|---|---|---|
| VIC-II performs 5 refresh cycles per raster line, unconditionally | Bauer, *The MOS 6567/6569 video controller (VIC-II) and its application in the Commodore 64* | [C] |
| Refresh is performed by ordinary read accesses, not RAS-only strobing | Bauer, same | [C] |
| Refresh rate: PAL 312 × 50 × 5 = 78,000/s; NTSC 262 × 60 × 5 = 78,600/s | Derived from the above | [M] |
| Address multiplexing: two 74LS257 at U13/U25, pairing `An`/`An+8` → `MAn` | Commodore schematic 251138, cross-checked in `c64-ice40-ram` §2.3 | [D] |
| Multiplexed address lines pass through 330 Ω series packs RP1/RP2 | Same | [D] |
| `/CAS` at the DRAM is CASRAM from the PLA, gated by the memory map | Same, §2.4 | [D] |
| Colour RAM is a separate 1K × 4 static RAM, not part of the 64 KB | `c64-ice40-ram` DEFERRED 14, citing `reference/vic-article.txt` | [C] |
| 4164 is 65,536 × 1 bit, organised 256 rows × 256 columns | 4164 datasheets | [D] |
| On a stock C64 each 4164 supplies one bit across the entire address space | `c64-ice40-ram/diag/README.md` | [C] |
| 4164 hold times: tRAH = 20 ns, tCAH = 25 ns | 4164 datasheets, via `c64-ice40-ram` §3.3 | [D] |

### ⚠ Facts still needed, and not yet held

| Needed for | Question | Tag |
|---|---|---|
| Topographical patterns (P5) | Which multiplexer half is the **row** address and which the **column**? `c64-ice40-ram` §5.3 deliberately never determined it, because that design has no refresh or page-mode dependency. This project does. | [A] |
| ~~Delivery vehicle (P0)~~ | ✅ **ANSWERED on Ultimate II+ hardware, 2026-09-26: `$DE02 = $02` leaves Ultimax and the cartridge stays mapped at `$8000`.** Measured by `src/g1probe_roml.asm`, which sweeps all eight values rather than assuming one. VICE agrees, but VICE was not the evidence. ⬜ Kung Fu Flash still unrun. | [M] |
| Screen placement | In Ultimax mode the VIC's fetches in `$3000–$3FFF` of its bank are said to come from cartridge ROMH. Verify before choosing a screen home. | [A] |
| Chip naming | Bit-to-designator tables per motherboard assembly, from Commodore schematics. | [A] |

---

## Fabrication of facts is the failure mode this file exists to prevent

A test tool's whole value is that its output can be believed. A verdict of *"replace the chip
at D3"* is a claim about someone else's hardware, and a wrong one costs them a chip, an hour,
and their trust in every other line the tool printed.

**So: no verdict may be printed that is not derivable from evidence the run actually
collected**, and no coverage may be claimed in the documentation that is not demonstrated by
a fault-injection test that fails without it. See `SPEC.md` §8.
