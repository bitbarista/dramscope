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
         0x18: "X", 0xA0: "#"}


def halt_address(stem: str) -> str:
    """⚠ Per build. Injected instructions move every later address, so the
    clean build's halt is not the fault build's halt -- breakpointing the
    wrong one just hangs."""
    for line in (BUILD / f"{stem}.labels").read_text().splitlines():
        m = re.match(r"\s*halt\s*=\s*\$([0-9a-fA-F]+)", line)
        if m:
            return "0x" + m.group(1)
    sys.exit("could not find the 'halt' symbol in build/labels.txt")


def run(crt: pathlib.Path, halt: str) -> tuple[bytes, bytes, int]:
    for f in ("screen.bin", "colour.bin", "vic.bin"):
        (BUILD / f).unlink(missing_ok=True)
    (BUILD / "mon.txt").write_text(
        'save "build/screen.bin" 0 0400 07ff\n'
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
BORDER = {1: "WHITE", 2: "RED", 3: "CYAN", 4: "PURPLE", 5: "GREEN", 10: "LTRED"}

CASES = [
    # name, cartridge, border, data lane, addr-hi lane, addr-lo lane
    ("clean -- every lane solid, A15 correctly shown untested",
     "dramscope.crt",     "GREEN", "########", ".#######", "########"),
    ("D3 stuck -- one X in the data lane, nothing else disturbed",
     "dramscope_fdb.crt", "LTRED", "####X###", ".#######", "########"),
    ("A5 faulty -- one X in the low address lane, data lane clean",
     "dramscope_fab.crt", "LTRED", "########", ".#######", "##X#####"),
]


def main() -> int:
    failures = 0
    for name, cart, want_border, want_db, want_ah, want_al in CASES:
        print(f"  {name}")
        stem = cart[:-4]
        scr, _col, border = run(BUILD / cart, halt_address(stem))
        got_border = BORDER.get(border, f"colour {border}")
        got = {
            "border":  got_border,
            "data":    text(scr, DB_ROW, PAN, PAN + 8),
            "addr hi": text(scr, AH_ROW, PAN, PAN + 8),
            "addr lo": text(scr, AL_ROW, PAN, PAN + 8),
        }
        want = {"border": want_border, "data": want_db,
                "addr hi": want_ah, "addr lo": want_al}
        for k in got:
            flag = "" if got[k] == want[k] else f"   <-- *** wanted {want[k]!r}"
            print(f"     {k:8s} {got[k]!r}{flag}")
            if got[k] != want[k]:
                failures += 1
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
