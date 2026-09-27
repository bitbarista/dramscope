#!/usr/bin/env python3
"""⚠ THE CHIP CHART EXISTS IN THREE FILES. THIS STOPS THEM DRIFTING APART.

`docs/CHIP-CHART.txt` is the printable one, `docs/BENCH-SHEET.txt` repeats it so
a bench user with one sheet is not stranded, and `PROVENANCE.md` carries it with
the evidence tags. Three copies of a table that names someone else's chip to
desolder is exactly the drift that has already cost this project a wrong
coverage figure in four places at once.

⚠ THE TRUTH IS HERE, IN CHART, NOT IN ANY OF THE DOCUMENTS. Every file is
checked against this, so a document that disagrees fails rather than quietly
becoming the version someone prints.

Runs in under a second and needs no emulator, so test/run.sh calls it first.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# assembly -> the eight designators, D0 first.
# ⚠ 250466 and 250469 are REVERSED relative to each other. That is not a typo
# and no rule predicts it; see PROVENANCE.md for the two independent sources.
CHART = {
    "326298": ["U21", "U9", "U22", "U10", "U23", "U11", "U24", "U12"],
    "250407": ["U21", "U9", "U22", "U10", "U23", "U11", "U24", "U12"],
    "250425": ["U21", "U9", "U22", "U10", "U23", "U11", "U24", "U12"],
    "250466": ["U10", "U10", "U10", "U10", "U9",  "U9",  "U9",  "U9"],
    "250469": ["U10", "U10", "U10", "U10", "U11", "U11", "U11", "U11"],
}
# Board type and RAM fitted, for anything that renders the chart.
# ⚠ 250466 is a LONG board with two chips. Counting chips does not tell you the
# board type, and an earlier version of the bench sheet said it did.
BOARDS = {
    "326298": ("long",  "8 x 4164"),
    "250407": ("long",  "8 x 4164"),
    "250425": ("long",  "8 x 4164"),
    "250466": ("long",  "2 x 41464"),
    "250469": ("short", "2 x 41464"),
}

# The on-screen table, which only ever names the 8 x 4164 boards.
ON_SCREEN = "u21 u9  u22 u10 u23 u11 u24 u12 "


def designators(line: str) -> list:
    """Every Ux token on a line, in order."""
    return re.findall(r"\bU\d+\b", line.upper())


def chart_rows(text: str, assy: str) -> list:
    """The TABLE rows for an assembly, in any of the three formats.

    ⚠ Must not match prose. Both documents also discuss these numbers in
    sentences -- "250466 is a LONG board with two RAM chips" -- and an earlier
    version of this check read those as table rows and reported nonsense.
    A real row starts with the assembly number once markdown pipes and bold
    markers are stripped, AND names the RAM part.
    """
    out = []
    for line in text.splitlines():
        # ⚠ Strip DECORATION, not just markdown. The 250466 row carries a "⚠"
        # because it rests on a single source, and that alone made this checker
        # report "no table row" -- a checker that goes quiet when a row is
        # marked as doubtful is worse than useless.
        bare = line.replace("|", " ").replace("*", " ").replace("⚠", " ").strip()
        # ⚠ BOTH part numbers, spelled out. "41464" does NOT contain "4164"
        # as a substring, so a single `"4164" in bare` silently skipped every
        # two-chip row and the check passed by testing nothing.
        if bare.startswith(assy) and re.search(r"\b(4164|41464)\b", bare):
            out.append(bare)
    return out


def check_rows(path: pathlib.Path, fails: list) -> None:
    text = path.read_text()
    for assy, want in CHART.items():
        rows = chart_rows(text, assy)
        if not rows:
            fails.append(f"{path.name}: no table row for {assy}")
            continue
        for row in rows:
            got = designators(row)
            # ⚠ Two legitimate spellings. PROVENANCE.md writes all eight cells
            # out; the printable chart spans a nibble with an arrow and names
            # the chip once. Accept either, insist both say the same thing.
            if len(got) == 8:
                ok = got == want
            elif len(got) == 2:
                ok = got == [want[0], want[4]]
            else:
                ok = False
            if not ok:
                fails.append(f"{path.name}: {assy} reads {got}, chart says "
                             f"{want} (or {[want[0], want[4]]} in arrow form)")


def main() -> int:
    fails = []
    for name in ("docs/CHIP-CHART.txt", "docs/BENCH-SHEET.txt", "PROVENANCE.md"):
        path = ROOT / name
        if not path.exists():
            fails.append(f"{name}: missing")
            continue
        check_rows(path, fails)

    # ⚠ And the cartridge itself. The table the tool prints is the one that
    # sends someone to a soldering iron, so it is checked against the same
    # source as the paperwork rather than trusted because it looks right.
    asm = (ROOT / "src/dramscope.asm").read_text()
    m = re.search(r'chips407:\s*!scr\s*"([^"]*)"', asm)
    if not m:
        fails.append("src/dramscope.asm: chips407 table not found")
    elif m.group(1) != ON_SCREEN:
        fails.append(f"src/dramscope.asm: chips407 is {m.group(1)!r}, "
                     f"expected {ON_SCREEN!r}")
    else:
        # and that the string really does spell the chart's 8 x 4164 order
        if [d.upper() for d in designators(m.group(1).upper())] != CHART["250407"]:
            fails.append("src/dramscope.asm: chips407 does not match the chart")

    print("chip chart consistency")
    if fails:
        for f in fails:
            print(f"  *** {f}")
        return 1
    print(f"  {len(CHART)} assemblies agree across CHIP-CHART, BENCH-SHEET, "
          f"PROVENANCE and the cartridge")
    return 0


if __name__ == "__main__":
    sys.exit(main())
