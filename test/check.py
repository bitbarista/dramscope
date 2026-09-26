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

GLYPH = {0x20: " ", 0x2E: ".", 0x2D: "-", 0x2F: "/", 0x2C: ",", 0x3D: "=",
         0x18: "X", 0xA0: "#", 0x2B: "+", 0x2A: "*", 0x23: "#"}


def halt_address(stem: str, sym: str = "pass_obs") -> str:
    """⚠ Per build. Injected instructions move every later address, so the
    clean build's halt is not the fault build's halt -- breakpointing the
    wrong one just hangs."""
    for line in (BUILD / f"{stem}.labels").read_text().splitlines():
        m = re.match(rf"\s*{sym}\s*=\s*\$([0-9a-fA-F]+)", line)
        if m:
            return "0x" + m.group(1)
    sys.exit("could not find the 'halt' symbol in build/labels.txt")


def run(crt: pathlib.Path, halt: str) -> tuple[bytes, bytes, int]:
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
        'save "build/vic.bin" 0 d020 d02f\n'
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
    return scr, col, vic[0] & 0x0F, wrk


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
STAT = 32   # the checklist status column


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
BORDER = {1: "WHITE", 2: "RED", 3: "CYAN", 4: "PURPLE", 5: "GREEN",
          6: "BLUE", 7: "YELLOW", 8: "ORANGE", 10: "LTRED"}

# name, cartridge, halt symbol, border, data lane, addr-hi, addr-lo
# Lanes None = the run never drew a screen, so only the border is meaningful.
# ⚠ Row 0 is the one that proves the map cannot over-claim:
#     $00-$01 untested, $02-$03 marched, $04-$07 PROBED ONLY, $08-$0F marched.
# If probed regions ever paint the same as marched ones, this case fails.
CASES = [
    ("clean -- every lane solid, all 16 address lines tested",
     "dramscope.crt",      "pass_obs",     "GREEN", "########", "########", "########",
     {"row0": "**#*****########", "rowC": "****************",
      "page40": "#", "errors": " 0000",
      "bits": " 59,648 FULL + 5,886 AT 9N = 65,534.", "chips": "",
      "colram": "OK"}),
    # ⚠ The classifier makes a claim about someone else's hardware. D3 is U10
    # on a 250407 -- schematic 251138 via c64-ice40-ram README §2.2.
    ("D3 stuck -- data lane X, and the chip named from the bit",
     "dramscope_fdb.crt",  "pass_obs",     "LTRED", "####X###", "########", "########",
     {"checklist": cl(0),
      "bits":  " BITS                   D3",
      "chips": " 250407                 U10"}),
    ("A5 faulty -- one X in the low address lane, data lane clean",
     "dramscope_fab.crt",  "pass_obs",     "LTRED", "########", "########", "##X#####",
     {"checklist": cl(1)}),
    # ⚠ P3 must be able to fail too. One stuck bit at $4037: page $40 red,
    # exactly one bad byte, every other page still clean.
    ("one stuck bit at $4037 -- page $40 red, count 1, nothing else",
     "dramscope_fmem.crt", "pass_obs",     "LTRED", "########", "########", "########",
     {"checklist": cl(2),
      "row0": "**#*****########", "rowC": "****************", "page40": "X",
      "errors": " 0001",
      "bits":  " BITS                               D0",
      "chips": " 250407                             U21",
      "caveat": " SHORT BOARD? 2X41464 NAMES DIFFER."}),
    # ⚠ The one a real device might actually hit. A Kung Fu Flash that ignores
    # $DE02 must SAY SO, not hang in Ultimax pretending to test 64 KB.
    # ⚠ P4 is a SEPARATE engine with its own read paths, so it needs its own
    # mutation. One bit wrong at $5012, seen by March LR's final r0.
    ("March LR catches what March B's pattern left -- page $50, bit D7",
     "dramscope_flr.crt",  "pass_obs",     "LTRED", "########", "########", "########",
     {"checklist": cl(3),
      "errors": " 0001",
      "bits":  " BITS   D7",
      "chips": " 250407 U12"}),
    # ⚠ P5 is a third engine again -- its own pattern generator and read path.
    # One bit wrong at $6071, on the topographical verify pass.
    ("topographical pass catches a disturbed cell -- page $60, D6",
     "dramscope_ftop.crt", "pass_obs",     "LTRED", "########", "########", "########",
     {"checklist": cl(4),
      "errors": " 0006",
      "bits":  " BITS       D6",
      "chips": " 250407     U24"}),
    # ⚠ P6 is a fourth engine again -- registers-only, self-modifying, and the
    # only one that runs with its own stack under test. One bad byte at $0140.
    ("zero page / stack phase catches a bad stack byte",
     "dramscope_fzp.crt",  "pass_obs",     "LTRED", "########", "########", "########",
     {"checklist": cl(5),
      "errors": " 0001",
      "bits":  " BITS                       D2",
      "chips": " 250407                     U22"}),
    # ⚠ The handover is a FIFTH engine, and the only one that marches the
    # region the display is standing on. One bad byte at $0555.
    ("handover catches a fault in the screen's own memory",
     "dramscope_fhv.crt",  "pass_obs",     "LTRED", "########", "########", "########",
     {"checklist": cl(6),
      "errors": " 0001",
      "bits":  " BITS               D4",
      "chips": " 250407             U23"}),
    # ⚠ P7 is the only phase where the fault appears AFTER a wait rather than
    # during a write/read pair. One cell forgets a bit over the dwell.
    ("retention: a cell that forgets a bit over 12 seconds",
     "dramscope_fret.crt", "pass_obs",     "LTRED", "########", "########", "########",
     {"checklist": cl(7),
      "errors": " 0001",
      "bits":  " BITS           D5",
      "chips": " 250407         U11"}),
    # ⚠ Colour RAM is a DIFFERENT CHIP. Its verdict is its own, its label goes
    # red, and it must NOT appear in the DRAM bad-byte count or name a 4164.
    ("colour ram fault -- own verdict, and no DRAM blamed",
     "dramscope_fcol.crt", "pass_obs", "LTRED", "########", "########", "########",
     {"checklist": cl(8),
      "errors": " 0000",
      "colram": "X",
      "vline":  " COLOUR RAM FAULT - A SEPARATE CHIP."}),
    # ⚠ THE SAFETY RULE. All eight bits wrong must name NO chip at all.
    ("all 8 bits wrong -- must REFUSE to name a chip",
     "dramscope_fall.crt", "pass_obs",     "LTRED", "########", "########", "########",
     {"checklist": cl(2),
      "bits":  " BITS   D7  D6  D5  D4  D3  D2  D1  D0",
      "chips": " ALL 8 BITS - NOT ONE CHIP. SEE PLA.",
      "caveat": " #=FULL *=9N +=PROBED .=NONE"}),
    ("device ignores $DE02 -- must report ORANGE, not hang",
     "dramscope_fef.crt",  "rom_halt", "ORANGE", None, None, None, None),
]


def main() -> int:
    failures = 0
    for name, cart, sym, want_border, want_db, want_ah, want_al, extra in CASES:
        print(f"  {name}")
        stem = cart[:-4]
        scr, col, border, wrk = run(BUILD / cart, halt_address(stem, sym))
        got = {"border": BORDER.get(border, f"colour {border}")}
        want = {"border": want_border}
        # ⚠ BURN-IN GUARD. pass_end fires after exactly one complete pass, so
        # the counter must read 0001 there. A zero means the loop never
        # completed; anything higher means the breakpoint is in the wrong place
        # and the harness is reading a later pass than it thinks.
        if want_db is not None:
            got["passes"] = text(scr, 0, 33, 38)
            want["passes"] = " 0001"
            # ⚠ THE CHECKLIST IS THE ANSWER TO "what ran and did it pass".
            # Asserting the whole column means a phase that silently stops
            # being run, or stops reporting, fails the build.
            got["checklist"] = "".join(
                text(scr, r, STAT, STAT + 2).strip() or ".."
                for r in (3, 6, 11, 12, 13, 14, 15, 16, 17))
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
            "errors":  lambda: text(scr, 0, 23, 28),
            "bits":    lambda: text(scr, V_ROW + 1),
            "chips":   lambda: text(scr, V_ROW + 2),
            "caveat":  lambda: text(scr, V_ROW + 3),
            "vline":   lambda: text(scr, V_ROW),
            # the COL RAM label's colour IS the verdict for that chip
            # ⚠ the colour RAM verdict is now a checklist row like any other
            "colram":  lambda: text(scr, 17, STAT, STAT + 2),
            "checklist": lambda: "".join(
                text(scr, r, STAT, STAT + 2).strip() or ".."
                for r in (3, 6, 11, 12, 13, 14, 15, 16, 17)),
        }
        if extra:
            for k in extra:
                got[k] = readers[k]()
            want.update(extra)
        for k in want:
            flag = "" if got[k] == want[k] else f"   <-- *** wanted {want[k]!r}"
            print(f"     {k:8s} {got[k]!r}{flag}")
            if got[k] != want[k]:
                failures += 1
        if want_db is not None:
            print(f"     verdict  {text(scr, V_ROW)!r}")
            print(f"              {text(scr, V_ROW + 1)!r}")
    print()
    if failures:
        print(f"  *** {failures} MISMATCHES")
        return 1
    print("  ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
