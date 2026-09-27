#!/usr/bin/env python3
"""Run each DRAMscope build in VICE and assert what it reported.

⚠ THE BORDER IS READ FROM $D020, NOT FROM A SCREENSHOT PIXEL.
An earlier version of this harness sampled pixel (6,6) of -exitscreenshot and
read WHITE on a run that had plainly finished green -- because with the
emulator stopped at a breakpoint the last fully rendered frame predates the
final border write. The register is the fact; the pixel is a rendering of it.

⚠ USES THE REAL COMMODORE ROMS from VICE's own data directory. They are not
vendored here and must not be. See test/run.sh.
"""
import re
import subprocess
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"

# ⚠ $A0 (inverse space, a solid block) is the map's "full" cell and renders
# here as "#". ASCII '#' ($23) is DELIBERATELY ABSENT: it used to be mapped to
# "#" as well, so a legend printing $23 and a map printing $A0 compared equal
# in every golden while looking completely different on screen. Unmapped codes
# render as "?", so if a literal '#' is ever reintroduced the goldens fail.
GLYPH = {0x20: " ", 0x2E: ".", 0x2D: "-", 0x2F: "/", 0x2C: ",", 0x3D: "=",
         0x18: "X", 0xA0: "#", 0x2B: "+", 0x2A: "*", 0x24: "$", 0x3A: ":"}


def halt_address(stem: str, sym: str = "pass_obs") -> str:
    """⚠ Per build. Injected instructions move every later address, so the
    clean build's halt is not the fault build's halt -- breakpointing the
    wrong one just hangs."""
    for line in (BUILD / f"{stem}.labels").read_text().splitlines():
        m = re.match(rf"\s*{sym}\s*=\s*\$([0-9a-fA-F]+)", line)
        if m:
            return "0x" + m.group(1)
    sys.exit("could not find the 'halt' symbol in build/labels.txt")


def run(crt: pathlib.Path, halt: str) -> tuple:
    for f in ("screen.bin", "colour.bin", "vic.bin"):
        (BUILD / f).unlink(missing_ok=True)
    # ⚠ `bank io` IS LOad-BEARING. Without it the monitor reads $D020 through
    # its default bank, which does not expose I/O while the machine is still in
    # Ultimax -- so the orange "device ignores $DE02" case read back as colour
    # 15 and looked like a failure of the cartridge rather than of the harness.
    # The first three cases only read correctly by luck, being out of Ultimax
    # with $01 = $37 by the time they halt. Same class of mistake as sampling a
    # screenshot pixel: reading the wrong thing and believing it.
    (BUILD / "mon.txt").write_text(
        'bank ram\n'
        'save "build/screen.bin" 0 0400 07ff\n'
        'save "build/work.bin" 0 0300 0330\n'
        'bank io\n'
        'save "build/colour.bin" 0 d800 dbff\n'
        # ⚠ FROM $D011, NOT $D020. The old range captured the border and
        # nothing else, so $D016 -- which decides whether the machine runs in
        # 40 or 38 columns -- was not even in the dump to be asserted.
        'save "build/vic.bin" 0 d011 d02f\n'
        "quit\n"
    )
    subprocess.run(
        ["x64sc", "-console", "-warp", "-initbreak", halt,
         "-moncommands", "build/mon.txt", "-cartcrt", str(crt)],
        cwd=ROOT, timeout=180,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    )
    try:
        scr = (BUILD / "screen.bin").read_bytes()[2:]
        col = (BUILD / "colour.bin").read_bytes()[2:]
        vic = (BUILD / "vic.bin").read_bytes()[2:]
        wrk = (BUILD / "work.bin").read_bytes()[2:]
    except FileNotFoundError:
        sys.exit(f"{crt.name}: VICE produced no dump -- it never reached halt")
    # ⚠ vic is now the whole $D011-$D02F block; the border is at $D020.
    return scr, col, vic[0x20 - 0x11] & 0x0F, wrk, vic


GOLD = ROOT / "test" / "golden"


def screen(scr) -> str:
    """The whole 25x40 screen as text -- what a person actually sees."""
    return "\n".join(text(scr, r, 0, 40).rstrip() for r in range(25))


def check_golden(stem: str, scr, bless: bool) -> int:
    """⚠ THE STRONGEST ASSERTION IN THE SUITE, and the one that was missing.
    Every other check names a cell someone thought of; this notices ANY change
    to what the user sees -- a shifted column, a lost coverage figure, a label
    running into its own status cell, a phase that never got marked. All four
    of those shipped, and all four would have failed here.
    Regenerate deliberately:  python3 test/check.py --bless"""
    GOLD.mkdir(exist_ok=True)
    f = GOLD / f"{stem}.txt"
    now = screen(scr)
    if bless or not f.exists():
        f.write_text(now + "\n")
        print(f"     golden    {'blessed' if bless else 'created'} {f.name}")
        return 0
    if f.read_text().rstrip("\n") == now:
        print("     golden    screen matches")
        return 0
    print("     golden    *** SCREEN CHANGED ***")
    for i, (a, b) in enumerate(zip(f.read_text().rstrip("\n").split("\n"),
                                   now.split("\n"))):
        if a != b:
            print(f"       row {i:2d} want |{a}|")
            print(f"              got  |{b}|")
    return 1


def plausible(scr, wrk, want_errs) -> int:
    """⚠ Does the result make SENSE, not merely match a cell?

    A mutation named "one bad byte" that reported 53,294 errors was accepted
    by this suite, because it was only ever asked whether some cell said X.
    These are the things a person would notice at a glance, written down:
      * the error count is EXACTLY what the case claims
      * a one-byte fault marks exactly ONE page red -- no more, no fewer
      * the figure on screen agrees with the counter in memory
    """
    bad = 0
    errs = wrk[14] + 256 * wrk[15]
    if errs != want_errs:
        print(f"     errors    {errs} in memory, case claims {want_errs}   <-- ***")
        bad += 1
    shown = errors_field(scr)
    if shown != str(errs):
        print(f"     errors    screen {shown!r} vs memory {errs}   <-- ***")
        bad += 1
    return bad


def red_pages(scr) -> int:
    """⚠ How many pages the map shows as failed. Stated per case, never
    inferred: a data-bus fault marks none, an address fault marks the nine
    pages P2 touched, and the handover marks all twenty-one it is responsible
    for because it cannot localise within them. Guessing a rule here would
    just be another assertion that agrees with whatever the code does."""
    return sum(1 for p in range(256) if cell(scr, p) == "X")


def text(scr: bytes, row: int, c0: int = 0, c1: int = 40) -> str:
    out = []
    for b in scr[row * 40 + c0: row * 40 + c1]:
        if 1 <= b <= 26:
            out.append(chr(64 + b))
        elif 0x30 <= b <= 0x39:
            out.append(chr(b))
        else:
            out.append(GLYPH.get(b, "?"))
    return "".join(out).rstrip()


# Display geometry -- must track SPEC.md / dramscope.asm
DB_ROW, AH_ROW, AL_ROW, V_ROW, PAN = 5, 8, 10, 21, 20
# ⚠ The checklist rows, in the SAME order as the cartridge's phrow table --
# ordered by when a phase completes, not by its index, because retention
# finishes after the colour-RAM check. Position in the string is still the
# phase index, which is what cl() depends on.
PHROW = (3, 6, 11, 12, 13, 14, 15, 17, 16)
STAT = 32   # the checklist status column
# ⚠ ONE definition of where the title-row counters are, because there are three
# readers and last time the layout moved only two of them were updated -- which
# is a harness that lies about the thing it exists to check.
# ⚠ DECIMAL NOW, AND RIGHT-ALIGNED IN FIVE COLUMNS. These were hex with a '$'
# until Carl asked what the '$' was for; a count is not an address. The fields
# are space-padded on the left, so every reader strips.
PASS_C0, PASS_C1 = 17, 22   # "RUNS ____1"
ERR_C0,  ERR_C1  = 34, 39   # "BAD BYTES ____0"


def passes_field(scr):
    return text(scr, 0, PASS_C0, PASS_C1).strip()


def errors_field(scr):
    return text(scr, 0, ERR_C0, ERR_C1).strip()


def vice_border(stem: str, sym: str, resumes: int = 0, limit: int | None = None):
    """Break at `sym` after `resumes` continues; return the border colour name,
    or None if that point was never reached.

    ⚠ A TIMEOUT IS A RESULT HERE, NOT A CRASH. When the regression this guards
    against is present -- the no-RAM verdict folded back into the steady one --
    the flash loop is never entered, the breakpoint is never hit and VICE runs
    until it is killed. Letting TimeoutExpired escape turns a finding into a
    traceback, and a traceback is not a report. Caught, it becomes None, which
    mismatches and prints like any other failure."""
    (BUILD / "mon.txt").write_text(
        "x\n" * resumes +
        'bank io\nsave "build/vic.bin" 0 d020 d02f\nquit\n')
    (BUILD / "vic.bin").unlink(missing_ok=True)
    cmd = ["x64sc", "-console", "-warp"]
    if limit is not None:
        cmd += ["-limitcycles", str(limit)]
    cmd += ["-initbreak", halt_address(stem, sym),
            "-moncommands", "build/mon.txt",
            "-cartcrt", str(BUILD / f"{stem}.crt")]
    try:
        subprocess.run(cmd, cwd=ROOT, timeout=400, check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return None
    f = BUILD / "vic.bin"
    return BORDER.get(f.read_bytes()[2] & 0x0F) if f.exists() else None


def cl(*bad):
    """⚠ The expected checklist. Naming WHICH phase must fail is far stronger
    than asserting that something did: it proves each mutation is caught by
    the phase that targets it and is invisible to the other eight."""
    return "".join("X" if i in bad else "OK" for i in range(9))
MAP_ROW, MAP_COL = 3, 2


def cell(scr: bytes, page: int) -> str:
    """The map cell for one page: row = high nibble, column = low nibble."""
    return text(scr, MAP_ROW + (page >> 4), MAP_COL + (page & 15),
                MAP_COL + (page & 15) + 1)


def maprow(scr: bytes, row: int) -> str:
    return text(scr, MAP_ROW + row, MAP_COL, MAP_COL + 16)
BORDER = {0: "BLACK", 1: "WHITE", 2: "RED", 3: "CYAN", 4: "PURPLE", 5: "GREEN",
          6: "BLUE", 7: "YELLOW", 8: "ORANGE", 10: "LTRED"}

# name, cartridge, halt symbol, border, data lane, addr-hi, addr-lo
# Lanes None = the run never drew a screen, so only the border is meaningful.
# ⚠ Row 0 is the one that proves the map cannot over-claim:
#     $00-$01 untested, $02-$03 marched, $04-$07 PROBED ONLY, $08-$0F marched.
# If probed regions ever paint the same as marched ones, this case fails.
CASES = [
    ("clean -- every lane solid, all 16 address lines tested",
     "dramscope.crt",      "pass_obs",     "GREEN", "########", "########", "########",
     {"redpages": 0,
      "errcount": 0,
      "row0": "**#*****########", "rowC": "****************",
      "page40": "#", "errors": "0",
      "bits": " 59,648 FULL + 5,886 LIGHTER = 65,534", "chips": "",
      "colram": "OK"}),
    # ⚠ The classifier makes a claim about someone else's hardware. D3 is U10
    # on a 250407 -- schematic 251138 via c64-ice40-ram README §2.2.
    ("D3 stuck -- data lane X, and the chip named from the bit",
     "dramscope_fdb.crt",  "pass_obs",     "LTRED", "####X###", "########", "########",
     {"redpages": 0,
      "errcount": 0,
      "checklist": cl(0),
      "bits":  " BITS                   D3",
      "chips": " LIKELY                 U10"}),
    ("A5 faulty -- one X in the low address lane, data lane clean",
     "dramscope_fab.crt",  "pass_obs",     "LTRED", "########", "########", "##X#####",
     {"redpages": 9,
      "errcount": 0,
      "checklist": cl(1)}),
    # ⚠ P3 must be able to fail too. One stuck bit at $4037: page $40 red,
    # exactly one bad byte, every other page still clean.
    ("one stuck bit at $4037 -- page $40 red, count 1, nothing else",
     "dramscope_fmem.crt", "pass_obs",     "LTRED", "########", "########", "########",
     {"redpages": 1,
      "errcount": 1,
      "checklist": cl(2),
      "row0": "**#*****########", "rowC": "****************", "page40": "X",
      "errors": "1",
      "bits":  " BITS                               D0",
      "chips": " LIKELY                             U21",
      "caveat": " 8X4164 ASSUMED. 41464? D0-D3=1 CHIP."}),
    # ⚠ The one a real device might actually hit. A Kung Fu Flash that ignores
    # $DE02 must SAY SO, not hang in Ultimax pretending to test 64 KB.
    # ⚠ P4 is a SEPARATE engine with its own read paths, so it needs its own
    # mutation. One bit wrong at $5012, seen by March LR's final r0.
    ("March LR catches what March B's pattern left -- page $50, bit D7",
     "dramscope_flr.crt",  "pass_obs",     "LTRED", "########", "########", "########",
     {"redpages": 1,
      "errcount": 1,
      "checklist": cl(3),
      "errors": "1",
      "bits":  " BITS   D7",
      "chips": " LIKELY U12"}),
    # ⚠ P5 is a third engine again -- its own pattern generator and read path.
    # One bit wrong at $6071, on the topographical verify pass.
    ("topographical pass catches a disturbed cell -- page $60, D6",
     "dramscope_ftop.crt", "pass_obs",     "LTRED", "########", "########", "########",
     {"redpages": 1,
      "errcount": 6,
      "checklist": cl(4),
      "errors": "6",
      "bits":  " BITS       D6",
      "chips": " LIKELY     U24"}),
    # ⚠ P6 is a fourth engine again -- registers-only, self-modifying, and the
    # only one that runs with its own stack under test. One bad byte at $0140.
    ("zero page / stack phase catches a bad stack byte",
     "dramscope_fzp.crt",  "pass_obs",     "LTRED", "########", "########", "########",
     {"redpages": 2,
      "errcount": 1,
      "checklist": cl(5),
      "errors": "1",
      "bits":  " BITS                       D2",
      "chips": " LIKELY                     U22"}),
    # ⚠ The handover is a FIFTH engine, and the only one that marches the
    # region the display is standing on. One bad byte at $0555.
    ("handover catches a fault in the screen's own memory",
     "dramscope_fhv.crt",  "pass_obs",     "LTRED", "########", "########", "########",
     # ⚠ 4, not 21: the screen region only. 21 was what the BROKEN hook
     # produced, by corrupting the workspace page it was marching through.
     {"redpages": 4,
      "errcount": 1,
      "checklist": cl(6),
      "errors": "1",
      "bits":  " BITS               D4",
      "chips": " LIKELY             U23"}),
    # ⚠ P7 is the only phase where the fault appears AFTER a wait rather than
    # during a write/read pair. One cell forgets a bit over the dwell.
    ("retention: a cell that forgets a bit over 12 seconds",
     "dramscope_fret.crt", "pass_obs",     "LTRED", "########", "########", "########",
     {"redpages": 1,
      "errcount": 1,
      "checklist": cl(7),
      "errors": "1",
      "bits":  " BITS           D5",
      "chips": " LIKELY         U11"}),
    # ⚠ Colour RAM is a DIFFERENT CHIP. Its verdict is its own, its label goes
    # red, and it must NOT appear in the DRAM bad-byte count or name a 4164.
    ("colour ram fault -- own verdict, and no DRAM blamed",
     "dramscope_fcol.crt", "pass_obs", "LTRED", "########", "########", "########",
     {"redpages": 0,
      "errcount": 0,
      "checklist": cl(8),
      "errors": "0",
      "colram": "X",
      "vline":  " COLOUR RAM BAD - A SEPARATE CHIP."}),
    # ⚠ THE SAFETY RULE. All eight bits wrong must name NO chip at all.
    ("all 8 bits wrong -- must REFUSE to name a chip",
     "dramscope_fall.crt", "pass_obs",     "LTRED", "########", "########", "########",
     {"redpages": 1,
      "errcount": 1,
      "checklist": cl(2),
      "bits":  " BITS   D7  D6  D5  D4  D3  D2  D1  D0",
      "chips": " 1 BYTE, ALL 8 BITS - NOT A CHIP.",
      "caveat": " RUNS UNTIL YOU RESET."}),
    # ⚠ A WHOLE PAGE WRONG ON EVERY BIT -- the only case that reaches the PLA
    # verdict. A single bad byte must NOT reach it, which is the case above.
    ("256 bad bytes, all 8 bits -- the systemic verdict, SEE PLA",
     "dramscope_fpla.crt", "pass_obs", "LTRED", "########", "########", "########",
     {"redpages": 1, "errcount": 256, "checklist": cl(2), "errors": "256",
      "bits":  " BITS   D7  D6  D5  D4  D3  D2  D1  D0",
      "chips": " ALL 8 BITS BAD - NOT ONE CHIP. SEE PLA"}),
    ("device ignores $DE02 -- must report ORANGE, not hang",
     "dramscope_fef.crt",  "rom_halt", "ORANGE", None, None, None, None),
    # ⚠ The scratch bytes are bad but memory IS fitted, so the sweep of
    # $0000-$0FFF must FIND RAM and hold a STEADY red. If the sweep ever went
    # the other way this would flash instead, and the user would be told to
    # check empty sockets on a machine whose sockets are full.
    # ⚠ The three nibble paths. On a 41464 board four bits are ONE chip, so
    # which nibble failed is the whole answer, and the three messages must
    # differ. fmem above is already the low-nibble case.
    ("D4-D7 bad -- must say the HIGH nibble is one chip",
     "dramscope_fnhi.crt", "pass_obs", "LTRED", "########", "########", "########",
     {"redpages": 1, "errcount": 1, "checklist": cl(2), "errors": "1",
      "caveat": " 8X4164 ASSUMED. 41464? D4-D7=1 CHIP."}),
    ("D0 and D4 bad -- must say TWO chips, not one",
     "dramscope_fnbo.crt", "pass_obs", "LTRED", "########", "########", "########",
     {"redpages": 1, "errcount": 1, "checklist": cl(2), "errors": "1",
      "caveat": " 8X4164 ASSUMED. 41464? 2 CHIPS."}),
    ("bad scratch byte, memory fitted -- STEADY red",
     "dramscope_fscr.crt", "rom_halt", "RED", None, None, None, None),
]


def main() -> int:
    bless = "--bless" in sys.argv
    failures = 0
    for name, cart, sym, want_border, want_db, want_ah, want_al, extra in CASES:
        print(f"  {name}")
        stem = cart[:-4]
        scr, col, border, wrk, vic = run(BUILD / cart, halt_address(stem, sym))
        got = {"border": BORDER.get(border, f"colour {border}")}
        want = {"border": want_border}
        # ⚠ The dump used to start at $D020, so $D016 was not merely
        # unasserted -- it was never captured. Widening the range and asserting
        # it is what turns "the border looked right" into "the display mode was
        # right", which is the distinction that let a real bug through.
        # ⚠⚠ ONLY FOR CASES THAT REACH THE DISPLAY. The fatal halts -- a dead
        # scratch, a device that cannot leave Ultimax -- stop at rom_halt
        # BEFORE the display is set up, so $D016 is legitimately untouched
        # there and DEN=0 makes the whole screen border anyway. The first
        # version of this check asserted it for every case and failed two of
        # them, which is the very fault this harness keeps being caught by:
        # ASSERTING MY EXPECTATION RATHER THAN THE PROGRAM'S CONTRACT.
        if vic is not None and sym == "pass_obs":
            got["D016"] = f"${vic[0x16 - 0x11]:02X}"
            want["D016"] = "$C8"
        # ⚠ BURN-IN GUARD. pass_end fires after exactly one complete pass, so
        # the counter must read 0001 there. A zero means the loop never
        # completed; anything higher means the breakpoint is in the wrong place
        # and the harness is reading a later pass than it thinks.
        if want_db is not None:
            got["passes"] = passes_field(scr)
            want["passes"] = "1"
            # ⚠ THE CHECKLIST IS THE ANSWER TO "what ran and did it pass".
            # Asserting the whole column means a phase that silently stops
            # being run, or stops reporting, fails the build.
            got["checklist"] = "".join(
                text(scr, r, STAT, STAT + 2).strip() or ".."
                for r in PHROW)
            want["checklist"] = want.get("checklist", "OK" * 9)
        # ⚠ LIVENESS GUARD. w_tick counts pages processed and drives both the
        # spinner and the border pulse. The final phase text blanks the spinner
        # cell, so the screen cannot prove it ran -- but a zero tick count
        # means the indicator was never called and the cartridge would look
        # identical to a hang for a minute. That is the thing being prevented.
        if want_db is not None:
            got["ticked"] = "yes" if wrk[26] != 0 else "NO - liveness dead"
            want["ticked"] = "yes"
        if want_db is not None:
            got["data"] = text(scr, DB_ROW, PAN, PAN + 8)
            got["addr hi"] = text(scr, AH_ROW, PAN, PAN + 8)
            got["addr lo"] = text(scr, AL_ROW, PAN, PAN + 8)
            want.update({"data": want_db, "addr hi": want_ah, "addr lo": want_al})
        # ⚠ Only read what the case actually asserts. An earlier version read
        # the bit and chip lines unconditionally, which blew up the moment a
        # case (colour RAM) had an opinion about neither.
        readers = {
            "row0":    lambda: maprow(scr, 0),
            "rowC":    lambda: maprow(scr, 0xC),
            "page40":  lambda: cell(scr, 0x40),
            "errors":  lambda: errors_field(scr),
            "bits":    lambda: text(scr, V_ROW + 1),
            "chips":   lambda: text(scr, V_ROW + 2),
            "caveat":  lambda: text(scr, V_ROW + 3),
            "vline":   lambda: text(scr, V_ROW),
            # the COL RAM label's colour IS the verdict for that chip
            # ⚠ the colour RAM verdict is now a checklist row like any other
            # ⚠ PHROW[8], not a literal row: the colour-RAM row moved once already.
            "colram":  lambda: text(scr, PHROW[8], STAT, STAT + 2),
            "checklist": lambda: "".join(
                text(scr, r, STAT, STAT + 2).strip() or ".."
                for r in PHROW),
        }
        if extra:
            for k in extra:
                if k in ("errcount", "redpages"):
                    continue
                got[k] = readers[k]()
            want.update({k: v for k, v in extra.items()
                         if k not in ("errcount", "redpages")})
        # ⚠ MANDATORY, not optional. Every case that reaches a screen must
        # declare how many bad bytes it expects, and the result must be both
        # that number AND internally consistent. A case that forgets to say
        # is a harness error, not a pass.
        if want_db is not None:
            if extra is None or "errcount" not in extra:
                sys.exit(f"{cart}: case does not declare 'errcount'")
            if "redpages" not in extra:
                sys.exit(f"{cart}: case does not declare 'redpages'")
            failures += plausible(scr, wrk, extra["errcount"])
            reds = red_pages(scr)
            if reds != extra["redpages"]:
                print(f"     map       {reds} pages red, case claims "
                      f"{extra['redpages']}   <-- ***")
                failures += 1
            failures += check_golden(stem, scr, bless)
        for k in want:
            flag = "" if got[k] == want[k] else f"   <-- *** wanted {want[k]!r}"
            print(f"     {k:8s} {got[k]!r}{flag}")
            if got[k] != want[k]:
                failures += 1
        if want_db is not None:
            print(f"     verdict  {text(scr, V_ROW)!r}")
            print(f"              {text(scr, V_ROW + 1)!r}")
    # ⚠ MID-PASS, THE COLUMN MUST SHOW PROGRESS THROUGH *THIS* PASS.
    # Passed phases reset to '..' at the start of each pass; only failures
    # persist. Without this the second pass onwards is a wall of OK left over
    # from the first, with nothing to watch. Checked part-way through pass 2,
    # where P1-P3 have run and P4 onwards have not.
    # ⚠⚠ HOSTILE POWER-ON. THE HARNESS'S BIGGEST BLIND SPOT, WRITTEN DOWN.
    # Two real bugs reached Carl's hardware and passed every check here:
    # $D016 was never initialised, so a real C64 ran in 38-column mode and
    # blanked columns 0 and 39; and the CIA interrupt masks were never cleared,
    # so CIA2 could fire an NMI through a vector that is RAM under test.
    # ⚠ BOTH WERE INVISIBLE BECAUSE VICE POWERS UP BENIGN. The emulator sets
    # CSEL and leaves the CIAs quiet, so every "the KERNAL normally does this
    # for us" assumption looked correct. An emulator kinder than the hardware
    # tests nothing -- which is exactly what the sibling project already
    # recorded about its own stub KERNAL, and was not applied here.
    # So: break at entry, POKE THE REGISTERS WRONG, and require the run to come
    # out clean anyway. The program must establish its own state.
    print("  hostile power-on -- $D016 cleared, both CIA masks armed at entry")
    for stem, want_ok, why in (
            ("dramscope",       True,  "must establish its own state"),
            ("dramscope_fd016", False, "skips $D016 -- must be caught"),
            ("dramscope_fnmi",  False, "skips the NMI mask -- must be caught")):
        (BUILD / "mon.txt").write_text(
            "bank io\n> d016 00\n> dc0d 81\n> dd0d 81\n"
            # ⚠ BARE HEX. "break 0xc0fb" sets NO breakpoint and fails silently;
            # the first version of this test ran forever and looked like a
            # finding. The instrument was broken, not the program.
            f"break {halt_address(stem, 'pass_obs')[2:]}\nx\n"
            'bank io\nsave "build/vic.bin" 0 d011 d02f\n'
            'bank ram\nsave "build/work.bin" 0 0300 0330\nquit\n')
        for f in ("vic.bin", "work.bin"):
            (BUILD / f).unlink(missing_ok=True)
        try:
            subprocess.run(
                ["x64sc", "-console", "-warp",
                 "-initbreak", halt_address(stem, "entry"),
                 "-moncommands", "build/mon.txt",
                 "-cartcrt", str(BUILD / f"{stem}.crt")],
                cwd=ROOT, timeout=240, check=False,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.TimeoutExpired:
            pass
        if not (BUILD / "vic.bin").exists():
            got_ok, detail = False, "never reached pass_obs"
        else:
            v = (BUILD / "vic.bin").read_bytes()[2:]
            w = (BUILD / "work.bin").read_bytes()[2:]
            d016, border = v[0x16 - 0x11], v[0x20 - 0x11] & 0x0F
            errs = w[14] + 256 * w[15]
            got_ok = (d016 == 0xC8 and border == 5 and errs == 0)
            detail = (f"$D016=${d016:02X} CSEL={(d016 >> 3) & 1} "
                      f"border={BORDER.get(border, border)} bad={errs}")
        mark = "" if got_ok == want_ok else "   <-- ***"
        verdict = "survives" if got_ok else "FAILS"
        print(f"     {stem:18s} {verdict:8s} {detail}{mark}")
        print(f"        ({why})")
        if got_ok != want_ok:
            failures += 1

    print("  mid-pass 2 -- passed phases reset, progress visible")
    (BUILD / "mon.txt").write_text(
        'x\nbank ram\nsave "build/screen.bin" 0 0400 07ff\nquit\n')
    subprocess.run(
        ["x64sc", "-console", "-warp", "-initbreak", halt_address("dramscope", "p4"),
         "-moncommands", "build/mon.txt",
         "-cartcrt", str(BUILD / "dramscope.crt")],
        cwd=ROOT, timeout=400,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    scr = (BUILD / "screen.bin").read_bytes()[2:]
    mid = "".join(text(scr, r, STAT, STAT + 2).strip() or ".."
                  for r in PHROW)
    want_mid = "OK" * 3 + ".." * 6
    ok = mid == want_mid
    print(f"     at P4          checklist={mid}"
          f"{'' if ok else f'   <-- *** wanted {want_mid}'}")
    if not ok:
        failures += 1

    # ⚠⚠ A TRANSIENT FAULT MUST SURVIVE THE NEXT CLEAN PASS.
    # Every other mutation fires on every pass, so none of them can catch a
    # checklist that forgets. This one fails once, in pass 1, and never again
    # -- which is the exact fault a burn-in exists for, and the case where the
    # status was being quietly overwritten with OK.
    # ⚠⚠ THE TWO P0a VERDICTS MUST NOT BE THE SAME ANSWER.
    # "The scratch will not hold a value" means either a faulty chip or no RAM
    # fitted at all, and those are different jobs for whoever is holding the
    # board. The steady case is a CASES entry above; this is the flashing one,
    # which no single sample can verify -- a sample of a flashing border looks
    # exactly like a steady one. So it is sampled once per interval and the
    # samples must ALTERNATE.
    print("  nothing responds anywhere -- red must FLASH, not sit steady")
    stem = "dramscope_fnor"
    seen = [vice_border(stem, "nr_toggle", resumes=i) for i in range(4)]
    want = ["RED", "BLACK", "RED", "BLACK"]
    ok = seen == want
    print(f"     intervals      {seen}"
          f"{'' if ok else f'   <-- *** wanted {want}'}")
    if not ok:
        failures += 1

    # ⚠ THE RATE IS A SAFETY CLAIM, SO IT IS MEASURED, NOT ASSERTED. Four
    # intervals are bracketed in emulated cycles: they must take MORE than
    # 3.4 M and LESS than 3.6 M, i.e. 850-900 k cycles each, i.e. 0.86-0.91 s
    # at the PAL phi2 of 985,248 Hz. A full on/off cycle is therefore 0.55-0.58
    # Hz against the three-flashes-per-second limit in WCAG 2.3.1 -- a 5.2x
    # margin or better, and it matters here because DEN=0 makes this fill the
    # whole screen rather than just the border.
    print("     flash rate -- 4 intervals must fall between 3.4 M and 3.6 M cycles")
    for limit, want_reach in ((3_400_000, False), (3_600_000, True)):
        got_reach = vice_border(stem, "nr_toggle", resumes=3,
                                limit=limit) is not None
        ok = got_reach == want_reach
        print(f"       {limit:>9,} cycles  "
              f"{'reached' if got_reach else 'not reached':12s}"
              f"{'' if ok else '   <-- *** too ' + ('fast' if got_reach else 'slow')}")
        if not ok:
            failures += 1

    # ⚠⚠ A VERDICT THAT CHANGES KIND MUST NOT LEAVE THE PREVIOUS ONE BEHIND.
    # verdict_line writes a string and nothing else, so a shorter verdict used
    # to leave the tail of a longer one showing. Run 1 here is CLEAN, so row 22
    # holds the 36-character coverage line; run 2 faults, and row 22 becomes the
    # bit lanes, which write only " BITS" and a "dN" out at column 36. Every
    # other mutation shows one verdict for the whole session, so none of them
    # could ever catch this.
    print("  verdict changes kind in run 2 -- no tail from the old one")
    stem = "dramscope_fchg"
    rows = {}
    for label, resumes in (("run 1 (clean)", 0), ("run 2 (faulty)", 1)):
        (BUILD / "mon.txt").write_text(
            "x\n" * resumes +
            'bank ram\nsave "build/screen.bin" 0 0400 07ff\nquit\n')
        (BUILD / "screen.bin").unlink(missing_ok=True)
        try:
            subprocess.run(
                ["x64sc", "-console", "-warp",
                 "-initbreak", halt_address(stem, "pass_obs"),
                 "-moncommands", "build/mon.txt",
                 "-cartcrt", str(BUILD / f"{stem}.crt")],
                cwd=ROOT, timeout=400, check=False,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.TimeoutExpired:
            pass
        f = BUILD / "screen.bin"
        rows[label] = (text(f.read_bytes()[2:], V_ROW, 0, 40).rstrip(),
                       text(f.read_bytes()[2:], V_ROW + 1, 0, 40).rstrip()) \
            if f.exists() else (None, None)
    v1, c1 = rows["run 1 (clean)"]
    v2, c2 = rows["run 2 (faulty)"]
    ok1 = v1 == " ALL TESTS PASSED."
    # ⚠ The exact test: nothing of the coverage line may survive into run 2.
    ok2 = (v2 or "").startswith(" MEMORY FAULT") and "LIGHTER" not in (c2 or "?") \
        and "FULL" not in (c2 or "?")
    print(f"     run 1 verdict  {v1!r}{'' if ok1 else '   <-- ***'}")
    print(f"     run 2 verdict  {v2!r}")
    print(f"     run 2 row 22   {c2!r}"
          f"{'' if ok2 else '   <-- *** tail of the coverage line survived'}")
    if not ok1:
        failures += 1
    if not ok2:
        failures += 1

    print("  transient fault -- must still be X at the end of pass 2")
    stem = "dramscope_fonce"
    for label, resumes, want_pass, want_cl in (
            ("end of pass 1", 0, "1", cl(2)),
            ("end of pass 2", 1, "2", cl(2))):
        (BUILD / "mon.txt").write_text(
            "x\n" * resumes +
            'bank ram\nsave "build/screen.bin" 0 0400 07ff\n'
            'save "build/work.bin" 0 0300 0330\n'
            'bank io\nsave "build/colour.bin" 0 d800 dbff\n'
            'save "build/vic.bin" 0 d020 d02f\nquit\n')
        subprocess.run(
            ["x64sc", "-console", "-warp", "-initbreak", halt_address(stem, "pass_obs"),
             "-moncommands", "build/mon.txt",
             "-cartcrt", str(BUILD / f"{stem}.crt")],
            cwd=ROOT, timeout=400,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        scr = (BUILD / "screen.bin").read_bytes()[2:]
        got_p = passes_field(scr).strip()
        got_c = "".join(text(scr, r, STAT, STAT + 2).strip() or ".."
                        for r in PHROW)
        ok = got_p == want_pass and got_c == want_cl
        print(f"     {label:14s} pass={got_p} checklist={got_c}"
              f"{'' if ok else f'   <-- *** wanted {want_pass} / {want_cl}'}")
        if not ok:
            failures += 1

    print()
    if failures:
        print(f"  *** {failures} MISMATCHES")
        return 1
    print("  ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
