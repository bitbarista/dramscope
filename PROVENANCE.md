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
| ⚠ **Other chips that can look like bad RAM.** `U14` 74LS258 and `U26` 74LS373 join `U13`/`U25` in switching the address lines between VIC and CPU; `U14` couples the CIA bank bits into the VIC address bus or bypasses them during refresh, `U26` allows the VIC to address char ROM and colour RAM | opencbm Hardware Reference component table for 250407, plus C64-Wiki *Hardware internals of the C64*. ⚠ **Carl raised this** — the guidance named only the RAM, its joints and the PLA | [C] |
| ⚠ **A shared-path fault cannot produce a single bad bit** | Derived: the address multiplexers, their series packs, the PLA's CASRAM and the VIC's RAS/CAS are common to all eight DRAMs, so a failure there takes more than one bit. ⚠ **This also means naming the PLA as a suspect for a ONE-BIT fault was wrong**, which the bench documents did until 2026-09-27 | [M] |

### ⚠ Facts still needed, and not yet held

| Needed for | Question | Tag |
|---|---|---|
| ~~March LR + address-dependent pattern (G3)~~ | ⚠ **ANSWERED, AND THE ANSWER IS NO — see the section below. March LR is implemented with FIXED patterns.** | [M] |
| ~~Topographical patterns (P5)~~ | ✅ **ANSWERED: ROW = A0–A7, COLUMN = A8–A15.** Bauer §3.13 states the 8-bit refresh counter generates *"256 DRAM **row** addresses"*, and its bit-level table places `REF7..REF0` on address bits **7..0**. 256 distinct rows from a counter that only moves the low byte means the row address IS the low byte. Cross-checked against the same article's *"A0-A5 and A8-A13 are multiplexed in pairs (i.e. A0/A8, A1/A9)"*, which matches U13/U25's `An`/`An+8` wiring. | [C] |
| ~~Delivery vehicle (P0)~~ | ✅ **ANSWERED ON BOTH DEVICES, 2026-09-26: `$DE02 = $02` leaves Ultimax and the cartridge stays mapped at `$8000`.** Ultimate II+ and Kung Fu Flash report identically. Measured by `src/g1probe_roml.asm`, which sweeps all eight values rather than assuming one. VICE agrees, but VICE was not the evidence. | [M] |
| Screen placement | In Ultimax mode the VIC's fetches in `$3000–$3FFF` of its bank are said to come from cartridge ROMH. Verify before choosing a screen home. | [A] |
| ~~Behaviour with **no DRAM fitted**~~ | ✅ **ANSWERED ON HARDWARE, 2026-09-27: it starts and reports.** With every DRAM out of its sockets, a Kung Fu Flash boots the remembered cartridge with no menu and the screen goes SOLID RED — `p0a_dead`, the only site of `C_RED` in the source, so the reading is unambiguous. ⚠ The Ultimate II+ could not reach it: its menu is a C64 program and needs RAM. **The claim holds for the cartridge; the launcher must map it without a menu.** VICE cannot emulate a C64 with empty sockets, so only the bench could show this. See `SPEC.md` G6. | [M] |
| Distinguishing *no RAM fitted* from *a bad scratch byte* | ✅ **BUILT 2026-09-27 (G6a).** Steady red = the scratch will not hold a value but something in `$0000–$0FFF` does, so RAM is fitted and a chip is faulty. Slowly flashing red = nothing anywhere responds, so no RAM is fitted or the PLA is not selecting it. Sixteen unrolled probes, registers only — zero page has just failed by definition, so there is no pointer to loop with. ⚠ The flash rate is a safety claim and is **measured**, not asserted: 850,000–900,000 PAL cycles per interval, bracketed in emulated cycles by `test/check.py`, giving 0.55–0.58 Hz against WCAG 2.3.1's 3/s — a ≥5.2× margin, wider than the running pulse's 3.2× because `DEN=0` makes this fill the whole screen. | [M] |
| ⚠ Could the P0 probes *falsely pass* on an undriven bus? | ❌ **NO — disproved on hardware, 2026-09-27.** Each probe writes a byte and immediately reads the same address back; with no chip fitted the last driven cycle is a cartridge-ROM instruction fetch, so it was argued the read might return the written value and the probe pass. The red screen shows it does not. ⚠ Recorded because the reasoning was sound and the conclusion was wrong — an undriven bus is to be measured, not inferred. | [M] |
| Behaviour when **every** byte of RAM is *fitted but faulty* | `dramscope_fall` injects all 8 bits bad at ONE byte; there is no mutation for a machine that fails every byte. The no-RAM result above is the nearest evidence and it is encouraging, but it is not the same machine. | [A] |
| ~~Chip naming, Assy 250407~~ | ✅ **HELD.** `D0=U21, D1=U9, D2=U22, D3=U10, D4=U23, D5=U11, D6=U24, D7=U12` — confirmed from schematic 251138 in `c64-ice40-ram` README §2.2, where the drawing places the RAMs in bus order U12, U24, U11, U23, U10, U22, U9, U21 against D7…D0. | [D] |
| ~~Chip naming, other assemblies~~ | ✅ **RESEARCHED 2026-09-27 — all five C64 assemblies, table below.** Two independent sources per board where possible; ⚠ one source was found to be demonstrably wrong and is named. | [C] |

---

## Bit → chip designator, every C64 assembly

Researched 2026-09-27 from published hardware references. ⚠ **Commodore schematics and
hardware reference guides are explicitly permitted source material** — the same class as
schematic 251138, which this project already used. No RAM-test source or binary was involved.

| Assembly | Board | DRAM | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 | Tag |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **326298** | long, 5-pin video | 8 × 4164 | U21 | U9 | U22 | U10 | U23 | U11 | U24 | U12 | [C] |
| **250407** | long, 8-pin video | 8 × 4164 | U21 | U9 | U22 | U10 | U23 | U11 | U24 | U12 | **[D][C]** |
| **250425** | long | 8 × 4164 | U21 | U9 | U22 | U10 | U23 | U11 | U24 | U12 | [C] |
| **250466** | long | 2 × 41464 | U10 | U10 | U10 | U10 | U9 | U9 | U9 | U9 | [C] |
| **250469** | **short** | 2 × 41464 | U10 | U10 | U10 | U10 | U11 | U11 | U11 | U11 | [C] |

✅ **THE THREE 8 × 4164 BOARDS ARE IDENTICAL.** The table this project already held for
250407 — from schematic 251138 via `c64-ice40-ram` §2.2 — is reproduced **exactly** by the
opencbm Hardware Reference and Repair Guide, and that guide gives the *same* mapping for
326298 and 250425. So the existing designators were already correct for three assemblies while
the tool labelled them for one: an **under-claim**, not an error.

⚠ **THE TWO 41464 BOARDS ARE REVERSED RELATIVE TO EACH OTHER, AND NO RULE PREDICTS IT.**
On **250469** the lower designator carries the **lower** nibble (U10 = D0–D3, U11 = D4–D7).
On **250466** the lower designator carries the **upper** nibble (U9 = D4–D7, U10 = D0–D3).
An "obvious" analogy from one to the other gives the wrong chip. ⚠ **This is exactly the
inference this file exists to forbid** — it was very nearly made here and was caught only by
looking for a second source.

⚠ **ONE SOURCE IS WRONG AND MUST NOT BE USED FOR 250466.** The opencbm guide's 250466 page
lists `U9 … DRAM 64K x 4 … D1` and `U10 … DRAM 64K x 4 … D3` — a **single-bit** assignment for
a **four-bit-wide** part, self-evidently impossible, and identical to the D1/D3 entries on the
eight-chip boards. It has plainly inherited the bit column from the 4164 layout. The 250466
row above therefore comes from *myoldcomputer.nl*, which states `U9 … D4..D7` and
`U10 … D0..D3`. The guide is reliable for the other four boards — it was validated against our
own schematic-derived 250407 table, which it matches on all eight bits — but not for this one.

**Sources:** opencbm Hardware Reference and Repair Guide, per-PCB component tables
(`opencbm.org/doc/c64/hardware_reference_and_repair_guide/pcb/`); *myoldcomputer.nl* mainboard
pages; retrorewind support wiki for assembly numbers, board types and schematic numbers
(326106, 251138, 251469, 252311/252312).

⚠ **Not yet held:** the 250466 mapping rests on a single source, because the one that would
have corroborated it is the one that is wrong. It is good enough to document and **not** good
enough to print as a confident chip name without saying which board it assumes.

---

## ⚠ Page 2 of the chip chart is ADVISORY and is fenced off deliberately

`CHIP-CHART` page 1 is derived from schematics and checked by `test/chart.py` against the
cartridge. **Page 2 is not, and says so on itself.** It is collected practice about buying and
substituting DRAM, and it exists because Carl asked for further advice *"made clear that it's
only advice and not fact"*. Its claims, and where they come from:

| Claim | Source | Tag |
|---|---|---|
| C64s shipped with DRAM marked **150 ns** and **200 ns** | C64-Wiki, *RAM* | [C] |
| `4164` is 64K × 1; `41464` (also sold as `4464`) is 64K × 4 | DRAM datasheets; C64-Wiki calls the two-chip part 4464 | [C] |
| A **41256** can stand in for a 4164 by tying **pin 1 to pin 16**, because pin 1 is `NC` on the 4164 and `A8` on the 41256 — grounding it stops `A8` floating and confines the chip to its lower 64K | C64-Wiki, *RAM*: *"solder a short piece of wire between pins 1 and 16 … make the chip look just like a '64 chip to the system"*; corroborated by 6502.org and Lemon64 forum reports | [C] |
| Replacements are new-old-stock or desoldered pulls, and a pull may have been removed *because it failed* | Follows from the parts being long out of production. ⚠ **An earlier draft said "much of what is sold is pulls, or relabelled, or simply dead"** — a proportion claim with nothing behind it, and my escalation of Carl's more careful "sources are questionable". Searching found counterfeiting material for **modern** RAM modules and **no documented cases of faked 4164s**, so the relabelling claim was dropped rather than hedged | [M] |
| Machined sockets use a multi-finger collet intended for **round** pins; dual-wipe contacts bear on the two broad faces of a flat DIP lead; both have failure modes and repairers disagree about which is better | Arcade-museum, Parallax and modwiggler forum discussions. ⚠ **An earlier draft simply recommended turned-pin sockets** — a bare preference, and Carl's objection was concrete: point-style contact on a flat lead, and possible trouble with RAM *replacement boards*, which commonly present square header pins. The page now declines to pick a side and states the compatibility consideration instead | [C] |
| Fitting a socket; running warm to find marginal cells | Ordinary repair practice, not a sourced claim | [A] |

⚠ **NONE OF PAGE 2 HAS BEEN TESTED BY THIS PROJECT.** No 41256 substitution has been built or
run here. The page states that about itself in a box at the top, because advice that looks like
the measured half of the same document would borrow credibility it has not earned.

---

## Fabrication of facts is the failure mode this file exists to prevent

A test tool's whole value is that its output can be believed. A verdict of *"replace the chip
at D3"* is a claim about someone else's hardware, and a wrong one costs them a chip, an hour,
and their trust in every other line the tool printed.

**So: no verdict may be printed that is not derivable from evidence the run actually
collected**, and no coverage may be claimed in the documentation that is not demonstrated by
a fault-injection test that fails without it. See `SPEC.md` §8.


---

## G2: row is the low byte, and that is not where intuition puts it

**ROW = A0–A7. COLUMN = A8–A15.** Two independent statements in Bauer's VIC-II reference
agree: §3.13 says the 8-bit refresh counter generates *"256 DRAM row addresses"*, and its
table places `REF7..REF0` on address bits 7..0. A counter that only varies the low byte
cannot produce 256 distinct **rows** unless the row address is the low byte.

⚠ **The consequence is the opposite of what the address space suggests.** On a 4164 organised
256 × 256:

| Physically adjacent | In the address space |
|---|---|
| Same row, next column | **256 bytes apart** — same offset, next page |
| Same column, next row | **1 byte apart** — next offset, same page |

So a DRAM *row* is one byte offset taken across all 256 pages, and a DRAM *column* is a
single page. Any pattern meant to stress physical adjacency has to be built from that, not
from address order. This is exactly the dependency `c64-ice40-ram` §5.3 declined to
establish — correctly, since that design has neither refresh nor page mode.

---

## ⚠ G3: the address-dependent substitution is NOT proven to preserve coupling coverage

**The question.** `c64-ice40-ram/diag/README.md` justifies its address-dependent pattern
like this: *"March B only requires two complementary values, so substituting P/~P preserves
the algorithm exactly."* Gate G3 asked whether that argument carries over to March LR before
building on it.

**It does not carry over, and on inspection it is weaker than it looks for March B too.**

The two-complementary-values argument is sound for the fault classes that concern **one
cell** — stuck-at, transition, and address decoder faults. Each cell still holds a value the
algorithm knows, still gets read back against it, and still makes both transitions. For
decoder faults the substitution is strictly *better*, which is the whole reason it exists: a
read from the wrong address returns the wrong value.

⚠ **Coupling faults are not about one cell.** A CFid is detected only when the aggressor
makes a particular transition *while the victim holds a particular value*. A fixed-pattern
march guarantees that coincidence by construction, because every cell is in the same state
at the same point in the march. With `P(a) = lo ⊕ hi ⊕ SEED` the cells are **not** in the
same state — at any step roughly half hold 0 and half hold 1, per bit — so whether a given
aggressor/victim pair is sensitised depends on whether `P` happens to differ between them.

Working it through for March B's M1, the aggressor makes an ↑ transition regardless of
`P(i)`, and the victim's state at that moment is `P(j)` above the march front and `~P(j)`
below it. So M1 sensitises only the pairs where `P(j)` has the needed polarity — and M2,
whose cells rest in the opposite state, appears to pick up the remainder. **That is an
argument that coverage probably survives. It is not a proof, and it is not the argument the
sibling project actually makes.**

**Decision: do not build on an unproven substitution.**

| Phase | Pattern | Why |
|---|---|---|
| **P3 March B** | address-dependent `P/~P` | decoder and aliasing coverage, which is what it was for |
| **P4 March LR** | **fixed `$00`/`$FF`** | the published linked-fault proof holds exactly as written |

Running both costs 31n and buys each property on its own terms, with neither resting on a
claim nobody has proved. ⚠ **This also means `c64-ice40-ram`'s "preserves the algorithm
exactly" is stronger than its evidence** — it is that project's line to correct, not this
one's, but it should be corrected.
