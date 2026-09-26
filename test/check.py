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
         0x18: "X", 0xA0: "#", 0x2B: "+"}


def halt_address(stem: str, sym: str = "halt") -> str:
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
    except FileNotFoundError:
        sys.exit(f"{crt.name}: VICE produced no dump -- it never reached halt")
    return scr, col, vic[0] & 0x0F


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
DB_ROW, AH_ROW, AL_ROW, V_ROW, PAN = 5, 9, 11, 21, 22
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
     "dramscope.crt",      "halt",     "GREEN", "########", "########", "########",
     {"row0": "..##++++########", "rowC": "++++++++++++####",
      "page40": "#", "errors": " 0000"}),
    ("D3 stuck -- one X in the data lane, nothing else disturbed",
     "dramscope_fdb.crt",  "halt",     "LTRED", "####X###", "########", "########", None),
    ("A5 faulty -- one X in the low address lane, data lane clean",
     "dramscope_fab.crt",  "halt",     "LTRED", "########", "########", "##X#####", None),
    # ⚠ P3 must be able to fail too. One stuck bit at $4037: page $40 red,
    # exactly one bad byte, every other page still clean.
    ("one stuck bit at $4037 -- page $40 red, count 1, nothing else",
     "dramscope_fmem.crt", "halt",     "LTRED", "########", "########", "########",
     {"row0": "..##++++########", "rowC": "++++++++++++####",
      "page40": "X", "errors": " 0001"}),
    # ⚠ The one a real device might actually hit. A Kung Fu Flash that ignores
    # $DE02 must SAY SO, not hang in Ultimax pretending to test 64 KB.
    ("device ignores $DE02 -- must report ORANGE, not hang",
     "dramscope_fef.crt",  "rom_halt", "ORANGE", None, None, None, None),
]


def main() -> int:
    failures = 0
    for name, cart, sym, want_border, want_db, want_ah, want_al, extra in CASES:
        print(f"  {name}")
        stem = cart[:-4]
        scr, _col, border = run(BUILD / cart, halt_address(stem, sym))
        got = {"border": BORDER.get(border, f"colour {border}")}
        want = {"border": want_border}
        if want_db is not None:
            got["data"] = text(scr, DB_ROW, PAN, PAN + 8)
            got["addr hi"] = text(scr, AH_ROW, PAN, PAN + 8)
            got["addr lo"] = text(scr, AL_ROW, PAN, PAN + 8)
            want.update({"data": want_db, "addr hi": want_ah, "addr lo": want_al})
        if extra:
            got["row0"] = maprow(scr, 0)
            got["rowC"] = maprow(scr, 0xC)
            got["page40"] = cell(scr, 0x40)
            got["errors"] = text(scr, 17, PAN - 1, PAN + 5)
            want.update(extra)
        for k in got:
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
